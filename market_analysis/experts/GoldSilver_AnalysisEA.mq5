//+------------------------------------------------------------------+
//| GoldSilver_AnalysisEA.mq5                                        |
//| Gold-Silver Ratio Analysis EA                                   |
//| Companion tool for "The Silver Catch-Up"                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader"
#property description "Gold-Silver Ratio Analysis EA (analysis only)"
#property description "Displays ratio, rolling percentile bands, Pearson correlation,"
#property description "and illustrative signal annotations inside the Strategy Tester."
#property description "Places no trades. Signals shown are historical illustrations"
#property description "of the ratio-divergence pattern, not tradeable in real time."

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input string InpGoldSymbol        = "XAUUSD";   // Gold instrument
input string InpSilverSymbol      = "XAGUSD";   // Silver instrument
input int    InpRatioPeriod       = 50;         // Lookback for rolling percentile bands (bars)
input int    InpCorrelationPeriod = 20;         // Lookback for Pearson correlation (bars)
input double InpUpperPercentile   = 80.0;       // Upper percentile threshold
input double InpLowerPercentile   = 60.0;       // Lower percentile threshold
input double InpLowCorrelation    = 0.18;       // Pearson decoupling threshold
input int    InpMinLowCorrBars    = 5;          // Required consecutive low-correlation bars

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                     |
//+------------------------------------------------------------------+
datetime lastBarTime = 0;
bool     symbolsOk   = false;

struct SignalRecord
  {
   datetime          time;
   int               type;         // 1 = entry, -1 = exit
   double            ratio;
   double            silverPrice;
   double            profit;       // % change in silver price between entry and exit
  };

SignalRecord signals[];

//+------------------------------------------------------------------+
//| Initialise the analysis state and verify the configured symbols. |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!SymbolSelect(InpGoldSymbol, true) || !SymbolSelect(InpSilverSymbol, true))
     {
      symbolsOk = false;
      Comment("ERROR: Cannot find symbols:\n  " + InpGoldSymbol +
              "\n  " + InpSilverSymbol +
              "\n\nCheck Market Watch (Ctrl+M) and use exact broker symbol names.");
      return(INIT_SUCCEEDED);
     }

   if(SymbolInfoDouble(InpGoldSymbol,   SYMBOL_BID) <= 0.0 ||
      SymbolInfoDouble(InpSilverSymbol, SYMBOL_BID) <= 0.0)
     {
      symbolsOk = false;
      Comment("ERROR: No price data for:\n  " + InpGoldSymbol +
              "\n  " + InpSilverSymbol);
      return(INIT_SUCCEEDED);
     }

   symbolsOk = true;
   ArrayResize(signals, 0);

   Comment("Gold-Silver Ratio EA ready.\nWaiting for first bar...");
   Print("Gold-Silver Ratio EA initialised. Symbols: ",
         InpGoldSymbol, " / ", InpSilverSymbol);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Rebuild the analysis once per newly formed chart bar.            |
//| The EA does not place or manage trades.                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!symbolsOk)
      return;

   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;

   int totalBars = Bars(_Symbol, PERIOD_CURRENT);
   if(totalBars < InpRatioPeriod + InpCorrelationPeriod + 10)
      return;

// Use the common history length available for both instruments.
   int goldBars      = Bars(InpGoldSymbol,   PERIOD_CURRENT);
   int silverBars    = Bars(InpSilverSymbol, PERIOD_CURRENT);
   int availableBars = MathMin(goldBars, silverBars);

// Rebuild the historical signal list from scratch on each new bar.
   ArrayResize(signals, 0);

   bool inStretchedZone   = false;
   int  consecutiveLowCorr = 0;

