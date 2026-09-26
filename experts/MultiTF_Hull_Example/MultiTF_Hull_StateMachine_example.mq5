//+------------------------------------------------------------------+
//|                             MultiTF_Hull_StateMachine_example.mq5|
//|                                  Copyright 2026, C.J. Weekes     |
//|                                                                  |
//+------------------------------------------------------------------+
//|  STRATEGY OVERVIEW                                               |
//|  -----------------                                               |
//|  A multi-timeframe Hull Moving Average system combined with      |
//|  Murrey Math levels, D1 ADX filtering, and H2 oscillators.       |
//|                                                                  |
//|  TREND FILTER (H6)                                               |
//|    - HMA30 and HMA100 must both be GREEN (bullish) or both RED   |
//|      (bearish) on the H6 timeframe.                              |
//|    - When this "match" exists, the EA is armed for entry.        |
//|                                                                  |
//|  ENTRY SEQUENCE (H2)                                             |
//|    Bullish:                                                      |
//|      1. Stochastic K & D both < 50                               |
//|      2. OsMA < 0                                                 |
//|      3. HMA20 turns GREEN                                        |
//|    Bearish:                                                      |
//|      1. Stochastic K & D both > 50                               |
//|      2. OsMA > 0                                                 |
//|      3. HMA20 turns RED                                          |
//|    Steps must occur in order; flags reset if H6 trend flips.     |
//|                                                                  |
//|  D1 CONFIRMATION                                                 |
//|    - ADX(14) must be above 20 before any trade is taken.         |
//|    - Optional D1 Hull validation (HMA20 matches HMA100 or        |
//|      HMA400 color) is applied only to the 2nd trade after a      |
//|      first loss.                                                 |
//|                                                                  |
//|  RISK & EXITS                                                    |
//|    - Stop Loss   = 3.0  x H6 ATR(14)                             |
//|    - Take Profit = 7.5  x H6 ATR(14)   (1 : 2.5 R:R)             |
//|    - Risk per trade = 1.2% of account equity (auto lot sizing).  |
//|                                                                  |
//|  ALTERNATIVE EXITS (override SL/TP)                              |
//|    Exit 1: H6 Hull60 and Hull100 color match (both GREEN for a   |
//|            SELL, both RED for a BUY).                            |
//|    Exit 2: Price comes within 15 pips of Murrey 0/8 or 8/8.      |
//|            (currently disabled in OnTick - re-enable if needed)  |
//|                                                                  |
//|  TRADE LIFECYCLE                                                 |
//|    - Max 2 trades per EA session.                                |
//|    - If trade #1 wins  -> EA removes itself (ExpertRemove).      |
//|    - If trade #1 loses -> 2nd trade allowed (D1 validation on).  |
//|    - After trade #2 (win or lose) -> EA removes itself.          |
//|                                                                  |
//|  INDICATORS USED                                                 |
//|    - UnifiedHullMA          (H6: 30/100/60, H2: 20/50, D1:20/100/400)
//|    - iATR                   (H6, period 14)                      |
//|    - iStochastic            (H2)                                 |
//|    - iOsMA                  (H2)                                 |
//|    - iADX                   (D1, period 14)                      |
//|    - MurreyMath Channel     (D1)                                 |
//|                                                                  |
//|  NOTE: UnifiedHullMA buffer layout ->                             |
//|        0/1 = Hull1 value/color, 2/3 = Hull2, 4/5 = Hull3,        |
//|        6/7 = Hull4. Colors: 0=Gray, 1=Green, 2=Red.              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  EDUCATIONAL EXAMPLE - NOT A TRADING SYSTEM                      |
//|                                                                  |
//|  This file is a reference implementation. It shows how to build  |
//|  a multi-timeframe Hull system in MQL5: a state machine for      |
//|  entries, a D1 validation gate, ATR-based risk sizing, and       |
//|  alternative exits.                                              |
//|                                                                  |
//|  It is not intended as a deployable strategy. It makes no        |
//|  performance claims. Use it as code to learn from, not as        |
//|  something to run on a live account.                             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader"
#property version   "1.10"
#property description "Multi-timeframe EA: H6 Hull trend filter, H2 sequential entry."
#property description "Stochastic and OsMA stages, D1 ADX confirmation."
#property description "ATR-based risk (SL=3xATR, TP=7.5xATR). Requires UnifiedHullMA."
#property description "Example: multi-timeframe Hull system (H6 filter, H2 entry)."
#property description "Demonstrates sequential state machine, D1 validation, ATR risk."
#property description "Educational reference only - not a complete trading system."
#property description "Requires the UnifiedHullMA indicator."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Arrays\ArrayDouble.mqh>

CTrade trade;
CPositionInfo positionInfo;
CAccountInfo accountInfo;

// Trading Parameters - UPDATED
double RiskPercent = 1.2;           // Risk percentage per trade (increased from 1.0%)
input int ATRPeriod = 14;                 // ATR Period for stop loss/take profit
double StopLossMultiplier = 3.0;    // Stop Loss = ATR * 3
double TakeProfitMultiplier = 7.5;  // Take Profit = ATR * 7.5

// H6 Hull Parameters
input int H6_Hull30_Period = 30;          // H6 Hull MA 30 Period
input int H6_Hull100_Period = 100;        // H6 Hull MA 100 Period
input double H6_Hull_Divisor = 2.0;       // H6 Hull Divisor

// H2 Hull Parameters - BOTH HULL 20 AND HULL 50
input int H2_Hull20_Period = 20;          // H2 Hull MA 20 Period
input int H2_Hull50_Period = 50;          // H2 Hull MA 50 Period
input int H2_Hull60_Period = 60;          // H2 Hull MA 60 Period

