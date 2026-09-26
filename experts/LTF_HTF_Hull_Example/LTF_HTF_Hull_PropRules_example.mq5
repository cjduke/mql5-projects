//+------------------------------------------------------------------+
//|                              LTF_HTF_Hull_PropRules_example.mq5  |
//|  v1.00 – LTF -> HTF approach (responsive entry, HTF context)     |
//+------------------------------------------------------------------+
//|  STRATEGY OVERVIEW                                               |
//|  -----------------                                               |
//|  A low-timeframe entry system that only fires when a stack of    |
//|  higher-timeframe Hull MA conditions are all aligned in the      |
//|  same direction. Built around prop-firm style risk rules.        |
//|                                                                  |
//|  PERSISTENT FLAGS (set once, reset if invalidated)               |
//|                                                                  |
//|    H1 HMA200 Flag  (context / trend anchor)                      |
//|       BUY : Price > HMA200  AND  HMA200 is GREEN                 |
//|       SELL: Price < HMA200  AND  HMA200 is RED                   |
//|                                                                  |
//|    H4 Structure Flag  (medium-term trend)                        |
//|       BUY : HMA20 > HMA50  AND  HMA50 is GREEN                   |
//|       SELL: HMA20 < HMA50  AND  HMA50 is RED                     |
//|                                                                  |
//|    D1 HMA8 Flag  (higher-timeframe direction)                    |
//|       BUY : D1 HMA8 is GREEN                                     |
//|       SELL: D1 HMA8 is RED                                       |
//|                                                                  |
//|    RSI Entry Flag  (H1 RSI period 3)                             |
//|       BUY : RSI < 45                                             |
//|       SELL: RSI > 55                                             |
//|                                                                  |
//|  ENTRY CONDITIONS                                                |
//|    All four flags must be SET and all must agree on direction.   |
//|    Additionally, on H1 the following stack must hold:            |
//|                                                                  |
//|       BUY : Price > HMA8 > HMA20 > HMA50   (all GREEN)           |
//|       SELL: Price < HMA8 < HMA20 < HMA50   (all RED)             |
//|                                                                  |
//|    If any flag flips against the others, AlignFlags() resets     |
//|    the conflicting flags so the setup must rebuild cleanly.      |
//|                                                                  |
//|  RISK & EXITS                                                    |
//|    - Stop Loss   = 3.0 x H1 ATR(14)                              |
//|    - Target      = 1 : 1 R:R  (TargetRatio = 1.0)                |
//|    - Risk per trade = 0.90% of account balance (auto lot).       |
//|    - Fixed-lot and lot-fallback options available.               |
//|                                                                  |
//|  ALTERNATIVE EXIT                                                |
//|    - BUY  closes if Price crosses below H1 HMA200.               |
//|    - SELL closes if Price crosses above H1 HMA200.               |
//|    - Whichever hits first: Target (1:1) or HMA200 cross.         |
//|                                                                  |
//|  PROP-FIRM / GOAT FUNDED RULES                                   |
//|    - Profit target % (default 4.0%) -> force-close + suspend.    |
//|    - Max total drawdown % (default 8.0%) -> force-close + stop.  |
//|    - Optional daily drawdown limit (default off).                |
//|    - Optional minimum valid trading days tracking.               |
//|    - Optional funded-phase flag.                                 |
//|    - Daily kill-switch re-enables trading after temporary        |
//|      suspensions on a new calendar day.                          |
//|                                                                  |
//|  TRADE LIFECYCLE                                                 |
//|    - Max 2 trades per session (MaxTrades).                       |
//|    - All flags are reset after each trade is opened.             |
//|    - External closes and partial closes are detected in          |
//|      OnTradeTransaction and reconciled.                          |
//|    - When MaxTrades reached -> permanent suspension.             |
//|                                                                  |
//|  INDICATORS USED                                                 |
//|    - UnifiedHullMA  (D1: 8/20/50/200, H4: 8/20/50/200,          |
//|                       H1: 8/20/50/200)                           |
//|    - iRSI           (H1, period 3)                               |
//|    - iATR           (H1, period 14)                              |
//|                                                                  |
//|  NOTE: UnifiedHullMA buffer layout ->                             |
//|        0/1 = HMA8  value/color                                   |
//|        2/3 = HMA20 value/color                                   |
//|        4/5 = HMA50 value/color                                   |
//|        6/7 = HMA200 value/color                                  |
//|        Colors: 0 = Gray, 1 = Green, 2 = Red.                     |
//|                                                                  |
//|  LOGGING                                                         |
//|    - CSV log written to Common\Files as LTF_Log_YYYYMMDD.csv     |
//|      (open, close, partial close, suspensions, rule triggers).   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  EDUCATIONAL EXAMPLE - NOT A TRADING SYSTEM                      |
//|                                                                  |
//|  This file is a reference implementation. It shows how to build  |
//|  a lower-timeframe-to-higher-timeframe system in MQL5:           |
//|  persistent per-timeframe flags, direction alignment, and a      |
//|  prop-firm risk layer with daily and total drawdown limits.      |
//|                                                                  |
//|  It is not intended as a deployable strategy. It makes no        |
//|  performance claims. Use it as code to learn from, not as        |
//|  something to run on a live account.                             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader"
#property version   "1.00"
#property description "Multi-timeframe mean-reversion EA using LTF -> HTF approach."
#property description "H1 HMA200 anchor, H4 structure, D1 colour filter, H1 RSI entry."
#property description "Prop-firm risk rules, CSV logging. Requires UnifiedHullMA."
#property description "Example: LTF-to-HTF Hull system (H1 anchor, H4/D1 context)."
#property description "Demonstrates persistent flags, direction alignment, prop rules."
#property description "Educational reference only - not a complete trading system."
#property description "Requires the UnifiedHullMA indicator."
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- RSI inputs (H1 RSI, period 3)
input int      H1_RSI_Period       = 3;
input int      H1_RSI_BuyThreshold = 45;    // RSI < 45 for BUY entry
input int      H1_RSI_SellThreshold = 55;   // RSI > 55 for SELL entry

//--- Hull Periods
input int      D1_HMA8_Period      = 8;
input int      H4_HMA8_Period      = 8;
input int      H4_HMA20_Period     = 20;
input int      H4_HMA50_Period     = 50;
input int      H1_HMA8_Period      = 8;
input int      H1_HMA20_Period     = 20;
input int      H1_HMA50_Period     = 50;
input int      H1_HMA200_Period    = 200;

//--- Target and Risk
input double   TargetRatio         = 1.0;
input double   TradeRiskPercent    = 0.90;
input double   StopMultiplier      = 3.0;

//--- Max trades
input int      MaxTrades           = 2;

//--- Trading Settings
input bool     EnableTrading        = true;
input int      MagicNumber          = 20250701;
input int      Slippage             = 30;

