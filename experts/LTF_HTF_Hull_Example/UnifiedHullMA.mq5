//+------------------------------------------------------------------+
//| UnifiedHullMA.mq5                                                |
//|                                                                  |
//| Hull Moving Average calculation built around the work of         |
//| Mladen Rakic.                                                    |
//|                                                                  |
//| This implementation extends that foundation with multiple Hull   |
//| periods, directional colouring, configurable Hull lines, stable   |
//| buffer layout, and ring-buffer based memory management.          |
//|                                                                  |
//| Copyright © 2026 Alfonso Golden Trader                            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, C.J. Weekes"
#property copyright "Copyright 2026, Alfonso Golden Trader"
#property version   "1.00"
#property description "Hull Moving Average indicator with four periods on a single chart."
#property description "Colour-coded by direction. Ring-buffer memory management."
#property description "Buffer layout: 0/1=Hull1, 2/3=Hull2, 4/5=Hull3, 6/7=Hull4."

#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   4

//--- Hull Line 1 (Buffer 0/1)
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrGray, clrLime, clrRed
#property indicator_width1  2
#property indicator_label1  "Hull1"

//--- Hull Line 2 (Buffer 2/3)
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  clrGray, clrDodgerBlue, clrOrangeRed
#property indicator_width2  2
#property indicator_label2  "Hull2"

//--- Hull Line 3 (Buffer 4/5)
#property indicator_type3   DRAW_COLOR_LINE
#property indicator_color3  clrGray, clrAqua, clrMagenta
#property indicator_width3  2
#property indicator_label3  "Hull3"

//--- Hull Line 4 (Buffer 6/7)
#property indicator_type4   DRAW_COLOR_LINE
#property indicator_color4  clrGray, clrGold, clrDarkOrchid
#property indicator_width4  2
#property indicator_label4  "Hull4"

//--- Input parameters
input int InpPeriod1   = 8;    // Hull 1 Period
input int InpPeriod2   = 20;   // Hull 2 Period
input int InpPeriod3   = 50;   // Hull 3 Period
input int InpPeriod4   = 200;  // Hull 4 Period
input int InpDivisor   = 2;    // Hull Divisor
input int InpMaxBars   = 5000; // Max bars to retain (0 = unlimited)

//--- Indicator buffers
double hull1Buffer[], color1Buffer[];
double hull2Buffer[], color2Buffer[];
double hull3Buffer[], color3Buffer[];
double hull4Buffer[], color4Buffer[];

//+------------------------------------------------------------------+
//| CHull class - memory-optimized Hull MA calculator                |
//+------------------------------------------------------------------+
class CHull
{
private:
   int m_fullPeriod;
   int m_halfPeriod;
   int m_sqrtPeriod;
   int m_maxBars;
   int m_arraySize;
   double m_weight1;
   double m_weight2;
   double m_weight3;
   double m_divisor;

   struct sHullArrayStruct
   {
      double value;
      double value3;
      double wsum1;
      double wsum2;
      double wsum3;
      double lsum1;
      double lsum2;
      double lsum3;
   };

   sHullArrayStruct m_array[];

   void ZeroArray()
   {
      for(int i = 0; i < m_arraySize; i++)
      {
         m_array[i].value  = 0;
         m_array[i].value3 = 0;
         m_array[i].wsum1  = 0;
         m_array[i].wsum2  = 0;
         m_array[i].wsum3  = 0;
         m_array[i].lsum1  = 0;
         m_array[i].lsum2  = 0;
         m_array[i].lsum3  = 0;
      }
   }

public:
   CHull() : m_fullPeriod(1), m_halfPeriod(1), m_sqrtPeriod(1),
             m_maxBars(0), m_arraySize(0), m_divisor(2.0) { }
   ~CHull() { ArrayFree(m_array); }

   bool init(int period, double divisor, int maxBars=0)
   {
      m_divisor    = (divisor > 1.0) ? divisor : 2.0;
      m_fullPeriod = (int)(period > 1 ? period : 1);
      m_halfPeriod = (int)(m_fullPeriod > 1 ? m_fullPeriod / m_divisor : 1);
      m_sqrtPeriod = (int)MathSqrt(m_fullPeriod);
      m_maxBars    = (maxBars > m_fullPeriod * 2) ? maxBars : 0;
      m_arraySize  = 0;
      m_weight1    = m_weight2 = m_weight3 = 1;

      if(m_maxBars > 0)
      {
         m_arraySize = ArrayResize(m_array, m_maxBars);
         if(m_arraySize < m_maxBars) return false;
         ZeroArray();
      }
      return true;
   }