// H2 Indicator Parameters
input int H2_Stochastic_KPeriod = 5;      // H2 Stochastic K Period
input int H2_Stochastic_DPeriod = 3;      // H2 Stochastic D Period
input int H2_Stochastic_Slowing = 3;      // H2 Stochastic Slowing
input ENUM_MA_METHOD H2_Stochastic_Method = MODE_SMA; // Stochastic Method
input ENUM_STO_PRICE H2_Stochastic_Price = STO_LOWHIGH; // Stochastic Price

input int H2_OsMA_FastEMA = 12;           // H2 OsMA Fast EMA
input int H2_OsMA_SlowEMA = 26;           // H2 OsMA Slow EMA
input int H2_OsMA_Signal = 9;             // H2 OsMA Signal
input ENUM_APPLIED_PRICE H2_OsMA_Price = PRICE_CLOSE; // H2 OsMA Price

// D1 ADX Parameters
input int D1_ADX_Period = 14;             // D1 ADX Period
input int D1_ADX_Level = 20;              // D1 ADX Minimum Level

// D1 Murrey Math Parameters
input int D1_MurrayPeriod = 64;           // D1 Murray Math Period
input bool ShowExtraLevels = false;       // Show all Murrey Math levels
input bool ShowPriceLabels = true;        // Show Murrey Math price labels
input int MurrayProximityPips = 15;       // Proximity to Murray level in pips (15 default)

// D1 Triple Hull Validation Parameters
bool EnableD1HullValidation = true; // Enable D1 Hull validation for 2nd trade

// Global variables
int h6_hull30Handle, h6_hull100Handle, h6_hull60Handle;
int h2_hull20Handle, h2_hull50Handle, h2_hull60Handle, h2_stochHandle, h2_osmaHandle;
int d1_adxHandle, d1_murrayHandle, d1_hullHandle;
int h6_atrHandle;

long magicNumber;

// H6 Master Flag - Based on HMA 30 & HMA 100 match
bool h6BullishFlag = false;
bool h6BearishFlag = false;

// H6 Hull color tracking for alternative exit - UPDATED: Now tracking Hull60 and Hull100
int h6Hull60CurrentColor = 0;
int h6Hull60PreviousColor = 0;
int h6Hull100CurrentColor = 0;
int h6Hull100PreviousColor = 0;

// H2 Sequential Flags - BOTH HULL 20 AND HULL 50
bool flag1_StochBelow50 = false;      // Stage 1: Stochastic K & D < 50
bool flag2_OsmaBelow0 = false;        // Stage 2: OsMA < 0
bool flag3_Hull20Green = false;       // Stage 3: HMA 20 is green

bool flag1_StochAbove50 = false;      // Stage 1: Stochastic K & D > 50
bool flag2_OsmaAbove0 = false;        // Stage 2: OsMA > 0
bool flag3_Hull20Red = false;         // Stage 3: HMA 20 is red

// Trading flags
bool tradeTaken = false;
int tradeCount = 0;
bool bullishSequenceComplete = false;
bool bearishSequenceComplete = false;

// Indicator values
double currentADX = 0, currentPlusDI = 0, currentMinusDI = 0;

// Buffers
double stochKBuffer[], stochDBuffer[];

// Murrey Math variables
double d1_murrayLevels[13];
bool murrayLevelsUpdated = false;
datetime lastMurrayCheck = 0;

// Murrey Math level names
string MurrayLevelNames[] =
  {
   "[+2/8]", "[+1/8]", "[8/8]", "[7/8]", "[6/8]", "[5/8]",
   "[4/8]", "[3/8]", "[2/8]", "[1/8]", "[0/8]", "[-1/8]", "[-2/8]"
  };


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== Modified H6-H2 Hull Trading EA Initialized ===");
   Print("H6: HMA30 & HMA100 MATCH REQUIRED");
   Print("H2: Stoch<50 + OsMA<0 + HMA20 Green (Bullish)");
   Print("H2: Stoch>50 + OsMA>0 + HMA20 Red (Bearish)");
   Print("Alternative Exit 1: H6 Hull60 & Hull100 color match");
   Print("Alternative Exit 2: Price within 15 pips of Murrey 0/8 or 8/8");
   Print("ATR: H6 Timeframe | SL: 3*ATR | TP: 7.5*ATR");
   Print("RISK-REWARD: 1:2.5 Ratio | Risk per trade: 1.2%");
   if(EnableD1HullValidation)
      Print("D1 HULL VALIDATION: Enabled for 2nd trade (after first loss)");

   magicNumber = GenerateMagicNumber();
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

//--- D1 Hull validation using UnifiedHullMA (buffers 1/3/5)
//--- Hull1=20, Hull2=100, Hull3=400
   if(EnableD1HullValidation)
     {
      d1_hullHandle = iCustom(_Symbol, PERIOD_D1, "UnifiedHullMA",
                              20, 100, 400, 200, 2, 5000);
      if(d1_hullHandle == INVALID_HANDLE)
        {
         Print("Warning: Could not load D1 Hull indicator 'UnifiedHullMA'. D1 validation disabled.");
         EnableD1HullValidation = false;
        }
      else
        {
         Print("D1 Hull indicator loaded successfully for validation");
        }
     }

//--- H6 Hull indicators using UnifiedHullMA
//--- Buffer layout: 0/1=Hull30, 2/3=Hull100, 4/5=Hull60
   h6_hull30Handle = iCustom(_Symbol, PERIOD_H6, "UnifiedHullMA",
                             H6_Hull30_Period, H6_Hull100_Period, H2_Hull60_Period, 200,
                             (int)H6_Hull_Divisor, 5000);
   h6_hull100Handle = h6_hull30Handle;  // same handle, buffers 2/3
   h6_hull60Handle  = h6_hull30Handle;  // same handle, buffers 4/5

//--- H6 ATR indicator
   h6_atrHandle = iATR(_Symbol, PERIOD_H6, ATRPeriod);