//--- Lot Sizing
input bool     UseFixedLot          = false;
input double   FixedLotSize         = 0.04;
input bool     UseLotFallback       = true;
input double   MinimumRiskLot       = 0.02;
input double   LotFallbackSize      = 0.04;

//--- ATR
input int      ATRPeriod            = 14;

//--- Goat Funded rules
input double   InpProfitTargetPercent   = 4.0;
input double   InpMaxTotalDrawdown      = 8.0;
input double   InpDailyDrawdownLimit    = 0.0;
input int      InpMinValidTradingDays   = 0;
input bool     InpIsFundedPhase         = false;

//--- Debug
input bool     PrintDebug          = false;

//--- Indicator handles
int            h1RSIHandle;
int            d1HullHandle;
int            h4HullHandle;
int            h1HullHandle;
int            hATR;

//--- D1 values
double         d1Hull8;
double         d1Color8;

//--- H4 values
double         h4Hull8_now, h4Hull20_now, h4Hull50_now;
double         h4Color8_now, h4Color20_now, h4Color50_now;

//--- H1 values
double         h1Hull8_now, h1Hull20_now, h1Hull50_now, h1Hull200_now;
double         h1Color8_now, h1Color20_now, h1Color50_now, h1Color200_now;
double         h1RSI_now = 50;

//--- Persistent Flags (LTF → HTF)
// H1 Flags
bool           h1HMA200Flag    = false;   // Price > HMA200 AND HMA200 = GREEN (BUY)
int            h1HMA200Direction = 0;     // 1 = BUY, -1 = SELL

// H4 Flags
bool           h4StructureFlag = false;   // HMA20 > HMA50 AND HMA50 = GREEN (BUY)
int            h4StructureDirection = 0;

// D1 Flags
bool           d1HMA8Flag      = false;   // HMA8 = GREEN (BUY)
int            d1HMA8Direction = 0;

// RSI Entry Flag (H1 RSI period 3)
bool           rsiEntryFlag    = false;   // RSI < 45 (BUY) or RSI > 55 (SELL)
int            rsiEntryDirection = 0;

// Combined Entry Flag (all conditions met)
bool           entryReady      = false;
int            entryDirection  = 0;

//--- Trade counter
int            tradeCounter      = 0;

//--- Trade state
int            tradeDirection        = 0;
ulong          tradeTicket           = 0;
double         entryPrice            = 0;
double         initialRisk           = 0;

//--- Goat Funded Tracking
double         dailyStartEquity     = 0;
datetime       lastDayReset         = 0;
datetime       lastAlertTime        = 0;
datetime       lastDateChecked      = 0;
datetime       lastValidDay         = 0;
double         dailyProfit          = 0;
int            validTradeDays       = 0;
bool           profitTargetReached  = false;
double         startingEquity       = 0;
double         totalClosedProfit    = 0;
bool           equityTargetReached  = false;
double         maxProfitAllowed     = 0;
double         highestEquity        = 0;
datetime       currentDay           = 0;

//--- Suspension types
enum ENUM_SUSPENSION_TYPE
  {
   SUSPENSION_NONE = 0,
   SUSPENSION_TEMPORARY = 1,
   SUSPENSION_PERMANENT = 2
  };
ENUM_SUSPENSION_TYPE suspensionType = SUSPENSION_NONE;
string         suspensionReason  = "";

//--- Logging
string         logFileName;
datetime       lastLogDate = 0;

//--- Forward declarations
double GetCurrentATR();
void   CheckTarget(int direction);
void   CheckAlternativeExit(int direction);
bool   OpenTrade(int direction);
double CalculateLotSize(double entryPrice, double stopLoss, double riskPercent);
double NormalizeLot(double lot, string symbol, bool logErrors = true);
void   LogEvent(string eventType, string status, string details);
void   CheckDailyKillSwitch();
void   CheckGoatRules();
void   CheckManualProfitTarget();
void   CheckConsistentTradeDays();
double GetDailyProfit();
void   ForceCloseAllPositions(string reason);
void   UpdateH1HMA200Flag();
void   UpdateH4StructureFlag();
void   UpdateD1HMA8Flag();
void   UpdateRSIEntryFlag();
void   UpdateEntryReady();
void   AlignFlags();
void   ResetFlags();
void   SuspendTrading(string reason, ENUM_SUSPENSION_TYPE type = SUSPENSION_PERMANENT);
void   ProcessExternalClose(double profit, double dealVolume, int closedDirection);
void   CloseEntireTrade(string reason, bool isError = false);
void   ClearTradeState();
bool   IsOurPositionOpen();

//+------------------------------------------------------------------+
//| Suspend trading                                                  |
//+------------------------------------------------------------------+
void SuspendTrading(string reason, ENUM_SUSPENSION_TYPE type = SUSPENSION_PERMANENT)
  {
   if(suspensionType == SUSPENSION_PERMANENT)
      return;
   suspensionType = type;
   suspensionReason = reason;
   if(type == SUSPENSION_PERMANENT)
      Print("*** TRADING PERMANENTLY SUSPENDED: ", reason, " ***");
   else
      Print("*** TRADING SUSPENDED: ", reason, " ***");
   LogEvent("TradingSuspended", reason, type == SUSPENSION_PERMANENT ? "PERMANENT" : "TEMPORARY");
   Alert("Trading suspended: ", reason);
  }

//+------------------------------------------------------------------+
//| Reset flags                                                      |
//+------------------------------------------------------------------+
void ResetFlags()
  {
   if(h1HMA200Flag)
     {
      h1HMA200Flag = false;
      h1HMA200Direction = 0;
     }
   if(h4StructureFlag)
     {
      h4StructureFlag = false;
      h4StructureDirection = 0;
     }
   if(d1HMA8Flag)
     {
      d1HMA8Flag = false;
      d1HMA8Direction = 0;
     }
   if(rsiEntryFlag)
     {
      rsiEntryFlag = false;
      rsiEntryDirection = 0;
     }
   if(entryReady)
     {
      entryReady = false;
      entryDirection = 0;
     }
   if(PrintDebug)
      Print("All flags reset.");
  }

