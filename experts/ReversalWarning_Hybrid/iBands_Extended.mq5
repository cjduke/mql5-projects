//+------------------------------------------------------------------+
//|                                          iBands_Extended.mq5     |
//|                    Bollinger Bands wrapper with extended buffers |
//|                    Five buffers: upper, middle, lower,           |
//|                    upper-middle, lower-middle                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader"
#property version   "1.00""
#property description "Bollinger Bands with five output buffers."
#property description "Adds upper-middle and lower-middle lines between the"
#property description "standard outer bands and the middle band."

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5
//--- the Upper plot
#property indicator_label1  "Upper"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumSeaGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1
//--- the Lower plot
#property indicator_label2  "Lower"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrMediumSeaGreen
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1
//--- the Middle plot
#property indicator_label3  "Middle"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrMediumSeaGreen
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1
//--- the Upper-Middle plot
#property indicator_label4  "Upper-Middle"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrRed
#property indicator_style4  STYLE_DOT
#property indicator_width4  1
//--- the Lower-Middle plot
#property indicator_label5  "Lower-Middle"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrBlue
#property indicator_style5  STYLE_DOT
#property indicator_width5  1
//+------------------------------------------------------------------+
//| Enumeration of the methods of handle creation                    |
//+------------------------------------------------------------------+
enum Creation
  {
   Call_iBands,            // use iBands
   Call_IndicatorCreate    // use IndicatorCreate
  };
//--- input parameters
input Creation             type=Call_iBands;          // type of the function 
input int                  bands_period=20;           // period of moving average
input int                  bands_shift=0;             // shift
input double               deviation=2.0;             // number of standard deviations 
input ENUM_APPLIED_PRICE   applied_price=PRICE_CLOSE; // type of price
input string               symbol=" ";                // symbol 
input ENUM_TIMEFRAMES      period=PERIOD_CURRENT;     // timeframe
//--- indicator buffers
double         UpperBuffer[];
double         LowerBuffer[];
double         MiddleBuffer[];
double         UpperMiddleBuffer[];
double         LowerMiddleBuffer[];
//--- variable for storing the handle of the iBands indicator
int    handle;
//--- variable for storing
string name=symbol;
//--- name of the indicator on a chart
string short_name;
//--- we will keep the number of values in the Bollinger Bands indicator
int    bars_calculated=0;
//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- assignment of arrays to indicator buffers
   SetIndexBuffer(0,UpperBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,LowerBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,MiddleBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,UpperMiddleBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,LowerMiddleBuffer,INDICATOR_DATA);
//--- set shift of each line
   PlotIndexSetInteger(0,PLOT_SHIFT,bands_shift);
   PlotIndexSetInteger(1,PLOT_SHIFT,bands_shift);      
   PlotIndexSetInteger(2,PLOT_SHIFT,bands_shift);      
   PlotIndexSetInteger(3,PLOT_SHIFT,bands_shift);      
   PlotIndexSetInteger(4,PLOT_SHIFT,bands_shift);      
//--- determine the symbol the indicator is drawn for
   name=symbol;
//--- delete spaces to the right and to the left
   StringTrimRight(name);
   StringTrimLeft(name);
//--- if it results in zero length of the 'name' string
   if(StringLen(name)==0)
     {
      //--- take the symbol of the chart the indicator is attached to
      name=_Symbol;
     }
//--- create handle of the indicator
   if(type==Call_iBands)
      handle=iBands(name,period,bands_period,bands_shift,deviation,applied_price);
   else
     {
      //--- fill the structure with parameters of the indicator
      MqlParam pars[4];
      //--- period of ma
      pars[0].type=TYPE_INT;
      pars[0].integer_value=bands_period;
      //--- shift
      pars[1].type=TYPE_INT;
      pars[1].integer_value=bands_shift;
      //--- number of standard deviation
      pars[2].type=TYPE_DOUBLE;
      pars[2].double_value=deviation;
      //--- type of price
      pars[3].type=TYPE_INT;
      pars[3].integer_value=applied_price;
      handle=IndicatorCreate(name,period,IND_BANDS,4,pars);
     }