//--- H2 Hull indicators using UnifiedHullMA
//--- Buffer layout: 0/1=Hull20, 2/3=Hull50
   h2_hull20Handle = iCustom(_Symbol, PERIOD_H2, "UnifiedHullMA",
                             H2_Hull20_Period, H2_Hull50_Period, 200, 200,
                             2, 5000);
   h2_hull50Handle = h2_hull20Handle;  // same handle, buffers 2/3

//--- H2 oscillators
   h2_stochHandle = iStochastic(_Symbol, PERIOD_H2,
                                H2_Stochastic_KPeriod, H2_Stochastic_DPeriod, H2_Stochastic_Slowing,
                                H2_Stochastic_Method, H2_Stochastic_Price);
   h2_osmaHandle = iOsMA(_Symbol, PERIOD_H2,
                         H2_OsMA_FastEMA, H2_OsMA_SlowEMA, H2_OsMA_Signal, H2_OsMA_Price);

//--- D1 indicators
   d1_adxHandle = iADX(_Symbol, PERIOD_D1, D1_ADX_Period);
   d1_murrayHandle = iCustom(_Symbol, PERIOD_D1, "Free Indicators\\MurreyMath Channel",
                             D1_MurrayPeriod, ShowExtraLevels, ShowPriceLabels);

//--- Check handles
   if(h6_hull30Handle == INVALID_HANDLE ||
      h6_atrHandle == INVALID_HANDLE || h2_hull20Handle == INVALID_HANDLE ||
      h2_stochHandle == INVALID_HANDLE || h2_osmaHandle == INVALID_HANDLE ||
      d1_adxHandle == INVALID_HANDLE)
     {
      Print("Error creating indicator handles");
      return INIT_FAILED;
     }

//--- Initialize buffer arrays
   ArraySetAsSeries(stochKBuffer, true);
   ArraySetAsSeries(stochDBuffer, true);

   Print("All indicators loaded successfully. Ready for real trading.");
   Print("ATR Configuration: Stop Loss = 3*ATR, Take Profit = 7.5*ATR (1:2.5 Risk-Reward)");
   Print("Risk per trade: 1.2% | Alternative Exit: H6 Hull60 & Hull100 color match");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(h6_hull30Handle != INVALID_HANDLE)
      IndicatorRelease(h6_hull30Handle);
// h6_hull100Handle and h6_hull60Handle are aliases - do NOT release again
   if(h6_atrHandle != INVALID_HANDLE)
      IndicatorRelease(h6_atrHandle);
   if(h2_hull20Handle != INVALID_HANDLE)
      IndicatorRelease(h2_hull20Handle);
// h2_hull50Handle is an alias - do NOT release again
   if(h2_stochHandle != INVALID_HANDLE)
      IndicatorRelease(h2_stochHandle);
   if(h2_osmaHandle != INVALID_HANDLE)
      IndicatorRelease(h2_osmaHandle);
   if(d1_adxHandle != INVALID_HANDLE)
      IndicatorRelease(d1_adxHandle);
   if(d1_murrayHandle != INVALID_HANDLE)
      IndicatorRelease(d1_murrayHandle);
   if(d1_hullHandle != INVALID_HANDLE)
      IndicatorRelease(d1_hullHandle);

   Print("=== Modified H6-H2 Hull Trading EA Deinitialized ===");
   Print("Total Trades Executed: ", tradeCount);
   Print("Final Configuration: SL=3*ATR, TP=7.5*ATR, Risk=1.2%, Exit=Hull60&100 match");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime lastH6Check = 0, lastH2Check = 0, lastD1Check = 0;
   datetime currentTime = TimeCurrent();

// Check H6 conditions on new H6 bar
   if(TimeCurrent() - lastH6Check >= PeriodSeconds(PERIOD_H6))
     {
      // Apply D1 Hull validation only if trade count is 1 (after first loss)
      if(tradeCount == 1 && EnableD1HullValidation)
        {
         if(CheckD1HullConditions())
           {
            Print("D1 Hull validation PASSED - proceeding with H6 conditions");
            CheckH6Conditions();
            UpdateH6HullColors();
           }
         else
           {
            Print("D1 Hull validation FAILED - skipping H6 check");
           }
        }
      else
        {
         // Normal operation for first trade or when D1 validation is disabled
         CheckH6Conditions();
         UpdateH6HullColors();
        }
      lastH6Check = currentTime;
     }

// Check D1 conditions on new D1 bar
   if(TimeCurrent() - lastD1Check >= PeriodSeconds(PERIOD_D1))
     {
      CheckD1ADXConditions();
      UpdateD1MurrayLevels();
      lastD1Check = currentTime;
     }

// Check H2 conditions on new H2 bar
   if(TimeCurrent() - lastH2Check >= PeriodSeconds(PERIOD_H2))
     {
      CheckH2Conditions();
      lastH2Check = currentTime;
     }

// TICK-BASED: Check Murrey Math proximity on every tick
//CheckMurrayProximityExit();

// Check for trade opportunities
   CheckTradeOpportunities();

// CHECK ALTERNATIVE EXIT CONDITION 1 - H6 Hull60 & Hull100 color match
   CheckAlternativeExit1();

   UpdateChartComment();
  }