//+------------------------------------------------------------------+
//| Align flags – ensure all directions match                        |
//+------------------------------------------------------------------+
void AlignFlags()
  {
// If any flag direction opposes another, reset everything
   int targetDir = 0;

   if(h1HMA200Flag)
      targetDir = h1HMA200Direction;
   else
      if(h4StructureFlag)
         targetDir = h4StructureDirection;
      else
         if(d1HMA8Flag)
            targetDir = d1HMA8Direction;
         else
            if(rsiEntryFlag)
               targetDir = rsiEntryDirection;
            else
               if(entryReady)
                  targetDir = entryDirection;

   if(targetDir == 0)
      return;

// Check each flag against target direction
   if(h1HMA200Flag && h1HMA200Direction != targetDir)
     {
      if(PrintDebug)
         Print("AlignFlags: H1 HMA200 flag opposes target – resetting");
      h1HMA200Flag = false;
      h1HMA200Direction = 0;
     }
   if(h4StructureFlag && h4StructureDirection != targetDir)
     {
      if(PrintDebug)
         Print("AlignFlags: H4 structure flag opposes target – resetting");
      h4StructureFlag = false;
      h4StructureDirection = 0;
     }
   if(d1HMA8Flag && d1HMA8Direction != targetDir)
     {
      if(PrintDebug)
         Print("AlignFlags: D1 HMA8 flag opposes target – resetting");
      d1HMA8Flag = false;
      d1HMA8Direction = 0;
     }
   if(rsiEntryFlag && rsiEntryDirection != targetDir)
     {
      if(PrintDebug)
         Print("AlignFlags: RSI entry flag opposes target – resetting");
      rsiEntryFlag = false;
      rsiEntryDirection = 0;
     }
   if(entryReady && entryDirection != targetDir)
     {
      if(PrintDebug)
         Print("AlignFlags: Entry ready flag opposes target – resetting");
      entryReady = false;
      entryDirection = 0;
     }
  }

//+------------------------------------------------------------------+
//| Clear trade state variables                                      |
//+------------------------------------------------------------------+
void ClearTradeState()
  {
   tradeTicket        = 0;
   entryPrice         = 0;
   initialRisk        = 0;
   tradeDirection     = 0;
  }

//+------------------------------------------------------------------+
//| Check if our tracked position is still open                      |
//+------------------------------------------------------------------+
bool IsOurPositionOpen()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         if(ticket != tradeTicket)
           {
            if(PrintDebug)
               Print("Position ticket updated: ", tradeTicket, " -> ", ticket);
            tradeTicket = ticket;
           }
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Close entire position                                            |
//+------------------------------------------------------------------+
void CloseEntireTrade(string reason, bool isError = false)
  {
   if(tradeTicket == 0)
     {
      ClearTradeState();
      return;
     }

   bool posExists = IsOurPositionOpen();
   double profit  = posExists ? PositionGetDouble(POSITION_PROFIT) : 0;

   Print("CloseEntireTrade: Ticket=", tradeTicket,
         " Reason=", reason,
         " Profit=", DoubleToString(profit,2),
         " Trade#", tradeCounter);

   LogEvent("TradeClosed", reason,
            StringFormat("Ticket=%d Profit=%.2f Trade#%d Error=%s",
                         tradeTicket, profit, tradeCounter,
                         isError ? "yes" : "no"));

   if(posExists)
     {
      if(!trade.PositionClose(tradeTicket))
         Print("PositionClose FAILED: error=", trade.ResultRetcode());
     }

   if(isError)
     {
      ClearTradeState();
      SuspendTrading("Trade closed due to error: " + reason, SUSPENSION_PERMANENT);
      return;
     }

   ClearTradeState();

   if(tradeCounter >= MaxTrades)
     {
      SuspendTrading("Maximum " + IntegerToString(MaxTrades) + " trades completed — no more trading", SUSPENSION_PERMANENT);
      return;
     }

   if(PrintDebug)
      Print("Trade closed. Total trades so far: ", tradeCounter);
  }

//+------------------------------------------------------------------+
//| Process external closure                                         |
//+------------------------------------------------------------------+
void ProcessExternalClose(double profit, double dealVolume, int closedDirection)
  {
   ClearTradeState();

   if(tradeCounter >= MaxTrades)
     {
      SuspendTrading("Maximum " + IntegerToString(MaxTrades) + " trades completed (external) — no more trading", SUSPENSION_PERMANENT);
      return;
     }

   if(PrintDebug)
      Print("Trade closed externally. Total trades so far: ", tradeCounter);
  }

//+------------------------------------------------------------------+
//| Check target – 1:1                                               |
//+------------------------------------------------------------------+
void CheckTarget(int direction)
  {
   if(tradeTicket == 0)
      return;
   if(!IsOurPositionOpen())
      return;

   double currentPrice;
   if(direction == 1)
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   else
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   bool targetHit = false;
   double targetPrice = 0;

   if(direction == 1)
     {
      targetPrice = entryPrice + TargetRatio * initialRisk;
      if(currentPrice >= targetPrice)
         targetHit = true;
     }
   else
      if(direction == -1)
        {
         targetPrice = entryPrice - TargetRatio * initialRisk;
         if(currentPrice <= targetPrice)
            targetHit = true;
        }

   if(targetHit)
     {
      Print("TARGET HIT: Trade #", tradeCounter,
            " dir=", direction==1?"BUY":"SELL",
            " price=", DoubleToString(currentPrice,_Digits));
      LogEvent("TargetHit", "Triggered",
               StringFormat("Trade#%d dir=%s price=%.5f",
                            tradeCounter, direction==1?"BUY":"SELL", currentPrice));
      CloseEntireTrade("Target reached", false);
     }
  }

//+------------------------------------------------------------------+
//| Alternative Exit – Price crosses below/above HMA200             |
//+------------------------------------------------------------------+
void CheckAlternativeExit(int direction)
  {
   if(tradeTicket == 0)
      return;
   if(!IsOurPositionOpen())
      return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool exitTriggered = false;
   string exitReason = "";

// BUY exit: Price crosses below HMA200
   if(direction == 1)
     {
      if(price < h1Hull200_now)
        {
         exitTriggered = true;
         exitReason = "BUY exit: Price < HMA200";
        }
     }
// SELL exit: Price crosses above HMA200
   else
      if(direction == -1)
        {
         if(price > h1Hull200_now)
           {
            exitTriggered = true;
            exitReason = "SELL exit: Price > HMA200";
           }
        }

   if(exitTriggered)
     {
      Print("⚠️ ALTERNATIVE EXIT: ", exitReason);
      LogEvent("AlternativeExit", "Triggered",
               StringFormat("Trade#%d dir=%s price=%.5f H200=%.5f",
                            tradeCounter,
                            direction==1?"BUY":"SELL",
                            price, h1Hull200_now));
      CloseEntireTrade(exitReason, false);
     }
  }

//+------------------------------------------------------------------+
//| H1 HMA200 Flag – Price > HMA200 AND HMA200 = GREEN (BUY)        |
//+------------------------------------------------------------------+
void UpdateH1HMA200Flag()
  {
   if(h1HMA200Flag)
     {
      // Reset if opposite condition appears
      if(h1HMA200Direction == 1)
        {
         bool stillValid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) > h1Hull200_now) &&
                           (MathAbs(h1Color200_now - 1) < 0.1);
         if(!stillValid)
           {
            if(PrintDebug)
               Print("H1 HMA200 flag reset (BUY invalid)");
            h1HMA200Flag = false;
            h1HMA200Direction = 0;
           }
        }
      else
         if(h1HMA200Direction == -1)
           {
            bool stillValid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) < h1Hull200_now) &&
                              (MathAbs(h1Color200_now - 2) < 0.1);
            if(!stillValid)
              {
               if(PrintDebug)
                  Print("H1 HMA200 flag reset (SELL invalid)");
               h1HMA200Flag = false;
               h1HMA200Direction = 0;
              }
           }
      return;
     }

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

