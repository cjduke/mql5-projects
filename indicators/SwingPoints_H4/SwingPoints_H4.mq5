//+------------------------------------------------------------------+
//|                                              SwingPoints_H4.mq5  |
//|                    Swing High / Low Detection with Labels        |
//|                    Structural classification: HH / HL / LH / LL  |
//+------------------------------------------------------------------+
//|                                                                  |
//|  Detects swing highs and swing lows using configurable left/     |
//|  right bar strength, plots them as arrows, and labels each one   |
//|  with its structural classification.                             |
//|                                                                  |
//|  FEATURES                                                        |
//|  --------                                                        |
//|  - Configurable left/right strength for pivot detection          |
//|  - Minimum price move filter to ignore trivial pivots            |
//|  - HH / HL / LH / LL labels for reading market structure         |
//|  - Object lifecycle management: old labels are cleaned up        |
//|  - Buffer-based output, readable via CopyBuffer() from EAs       |
//|  - Public accessors: GetLastSwingHigh(), GetLastSwingLow()       |
//|                                                                  |
//|  INPUTS                                                          |
//|  ------                                                          |
//|  InpLeftBars       - bars required to the left (default 3)       |
//|  InpRightBars      - bars required to the right (default 2)      |
//|  InpMinMovePoints  - minimum move in points (default 10)         |
//|  InpShowLabels     - show HH/HL/LH/LL labels (default true)      |
//|  InpMaxBars        - bars to calculate (default 500)             |
//|                                                                  |
//|  NOTE                                                            |
//|  ----                                                            |
//|  This is a reference implementation published as part of the     |
//|  mql5-projects library. It makes no performance claims and is    |
//|  not a standalone trading system.                                |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader
#property version   "1.00"
#property description "Swing high/low detection with HH/HL/LH/LL labels."
#property description "Configurable strength, minimum move filter, object cleanup."
#property description "Buffer output, EA-accessible. Reference implementation."


//--- Plot Swing Highs
#property indicator_label1  "SwingHigh"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrRed
#property indicator_width1  2
#property indicator_style1  STYLE_SOLID

//--- Plot Swing Lows
#property indicator_label2  "SwingLow"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrBlue
#property indicator_width2  2
#property indicator_style2  STYLE_SOLID

//--- Input Parameters
input int      InpLeftBars      = 3;     // Left Strength (bars before)
input int      InpRightBars     = 2;     // Right Strength (bars after) 
input double   InpMinMovePoints = 10;    // Min price move in points
input bool     InpShowLabels    = true;  // Show HH/HL/LH/LL labels
input int      InpMaxBars       = 500;   // Bars to calculate

//--- Indicator buffers
double SwingHighBuffer[];
double SwingLowBuffer[];
double HighPriceBuffer[];
double LowPriceBuffer[];