//+------------------------------------------------------------------+
//| Check D1 Hull conditions (20 matches 100 or 400)                |
//+------------------------------------------------------------------+
bool CheckD1HullConditions()
  {
   if(d1_hullHandle == INVALID_HANDLE)
     {
      Print("D1 Hull indicator not available - validation skipped");
      return true; // Allow trade if indicator not available
     }

// Get current colors from D1 Hull indicator
   double color20[1], color100[1], color400[1];

// Copy Hull 20 colors (buffer 1)
   if(CopyBuffer(d1_hullHandle, 1, 0, 1, color20) != 1)
     {
      Print("Error copying D1 Hull 20 colors");
      return false;
     }

// Copy Hull 100 colors (buffer 3)
   if(CopyBuffer(d1_hullHandle, 3, 0, 1, color100) != 1)
     {
      Print("Error copying D1 Hull 100 colors");
      return false;
     }

// Copy Hull 400 colors (buffer 5)
   if(CopyBuffer(d1_hullHandle, 5, 0, 1, color400) != 1)
     {
      Print("Error copying D1 Hull 400 colors");
      return false;
     }

   int currentColor20 = (int)color20[0];
   int currentColor100 = (int)color100[0];
   int currentColor400 = (int)color400[0];

   Print(StringFormat("D1 Hull Colors - 20: %d (%s), 100: %d (%s), 400: %d (%s)",
                      currentColor20, GetHullColorText(currentColor20),
                      currentColor100, GetHullColorText(currentColor100),
                      currentColor400, GetHullColorText(currentColor400)));

// Check if 20 HMA color matches 100 HMA color (and not gray/neutral)
   bool match20_100 = (currentColor20 == currentColor100 && currentColor20 != 0);

// Check if 20 HMA color matches 400 HMA color (and not gray/neutral)
   bool match20_400 = (currentColor20 == currentColor400 && currentColor20 != 0);

   bool validationPassed = (match20_100 || match20_400);

   if(validationPassed)
     {
      string matchType = match20_100 ? "20 HMA matches 100 HMA" : "20 HMA matches 400 HMA";
      Print("D1 Hull Validation PASSED: " + matchType + " - Color: " + GetHullColorText(currentColor20));
     }
   else
     {
      Print("D1 Hull Validation FAILED: No color match found");
     }

   return validationPassed;
  }

//+------------------------------------------------------------------+
//| Update H6 Hull colors for alternative exit - UPDATED            |
//+------------------------------------------------------------------+
void UpdateH6HullColors()
  {
   double hull60Colors[], hull100Colors[];
   ArraySetAsSeries(hull60Colors, true);
   ArraySetAsSeries(hull100Colors, true);

// Copy H6 Hull60 color values (buffer 1 for color)
   if(CopyBuffer(h6_hull60Handle, 5, 0, 3, hull60Colors) < 3)
     {
      Print("Error: Failed to copy H6 Hull60 color values");
      return;
     }

// Copy H6 Hull100 color values (buffer 3 for color)
   if(CopyBuffer(h6_hull100Handle, 3, 0, 3, hull100Colors) < 3)
     {
      Print("Error: Failed to copy H6 Hull100 color values");
      return;
     }

// Update previous colors
   h6Hull60PreviousColor = h6Hull60CurrentColor;
   h6Hull100PreviousColor = h6Hull100CurrentColor;

// Convert double color values to integers
   h6Hull60CurrentColor = (int)hull60Colors[0];
   h6Hull100CurrentColor = (int)hull100Colors[0];

// Debug output for color changes
   if(h6Hull60CurrentColor != h6Hull60PreviousColor || h6Hull100CurrentColor != h6Hull100PreviousColor)
     {
      Print("H6 Hull Colors - Hull60: ", GetHullColorText(h6Hull60CurrentColor),
            " | Hull100: ", GetHullColorText(h6Hull100CurrentColor));
     }
  }