// BUY: Price > HMA200 AND HMA200 = GREEN
   bool buyCond = (price > h1Hull200_now) && (MathAbs(h1Color200_now - 1) < 0.1);

// SELL: Price < HMA200 AND HMA200 = RED
   bool sellCond = (price < h1Hull200_now) && (MathAbs(h1Color200_now - 2) < 0.1);

   if(buyCond)
     {
      h1HMA200Flag = true;
      h1HMA200Direction = 1;
      if(PrintDebug)
         Print("H1 HMA200 Flag SET (BUY) – Price > HMA200 & GREEN");
      LogEvent("H1HMA200Flag", "Set", "Buy");
     }
   else
      if(sellCond)
        {
         h1HMA200Flag = true;
         h1HMA200Direction = -1;
         if(PrintDebug)
            Print("H1 HMA200 Flag SET (SELL) – Price < HMA200 & RED");
         LogEvent("H1HMA200Flag", "Set", "Sell");
        }
  }

//+------------------------------------------------------------------+
//| H4 Structure Flag – HMA20 > HMA50 AND HMA50 = GREEN (BUY)       |
//+------------------------------------------------------------------+
void UpdateH4StructureFlag()
  {
   if(h4StructureFlag)
     {
      if(h4StructureDirection == 1)
        {
         bool stillValid = (h4Hull20_now > h4Hull50_now) &&
                           (MathAbs(h4Color50_now - 1) < 0.1);
         if(!stillValid)
           {
            if(PrintDebug)
               Print("H4 structure flag reset (BUY invalid)");
            h4StructureFlag = false;
            h4StructureDirection = 0;
           }
        }
      else
         if(h4StructureDirection == -1)
           {
            bool stillValid = (h4Hull20_now < h4Hull50_now) &&
                              (MathAbs(h4Color50_now - 2) < 0.1);
            if(!stillValid)
              {
               if(PrintDebug)
                  Print("H4 structure flag reset (SELL invalid)");
               h4StructureFlag = false;
               h4StructureDirection = 0;
              }
           }
      return;
     }

// BUY: HMA20 > HMA50 AND HMA50 = GREEN
   bool buyCond = (h4Hull20_now > h4Hull50_now) &&
                  (MathAbs(h4Color50_now - 1) < 0.1);

// SELL: HMA20 < HMA50 AND HMA50 = RED
   bool sellCond = (h4Hull20_now < h4Hull50_now) &&
                   (MathAbs(h4Color50_now - 2) < 0.1);

   if(buyCond)
     {
      h4StructureFlag = true;
      h4StructureDirection = 1;
      if(PrintDebug)
         Print("H4 Structure Flag SET (BUY) – H20 > H50 & H50 GREEN");
      LogEvent("H4StructureFlag", "Set", "Buy");
     }
   else
      if(sellCond)
        {
         h4StructureFlag = true;
         h4StructureDirection = -1;
         if(PrintDebug)
            Print("H4 Structure Flag SET (SELL) – H20 < H50 & H50 RED");
         LogEvent("H4StructureFlag", "Set", "Sell");
        }
  }

//+------------------------------------------------------------------+
//| D1 HMA8 Flag – HMA8 = GREEN (BUY) / RED (SELL)                  |
//+------------------------------------------------------------------+
void UpdateD1HMA8Flag()
  {
   if(d1HMA8Flag)
     {
      if(d1HMA8Direction == 1)
        {
         if(MathAbs(d1Color8 - 1) >= 0.1)
           {
            if(PrintDebug)
               Print("D1 HMA8 flag reset (BUY invalid)");
            d1HMA8Flag = false;
            d1HMA8Direction = 0;
           }
        }
      else
         if(d1HMA8Direction == -1)
           {
            if(MathAbs(d1Color8 - 2) >= 0.1)
              {
               if(PrintDebug)
                  Print("D1 HMA8 flag reset (SELL invalid)");
               d1HMA8Flag = false;
               d1HMA8Direction = 0;
              }
           }
      return;
     }

   bool buyCond = (MathAbs(d1Color8 - 1) < 0.1);   // GREEN
   bool sellCond = (MathAbs(d1Color8 - 2) < 0.1);  // RED

   if(buyCond)
     {
      d1HMA8Flag = true;
      d1HMA8Direction = 1;
      if(PrintDebug)
         Print("D1 HMA8 Flag SET (BUY) – HMA8 GREEN");
      LogEvent("D1HMA8Flag", "Set", "Buy");
     }
   else
      if(sellCond)
        {
         d1HMA8Flag = true;
         d1HMA8Direction = -1;
         if(PrintDebug)
            Print("D1 HMA8 Flag SET (SELL) – HMA8 RED");
         LogEvent("D1HMA8Flag", "Set", "Sell");
        }
  }

//+------------------------------------------------------------------+
//| RSI Entry Flag – H1 RSI(3) < 45 (BUY) / > 55 (SELL)            |
//+------------------------------------------------------------------+
void UpdateRSIEntryFlag()
  {
   if(rsiEntryFlag)
     {
      if(rsiEntryDirection == 1)
        {
         if(h1RSI_now >= H1_RSI_BuyThreshold)
           {
            if(PrintDebug)
               Print("RSI entry flag reset (BUY invalid) – RSI=", h1RSI_now);
            rsiEntryFlag = false;
            rsiEntryDirection = 0;
           }
        }
      else
         if(rsiEntryDirection == -1)
           {
            if(h1RSI_now <= H1_RSI_SellThreshold)
              {
               if(PrintDebug)
                  Print("RSI entry flag reset (SELL invalid) – RSI=", h1RSI_now);
               rsiEntryFlag = false;
               rsiEntryDirection = 0;
              }
           }
      return;
     }

   bool buyCond = (h1RSI_now < H1_RSI_BuyThreshold);
   bool sellCond = (h1RSI_now > H1_RSI_SellThreshold);

   if(buyCond)
     {
      rsiEntryFlag = true;
      rsiEntryDirection = 1;
      if(PrintDebug)
         Print("RSI Entry Flag SET (BUY) – RSI=", h1RSI_now, " < ", H1_RSI_BuyThreshold);
      LogEvent("RSIEntryFlag", "Set", "Buy");
     }
   else
      if(sellCond)
        {
         rsiEntryFlag = true;
         rsiEntryDirection = -1;
         if(PrintDebug)
            Print("RSI Entry Flag SET (SELL) – RSI=", h1RSI_now, " > ", H1_RSI_SellThreshold);
         LogEvent("RSIEntryFlag", "Set", "Sell");
        }
  }

