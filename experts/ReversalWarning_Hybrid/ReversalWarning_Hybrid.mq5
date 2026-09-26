
//+------------------------------------------------------------------+
//|                                     ReversalWarning_Hybrid.mq5   |
//|                    Reversal warning with hybrid signal model     |
//|                    Indicators OR candlestick patterns            |
//+------------------------------------------------------------------+
//|                                                                  |
//|  Combines five indicator conditions (EMA, DEMA, ATR, RSI,        |
//|  Bollinger Bands) with five candlestick patterns (bullish and    |
//|  bearish engulfing, hammer, shooting star, dark cloud cover).    |
//|                                                                  |
//|  The user input UseCandlestickOR toggles whether candle signals  |
//|  can fire alone, or must coincide with an indicator condition.   |
//|                                                                  |
//|  Reference implementation. Makes no performance claims.          |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader"
#property version   "1.00""
#property description "Reversal warning EA combining indicator conditions"
#property description "with candlestick patterns via OR logic."
#property description "Reference implementation. No trading logic."


//--- Enumeration of the methods of handle creation
enum Creation
  {
   Call_iBands,            // use iBands
   Call_IndicatorCreate    // use IndicatorCreate
  };


//--- Inputs
input int                 EMA_Period = 200;
input int                 DEMA_Period = 20;
input int                 ATR_Period = 14;
input int                 RSI_Period = 14;
input double              ATR_Threshold = 0.5;
input ENUM_APPLIED_PRICE  Price_Type = PRICE_CLOSE;
input int                 Trend_Lookback = 5;
input double              RSI_Bullish = 55.0;
input double              RSI_Bearish = 45.0;
input bool                UseCandlestickOR = true; // ✅ if true, signals can come from candles OR indicators

//--- Handles
int ema_handle, dema_handle, atr_handle, rsi_handle;
int bb_handle;

//--- Buffers
double ema_buffer[], dema_buffer[], atr_buffer[];
double bb_upper[], bb_middle[], bb_lower[], bb_upper_mid[], bb_lower_mid[];
double rsi_buffer[];

