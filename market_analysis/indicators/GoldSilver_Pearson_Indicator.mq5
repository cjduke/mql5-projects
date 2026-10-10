//+------------------------------------------------------------------+
//|                   GoldSilver_Pearson_Indicator.mq5               |
//|                   Gold-Silver Ratio Analysis                     |
//|                   Pearson Correlation Indicator                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader"
#property description "Gold-Silver Pearson Correlation Indicator"
#property description "Displays rolling Pearson correlation between gold and silver"
#property description "For relative-value analysis and article visuals"

#property indicator_separate_window
#property indicator_buffers 1
#property indicator_plots 1

//--- Plot: rolling Pearson correlation
#property indicator_label1  "Pearson Correlation"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_level1 0.20


//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input string InpGoldSymbol        = "XAUUSD";        // Gold symbol
input string InpSilverSymbol      = "XAGUSD";        // Silver symbol
input int    InpCorrelationPeriod = 20;              // Correlation lookback


//+------------------------------------------------------------------+
//| Indicator buffers                                                |
//+------------------------------------------------------------------+
double CorrelationBuffer[];


//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Ensure both analysis symbols are available to the terminal.
   if(!SymbolSelect(InpGoldSymbol, true) || !SymbolSelect(InpSilverSymbol, true))
     {
      Print("ERROR: Cannot find symbols: ", InpGoldSymbol, " / ", InpSilverSymbol);
      Print("Please check Market Watch (Ctrl+M) and use the exact broker symbol names.");
      return(INIT_FAILED);
     }

   SetIndexBuffer(0, CorrelationBuffer, INDICATOR_DATA);
   PlotIndexSetString(0, PLOT_LABEL, "Pearson Correlation");

   ArraySetAsSeries(CorrelationBuffer, true);

   IndicatorSetString(INDICATOR_SHORTNAME, "Gold-Silver Correlation");
   IndicatorSetInteger(INDICATOR_DIGITS, 3);
   IndicatorSetDouble(INDICATOR_MINIMUM, -1.0);
   IndicatorSetDouble(INDICATOR_MAXIMUM, 1.0);

   PlotIndexSetString(0, PLOT_LABEL, "Pearson Indicator");
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
   if(rates_total < InpCorrelationPeriod + 10)
      return(0);

   // Explicitly use timeseries indexing for the price arrays.
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);
   ArraySetAsSeries(volume, true);
   ArraySetAsSeries(spread, true);

   // Recalculate the displayed correlation values.
   ArrayInitialize(CorrelationBuffer, 0.0);

   // With series indexing:
   //   0              = newest bar
   //   rates_total-1  = oldest bar
   //
   // Calculate from older bars toward newer bars so that each value is
   // derived from the historical data available at that bar position.
   int start = rates_total - InpCorrelationPeriod - 1;

   for(int i = start; i >= 0; i--)
     {
      CorrelationBuffer[i] = CalculatePearsonAtBar(i);
     }

   return(rates_total);
  }


//+------------------------------------------------------------------+
//| Calculate Pearson correlation at a specified bar                 |
//+------------------------------------------------------------------+
double CalculatePearsonAtBar(int barIndex)
  {
   int goldBars   = Bars(InpGoldSymbol, PERIOD_CURRENT);
   int silverBars = Bars(InpSilverSymbol, PERIOD_CURRENT);
   int availableBars = MathMin(goldBars, silverBars);

   if(barIndex < 0 || barIndex + InpCorrelationPeriod >= availableBars)
      return 0.0;

   double rx[], ry[];
   ArrayResize(rx, InpCorrelationPeriod);
   ArrayResize(ry, InpCorrelationPeriod);

   // Build paired percentage-return series for gold and silver.
   for(int i = 0; i < InpCorrelationPeriod; i++)
     {
      double g0 = iClose(InpGoldSymbol, PERIOD_CURRENT, barIndex + i);
      double g1 = iClose(InpGoldSymbol, PERIOD_CURRENT, barIndex + i + 1);
      double s0 = iClose(InpSilverSymbol, PERIOD_CURRENT, barIndex + i);
      double s1 = iClose(InpSilverSymbol, PERIOD_CURRENT, barIndex + i + 1);

      if(g0 <= 0 || g1 <= 0 || s0 <= 0 || s1 <= 0)
        {
         rx[i] = 0;
         ry[i] = 0;
         continue;
        }

      rx[i] = (g1 - g0) / g0;
      ry[i] = (s1 - s0) / s0;
     }

   return PearsonCore(rx, ry);
  }


//+------------------------------------------------------------------+
//| Calculate Pearson correlation from two return arrays             |
//+------------------------------------------------------------------+
double PearsonCore(const double &x[], const double &y[])
  {
   int n = ArraySize(x);
   double mx = 0, my = 0;
   int cnt = 0;

   // Calculate the mean of the valid paired observations.
   for(int i = 0; i < n; i++)
     {
      if(x[i] != 0 && y[i] != 0)
        {
         mx += x[i];
         my += y[i];
         cnt++;
        }
     }

   if(cnt < 5)
      return 0;

   mx /= cnt;
   my /= cnt;

   double cov = 0, vx = 0, vy = 0;

   // Calculate covariance and the two variance terms used by Pearson's r.
   for(int i = 0; i < n; i++)
     {
      if(x[i] == 0 || y[i] == 0)
         continue;

      cov += (x[i] - mx) * (y[i] - my);
      vx  += (x[i] - mx) * (x[i] - mx);
      vy  += (y[i] - my) * (y[i] - my);
     }

   if(vx == 0 || vy == 0)
      return 0;

   return cov / (MathSqrt(vx) * MathSqrt(vy));
  }


//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("Gold-Silver Correlation Indicator removed.");
  }
//+------------------------------------------------------------------+