// Process the history from oldest to newest so the signal state
   // evolves in chronological order.
   for(int i = totalBars - 1; i >= 0; i--)
     {
      double gold   = iClose(InpGoldSymbol,   PERIOD_CURRENT, i);
      double silver = iClose(InpSilverSymbol, PERIOD_CURRENT, i);

      if(gold <= 0.0 || silver <= 0.0)
         continue;

      double ratio = gold / silver;
      double upper = GetPercentileValue(InpUpperPercentile, i, availableBars);
      double lower = GetPercentileValue(InpLowerPercentile, i, availableBars);
      double corr  = CalculatePearsonAtBar(i, availableBars);

      if(upper <= 0.0 || lower <= 0.0)
         continue;

      bool isLowCorr   = (corr < InpLowCorrelation);
      bool isStretched = (ratio > upper);
      bool isNormal    = (ratio < lower);

      if(isLowCorr)
         consecutiveLowCorr++;
      else
         consecutiveLowCorr = 0;

      datetime barTime = iTime(_Symbol, PERIOD_CURRENT, i);

      // ENTRY: the ratio is above its upper rolling percentile and
      // Pearson correlation has remained below the decoupling
      // threshold for the required number of consecutive bars.
      if(!inStretchedZone && isLowCorr && isStretched &&
         consecutiveLowCorr >= InpMinLowCorrBars)
        {
         inStretchedZone = true;
         int idx = ArraySize(signals);
         ArrayResize(signals, idx + 1);
         signals[idx].time        = barTime;
         signals[idx].type        = 1;
         signals[idx].ratio       = ratio;
         signals[idx].silverPrice = silver;
         signals[idx].profit      = 0.0;
        }

      // EXIT: the ratio has returned below the lower rolling percentile.
      if(inStretchedZone && isNormal)
        {
         inStretchedZone = false;
         int idx = ArraySize(signals);
         ArrayResize(signals, idx + 1);
         signals[idx].time        = barTime;
         signals[idx].type        = -1;
         signals[idx].ratio       = ratio;
         signals[idx].silverPrice = silver;
         signals[idx].profit      = CalculateSignalReturn(idx);
        }
     }

   UpdateChartComment();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Calculate a rolling ratio percentile from preceding bars only.   |