//--- if the handle is not created
   if(handle==INVALID_HANDLE)
     {
      //--- tell about the failure and output the error code
      PrintFormat("Failed to create handle of the iBands indicator for the symbol %s/%s, error code %d",
                  name,
                  EnumToString(period),
                  GetLastError());
      //--- the indicator is stopped early
      return(INIT_FAILED);
     }
//--- show the symbol/timeframe the Bollinger Bands indicator is calculated for
   short_name=StringFormat("iBands(%s/%s, %d,%d,%G,%s)",name,EnumToString(period),
                           bands_period,bands_shift,deviation,EnumToString(applied_price));
   IndicatorSetString(INDICATOR_SHORTNAME,short_name);
//--- normal initialization of the indicator  
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
//--- number of values copied from the iBands indicator
   int values_to_copy;
//--- determine the number of values calculated in the indicator
   int calculated=BarsCalculated(handle);
   if(calculated<=0)
     {
      PrintFormat("BarsCalculated() returned %d, error code %d",calculated,GetLastError());
      return(0);
     }
//--- if it is the first start of calculation of the indicator or if the number of values in the iBands indicator changed
//---or if it is necessary to calculated the indicator for two or more bars (it means something has changed in the price history)
   if(prev_calculated==0 || calculated!=bars_calculated || rates_total>prev_calculated+1)
     {
      //--- if the size of indicator buffers is greater than the number of values in the iBands indicator for symbol/period, then we don't copy everything 
      //--- otherwise, we copy less than the size of indicator buffers
      if(calculated>rates_total) values_to_copy=rates_total;
      else                       values_to_copy=calculated;
     }
   else
     {
      //--- it means that it's not the first time of the indicator calculation, and since the last call of OnCalculate()
      //--- for calculation not more than one bar is added
      values_to_copy=(rates_total-prev_calculated)+1;
     }
//--- fill the array with values of the Bollinger Bands indicator
//--- if FillArraysFromBuffer returns false, it means the information is nor ready yet, quit operation
   if(!FillArraysFromBuffers(MiddleBuffer,UpperBuffer,LowerBuffer,UpperMiddleBuffer,LowerMiddleBuffer,bands_shift,handle,values_to_copy)) return(0);
//--- form the message
   string comm=StringFormat("%s ==>  Updated value in the indicator %s: %d",
                            TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                            short_name,
                            values_to_copy);
//--- display the service message on the chart
   Comment(comm);
//--- memorize the number of values in the Bollinger Bands indicator
   bars_calculated=calculated;
//--- return the prev_calculated value for the next call
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Filling indicator buffers from the iBands indicator              |
//+------------------------------------------------------------------+
bool FillArraysFromBuffers(double &base_values[],     // indicator buffer of the middle line of Bollinger Bands
                           double &upper_values[],    // indicator buffer of the upper border
                           double &lower_values[],    // indicator buffer of the lower border
                           double &upper_middle_values[], // indicator buffer of the upper-middle line
                           double &lower_middle_values[], // indicator buffer of the lower-middle line
                           int shift,                 // shift
                           int ind_handle,            // handle of the iBands indicator
                           int amount                 // number of copied values
                           )
  {
//--- reset error code
   ResetLastError();
//--- fill a part of the MiddleBuffer array with values from the indicator buffer that has 0 index
   if(CopyBuffer(ind_handle,0,-shift,amount,base_values)<0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the iBands indicator, error code %d",GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return(false);
     }
 
//--- fill a part of the UpperBuffer array with values from the indicator buffer that has index 1
   if(CopyBuffer(ind_handle,1,-shift,amount,upper_values)<0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the iBands indicator, error code %d",GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return(false);
     }
 
//--- fill a part of the LowerBuffer array with values from the indicator buffer that has index 2
   if(CopyBuffer(ind_handle,2,-shift,amount,lower_values)<0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the iBands indicator, error code %d",GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return(false);
     }
 
//--- calculate the upper-middle and lower-middle lines
   for(int i=0; i<amount; i++)
     {
      upper_middle_values[i] = (upper_values[i] + base_values[i]) / 2.0;
      lower_middle_values[i] = (lower_values[i] + base_values[i]) / 2.0;
     }
 
//--- everything is fine
   return(true);
  }
//+------------------------------------------------------------------+
//| Indicator deinitialization function                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handle!=INVALID_HANDLE)
      IndicatorRelease(handle);
//--- clear the chart after deleting the indicator
   Comment("");
  }