# Experts

Expert Advisors (EAs) for MetaTrader 5.

The EAs in this folder are **reference implementations**. They demonstrate how 
to structure a trading system in MQL5 — state machines, persistent flags, 
multi-timeframe alignment, risk layers, and calendar awareness. They are 
published as code to learn from, not as systems to deploy.

None of them make performance claims. None are intended for live trading 
without substantial modification and independent testing.

## Contents

- [MultiTF_Hull_Example](MultiTF_Hull_Example/) — multi-timeframe Hull system 
  with a sequential three-stage entry state machine
- [LTF_HTF_Hull_Example](LTF_HTF_Hull_Example/) — lower-timeframe entry with 
  higher-timeframe context, using persistent per-timeframe flags
- [NewsCalendarHelper](NewsCalendarHelper/) — utility for reading high-importance 
  economic events affecting the chart symbol

## Common Requirements

All EAs in this folder depend on the `UnifiedHullMA` indicator, which is 
published in the `indicators/` folder of this repository. Compile and install 
that indicator before running any of these EAs.

## Common Notes

- All EAs are written for MetaTrader 5 (MQL5).
- None of them place trades on a live account by default without user configuration.
- Risk parameters (if present) are illustrative and should be reviewed before use.
- Code is provided as-is, without warranty. See the repository root for license.