//+------------------------------------------------------------------+
//| Update Entry Ready – all flags set + structural checks          |
//+------------------------------------------------------------------+
void UpdateEntryReady()
  {
// If entry already ready, keep it
   if(entryReady)
     {
      // Check if still valid
      if(entryDirection == 1)
        {
         bool stillValid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) > h1Hull8_now) &&
                           (h1Hull8_now > h1Hull20_now) &&
                           (h1Hull20_now > h1Hull50_now) &&
                           (MathAbs(h1Color8_now - 1) < 0.1) &&
                           (MathAbs(h1Color20_now - 1) < 0.1) &&
                           (MathAbs(h1Color50_now - 1) < 0.1);
         if(!stillValid)
           {
            if(PrintDebug)
               Print("Entry Ready reset – structure broke");
            entryReady = false;
            entryDirection = 0;
           }
        }
      else
         if(entryDirection == -1)
           {
            bool stillValid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) < h1Hull8_now) &&
                              (h1Hull8_now < h1Hull20_now) &&
                              (h1Hull20_now < h1Hull50_now) &&
                              (MathAbs(h1Color8_now - 2) < 0.1) &&
                              (MathAbs(h1Color20_now - 2) < 0.1) &&
                              (MathAbs(h1Color50_now - 2) < 0.1);
            if(!stillValid)
              {
               if(PrintDebug)
                  Print("Entry Ready reset – structure broke");
               entryReady = false;
               entryDirection = 0;
              }
           }
      return;
     }

// Check all flags are set and aligned
   if(!h1HMA200Flag || !h4StructureFlag || !d1HMA8Flag || !rsiEntryFlag)
      return;

// All directions must match
   if(h1HMA200Direction != h4StructureDirection ||
      h4StructureDirection != d1HMA8Direction ||
      d1HMA8Direction != rsiEntryDirection)
      return;

   int dir = h1HMA200Direction;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

// BUY entry structure: Price > HMA8 > HMA20 > HMA50 (all GREEN)
   if(dir == 1)
     {
      bool structure = (price > h1Hull8_now) &&
                       (h1Hull8_now > h1Hull20_now) &&
                       (h1Hull20_now > h1Hull50_now);
      bool colours = (MathAbs(h1Color8_now - 1) < 0.1) &&
                     (MathAbs(h1Color20_now - 1) < 0.1) &&
                     (MathAbs(h1Color50_now - 1) < 0.1);
      if(structure && colours)
        {
         entryReady = true;
         entryDirection = 1;
         if(PrintDebug)
            Print("ENTRY READY (BUY) – all flags + structure confirmed");
         LogEvent("EntryReady", "Set", "Buy");
        }
     }
// SELL entry structure: Price < HMA8 < HMA20 < HMA50 (all RED)
   else
      if(dir == -1)
        {
         bool structure = (price < h1Hull8_now) &&
                          (h1Hull8_now < h1Hull20_now) &&
                          (h1Hull20_now < h1Hull50_now);
         bool colours = (MathAbs(h1Color8_now - 2) < 0.1) &&
                        (MathAbs(h1Color20_now - 2) < 0.1) &&
                        (MathAbs(h1Color50_now - 2) < 0.1);
         if(structure && colours)
           {
            entryReady = true;
            entryDirection = -1;
            if(PrintDebug)
               Print("ENTRY READY (SELL) – all flags + structure confirmed");
            LogEvent("EntryReady", "Set", "Sell");
           }
        }
  }

//+------------------------------------------------------------------+
//| Open trade                                                       |
//+------------------------------------------------------------------+
bool OpenTrade(int direction)
  {
   if(!EnableTrading || equityTargetReached)
      return false;
   if(suspensionType == SUSPENSION_PERMANENT)
      return false;
   if(tradeCounter >= MaxTrades)
      return false;

   double price = (direction == 1)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = GetCurrentATR();
   if(atr == 0)
     {
      if(PrintDebug)
         Print("ATR zero — abort.");
      return false;
     }

   double slDistance = atr * StopMultiplier;
   double sl = (direction == 1) ? price - slDistance : price + slDistance;

   double rawLot;

   if(UseFixedLot)
     {
      rawLot = FixedLotSize;
     }
   else
     {
      rawLot = CalculateLotSize(price, sl, TradeRiskPercent);
      if(UseLotFallback && rawLot < MinimumRiskLot)
        {
         rawLot = LotFallbackSize;
         if(PrintDebug)
            Print("Lot fallback triggered: ", DoubleToString(rawLot,2));
        }
     }

   double lot = NormalizeLot(rawLot, _Symbol, true);
   if(lot <= 0)
      return false;

   string comment = "LTF_Trade" + IntegerToString(tradeCounter+1) + (direction == 1 ? "_Buy" : "_Sell");
   ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   if(!trade.PositionOpen(_Symbol, orderType, lot, price, sl, 0, comment))
     {
      if(PrintDebug)
         Print("PositionOpen FAILED: error ", trade.ResultRetcode());
      LogEvent("TradeOpen", "Failure",
               StringFormat("%s at %.5f lot=%.2f error=%d",
                            direction == 1 ? "Buy" : "Sell", price, lot, trade.ResultRetcode()));
      return false;
     }

   ulong ticket = trade.ResultOrder();
   if(ticket != 0)
     {
      tradeTicket      = ticket;
      tradeDirection   = direction;
      entryPrice       = price;
      initialRisk      = slDistance;
      tradeCounter++;

      double targetPrice = (direction == 1)
                           ? price + TargetRatio * slDistance
                           : price - TargetRatio * slDistance;

      Print("TRADE #", tradeCounter, " OPENED: ",
            direction == 1 ? "BUY" : "SELL",
            " Ticket=", ticket,
            " SL=", DoubleToString(sl, _Digits),
            " (", DoubleToString(StopMultiplier,1), "x ATR)",
            " Risk=", DoubleToString(TradeRiskPercent,2), "%",
            " Target=1:", DoubleToString(TargetRatio,2), " at ", DoubleToString(targetPrice, _Digits),
            " Lot=", DoubleToString(lot,2));

      LogEvent("TradeOpen", "Success",
               StringFormat("#%d %s at %.5f lot=%.2f stop=%.5f risk=%.2f%% ratio=%.2f",
                            tradeCounter, direction == 1 ? "Buy" : "Sell", price, lot, sl, TradeRiskPercent, TargetRatio));
      Comment("TRADE #", tradeCounter, " OPENED: ",
              direction == 1 ? "BUY" : "SELL", " Ticket ", ticket,
              " Target 1:", DoubleToString(TargetRatio,2));

      // --- RESET ALL FLAGS AFTER TRADE IS TAKEN ---
      ResetFlags();
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Lot helpers                                                      |
//+------------------------------------------------------------------+
double NormalizeLot(double lot, string symbol, bool logErrors = true)
  {
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step  <= 0)
      step  = 0.01;
   double original = lot;
   lot = MathRound(lot / step) * step;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = NormalizeDouble(lot, 2);
   if(logErrors && MathAbs(original - lot) > 0.001)
      Print("Lot normalised: ", DoubleToString(original,2), " -> ", DoubleToString(lot,2));
   return lot;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double ep, double stopLoss, double riskPercent)
  {
   double riskAmount    = AccountInfoDouble(ACCOUNT_BALANCE) * riskPercent / 100.0;
   double stopDistance  = MathAbs(ep - stopLoss);
   if(stopDistance == 0)
      return 0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize == 0 || tickValue == 0)
     {
      tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize == 0 || tickValue == 0)
         return 0;
     }

   double stopPoints  = stopDistance / tickSize;
   double riskPerLot  = stopPoints * tickValue;
   if(riskPerLot <= 0)
      return 0;

   double lot = riskAmount / riskPerLot;
   lot = NormalizeLot(lot, _Symbol, true);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < minLot)
      lot = minLot;
   return lot;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetCurrentATR()
  {
   double buffer[1];
   if(hATR != INVALID_HANDLE && CopyBuffer(hATR, 0, 0, 1, buffer) == 1)
      return buffer[0];
   return 0;
  }

