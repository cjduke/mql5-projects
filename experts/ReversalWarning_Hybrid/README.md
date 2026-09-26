# ReversalWarning_Hybrid

A two-file proof of concept demonstrating:

1. Two different methods of creating an indicator handle in MQL5
2. A hybrid signal model combining indicator conditions with candlestick patterns

The pair is published as a reference implementation. It does not place trades.
It demonstrates structure.

## Files

- `iBands_Extended.mq5` — a Bollinger Bands wrapper that exposes five buffers
  (upper, middle, lower, upper-middle, lower-middle). Demonstrates both
  `iBands()` and `IndicatorCreate()` handle-creation methods.
- `candlestick_or_indicators.mq5` — a reversal warning EA that combines five
  indicators (EMA, DEMA, ATR, RSI, Bollinger Bands) with five candlestick
  patterns (bullish/bearish engulfing, hammer, shooting star, dark cloud cover).

## What makes it non-trivial

**Handle creation, both ways.** `Demo_iBands` shows the shortcut method
(`iBands()`) and the generic method (`IndicatorCreate()` with an `MqlParam`
array) side by side. Developers who have only ever used the shortcut can see
exactly what the generic method requires, and why you would choose one over
the other.

**Extended Bollinger Bands.** Standard `iBands` returns three buffers (upper,
middle, lower). The wrapper adds two more — upper-middle and lower-middle —
which are the midpoints between the middle band and each outer band. These
intermediate levels are useful as support/resistance references inside the
band structure.

**Hybrid signal architecture.** The reversal EA uses an OR condition between
two signal sources: indicator-based conditions and candlestick patterns. The
user input `UseCandlestickOR` toggles whether candle signals can fire alone,
or whether they must coincide with an indicator condition. This is a clean
pattern for combining discretionary chart reading with systematic rules.

**Multiple candlestick patterns.** Five patterns are implemented as small
self-contained functions (`IsBullishEngulfing`, `IsBearishEngulfing`,
`IsHammer`, `IsShootingStar`, `IsDarkCloud`). Each can be tested independently.

**Live comment panel.** The EA writes a full state report to the chart on
every tick — indicator values, ATR average, and which signals (indicator or
candle) are currently firing. Useful as a debugging pattern.

## Inputs (candlestick_or_indicators)

- `EMA_Period` — default 200
- `DEMA_Period` — default 20
- `ATR_Period` — default 14
- `RSI_Period` — default 14
- `ATR_Threshold` — ATR filter multiplier (default 0.5)
- `Trend_Lookback` — bars used for trend direction (default 5)
- `RSI_Bullish` / `RSI_Bearish` — RSI thresholds (defaults 55 / 45)
- `UseCandlestickOR` — whether candle signals can fire alone (default true)

## Dependencies

Requires `Demo_iBands.mq5` to be installed in the Indicators folder under
that exact name. The EA calls it via `iCustom()`.

## Notes

This is a proof of concept. It demonstrates patterns for handling indicators
in MQL5 and combining multiple signal sources. It is not intended as a
deployable reversal system, and it makes no performance claims.