//+------------------------------------------------------------------+
//| Check Alternative Exit 1 - H6 Hull60 & Hull100 color match - UPDATED |
//+------------------------------------------------------------------+
void CheckAlternativeExit1()
  {
   if(!HasOpenPosition())
     {
      return;
     }

// Get current position type
   long positionType = PositionGetInteger(POSITION_TYPE);

// Check for color match - both must be the same color
   bool colorsMatch = (h6Hull60CurrentColor == h6Hull100CurrentColor);

   if(colorsMatch)
     {
      // Check for SELL position exit condition
      if(positionType == POSITION_TYPE_SELL && h6Hull60CurrentColor == 1) // Both GREEN
        {
         Print("ALTERNATIVE EXIT 1 TRIGGERED: H6 Hull60 & Hull100 both GREEN - Closing SELL position");
         CloseAllPositions();
         return;
        }

      // Check for BUY position exit condition
      if(positionType == POSITION_TYPE_BUY && h6Hull60CurrentColor == 2) // Both RED
        {
         Print("ALTERNATIVE EXIT 1 TRIGGERED: H6 Hull60 & Hull100 both RED - Closing BUY position");
         CloseAllPositions();
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Check Murray Proximity Exit - TICK BASED                        |
//+------------------------------------------------------------------+
void CheckMurrayProximityExit()
  {
   if(!HasOpenPosition() || !murrayLevelsUpdated)
     {
      return;
     }

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double proximity_points = MurrayProximityPips * 10 * _Point; // Convert pips to points

// Check 0/8 and 8/8 levels only
   double level_0_8 = d1_murrayLevels[10]; // 0/8 level
   double level_8_8 = d1_murrayLevels[2];  // 8/8 level

// Get current position type
   long positionType = PositionGetInteger(POSITION_TYPE);

// Check proximity to 0/8 level (major support)
   if(level_0_8 != EMPTY_VALUE && level_0_8 > 0.0)
     {
      double difference = MathAbs(currentPrice - level_0_8);
      if(difference <= proximity_points)
        {
         string approach = (currentPrice < level_0_8) ? "Approaching from Below" : "Approaching from Above";
         string msg = StringFormat("MURREY PROXIMITY: Price %.5f is within %d pips of 0/8 level (%.5f) - %s",
                                   currentPrice, MurrayProximityPips, level_0_8, approach);
         Print(msg);

         // Close position if approaching 0/8 level (major support)
         if(positionType == POSITION_TYPE_SELL)
           {
            Print("ALTERNATIVE EXIT 2 TRIGGERED: Price near 0/8 support level - Closing SELL position");
            CloseAllPositions();
            return;
           }
        }
     }

// Check proximity to 8/8 level (major resistance)
   if(level_8_8 != EMPTY_VALUE && level_8_8 > 0.0)
     {
      double difference = MathAbs(currentPrice - level_8_8);
      if(difference <= proximity_points)
        {
         string approach = (currentPrice < level_8_8) ? "Approaching from Below" : "Approaching from Above";
         string msg = StringFormat("MURREY PROXIMITY: Price %.5f is within %d pips of 8/8 level (%.5f) - %s",
                                   currentPrice, MurrayProximityPips, level_8_8, approach);
         Print(msg);

         // Close position if approaching 8/8 level (major resistance)
         if(positionType == POSITION_TYPE_BUY)
           {
            Print("ALTERNATIVE EXIT 2 TRIGGERED: Price near 8/8 resistance level - Closing BUY position");
            CloseAllPositions();
            return;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Update D1 Murray Math levels                                    |
//+------------------------------------------------------------------+
bool UpdateD1MurrayLevels()
  {
   double temp_buffer[1];

   for(int i = 0; i < 13; i++)
     {
      if(CopyBuffer(d1_murrayHandle, i, 0, 1, temp_buffer) == 1)
        {
         d1_murrayLevels[i] = temp_buffer[0];
        }
      else
        {
         d1_murrayLevels[i] = EMPTY_VALUE;
        }
     }

   murrayLevelsUpdated = true;
   return true;
  }

//+------------------------------------------------------------------+
//| Check H6 conditions - HMA 30 & HMA 100 match required          |
//+------------------------------------------------------------------+
void CheckH6Conditions()
  {
   double hull30[], hull100[];
   double hull30Colors[], hull100Colors[];

   ArraySetAsSeries(hull30, true);
   ArraySetAsSeries(hull100, true);
   ArraySetAsSeries(hull30Colors, true);
   ArraySetAsSeries(hull100Colors, true);

// Get HMA 30 values (buffer 0: value, buffer 1: color)
   if(CopyBuffer(h6_hull30Handle, 0, 0, 2, hull30) < 2)
      return;
   if(CopyBuffer(h6_hull30Handle, 1, 0, 2, hull30Colors) < 2)
      return;

// Get HMA 100 values (buffer 2: value, buffer 3: color)
   if(CopyBuffer(h6_hull100Handle, 2, 0, 2, hull100) < 2)
      return;
   if(CopyBuffer(h6_hull100Handle, 3, 0, 2, hull100Colors) < 2)
      return;

   int currentHull30Color = (int)hull30Colors[0];
   int currentHull100Color = (int)hull100Colors[0];

// H6 Signal: Both HMA 30 and HMA 100 must match direction
   bool newH6Bullish = (currentHull30Color == 1 && currentHull100Color == 1);  // Both green
   bool newH6Bearish = (currentHull30Color == 2 && currentHull100Color == 2);  // Both red

// Reset flags if H6 conditions change
   if(newH6Bullish != h6BullishFlag || newH6Bearish != h6BearishFlag)
     {
      Print("H6 CONDITIONS CHANGED - Resetting sequential flags");
      ResetAllSequentialFlags();
     }

   h6BullishFlag = newH6Bullish;
   h6BearishFlag = newH6Bearish;

   if(h6BullishFlag)
      Print("H6 BULLISH: HMA 30 and HMA 100 both GREEN");
   else
      if(h6BearishFlag)
         Print("H6 BEARISH: HMA 30 and HMA 100 both RED");
  }

//+------------------------------------------------------------------+
//| Check H2 conditions - Entry sequence with Hull20               |
//+------------------------------------------------------------------+
void CheckH2Conditions()
  {
   if(!UpdateH2IndicatorValues())
      return;

   double currentK = stochKBuffer[0];
   double currentD = stochDBuffer[0];
   double currentOsMA = GetH2OsMAValue(0);

   Print("H2 VALUES - Stoch K:", DoubleToString(currentK,1),
         " D:", DoubleToString(currentD,1),
         " OsMA:", DoubleToString(currentOsMA,5));

// Check sequences only when H6 conditions are met
   if(h6BullishFlag)
     {
      CheckBullishSequentialFlags(currentK, currentD, currentOsMA);
     }

   if(h6BearishFlag)
     {
      CheckBearishSequentialFlags(currentK, currentD, currentOsMA);
     }
  }

//+------------------------------------------------------------------+
//| Check Bullish Sequential Flags - HULL20 FOR ENTRY              |
//+------------------------------------------------------------------+
void CheckBullishSequentialFlags(double currentK, double currentD, double currentOsMA)
  {
// FLAG 1: Stochastic K & D < 50
   if(!flag1_StochBelow50 && !flag2_OsmaBelow0 && !flag3_Hull20Green)
     {
      flag1_StochBelow50 = (currentK < 50 && currentD < 50);
      if(flag1_StochBelow50)
         Print(">>> BULLISH FLAG 1 ACTIVATED: Stochastic K & D < 50");
     }

// FLAG 2: OsMA < 0
   if(flag1_StochBelow50 && !flag2_OsmaBelow0 && !flag3_Hull20Green)
     {
      flag2_OsmaBelow0 = (currentOsMA < 0);
      if(flag2_OsmaBelow0)
         Print(">>> BULLISH FLAG 2 ACTIVATED: OsMA < 0");
     }

// FLAG 3: HMA 20 is green - ENTRY CONFIRMATION
   if(flag1_StochBelow50 && flag2_OsmaBelow0 && !flag3_Hull20Green)
     {
      double hull20Colors[];
      ArraySetAsSeries(hull20Colors, true);
      if(CopyBuffer(h2_hull20Handle, 1, 0, 1, hull20Colors) >= 1) // Buffer 1 for Hull20 color
        {
         int hullColor = (int)hull20Colors[0];
         flag3_Hull20Green = (hullColor == 1);
         if(flag3_Hull20Green)
           {
            Print(">>> BULLISH FLAG 3 ACTIVATED: HMA 20 is GREEN");
            bullishSequenceComplete = true;
            Print("=== BULLISH SEQUENCE COMPLETE ===");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check Bearish Sequential Flags - HULL20 FOR ENTRY              |
//+------------------------------------------------------------------+
void CheckBearishSequentialFlags(double currentK, double currentD, double currentOsMA)
  {
// FLAG 1: Stochastic K & D > 50
   if(!flag1_StochAbove50 && !flag2_OsmaAbove0 && !flag3_Hull20Red)
     {
      flag1_StochAbove50 = (currentK > 50 && currentD > 50);
      if(flag1_StochAbove50)
         Print(">>> BEARISH FLAG 1 ACTIVATED: Stochastic K & D > 50");
     }

// FLAG 2: OsMA > 0
   if(flag1_StochAbove50 && !flag2_OsmaAbove0 && !flag3_Hull20Red)
     {
      flag2_OsmaAbove0 = (currentOsMA > 0);
      if(flag2_OsmaAbove0)
         Print(">>> BEARISH FLAG 2 ACTIVATED: OsMA > 0");
     }

// FLAG 3: HMA 20 is red - ENTRY CONFIRMATION
   if(flag1_StochAbove50 && flag2_OsmaAbove0 && !flag3_Hull20Red)
     {
      double hull20Colors[];
      ArraySetAsSeries(hull20Colors, true);
      if(CopyBuffer(h2_hull20Handle, 1, 0, 1, hull20Colors) >= 1) // Buffer 1 for Hull20 color
        {
         int hullColor = (int)hull20Colors[0];
         flag3_Hull20Red = (hullColor == 2);
         if(flag3_Hull20Red)
           {
            Print(">>> BEARISH FLAG 3 ACTIVATED: HMA 20 is RED");
            bearishSequenceComplete = true;
            Print("=== BEARISH SEQUENCE COMPLETE ===");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Reset All Sequential Flags                                      |
//+------------------------------------------------------------------+
void ResetAllSequentialFlags()
  {
   flag1_StochBelow50 = flag2_OsmaBelow0 = flag3_Hull20Green = false;
   flag1_StochAbove50 = flag2_OsmaAbove0 = flag3_Hull20Red = false;
   bullishSequenceComplete = bearishSequenceComplete = false;
   Print("All sequential flags reset");
  }

//+------------------------------------------------------------------+
//| Update H2 Indicator Values                                      |
//+------------------------------------------------------------------+
bool UpdateH2IndicatorValues()
  {
   if(CopyBuffer(h2_stochHandle, 0, 0, 2, stochKBuffer) < 2)
     {
      Print("ERROR: Failed to copy Stochastic K values");
      return false;
     }
   if(CopyBuffer(h2_stochHandle, 1, 0, 2, stochDBuffer) < 2)
     {
      Print("ERROR: Failed to copy Stochastic D values");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Get H2 OsMA Value                                               |
//+------------------------------------------------------------------+
double GetH2OsMAValue(int shift)
  {
   double value[1];
   if(CopyBuffer(h2_osmaHandle, 0, shift, 1, value) <= 0)
     {
      Print("Error copying H2 OsMA buffer");
      return 0;
     }
   return value[0];
  }

//+------------------------------------------------------------------+
//| Check D1 ADX Conditions                                         |
//+------------------------------------------------------------------+
void CheckD1ADXConditions()
  {
   double adx[], plusDI[], minusDI[];
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(plusDI, true);
   ArraySetAsSeries(minusDI, true);

   if(CopyBuffer(d1_adxHandle, 0, 0, 3, adx) < 3)
      return;
   if(CopyBuffer(d1_adxHandle, 1, 0, 3, plusDI) < 3)
      return;
   if(CopyBuffer(d1_adxHandle, 2, 0, 3, minusDI) < 3)
      return;

   currentADX = adx[0];
   currentPlusDI = plusDI[0];
   currentMinusDI = minusDI[0];

   Print("D1 ADX Updated: ", DoubleToString(currentADX,1),
         " +DI:", DoubleToString(currentPlusDI,1),
         " -DI:", DoubleToString(currentMinusDI,1));
  }

//+------------------------------------------------------------------+
//| Check Trade Opportunities                                       |
//+------------------------------------------------------------------+
void CheckTradeOpportunities()
  {
// BULLISH Trade: All sequential flags + D1 ADX conditions
   if(bullishSequenceComplete && currentADX > D1_ADX_Level)
     {
      Print("=== BULLISH TRADE SIGNAL DETECTED ===");
      Print("ALL BULLISH FLAGS ACTIVATED + D1 ADX CONFIRMED!");

      Print("Executing REAL BUY Trade");
      ExecuteRealBuyTrade();
     }

// BEARISH Trade: All sequential flags + D1 conditions
   if(bearishSequenceComplete && currentADX > D1_ADX_Level)
     {
      Print("=== BEARISH TRADE SIGNAL DETECTED ===");
      Print("ALL BEARISH FLAGS ACTIVATED + D1 ADX CONFIRMED!");

      Print("Executing REAL SELL Trade");
      ExecuteRealSellTrade();
     }
  }

//+------------------------------------------------------------------+
//| Get ATR value from H6 timeframe                                 |
//+------------------------------------------------------------------+
double GetATRValue()
  {
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(h6_atrHandle, 0, 0, 1, atr) < 1)
     {
      Print("Error: Failed to copy H6 ATR values");
      return 0;
     }
   return NormalizeDouble(atr[0], _Digits);
  }

//+------------------------------------------------------------------+
//| Execute Real Buy Trade                                          |
//+------------------------------------------------------------------+
void ExecuteRealBuyTrade()
  {
   if(HasOpenPosition())
     {
      Print("BUY Trade Skipped: Position already active");
      ResetAllSequentialFlags();
      return;
     }

   double atrValue = GetATRValue();
   if(atrValue <= 0)
     {
      Print("BUY Trade Skipped: Invalid ATR value");
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

// Calculate stop loss and take profit using H6 ATR - 3*ATR SL, 7.5*ATR TP
   double stopLoss = ask - (StopLossMultiplier * atrValue);  // 3 * ATR
   double takeProfit = ask + (TakeProfitMultiplier * atrValue); // 7.5 * ATR

   double lotSize = CalculateLotSize(ask, stopLoss);

   Print("H6 ATR Value: ", atrValue,
         " | SL Distance: ", (StopLossMultiplier * atrValue),
         " | TP Distance: ", (TakeProfitMultiplier * atrValue),
         " | Risk-Reward: 1:2.5");

   if(trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit, "H6-H2 Hull BUY"))
     {
      tradeTaken = true;
      tradeCount++;
      Print("REAL BUY Trade Executed: Price=", ask, " SL=", stopLoss, " TP=", takeProfit, " Lots=", lotSize);
      Print("Stop Loss: 3*ATR | Take Profit: 7.5*ATR | Risk-Reward: 1:2.5 | Risk: 1.2%");
      ResetAllSequentialFlags();
     }
   else
     {
      Print("REAL BUY Trade Failed: Error ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Execute Real Sell Trade                                         |
//+------------------------------------------------------------------+
void ExecuteRealSellTrade()
  {
   if(HasOpenPosition())
     {
      Print("SELL Trade Skipped: Position already active");
      ResetAllSequentialFlags();
      return;
     }

   double atrValue = GetATRValue();
   if(atrValue <= 0)
     {
      Print("SELL Trade Skipped: Invalid ATR value");
      return;
     }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

// Calculate stop loss and take profit using H6 ATR - 3*ATR SL, 7.5*ATR TP
   double stopLoss = bid + (StopLossMultiplier * atrValue);  // 3 * ATR
   double takeProfit = bid - (TakeProfitMultiplier * atrValue); // 7.5 * ATR

   double lotSize = CalculateLotSize(bid, stopLoss);

   Print("H6 ATR Value: ", atrValue,
         " | SL Distance: ", (StopLossMultiplier * atrValue),
         " | TP Distance: ", (TakeProfitMultiplier * atrValue),
         " | Risk-Reward: 1:2.5");

   if(trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit, "H6-H2 Hull SELL"))
     {
      tradeTaken = true;
      tradeCount++;
      Print("REAL SELL Trade Executed: Price=", bid, " SL=", stopLoss, " TP=", takeProfit, " Lots=", lotSize);
      Print("Stop Loss: 3*ATR | Take Profit: 7.5*ATR | Risk-Reward: 1:2.5 | Risk: 1.2%");
      ResetAllSequentialFlags();
     }
   else
     {
      Print("REAL SELL Trade Failed: Error ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Check if there's an open position                               |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber)
        {
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                     |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
  {
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = accountEquity * (RiskPercent / 100.0);

   double stopDistance = MathAbs(entryPrice - stopLoss);
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(stopDistance == 0 || pointValue == 0)
     {
      Print("Error: Invalid stop distance or point value");
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
     }

// Calculate pip value for 1 lot
   double pipValue;
   if(_Digits == 3 || _Digits == 5) // 3/5 digit brokers
      pipValue = (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)) / pointValue;
   else
      pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

// Calculate lots based on risk
   double pipsRisk = stopDistance / pointValue;
   double lotSize = riskAmount / (pipsRisk * pipValue);

// Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = MathRound(lotSize / lotStep) * lotStep;

   Print("Lot Calculation: Equity=$", accountEquity,
         " Risk=$", riskAmount, " (", RiskPercent, "%)",
         " StopPips=", pipsRisk,
         " PipValue=$", pipValue,
         " Lots=", lotSize);

   return NormalizeDouble(lotSize, 2);
  }

//+------------------------------------------------------------------+
//| Generate magic number                                           |
//+------------------------------------------------------------------+
long GenerateMagicNumber()
  {
   return (long)(GetTickCount() % 1000000 + 400000);
  }

//+------------------------------------------------------------------+
//| Close all positions                                             |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);
      if(_Symbol == symbol)
        {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         if(!trade.PositionClose(ticket))
           {
            Print(PositionGetSymbol(i), "PositionClose() failed. Return code= " + i, trade.ResultRetcode(), ". Code description: ", trade.ResultRetcodeDescription());
           }
         else
           {
            Print(PositionGetSymbol(i), "PositionClose() successful. Return code=", trade.ResultRetcode(), " (", trade.ResultRetcodeDescription(), ")");
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper function: Get Hull color as text                         |
//+------------------------------------------------------------------+
string GetHullColorText(int colour)
  {
   if(colour == 1)
      return "GREEN (UP)";
   if(colour == 2)
      return "RED (DOWN)";
   if(colour == 0)
      return "GRAY (NEUTRAL)";
   return "UNKNOWN (" + IntegerToString(colour) + ")";
  }

//+------------------------------------------------------------------+
//| Update Chart Comment                                            |
//+------------------------------------------------------------------+
void UpdateChartComment()
  {
   double currentOsMA = GetH2OsMAValue(0);
   double currentK = stochKBuffer[0];
   double currentD = stochDBuffer[0];
   double currentATR = GetATRValue();

// Get H2 Hull20 and Hull50 colors
   double h2_hull20Colors[], h2_hull50Colors[];
   ArraySetAsSeries(h2_hull20Colors, true);
   ArraySetAsSeries(h2_hull50Colors, true);
   int currentHull20Color = 0, currentHull50Color = 0;
   if(CopyBuffer(h2_hull20Handle, 1, 0, 1, h2_hull20Colors) >= 1)
      currentHull20Color = (int)h2_hull20Colors[0];
   if(CopyBuffer(h2_hull50Handle, 3, 0, 1, h2_hull50Colors) >= 1)
      currentHull50Color = (int)h2_hull50Colors[0];

   string commentText = "";
   commentText += "=== H6-H2 HULL TRADING EA v1.10 ===\n";
   commentText += "H6: HMA30 & HMA100 MATCH REQUIRED\n";
   commentText += "H2: Stoch<50 + OsMA<0 + HMA20 Green (Entry)\n";
   commentText += "Exit 1: H6 Hull60 & Hull100 color match\n";
   commentText += "Exit 2: Price near Murrey 0/8 or 8/8 levels\n";
   commentText += "ATR: H6 | SL: 3*ATR | TP: 7.5*ATR | R:R 1:2.5\n";
   commentText += "Risk: 1.2% per trade\n";
   commentText += "D1 Validation: " + (EnableD1HullValidation ? "ENABLED for 2nd trade" : "DISABLED") + "\n\n";

   commentText += "H6 STATUS: " + (h6BullishFlag ? "BULLISH" : h6BearishFlag ? "BEARISH" : "NEUTRAL") + "\n";
   commentText += "H6 Hull60: " + GetHullColorText(h6Hull60CurrentColor) + " | Hull100: " + GetHullColorText(h6Hull100CurrentColor) + "\n";
   commentText += "Color Match: " + (h6Hull60CurrentColor == h6Hull100CurrentColor ? "YES" : "NO") + "\n";
   commentText += "H6 ATR: " + DoubleToString(currentATR, _Digits) + " | SL: " + DoubleToString(StopLossMultiplier * currentATR, _Digits) + " | TP: " + DoubleToString(TakeProfitMultiplier * currentATR, _Digits) + "\n\n";

   commentText += "H2 HULL STATUS:\n";
   commentText += "Hull20: " + GetHullColorText(currentHull20Color) + " | Hull50: " + GetHullColorText(currentHull50Color) + "\n\n";

   commentText += "H2 OSCILLATORS:\n";
   commentText += "Stoch K:" + DoubleToString(currentK,1) + " D:" + DoubleToString(currentD,1) + "\n";
   commentText += "OsMA: " + DoubleToString(currentOsMA,5) + "\n\n";

   commentText += "BULLISH ENTRY SEQUENCE:\n";
   commentText += "1. Stoch <50: " + (flag1_StochBelow50 ? "✓" : "✗") + "\n";
   commentText += "2. OsMA <0: " + (flag2_OsmaBelow0 ? "✓" : "✗") + "\n";
   commentText += "3. Hull20 Green: " + (flag3_Hull20Green ? "✓" : "✗") + "\n";
   commentText += "SEQUENCE: " + (bullishSequenceComplete ? "COMPLETE" : "IN PROGRESS") + "\n\n";

   commentText += "BEARISH ENTRY SEQUENCE:\n";
   commentText += "1. Stoch >50: " + (flag1_StochAbove50 ? "✓" : "✗") + "\n";
   commentText += "2. OsMA >0: " + (flag2_OsmaAbove0 ? "✓" : "✗") + "\n";
   commentText += "3. Hull20 Red: " + (flag3_Hull20Red ? "✓" : "✗") + "\n";
   commentText += "SEQUENCE: " + (bearishSequenceComplete ? "COMPLETE" : "IN PROGRESS") + "\n\n";

   commentText += "D1 CONDITIONS:\n";
   commentText += "ADX: " + DoubleToString(currentADX,1) + " | +DI:" + DoubleToString(currentPlusDI,1) + " | -DI:" + DoubleToString(currentMinusDI,1) + "\n";
   commentText += "ADX Confirmed: " + (currentADX > D1_ADX_Level ? "✓" : "✗") + "\n\n";

   commentText += "MURREY MATH EXIT:\n";
   commentText += "0/8 & 8/8 Proximity: " + IntegerToString(MurrayProximityPips) + " pips\n";
   commentText += "Monitoring: " + (murrayLevelsUpdated ? "ACTIVE" : "INACTIVE") + "\n\n";

   commentText += "TRADING: " + (HasOpenPosition() ? "POSITION ACTIVE" : "NO POSITION") + "\n";
   commentText += "Trade Count: " + IntegerToString(tradeCount);

   Comment(commentText);
  }

//+------------------------------------------------------------------+
//| Trade transaction handler                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   ENUM_TRADE_TRANSACTION_TYPE type = trans.type;
   if(type == TRADE_TRANSACTION_DEAL_ADD)
     {
      long       deal_entry      = 0;
      string     deal_symbol     = "";
      long       deal_magic      = 0;
      double     deal_profit     = 0.0;
      string     deal_comment    = "";

      if(HistoryDealSelect(trans.deal))
        {
         deal_entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         deal_symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         deal_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         deal_profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
        }
      else
         return;

      if(deal_symbol == Symbol() && deal_magic == magicNumber)
        {
         if(deal_entry == DEAL_ENTRY_OUT)
           {
            // Reset trade flags
            tradeTaken = false;

            if(deal_profit > 0)
              {
               // PROFIT - Remove EA immediately
               Print("Trade closed with PROFIT of $", deal_profit, " | Comment: ", deal_comment);
               Comment("Trade closed with PROFIT of $", deal_profit, " | Comment: ", deal_comment);
               ExpertRemove();
              }
            else
               if(deal_profit < 0)
                 {
                  // LOSS - Check if this is first or second trade
                  Print("Trade closed with LOSS of $", deal_profit, " | Comment: ", deal_comment);

                  if(tradeCount >= 2)
                    {
                     // Second trade (whether profit or loss) - Remove EA
                     Print("Second trade completed - Removing EA");
                     ExpertRemove();
                    }
                  else
                    {
                     // First loss - Allow for second trade
                     Print("First trade loss - Allowing for second trade opportunity");
                     // tradeTaken is already false, allowing new trades
                    }
                 }
               else
                 {
                  // BREAK EVEN - Remove EA
                  Print("Trade closed at BREAK EVEN", " | Comment: ", deal_comment);
                  ExpertRemove();
                 }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