//+------------------------------------------------------------------+
//| Goat Funded rules                                                |
//+------------------------------------------------------------------+
void CheckManualProfitTarget()
  {
   double currentEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double profitTargetAmt = startingEquity * (InpProfitTargetPercent / 100.0);
   double profit          = currentEquity - startingEquity;
   if(profit >= profitTargetAmt && !profitTargetReached)
     {
      profitTargetReached = true;
      Print("*** PROFIT TARGET REACHED: ", DoubleToString(profit,2),
            " (", DoubleToString(InpProfitTargetPercent,1), "%) ***");
      LogEvent("ProfitTarget", "Reached", StringFormat("%.2f", profit));
      ForceCloseAllPositions("Profit Target Reached");
      SuspendTrading(StringFormat("%.1f%% Profit Target Reached", InpProfitTargetPercent), SUSPENSION_PERMANENT);
      Alert(StringFormat("%.1f%% PROFIT TARGET REACHED. Trading Suspended.", InpProfitTargetPercent));
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckGoatRules()
  {
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayStart = StructToTime(dt);

   if(todayStart != currentDay)
     {
      currentDay    = todayStart;
      highestEquity = currentEquity;
     }
   if(currentEquity > highestEquity)
      highestEquity = currentEquity;

   if(InpDailyDrawdownLimit > 0)
     {
      double threshold = highestEquity * (1 - InpDailyDrawdownLimit / 100.0);
      if(currentEquity <= threshold)
        {
         string reason = StringFormat("Daily DD Limit: Equity=%.2f <= %.2f", currentEquity, threshold);
         Print("*** ", reason, " ***");
         LogEvent("DailyDrawdown", "Triggered", reason);
         ForceCloseAllPositions(reason);
         SuspendTrading(reason, SUSPENSION_TEMPORARY);
         return;
        }
     }

   double maxDDThreshold = startingEquity * (1 - InpMaxTotalDrawdown / 100.0);
   if(currentEquity <= maxDDThreshold)
     {
      string reason = StringFormat("Max Total DD: Equity=%.2f <= %.2f", currentEquity, maxDDThreshold);
      Print("*** ", reason, " ***");
      LogEvent("MaxDrawdown", "Triggered", reason);
      ForceCloseAllPositions(reason);
      SuspendTrading(reason, SUSPENSION_PERMANENT);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckDailyKillSwitch()
  {
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayStart = StructToTime(dt);
   if(todayStart != lastDayReset)
     {
      lastDayReset      = todayStart;
      dailyStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      if(suspensionType == SUSPENSION_TEMPORARY)
        {
         suspensionType = SUSPENSION_NONE;
         suspensionReason = "";
         if(PrintDebug)
            Print("Daily reset: temporary suspension cleared.");
        }
      if(PrintDebug)
         Print("Daily reset. Start equity = ", DoubleToString(dailyStartEquity,2));
     }
   CheckGoatRules();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckConsistentTradeDays()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayStart = StructToTime(dt);
   if(todayStart != lastDateChecked)
     {
      dailyProfit      = 0;
      lastDateChecked  = todayStart;
     }
   dailyProfit = GetDailyProfit();
   if(InpMinValidTradingDays > 0 &&
      dailyProfit >= startingEquity * 0.005 &&
      dailyProfit > 0)
     {
      if(lastValidDay != todayStart)
        {
         validTradeDays++;
         lastValidDay = todayStart;
         Print("Valid trade day #", validTradeDays,
               " profit=", DoubleToString(dailyProfit,2));
         LogEvent("ValidTradeDay", "Recorded",
                  StringFormat("Day %d: %.2f", validTradeDays, dailyProfit));
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetDailyProfit()
  {
   double profit = 0;
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayStart = StructToTime(dt);
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
        {
         datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         if(closeTime >= todayStart)
            profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
        }
     }
   return profit;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void LogEvent(string eventType, string status, string details = "")
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   string dateStr = StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
   if(lastLogDate != now)
     {
      logFileName = "LTF_Log_" + dateStr + ".csv";
      bool fileExists = FileIsExist(logFileName, FILE_COMMON);
      int handle = FileOpen(logFileName, FILE_WRITE|FILE_TXT|FILE_READ|FILE_COMMON, ",");
      if(handle != INVALID_HANDLE)
        {
         if(!fileExists)
            FileWrite(handle, "Timestamp,Symbol,Event,Status,Details");
         FileClose(handle);
        }
      lastLogDate = now;
     }
   string timeStr = TimeToString(now);
   string logLine = StringFormat("%s,%s,%s,%s,%s",
                                 timeStr, _Symbol, eventType, status, details);
   int handle = FileOpen(logFileName, FILE_WRITE|FILE_TXT|FILE_READ|FILE_COMMON, ",");
   if(handle != INVALID_HANDLE)
     {
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, logLine);
      FileClose(handle);
     }
   else
      Print("Failed to open log file: ", logFileName, " error=", GetLastError());
  }

//+------------------------------------------------------------------+
//|       Close Positions                                            |               
//+------------------------------------------------------------------+
void ForceCloseAllPositions(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL)  == _Symbol &&
            PositionGetInteger(POSITION_MAGIC)  == MagicNumber)
           {
            Print("Closing ticket ", ticket, " reason: ", reason);
            if(!trade.PositionClose(ticket))
               Print("Failed to close ticket ", ticket, " error=", trade.ResultRetcode());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Update all indicator values                                      |
//+------------------------------------------------------------------+
void UpdateAllValues()
  {
   double buffer[1];

// H1 RSI
   if(h1RSIHandle != INVALID_HANDLE &&
      CopyBuffer(h1RSIHandle, 0, 0, 1, buffer) == 1)
      h1RSI_now = buffer[0];
   else
      h1RSI_now = 50;

// D1 Hull
   if(d1HullHandle != INVALID_HANDLE)
     {
      if(CopyBuffer(d1HullHandle, 0, 0, 1, buffer) == 1)
         d1Hull8   = buffer[0];
      if(CopyBuffer(d1HullHandle, 1, 0, 1, buffer) == 1)
         d1Color8  = buffer[0];
     }

// H4 Hull
   if(h4HullHandle != INVALID_HANDLE)
     {
      if(CopyBuffer(h4HullHandle, 0, 0, 1, buffer) == 1)
         h4Hull8_now   = buffer[0];
      if(CopyBuffer(h4HullHandle, 1, 0, 1, buffer) == 1)
         h4Color8_now  = buffer[0];
      if(CopyBuffer(h4HullHandle, 2, 0, 1, buffer) == 1)
         h4Hull20_now  = buffer[0];
      if(CopyBuffer(h4HullHandle, 3, 0, 1, buffer) == 1)
         h4Color20_now = buffer[0];
      if(CopyBuffer(h4HullHandle, 4, 0, 1, buffer) == 1)
         h4Hull50_now  = buffer[0];
      if(CopyBuffer(h4HullHandle, 5, 0, 1, buffer) == 1)
         h4Color50_now = buffer[0];
     }

// H1 Hull
   if(h1HullHandle != INVALID_HANDLE)
     {
      if(CopyBuffer(h1HullHandle, 0, 0, 1, buffer) == 1)
         h1Hull8_now   = buffer[0];
      if(CopyBuffer(h1HullHandle, 1, 0, 1, buffer) == 1)
         h1Color8_now  = buffer[0];
      if(CopyBuffer(h1HullHandle, 2, 0, 1, buffer) == 1)
         h1Hull20_now  = buffer[0];
      if(CopyBuffer(h1HullHandle, 3, 0, 1, buffer) == 1)
         h1Color20_now = buffer[0];
      if(CopyBuffer(h1HullHandle, 4, 0, 1, buffer) == 1)
         h1Hull50_now  = buffer[0];
      if(CopyBuffer(h1HullHandle, 5, 0, 1, buffer) == 1)
         h1Color50_now = buffer[0];
      if(CopyBuffer(h1HullHandle, 6, 0, 1, buffer) == 1)
         h1Hull200_now = buffer[0];
      if(CopyBuffer(h1HullHandle, 7, 0, 1, buffer) == 1)
         h1Color200_now= buffer[0];
     }
  }

//+------------------------------------------------------------------+
//| Main trading logic                                               |
//+------------------------------------------------------------------+
void ProcessTrading()
  {
   if(!EnableTrading)
      return;
   if(suspensionType == SUSPENSION_PERMANENT)
      return;

// --- 1. Update all flags (persistent, LTF → HTF) ---
   UpdateH1HMA200Flag();    // H1: Price vs HMA200 + colour
   UpdateH4StructureFlag(); // H4: HMA20 vs HMA50 + HMA50 colour
   UpdateD1HMA8Flag();      // D1: HMA8 colour
   UpdateRSIEntryFlag();    // H1: RSI(3) threshold

// --- 2. Align flags – reset mismatched directions ---
   AlignFlags();

// --- 3. Check if all flags are set and entry structure valid ---
   UpdateEntryReady();

// --- 4. If no valid trade state, check for open trade management ---
   if(!entryReady || entryDirection == 0)
     {
      // Still manage open trades (exit logic)
      if(IsOurPositionOpen())
        {
         CheckTarget(tradeDirection);
         CheckAlternativeExit(tradeDirection);
        }
      return;
     }

// --- 5. Manage open trade exits (if any) ---
   if(IsOurPositionOpen())
     {
      CheckTarget(tradeDirection);
      CheckAlternativeExit(tradeDirection);
      return;
     }

// --- 6. Clear stale state ---
   if(tradeTicket != 0)
     {
      if(PrintDebug)
         Print("ProcessTrading: clearing stale tradeTicket=", tradeTicket);
      ClearTradeState();
     }

   if(tradeCounter >= MaxTrades)
     {
      if(PrintDebug)
         Print("ProcessTrading: max trades reached (", tradeCounter, "/", MaxTrades, ")");
      return;
     }

// --- 7. Open trade ---
   if(OpenTrade(entryDirection))
      if(PrintDebug)
         Print("Trade #", tradeCounter, " opened.");
  }

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   long   dealEntry      = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   string dealSymbol     = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long   dealMagic      = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   long   dealPositionId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   double dealVolume     = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double dealProfit     = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);

   if(dealSymbol != _Symbol || dealMagic != MagicNumber)
      return;
   if(dealEntry  != DEAL_ENTRY_OUT)
      return;

   if((ulong)dealPositionId != tradeTicket)
      return;

   bool isFullClose = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         isFullClose = false;
         if(posTicket != tradeTicket)
           {
            if(PrintDebug)
               Print("OnTradeTransaction: partial detected, ticket ",
                     tradeTicket, " -> ", posTicket);
            tradeTicket = posTicket;
           }
         break;
        }
     }

   if(!isFullClose)
     {
      LogEvent("PartialClose", "External",
               StringFormat("vol=%.4f profit=%.2f", dealVolume, dealProfit));
      return;
     }

   LogEvent("ExternalClose", "FullClose",
            StringFormat("Ticket=%d Profit=%.2f Trade#%d",
                         tradeTicket, dealProfit, tradeCounter));

   ProcessExternalClose(dealProfit, dealVolume, tradeDirection);
  }

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   h1RSIHandle = iRSI(_Symbol, PERIOD_H1, H1_RSI_Period, PRICE_CLOSE);
   if(h1RSIHandle == INVALID_HANDLE)
     {
      Print("Failed to create H1 RSI handle. Error: ", GetLastError());
      return INIT_FAILED;
     }

//--- D1 Hull8/20/50/200 (buffers 0-7)
   d1HullHandle = iCustom(_Symbol, PERIOD_D1, "UnifiedHullMA",
                          D1_HMA8_Period, 20, 50, 200, 2, 5000);
   if(d1HullHandle == INVALID_HANDLE)
     {
      Print("Failed to create D1 Hull handle. Error: ", GetLastError());
      return INIT_FAILED;
     }

//--- H4 Hull8/20/50/200 (buffers 0-7)
   h4HullHandle = iCustom(_Symbol, PERIOD_H4, "UnifiedHullMA",
                          H4_HMA8_Period, H4_HMA20_Period, H4_HMA50_Period, 200, 2, 5000);
   if(h4HullHandle == INVALID_HANDLE)
     {
      Print("Failed to create H4 Hull handle. Error: ", GetLastError());
      return INIT_FAILED;
     }

//--- H1 Hull8/20/50/200 (buffers 0-7)
   h1HullHandle = iCustom(_Symbol, PERIOD_H1, "UnifiedHullMA",
                          H1_HMA8_Period, H1_HMA20_Period, H1_HMA50_Period,
                          H1_HMA200_Period, 2, 5000);
   if(h1HullHandle == INVALID_HANDLE)
     {
      Print("Failed to create H1 Hull handle. Error: ", GetLastError());
      return INIT_FAILED;
     }

   hATR = iATR(_Symbol, PERIOD_H1, ATRPeriod);
   if(hATR == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle. Error: ", GetLastError());
      return INIT_FAILED;
     }

   startingEquity      = AccountInfoDouble(ACCOUNT_EQUITY);
   totalClosedProfit   = 0;
   equityTargetReached = false;
   maxProfitAllowed    = startingEquity * 0.5 / 100.0;
   highestEquity       = startingEquity;
   currentDay          = 0;
   tradeCounter        = 0;
   suspensionType      = SUSPENSION_NONE;

   Print("=== GoatFunded_LTF_MeanReversion v1.00 ===");
   Print("LTF → HTF Approach (responsive entry, HTF context)");
   Print("H1: Price > HMA200 & HMA200 GREEN (BUY) – sets persistent flag.");
   Print("H4: HMA20 > HMA50 & HMA50 GREEN (BUY) – sets persistent flag.");
   Print("D1: HMA8 GREEN (BUY) – sets persistent flag.");
   Print("Entry: RSI(3) < 45 (BUY) + Price > HMA8 > HMA20 > HMA50 (all GREEN).");
   Print("Alternative Exit: Price crosses below/above HMA200.");
   Print("Target: 1:1.");
   Print("Risk: ", TradeRiskPercent, "% | Stop: ", StopMultiplier, "x ATR.");
   Print("Max trades: ", MaxTrades);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| De-Initialisation                                                |              
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(h1RSIHandle  != INVALID_HANDLE)
      IndicatorRelease(h1RSIHandle);
   if(d1HullHandle != INVALID_HANDLE)
      IndicatorRelease(d1HullHandle);
   if(h4HullHandle != INVALID_HANDLE)
      IndicatorRelease(h4HullHandle);
   if(h1HullHandle != INVALID_HANDLE)
      IndicatorRelease(h1HullHandle);
   if(hATR         != INVALID_HANDLE)
      IndicatorRelease(hATR);
   Comment("");
  }