   double calculate(double value, int i, int bars)
   {
      if(m_maxBars <= 0)
      {
         if(m_arraySize < bars)
         {
            m_arraySize = ArrayResize(m_array, bars + 500);
            if(m_arraySize < bars) return 0;
         }
         return CalculateUnlimited(value, i);
      }
      return CalculateRingBuffer(value, i);
   }

private:
   double CalculateUnlimited(double value, int i)
   {
      m_array[i].value = value;

      if(i > m_fullPeriod)
      {
         m_array[i].wsum1 = m_array[i-1].wsum1 + value * m_halfPeriod - m_array[i-1].lsum1;
         m_array[i].lsum1 = m_array[i-1].lsum1 + value - m_array[i-m_halfPeriod].value;
         m_array[i].wsum2 = m_array[i-1].wsum2 + value * m_fullPeriod - m_array[i-1].lsum2;
         m_array[i].lsum2 = m_array[i-1].lsum2 + value - m_array[i-m_fullPeriod].value;
      }
      else
      {
         m_array[i].wsum1 = m_array[i].wsum2 =
         m_array[i].lsum1 = m_array[i].lsum2 = m_weight1 = m_weight2 = 0;
         for(int k=0, w1=m_halfPeriod, w2=m_fullPeriod; w2>0 && i>=k; k++, w1--, w2--)
         {
            if(w1>0)
            {
               m_array[i].wsum1 += m_array[i-k].value * w1;
               m_array[i].lsum1 += m_array[i-k].value;
               m_weight1        += w1;
            }
            m_array[i].wsum2 += m_array[i-k].value * w2;
            m_array[i].lsum2 += m_array[i-k].value;
            m_weight2        += w2;
         }
      }

      m_array[i].value3 = 2.0 * m_array[i].wsum1 / m_weight1 - m_array[i].wsum2 / m_weight2;

      if(i > m_sqrtPeriod)
      {
         m_array[i].wsum3 = m_array[i-1].wsum3 + m_array[i].value3 * m_sqrtPeriod - m_array[i-1].lsum3;
         m_array[i].lsum3 = m_array[i-1].lsum3 + m_array[i].value3 - m_array[i-m_sqrtPeriod].value3;
      }
      else
      {
         m_array[i].wsum3 =
         m_array[i].lsum3 = m_weight3 = 0;
         for(int k=0, w3=m_sqrtPeriod; w3>0 && i>=k; k++, w3--)
         {
            m_array[i].wsum3 += m_array[i-k].value3 * w3;
            m_array[i].lsum3 += m_array[i-k].value3;
            m_weight3        += w3;
         }
      }

      return(m_array[i].wsum3 / m_weight3);
   }