//| Excluding the current bar avoids look-ahead in the historical    |
//| analysis.                                                        |
//+------------------------------------------------------------------+
double GetPercentileValue(double percentile, int barIndex, int availableBars)
  {
   if(barIndex < 0 || barIndex + InpRatioPeriod >= availableBars)
      return 0.0;

   double values[];
   ArrayResize(values, InpRatioPeriod);

   int count = 0;
   for(int i = 1; i <= InpRatioPeriod; i++)
     {
      int shift = barIndex + i;
      if(shift < 0)
         continue;

      double gold   = iClose(InpGoldSymbol,   PERIOD_CURRENT, shift);
      double silver = iClose(InpSilverSymbol, PERIOD_CURRENT, shift);

      if(gold <= 0.0 || silver <= 0.0)
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
//| Calculate Pearson correlation from Gold and Silver returns.      |
//| The current bar is excluded from the observation window.        |
//+------------------------------------------------------------------+
double CalculatePearsonAtBar(int barIndex, int availableBars)
  {
   if(barIndex < 0 || barIndex + InpCorrelationPeriod + 1 >= availableBars)
      return 0.0;

   double rx[], ry[];
   ArrayResize(rx, InpCorrelationPeriod);
   ArrayResize(ry, InpCorrelationPeriod);

   for(int i = 0; i < InpCorrelationPeriod; i++)
     {
      double g0 = iClose(InpGoldSymbol,   PERIOD_CURRENT, barIndex + i);
      double g1 = iClose(InpGoldSymbol,   PERIOD_CURRENT, barIndex + i + 1);
      double s0 = iClose(InpSilverSymbol, PERIOD_CURRENT, barIndex + i);
      double s1 = iClose(InpSilverSymbol, PERIOD_CURRENT, barIndex + i + 1);

      if(g0 <= 0.0 || g1 <= 0.0 || s0 <= 0.0 || s1 <= 0.0)
        {
         rx[i] = 0.0;
         ry[i] = 0.0;
         continue;
        }

      rx[i] = (g1 - g0) / g0;
      ry[i] = (s1 - s0) / s0;
     }

   return PearsonCore(rx, ry);
  }

//+------------------------------------------------------------------+
//| Calculate the Pearson correlation coefficient for two return     |
//| arrays, using only observations with non-zero values.            |
//+------------------------------------------------------------------+
double PearsonCore(const double &x[], const double &y[])
  {
   int n = ArraySize(x);
   double mx = 0.0, my = 0.0;
   int cnt = 0;

   for(int i = 0; i < n; i++)
     {
      if(x[i] != 0.0 && y[i] != 0.0)
        {
         mx += x[i];
         my += y[i];
         cnt++;
        }
     }

   if(cnt < 5)
      return 0.0;

   mx /= cnt;
   my /= cnt;

   double cov = 0.0, vx = 0.0, vy = 0.0;

   for(int i = 0; i < n; i++)
     {
      if(x[i] == 0.0 || y[i] == 0.0)
         continue;

      cov += (x[i] - mx) * (y[i] - my);
      vx  += (x[i] - mx) * (x[i] - mx);
      vy  += (y[i] - my) * (y[i] - my);
     }

   if(vx == 0.0 || vy == 0.0)
      return 0.0;

   return cov / (MathSqrt(vx) * MathSqrt(vy));
  }

//+------------------------------------------------------------------+
//| Calculate the illustrative Silver return between a recorded      |
//| entry and its matching exit.                                     |
//+------------------------------------------------------------------+
double CalculateSignalReturn(int signalIndex)
  {
   if(signalIndex < 1)
      return 0.0;

   for(int i = signalIndex - 1; i >= 0; i--)
     {
      if(signals[i].type == 1)
        {
         double entry = signals[i].silverPrice;
         double exit  = signals[signalIndex].silverPrice;

         if(entry > 0.0 && exit > 0.0)
            return ((exit - entry) / entry) * 100.0;

         break;
        }
     }

   return 0.0;
  }

//+------------------------------------------------------------------+
//| Build the on-chart analysis summary and recent signal history.   |
//+------------------------------------------------------------------+
void UpdateChartComment()
  {
// Latest values
   double currentRatio = iClose(InpGoldSymbol,   PERIOD_CURRENT, 0) /
                         iClose(InpSilverSymbol, PERIOD_CURRENT, 0);

   double currentCorr = correlationAtCurrentBar();

   string comment = "═══════ GOLD-SILVER RATIO ANALYSIS ═══════\n";
   comment += "Last bar:              " + TimeToString(lastBarTime) + "\n";
   comment += "Current ratio:         " + DoubleToString(currentRatio, 2) + "\n";
   comment += "Correlation (Pearson): " + DoubleToString(currentCorr, 3) + "\n";
   comment += "Total signal events:   " + (string)ArraySize(signals) + "\n";

   int entries = 0, exits = 0, wins = 0, losses = 0;
   double totalReturn = 0.0;

   for(int i = 0; i < ArraySize(signals); i++)
     {
      if(signals[i].type == 1)
         entries++;
      else
        {
         exits++;
         totalReturn += signals[i].profit;

         if(signals[i].profit > 0.0)
            wins++;
         else
            if(signals[i].profit < 0.0)
               losses++;
        }
     }

   double winRate = 0.0;
   if(exits > 0)
      winRate = (double)wins / exits * 100.0;

   double avgReturn = 0.0;
   if(exits > 0)
      avgReturn = totalReturn / exits;

   double compounded = 1.0;
   for(int i = 0; i < ArraySize(signals); i++)
     {
      if(signals[i].type == -1)
         compounded *= (1.0 + signals[i].profit / 100.0);
     }
   compounded = (compounded - 1.0) * 100.0;

   comment += "\n--- ILLUSTRATIVE RESULTS (signal-to-signal) ---\n";
   comment += "Entries:              " + (string)entries + "\n";
   comment += "Exits:                " + (string)exits + "\n";
   comment += "Winning exits:        " + (string)wins + "\n";
   comment += "Losing exits:         " + (string)losses + "\n";
   comment += "Win rate:             " + DoubleToString(winRate, 1) + "%\n";
   comment += "Sum of returns:       " + DoubleToString(totalReturn, 2) + "%\n";
   comment += "Average per exit:     " + DoubleToString(avgReturn, 2) + "%\n";
   comment += "Compounded:           " + DoubleToString(compounded, 2) + "%\n";

   comment += "\n--- SIGNAL HISTORY (last 10) ---\n";
   int start = MathMax(0, ArraySize(signals) - 10);
   for(int i = start; i < ArraySize(signals); i++)
     {
      string tag = (signals[i].type == 1) ? "ENTRY" : "EXIT ";
      comment += TimeToString(signals[i].time) + "  " + tag;
      comment += "  ratio=" + DoubleToString(signals[i].ratio, 2);
      if(signals[i].type == -1)
         comment += "  return=" + DoubleToString(signals[i].profit, 1) + "%";
      comment += "\n";
     }

   comment += "═══════════════════════════════════════════\n";
   comment += "Illustrative signals only — based on historical\n";
   comment += "ratio divergence, not tradeable in real time.";

   Comment(comment);
  }

//+------------------------------------------------------------------+
//| Calculate Pearson correlation for the most recent closed bar.    |
//+------------------------------------------------------------------+
double correlationAtCurrentBar()
  {
   int goldBars      = Bars(InpGoldSymbol,   PERIOD_CURRENT);
   int silverBars    = Bars(InpSilverSymbol, PERIOD_CURRENT);
   int availableBars = MathMin(goldBars, silverBars);

   return CalculatePearsonAtBar(1, availableBars);
  }

//+------------------------------------------------------------------+
//| Clear the analysis display when the EA is removed.               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
   Print("Gold-Silver Ratio EA removed. Reason: ", reason);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