//+------------------------------------------------------------------+
//|                     On tick function                             |                
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckDailyKillSwitch();
   CheckManualProfitTarget();
   CheckConsistentTradeDays();
   UpdateAllValues();
   ProcessTrading();

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string st  = "";
   if(tradeTicket > 0)
      st = StringFormat("Target: 1:%.2f at %.5f",
                        TargetRatio,
                        tradeDirection==1 ? entryPrice + TargetRatio*initialRisk : entryPrice - TargetRatio*initialRisk);
   else
      st = "No trade";

   string suspStr = "";
   if(suspensionType == SUSPENSION_PERMANENT)
      suspStr = "PERMANENT: " + suspensionReason;
   else
      if(suspensionType == SUSPENSION_TEMPORARY)
         suspStr = "TEMPORARY: " + suspensionReason;

   string comment = "═══ GoatFunded_LTF_MeanReversion v1.00 ═══\n";
   if(suspensionType != SUSPENSION_NONE)
      comment += "!!! SUSPENDED: " + suspStr + " !!!\n";
   comment += StringFormat("Trades: %d/%d\n", tradeCounter, MaxTrades);
   comment += StringFormat("H1 HMA200 Flag: %s (%s) | Price %s H200\n",
                           h1HMA200Flag?"SET":"---",
                           h1HMA200Direction==1?"BUY":h1HMA200Direction==-1?"SELL":"-",
                           bid > h1Hull200_now ? ">" : "<");
   comment += StringFormat("H4 Structure Flag: %s (%s) | H20 %s H50 | H50 %s\n",
                           h4StructureFlag?"SET":"---",
                           h4StructureDirection==1?"BUY":h4StructureDirection==-1?"SELL":"-",
                           h4Hull20_now > h4Hull50_now ? ">" : "<",
                           (h4Color50_now==1?"GREEN":(h4Color50_now==2?"RED":"-")));
   comment += StringFormat("D1 HMA8 Flag: %s (%s) | D1 H8 %s\n",
                           d1HMA8Flag?"SET":"---",
                           d1HMA8Direction==1?"BUY":d1HMA8Direction==-1?"SELL":"-",
                           (d1Color8==1?"GREEN":(d1Color8==2?"RED":"-")));
   comment += StringFormat("RSI Entry Flag: %s (%s) | RSI(3)=%.1f\n",
                           rsiEntryFlag?"SET":"---",
                           rsiEntryDirection==1?"BUY":rsiEntryDirection==-1?"SELL":"-",
                           h1RSI_now);
   comment += StringFormat("Entry Ready: %s (%s)\n",
                           entryReady?"✅":"❌",
                           entryDirection==1?"BUY":entryDirection==-1?"SELL":"-");
   comment += StringFormat("H1 Structure: P %s H8 %s H20 %s H50 | Colours 8:%s 20:%s 50:%s\n",
                           bid > h1Hull8_now ? ">" : "<",
                           h1Hull8_now > h1Hull20_now ? ">" : "<",
                           h1Hull20_now > h1Hull50_now ? ">" : "<",
                           (h1Color8_now==1?"G":(h1Color8_now==2?"R":"-")),
                           (h1Color20_now==1?"G":(h1Color20_now==2?"R":"-")),
                           (h1Color50_now==1?"G":(h1Color50_now==2?"R":"-")));
   comment += StringFormat("H1 HMA200: %.5f (%s)\n",
                           h1Hull200_now,
                           (h1Color200_now==1?"GREEN":(h1Color200_now==2?"RED":"-")));
   if(tradeTicket > 0)
      comment += StringFormat("Trade: %s T=%d | %s\n",
                              tradeDirection == 1 ? "LONG" : "SHORT",
                              tradeTicket, st);
   else
      comment += "Trade: none\n";
   comment += StringFormat("Equity: %.2f (%.1f%%) | Target:%.1f%% | DD:%.1f/%.1f%%",
                           AccountInfoDouble(ACCOUNT_EQUITY),
                           (AccountInfoDouble(ACCOUNT_EQUITY) - startingEquity) / startingEquity * 100,
                           InpProfitTargetPercent,
                           (startingEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / startingEquity * 100,
                           InpMaxTotalDrawdown);
   Comment(comment);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