//--- Comment text
string comment_text;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("Initializing Reversal Warning EA (OR-check)...");

   ema_handle  = iMA(_Symbol, PERIOD_H3, EMA_Period, 0, MODE_EMA, Price_Type);
   dema_handle = iDEMA(_Symbol, PERIOD_H3, DEMA_Period, 0, Price_Type);
   atr_handle  = iATR(_Symbol, PERIOD_H3, ATR_Period);
   rsi_handle  = iRSI(_Symbol, PERIOD_H3, RSI_Period, Price_Type);

   // Use custom iBands_Extended
   bb_handle = iCustom(_Symbol, PERIOD_H3, "iBands_Extended",
                       Call_iBands, 20, 0, 2.0, Price_Type, " ", PERIOD_H3);

   if(ema_handle==INVALID_HANDLE || dema_handle==INVALID_HANDLE ||
      atr_handle==INVALID_HANDLE || rsi_handle==INVALID_HANDLE ||
      bb_handle==INVALID_HANDLE)
   {
      Print("Error creating indicator handles. Code: ", GetLastError());
      return(INIT_FAILED);
   }

   ArraySetAsSeries(ema_buffer,true);
   ArraySetAsSeries(dema_buffer,true);
   ArraySetAsSeries(atr_buffer,true);
   ArraySetAsSeries(rsi_buffer,true);

   ArraySetAsSeries(bb_upper,true);
   ArraySetAsSeries(bb_middle,true);
   ArraySetAsSeries(bb_lower,true);
   ArraySetAsSeries(bb_upper_mid,true);
   ArraySetAsSeries(bb_lower_mid,true);

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(ema_handle);
   IndicatorRelease(dema_handle);
   IndicatorRelease(atr_handle);
   IndicatorRelease(rsi_handle);
   IndicatorRelease(bb_handle);
   Comment("");
}
//+------------------------------------------------------------------+
void OnTick()
{
   int required = MathMax(EMA_Period, MathMax(DEMA_Period, MathMax(ATR_Period, Trend_Lookback)))+10;
   if(Bars(_Symbol,PERIOD_H3) < required) return;

   if(!GetIndicatorValues()) return;

   CheckForReversal();
   UpdateComment();
}
//+------------------------------------------------------------------+
bool GetIndicatorValues()
{
   if(CopyBuffer(ema_handle,0,0,Trend_Lookback+1,ema_buffer)<0) return false;
   if(CopyBuffer(dema_handle,0,0,Trend_Lookback+1,dema_buffer)<0) return false;
   if(CopyBuffer(atr_handle,0,0,ATR_Period+1,atr_buffer)<0) return false;
   if(CopyBuffer(rsi_handle,0,0,2,rsi_buffer)<0) return false;

   if(CopyBuffer(bb_handle,0,0,3,bb_upper)<0) return false;
   if(CopyBuffer(bb_handle,1,0,3,bb_lower)<0) return false;
   if(CopyBuffer(bb_handle,2,0,3,bb_middle)<0) return false;
   if(CopyBuffer(bb_handle,3,0,3,bb_upper_mid)<0) return false;
   if(CopyBuffer(bb_handle,4,0,3,bb_lower_mid)<0) return false;

   return true;
}
//+------------------------------------------------------------------+
void CheckForReversal()
{
   double price = iClose(_Symbol,PERIOD_H3,0);

   bool ema_rising  = IsTrendRising(ema_buffer,Trend_Lookback);
   bool ema_falling = IsTrendFalling(ema_buffer,Trend_Lookback);
   bool dema_rising = IsTrendRising(dema_buffer,Trend_Lookback);
   bool dema_falling= IsTrendFalling(dema_buffer,Trend_Lookback);

   double atr_avg=CalculateATR_Average();
   bool atr_low=(atr_buffer[0]<atr_avg*ATR_Threshold);

   double rsi=rsi_buffer[0];

   // ✅ Candlestick confirmations
   bool bullish_candle = IsBullishEngulfing(1) || IsHammer(1);
   bool bearish_candle = IsBearishEngulfing(1) || IsShootingStar(1) || IsDarkCloud(1);

   // Indicator-only warnings
   bool bearish_ind = ema_rising && dema_falling && price<bb_lower_mid[0] && atr_low && rsi<RSI_Bearish;
   bool bullish_ind = ema_falling && dema_rising && price>bb_upper_mid[0] && atr_low && rsi>RSI_Bullish;

   // Final OR check
   bool bearish_warning = bearish_ind || (UseCandlestickOR && bearish_candle);
   bool bullish_warning = bullish_ind || (UseCandlestickOR && bullish_candle);

   if(bearish_warning)
   {
      Alert("Bearish reversal warning (OR-check): ",_Symbol," H3");
      SendNotification("Bearish reversal warning (OR): "+_Symbol);
      PlaySound("alert.wav");
   }
   if(bullish_warning)
   {
      Alert("Bullish reversal warning (OR-check): ",_Symbol," H3");
      SendNotification("Bullish reversal warning (OR): "+_Symbol);
      PlaySound("alert.wav");
   }

   comment_text=StringFormat("Reversal EA OR %s H3\nPrice: %.5f | RSI: %.2f\nEMA: %.5f | DEMA: %.5f\nBB LowerMid: %.5f | UpperMid: %.5f\nATR: %.5f (%.5f avg)\nIndBear=%s | IndBull=%s\nCandleBear=%s | CandleBull=%s",
                             _Symbol,price,rsi,
                             ema_buffer[0],dema_buffer[0],
                             bb_lower_mid[0],bb_upper_mid[0],
                             atr_buffer[0],atr_avg,
                             bearish_ind?"YES":"NO",
                             bullish_ind?"YES":"NO",
                             bearish_candle?"YES":"NO",
                             bullish_candle?"YES":"NO");
}
//+------------------------------------------------------------------+
double CalculateATR_Average()
{
   double sum=0;
   for(int i=1;i<=ATR_Period;i++) sum+=atr_buffer[i];
   return sum/ATR_Period;
}
//+------------------------------------------------------------------+
bool IsTrendRising(double &buf[],int lookback)
{
   for(int i=1;i<lookback;i++) if(buf[i]<buf[i+1]) return false;
   return true;
}
bool IsTrendFalling(double &buf[],int lookback)
{
   for(int i=1;i<lookback;i++) if(buf[i]>buf[i+1]) return false;
   return true;
}
//+------------------------------------------------------------------+
//| Candlestick patterns                                             |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(int shift)
{
   double o1=iOpen(_Symbol,PERIOD_H3,shift+1);
   double c1=iClose(_Symbol,PERIOD_H3,shift+1);
   double o2=iOpen(_Symbol,PERIOD_H3,shift);
   double c2=iClose(_Symbol,PERIOD_H3,shift);
   return (c1<o1 && c2>o2 && c2>o1 && o2<c1);
}
bool IsBearishEngulfing(int shift)
{
   double o1=iOpen(_Symbol,PERIOD_H3,shift+1);
   double c1=iClose(_Symbol,PERIOD_H3,shift+1);
   double o2=iOpen(_Symbol,PERIOD_H3,shift);
   double c2=iClose(_Symbol,PERIOD_H3,shift);
   return (c1>o1 && c2<o2 && c2<o1 && o2>c1);
}
bool IsHammer(int shift)
{
   double o=iOpen(_Symbol,PERIOD_H3,shift);
   double c=iClose(_Symbol,PERIOD_H3,shift);
   double h=iHigh(_Symbol,PERIOD_H3,shift);
   double l=iLow(_Symbol,PERIOD_H3,shift);
   double body=MathAbs(c-o);
   double lower_wick=o<c ? o-l : c-l;
   return (body<(h-l)*0.3 && lower_wick>(h-l)*0.5);
}
bool IsShootingStar(int shift)
{
   double o=iOpen(_Symbol,PERIOD_H3,shift);
   double c=iClose(_Symbol,PERIOD_H3,shift);
   double h=iHigh(_Symbol,PERIOD_H3,shift);
   double l=iLow(_Symbol,PERIOD_H3,shift);
   double body=MathAbs(c-o);
   double upper_wick=h-MathMax(o,c);
   return (body<(h-l)*0.3 && upper_wick>(h-l)*0.5);
}
bool IsDarkCloud(int shift)
{
   double o1=iOpen(_Symbol,PERIOD_H3,shift+1);
   double c1=iClose(_Symbol,PERIOD_H3,shift+1);
   double o2=iOpen(_Symbol,PERIOD_H3,shift);
   double c2=iClose(_Symbol,PERIOD_H3,shift);
   return (c1>o1 && o2>c1 && c2<(o1+c1)/2.0 && c2>o1);
}
//+------------------------------------------------------------------+
void UpdateComment(){ Comment(comment_text); }
