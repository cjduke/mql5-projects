//+------------------------------------------------------------------+
//| GoldSilver_Master_Indicator.mq5                                  |
//| Gold/Silver ratio and rolling percentile analysis with Pearson  |
//| correlation displayed in a subordinate chart subwindow.         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader"
#property description "GoldSilver_Master_Indicator Indicator"
#property description "Gold/Silver ratio and rolling percentile analysis with Pearson."
#property description "correlation displayed in a subordinate chart subwindow."
#property strict

#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "Gold/Silver Ratio"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

#property indicator_label2  "Upper Extreme (80%)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#property indicator_label3  "Lower Exit (60%)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrLimeGreen
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

input string InpGoldSymbol        = "XAUUSD";
input string InpSilverSymbol      = "XAGUSD";
input int    InpRatioPeriod       = 50;
input double InpUpperPercentile   = 80.0;
input double InpLowerPercentile   = 60.0;
input int    InpCorrelationPeriod = 20;

double RatioBuffer[];
double UpperBandBuffer[];
double LowerBandBuffer[];

int PearsonHandle = INVALID_HANDLE;
int PearsonWindow = -1;

const string PearsonShortName = "Gold-Silver Correlation";

//+------------------------------------------------------------------+
//| Calculate a rolling percentile of the Gold/Silver ratio.         |
//| The current bar is excluded; only preceding observations are    |
//| used so the calculation does not introduce look-ahead bias.     |
//+------------------------------------------------------------------+
double GetPercentileValue(const double percentile,const int barIndex)
{
   double values[];
   ArrayResize(values,InpRatioPeriod);

   int count=0;

   for(int i=1;i<=InpRatioPeriod;i++)
   {
      const int shift=barIndex+i;
      const double gold=iClose(InpGoldSymbol,PERIOD_CURRENT,shift);
      const double silver=iClose(InpSilverSymbol,PERIOD_CURRENT,shift);

      if(gold<=0.0 || silver<=0.0)
         continue;

      values[count]=gold/silver;
      count++;
   }

   if(count<10)
      return(0.0);

   ArrayResize(values,count);
   ArraySort(values);

   int index=(int)(percentile/100.0*count);

   if(index>=count)
      index=count-1;

   if(index<0)
      index=0;

   return(values[index]);
}

//+------------------------------------------------------------------+
//| Release the Pearson indicator instance created by this master.  |
//| This removes the visual subwindow instance and releases its      |
//| indicator handle.                                                |
//+------------------------------------------------------------------+
void ReleasePearson()
{
   if(PearsonWindow>=0)
   {
      ResetLastError();

      if(!ChartIndicatorDelete(0,PearsonWindow,PearsonShortName))
      {
         Print("WARNING: Could not delete Pearson indicator from subwindow ",
               PearsonWindow,
               ". Error = ",GetLastError());
      }
      else
      {
         PrintFormat("Pearson indicator removed from subwindow %d",
                     PearsonWindow);
      }

      PearsonWindow=-1;
   }

   if(PearsonHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(PearsonHandle);
      PearsonHandle=INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Initialise buffers and create the subordinate Pearson indicator. |
//| The Pearson indicator is added to the next available chart       |
//| subwindow while the ratio and percentile bands remain in the    |
//| master's own indicator window.                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0,RatioBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,UpperBandBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,LowerBandBuffer,INDICATOR_DATA);

   ArraySetAsSeries(RatioBuffer,true);
   ArraySetAsSeries(UpperBandBuffer,true);
   ArraySetAsSeries(LowerBandBuffer,true);

   IndicatorSetString(INDICATOR_SHORTNAME,"Gold/Silver Master");

   // Create the subordinate Pearson indicator on the chart symbol and timeframe.
   ResetLastError();

   PearsonHandle=iCustom(ChartSymbol(0),
                          ChartPeriod(0),
                          "GoldSilver_Pearson_Indicator_v1.05",
                          InpGoldSymbol,
                          InpSilverSymbol,
                          InpCorrelationPeriod);

   if(PearsonHandle==INVALID_HANDLE)
   {
      Print("WARNING: Could not create Pearson indicator handle. Error = ",
            GetLastError());

      // The ratio master remains usable without the visual Pearson window.
      return(INIT_SUCCEEDED);
   }

   // Add the subordinate indicator to the next available chart
   // subwindow. The handle is retained for lifecycle management.
   const int subwindow=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL);

   ResetLastError();

   if(!ChartIndicatorAdd(0,subwindow,PearsonHandle))
   {
      const int error=GetLastError();

      Print("WARNING: Could not add Pearson indicator to chart. Error = ",
            error);

      IndicatorRelease(PearsonHandle);
      PearsonHandle=INVALID_HANDLE;
   }
   else
   {
      PearsonWindow=subwindow;

      PrintFormat("Pearson indicator added successfully to subwindow %d",
                  PearsonWindow);
   }

   ChartRedraw(0);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Calculate the Gold/Silver ratio and its rolling percentile bands. |
//| The percentile function uses only bars preceding each evaluated  |
//| bar, keeping the historical calculation free of look-ahead.     |
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
   if(rates_total<InpRatioPeriod+10)
      return(0);

   ArraySetAsSeries(RatioBuffer,true);
   ArraySetAsSeries(UpperBandBuffer,true);
   ArraySetAsSeries(LowerBandBuffer,true);

   ArrayInitialize(RatioBuffer,0.0);
   ArrayInitialize(UpperBandBuffer,0.0);
   ArrayInitialize(LowerBandBuffer,0.0);

   const int start=rates_total-InpRatioPeriod;

   for(int i=start;i>=0;i--)
   {
      const double gold=iClose(InpGoldSymbol,PERIOD_CURRENT,i);
      const double silver=iClose(InpSilverSymbol,PERIOD_CURRENT,i);

      if(gold<=0.0 || silver<=0.0)
         continue;

      RatioBuffer[i]=gold/silver;
      UpperBandBuffer[i]=GetPercentileValue(InpUpperPercentile,i);
      LowerBandBuffer[i]=GetPercentileValue(InpLowerPercentile,i);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Remove the subordinate Pearson indicator and release resources.  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ReleasePearson();
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