//--- Global variables
datetime lastAlertTime = 0;
int swingHighIndex, swingLowIndex;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                        |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set index mapping
   SetIndexBuffer(0, SwingHighBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SwingLowBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, HighPriceBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, LowPriceBuffer, INDICATOR_CALCULATIONS);
   
   // Set empty value
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0);
   
   // Set arrow codes (MQL5 uses Wingdings character codes)
   PlotIndexSetInteger(0, PLOT_ARROW, 217);  // Down arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 218);  // Up arrow
   
   // Set arrow shifts
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 5);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -5);
   
   IndicatorSetString(INDICATOR_SHORTNAME, "SwingPoints_H4 (" + IntegerToString(InpLeftBars) + "," + 
                      IntegerToString(InpRightBars) + ")");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // Ensure arrays are properly sized
   if(rates_total <= InpLeftBars + InpRightBars)
      return(0);
   
   // Limit calculation range for performance
   int start = prev_calculated - InpRightBars - 1;
   if(start < InpRightBars + 1) 
      start = InpRightBars + 1;
   
   // Limit to MaxBars for speed
   int end = rates_total - 1;
   if(end - start > InpMaxBars && prev_calculated == 0)
      start = end - InpMaxBars;
   if(start < InpRightBars + 1)
      start = InpRightBars + 1;
   
   // Clear buffers at start
   if(prev_calculated == 0)
   {
      ArrayInitialize(SwingHighBuffer, 0);
      ArrayInitialize(SwingLowBuffer, 0);
      ArrayInitialize(HighPriceBuffer, 0);
      ArrayInitialize(LowPriceBuffer, 0);
   }
   
   // Detect swing points
   for(int i = start; i <= end - InpRightBars && !IsStopped(); i++)
   {
      // Skip if no price movement
      if(high[i] == low[i]) continue;
      
      // Check for Swing High
      if(IsSwingHigh(high, i, rates_total))
      {
         SwingHighBuffer[i] = high[i];
         HighPriceBuffer[i] = high[i];
         
         // Draw HH/HL label if enabled
         if(InpShowLabels)
            DrawSwingLabel(time, high, low, i, true);
      }
      else
         SwingHighBuffer[i] = 0;
      
      // Check for Swing Low
      if(IsSwingLow(low, i, rates_total))
      {
         SwingLowBuffer[i] = low[i];
         LowPriceBuffer[i] = low[i];
         
         // Draw LH/LL label if enabled
         if(InpShowLabels)
            DrawSwingLabel(time, high, low, i, false);
      }
      else
         SwingLowBuffer[i] = 0;
   }
   
   // Clean up old trend labels if needed
   if(InpShowLabels && prev_calculated > 0)
      CleanupOldLabels(time, rates_total);
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Check if bar at index is a swing high                           |
//+------------------------------------------------------------------+
bool IsSwingHigh(const double &high[], int index, int rates_total)
{
   // Need enough bars on both sides
   if(index < InpLeftBars || index + InpRightBars >= rates_total)
      return false;
   
   double candidateHigh = high[index];
   double minMove = InpMinMovePoints * _Point;
   
   // Check left side - all must be lower
   for(int l = 1; l <= InpLeftBars; l++)
   {
      if(high[index - l] >= candidateHigh - minMove)
         return false;
   }
   
   // Check right side - all must be lower
   for(int r = 1; r <= InpRightBars; r++)
   {
      if(high[index + r] >= candidateHigh - minMove)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar at index is a swing low                            |
//+------------------------------------------------------------------+
bool IsSwingLow(const double &low[], int index, int rates_total)
{
   // Need enough bars on both sides
   if(index < InpLeftBars || index + InpRightBars >= rates_total)
      return false;
   
   double candidateLow = low[index];
   double minMove = InpMinMovePoints * _Point;
   
   // Check left side - all must be higher
   for(int l = 1; l <= InpLeftBars; l++)
   {
      if(low[index - l] <= candidateLow + minMove)
         return false;
   }
   
   // Check right side - all must be higher
   for(int r = 1; r <= InpRightBars; r++)
   {
      if(low[index + r] <= candidateLow + minMove)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Draw HH/HL/LH/LL labels                                          |
//+------------------------------------------------------------------+
void DrawSwingLabel(const datetime &time[], const double &high[], const double &low[], int index, bool isHigh)
{
   string labelName = "SwingLabel_" + IntegerToString(index) + "_" + (isHigh ? "H" : "L");
   
   // Delete existing label if it exists
   ObjectDelete(0, labelName);
   
   // Determine if this is HH/HL or LH/LL by comparing to previous swing
   bool isHigher = false;
   bool isLower = false;
   
   // Find previous swing of same type
   int prevIndex = FindPreviousSwing(index - 1, isHigh);
   
   if(prevIndex >= 0)
   {
      if(isHigh)
      {
         if(high[index] > high[prevIndex])
            isHigher = true;  // HH
         else
            isLower = true;   // LH
      }
      else
      {
         if(low[index] < low[prevIndex])
            isLower = true;   // LL
         else
            isHigher = true;  // HL
      }
   }
   
   // Create label
   string labelText = "";
   color labelColor = clrGray;
   double labelPrice;
   
   if(isHigh)
   {
      labelPrice = high[index] + (20 * _Point);
      if(isHigher) { labelText = "HH"; labelColor = clrLimeGreen; }
      else if(isLower) { labelText = "LH"; labelColor = clrOrange; }
      else labelText = "H";
   }
   else
   {
      labelPrice = low[index] - (20 * _Point);
      if(isLower) { labelText = "LL"; labelColor = clrRed; }
      else if(isHigher) { labelText = "HL"; labelColor = clrGreen; }
      else labelText = "L";
   }
   
   if(StringLen(labelText) > 0)
   {
      ObjectCreate(0, labelName, OBJ_TEXT, 0, time[index], labelPrice);
      ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, labelColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, labelName, OBJPROP_BACK, true);
   }
}

//+------------------------------------------------------------------+
//| Find previous swing point                                        |
//+------------------------------------------------------------------+
int FindPreviousSwing(int startIndex, bool isHigh)
{
   if(isHigh)
   {
      for(int i = startIndex; i >= 0; i--)
      {
         if(i < ArraySize(SwingHighBuffer) && SwingHighBuffer[i] > 0)
            return i;
      }
   }
   else
   {
      for(int i = startIndex; i >= 0; i--)
      {
         if(i < ArraySize(SwingLowBuffer) && SwingLowBuffer[i] > 0)
            return i;
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Clean up old labels                                              |
//+------------------------------------------------------------------+
void CleanupOldLabels(const datetime &time[], int total)
{
   // Keep only last 100 labels for performance
   string prefix = "SwingLabel_";
   int keepCount = 100;
   int found = 0;
   
   for(int i = total - 1; i >= 0 && found < keepCount; i--)
   {
      string nameH = prefix + IntegerToString(i) + "_H";
      string nameL = prefix + IntegerToString(i) + "_L";
      
      if(ObjectFind(0, nameH) >= 0)
         found++;
      if(ObjectFind(0, nameL) >= 0)
         found++;
   }
   
   // Delete older ones
   for(int i = 0; i < total - keepCount * 2; i++)
   {
      string nameH = prefix + IntegerToString(i) + "_H";
      string nameL = prefix + IntegerToString(i) + "_L";
      
      ObjectDelete(0, nameH);
      ObjectDelete(0, nameL);
   }
}

//+------------------------------------------------------------------+
//| Get latest swing high (for EA use)                              |
//+------------------------------------------------------------------+
double GetLastSwingHigh(int shift = 1)
{
   int total = ArraySize(SwingHighBuffer);
   for(int i = total - shift; i >= 0; i--)
   {
      if(i < total && SwingHighBuffer[i] > 0)
         return SwingHighBuffer[i];
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Get latest swing low (for EA use)                               |
//+------------------------------------------------------------------+
double GetLastSwingLow(int shift = 1)
{
   int total = ArraySize(SwingLowBuffer);
   for(int i = total - shift; i >= 0; i--)
   {
      if(i < total && SwingLowBuffer[i] > 0)
         return SwingLowBuffer[i];
   }
   return 0;
}
//+------------------------------------------------------------------+