   double CalculateRingBuffer(double value, int i)
   {
      int idx     = i % m_maxBars;
      int prevIdx = (i > 0) ? (i-1) % m_maxBars : idx;

      m_array[idx].value = value;

      if(i > m_fullPeriod)
      {
         int halfBackIdx = (i - m_halfPeriod) % m_maxBars;
         int fullBackIdx = (i - m_fullPeriod) % m_maxBars;

         m_array[idx].wsum1 = m_array[prevIdx].wsum1 + value * m_halfPeriod - m_array[prevIdx].lsum1;
         m_array[idx].lsum1 = m_array[prevIdx].lsum1 + value - m_array[halfBackIdx].value;
         m_array[idx].wsum2 = m_array[prevIdx].wsum2 + value * m_fullPeriod - m_array[prevIdx].lsum2;
         m_array[idx].lsum2 = m_array[prevIdx].lsum2 + value - m_array[fullBackIdx].value;
      }
      else
      {
         m_array[idx].wsum1 = m_array[idx].wsum2 =
         m_array[idx].lsum1 = m_array[idx].lsum2 = m_weight1 = m_weight2 = 0;
         for(int k=0, w1=m_halfPeriod, w2=m_fullPeriod; w2>0 && i>=k; k++, w1--, w2--)
         {
            int backIdx = (i - k) % m_maxBars;
            if(w1>0)
            {
               m_array[idx].wsum1 += m_array[backIdx].value * w1;
               m_array[idx].lsum1 += m_array[backIdx].value;
               m_weight1          += w1;
            }
            m_array[idx].wsum2 += m_array[backIdx].value * w2;
            m_array[idx].lsum2 += m_array[backIdx].value;
            m_weight2          += w2;
         }
      }

      m_array[idx].value3 = 2.0 * m_array[idx].wsum1 / m_weight1 - m_array[idx].wsum2 / m_weight2;

      if(i > m_sqrtPeriod)
      {
         int sqrtBackIdx = (i - m_sqrtPeriod) % m_maxBars;
         m_array[idx].wsum3 = m_array[prevIdx].wsum3 + m_array[idx].value3 * m_sqrtPeriod - m_array[prevIdx].lsum3;
         m_array[idx].lsum3 = m_array[prevIdx].lsum3 + m_array[idx].value3 - m_array[sqrtBackIdx].value3;
      }
      else
      {
         m_array[idx].wsum3 =
         m_array[idx].lsum3 = m_weight3 = 0;
         for(int k=0, w3=m_sqrtPeriod; w3>0 && i>=k; k++, w3--)
         {
            int backIdx = (i - k) % m_maxBars;
            m_array[idx].wsum3 += m_array[backIdx].value3 * w3;
            m_array[idx].lsum3 += m_array[backIdx].value3;
            m_weight3          += w3;
         }
      }

      return(m_array[idx].wsum3 / m_weight3);
   }
};

CHull iHull1, iHull2, iHull3, iHull4;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, hull1Buffer,   INDICATOR_DATA);
   SetIndexBuffer(1, color1Buffer,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, hull2Buffer,   INDICATOR_DATA);
   SetIndexBuffer(3, color2Buffer,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, hull3Buffer,   INDICATOR_DATA);
   SetIndexBuffer(5, color3Buffer,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6, hull4Buffer,   INDICATOR_DATA);
   SetIndexBuffer(7, color4Buffer,  INDICATOR_COLOR_INDEX);

   iHull1.init(InpPeriod1, InpDivisor, InpMaxBars);
   iHull2.init(InpPeriod2, InpDivisor, InpMaxBars);
   iHull3.init(InpPeriod3, InpDivisor, InpMaxBars);
   iHull4.init(InpPeriod4, InpDivisor, InpMaxBars);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("UnifiedHullMA(%d,%d,%d,%d)",
                   InpPeriod1, InpPeriod2, InpPeriod3, InpPeriod4));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return INIT_SUCCEEDED;
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
   int i = prev_calculated - 1;
   if(i < 0) i = 0;

   for(; i < rates_total && !_StopFlag; i++)
   {
      double price = close[i];

      hull1Buffer[i] = iHull1.calculate(price, i, rates_total);
      hull2Buffer[i] = iHull2.calculate(price, i, rates_total);
      hull3Buffer[i] = iHull3.calculate(price, i, rates_total);
      hull4Buffer[i] = iHull4.calculate(price, i, rates_total);

      if(i > 0)
      {
         color1Buffer[i] = (hull1Buffer[i] > hull1Buffer[i-1]) ? 1 :
                           ((hull1Buffer[i] < hull1Buffer[i-1]) ? 2 : color1Buffer[i-1]);
         color2Buffer[i] = (hull2Buffer[i] > hull2Buffer[i-1]) ? 1 :
                           ((hull2Buffer[i] < hull2Buffer[i-1]) ? 2 : color2Buffer[i-1]);
         color3Buffer[i] = (hull3Buffer[i] > hull3Buffer[i-1]) ? 1 :
                           ((hull3Buffer[i] < hull3Buffer[i-1]) ? 2 : color3Buffer[i-1]);
         color4Buffer[i] = (hull4Buffer[i] > hull4Buffer[i-1]) ? 1 :
                           ((hull4Buffer[i] < hull4Buffer[i-1]) ? 2 : color4Buffer[i-1]);
      }
      else
      {
         color1Buffer[i] = color2Buffer[i] = color3Buffer[i] = color4Buffer[i] = 0;
      }
   }
   return rates_total;
}
//+------------------------------------------------------------------+