//+------------------------------------------------------------------+
//|                         GoldSilver_Ratio_Indicator.mq5           |
//|                  Gold-Silver Ratio Analysis Indicator          |
//|                  Companion tool for "The Silver Catch-Up"     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader"
#property description "Gold-Silver Ratio Analysis Indicator"
#property description "Displays the Gold/Silver ratio and rolling percentile bands."
#property description "Analysis-only indicator; it does not generate or execute trades."

#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   3

//--- Plot 1: Ratio
#property indicator_label1  "Gold/Silver Ratio"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: Upper band (80th percentile)
#property indicator_label2  "Upper Extreme (80th)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Plot 3: Lower band (60th percentile)
#property indicator_label3  "Lower Exit (60th)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrLimeGreen
#property indicator_style3  STYLE_DOT
#property indicator_width3  1


//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input string InpGoldSymbol       = "XAUUSD";        // Gold symbol
input string InpSilverSymbol     = "XAGUSD";        // Silver symbol
input int    InpRatioPeriod      = 50;              // Percentile lookback
input double InpUpperPercentile  = 80.0;            // Upper (extreme) percentile
input double InpLowerPercentile  = 60.0;            // Lower (normal) percentile


//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                |
//+------------------------------------------------------------------+
double RatioBuffer[];
double UpperBandBuffer[];
double LowerBandBuffer[];




//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
// Verify that the configured Gold and Silver symbols are available.
   if(!SymbolSelect(InpGoldSymbol, true) || !SymbolSelect(InpSilverSymbol, true))
     {
      Print("ERROR: Cannot find symbols: ", InpGoldSymbol, " / ", InpSilverSymbol);
      Print("Please check Market Watch (Ctrl+M) and use the exact broker symbol names.");
      return(INIT_FAILED);
     }

   SetIndexBuffer(0, RatioBuffer,       INDICATOR_DATA);
   SetIndexBuffer(1, UpperBandBuffer,   INDICATOR_DATA);
   SetIndexBuffer(2, LowerBandBuffer,   INDICATOR_DATA);


   ArraySetAsSeries(RatioBuffer, true);
   ArraySetAsSeries(UpperBandBuffer, true);
   ArraySetAsSeries(LowerBandBuffer, true);

   IndicatorSetString(INDICATOR_SHORTNAME, "Gold-Silver Ratio");
   IndicatorSetInteger(INDICATOR_DIGITS, 2);


   PlotIndexSetString(0, PLOT_LABEL, "Gold/Silver Ratio");
   PlotIndexSetString(1, PLOT_LABEL, "Upper Extreme (80%)");
   PlotIndexSetString(2, PLOT_LABEL, "Lower Exit (60%)");


   Print("Gold-Silver Ratio Indicator loaded. Symbols: ",
         InpGoldSymbol, " / ", InpSilverSymbol);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
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
   if(rates_total < InpRatioPeriod + 10)
      return(0);

// Use timeseries indexing: index 0 is the newest bar.
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);
   ArraySetAsSeries(volume, true);
   ArraySetAsSeries(spread, true);

// Recalculate the displayed series from the available history.
   ArrayInitialize(RatioBuffer, 0.0);
   ArrayInitialize(UpperBandBuffer, 0.0);
   ArrayInitialize(LowerBandBuffer, 0.0);

// With series indexing, 0 is the newest bar and rates_total-1 is the oldest.
// Calculate from older bars toward newer bars so each percentile band
// is derived from observations preceding the bar being evaluated.
   int start = rates_total - InpRatioPeriod;

   for(int i = start; i >= 0; i--)
     {
      double gold   = iClose(InpGoldSymbol, PERIOD_CURRENT, i);
      double silver = iClose(InpSilverSymbol, PERIOD_CURRENT, i);

      if(gold <= 0 || silver <= 0)
         continue;

      double ratio = gold / silver;

      RatioBuffer[i] = ratio;


      // The percentile bands use only prior ratio observations,
      // excluding the bar currently being evaluated.
      UpperBandBuffer[i] = GetPercentileValue(InpUpperPercentile, i);
      LowerBandBuffer[i] = GetPercentileValue(InpLowerPercentile, i);




     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Calculate a rolling percentile from prior ratio observations     |
//+------------------------------------------------------------------+
double GetPercentileValue(double percentile, int barIndex)
  {
   double values[];
   ArrayResize(values, InpRatioPeriod);

   int count = 0;

   for(int i = 1; i <= InpRatioPeriod; i++)
     {
      int shift = barIndex + i;
      
      double gold   = iClose(InpGoldSymbol, PERIOD_CURRENT, shift);
      double silver = iClose(InpSilverSymbol, PERIOD_CURRENT, shift);

      if(gold <= 0 || silver <= 0)
         continue;

      values[count] = gold / silver;
      count++;
     }

   if(count < 10)
      return 0.0;

   ArrayResize(values, count);
   ArraySort(values);

   int index = (int)(percentile / 100.0 * count);

   if(index >= count)
      index = count - 1;

   return values[index];
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("Gold-Silver Ratio Indicator removed.");
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
