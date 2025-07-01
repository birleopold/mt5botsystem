# Regime-Adaptive Neural Scalper (MQL5)

## Overview
This Expert Advisor (EA) is a sophisticated, adaptive scalping system for MetaTrader 5, designed to dynamically adjust its trading behavior based on market regime, neural network predictions, portfolio risk, and advanced pattern recognition. It features self-optimizing thresholds, walk-forward parameter tuning, and in-chart controls for live parameter adjustment.

---

## Architecture Summary

### 1. **Input Parameters**
- Extensive set of `input` parameters for risk, thresholds, regime adaptation, partial take-profits, clustering, and feature toggles.
- Key parameters include: `maxPortfolioRiskPct`, `correlatedGroups`, `maxKellyFraction`, `useKellySizing`, `minBuyThresh`, `maxBuyThresh`, `volThreshLo`, `useEnsemble`, `inputRisk`, etc.

### 2. **Feature Extraction**
- Extracts a set of core features from price, volatility, volume, momentum, and market microstructure.
- Additional features for volume spikes, order flow, and imbalance can be toggled.

### 3. **Neural Network Prediction**
- Uses a neural network (MLP) to predict trade direction probability.
- Thresholds for buy/sell are dynamically adjusted based on recent accuracy and regime.

### 4. **Regime Detection and Adaptation**
- Identifies market regimes: Trending Up, Trending Down, High/Low Volatility, Ranging.
- Each regime has its own performance metrics, risk, and thresholds.
- Risk and thresholds are auto-optimized per regime using rolling window statistics.

### 5. **Portfolio Risk and Correlation Management**
- Tracks total portfolio risk as a fraction of balance.
- Blocks or reduces trades if correlated exposure or risk cap is exceeded.

### 6. **Performance Metrics**
- Tracks win rate, profit factor, Sharpe ratio, and drawdown per regime.
- Integrates these metrics into live risk and threshold adaptation.

### 7. **Pattern Discovery and Clustering**
- Maintains rolling statistics for pattern types (bull, bear, none).
- Boosts signals for clusters with high win rate and profit.

### 8. **Walk-Forward & Genetic Parameter Optimization**
- Maintains a population of parameter sets.
- Periodically evaluates and mutates parameter sets based on recent trade performance.

### 9. **Position Sizing (Kelly/Optimal F)**
- Calculates position size using Kelly or Optimal F, capped for safety.
- Adapts to regime-specific win/loss stats.

### 10. **In-Chart Controls & Diagnostics**
- Draws interactive buttons for adjusting risk and thresholds live.
- Displays key diagnostics (regime, prediction, risk, win rate, PF, Sharpe, drawdown) on chart.

---

## Key Functions & Modules

- **GetATR, GetMA, GetADX, GetBands, GetMomentum, GetRSI**: Utility wrappers for indicator values.
- **IsSymbolCorrelated, GetTotalPortfolioRisk, AllowNewTrade**: Portfolio/correlation risk management.
- **UpdatePredictionStats, UpdateRegimeStats**: Tracks and adapts neural and regime stats.
- **UpdatePerformanceMetrics, InitializeMetricArrays**: Rolling window stats for regime performance.
- **UpdateRegimeLearning, UpdateAdaptiveThresholds**: Auto-optimizes regime risk and thresholds.
- **BuildTradeFeatureVector, GetFeatures**: Extracts features for neural and ensemble logic.
- **OnTradeTransaction**: Integrates trade result feedback into learning and stats.
- **CalculateDynamicSize, CalculateKellyFraction, CalculateOptimalF**: Position sizing routines.
- **Pattern/Cluster routines**: Tracks and boosts profitable patterns.
- **WalkForwardOptimize, MutateParamSets**: Walk-forward and genetic optimization.
- **DrawParameterControls, CheckButtonClicks, ShowDiagnostics**: UI and live parameter adjustment.

---

## Usage & Customization

- **Attach to any symbol/timeframe.**
- **Tune input parameters** to match your risk tolerance and trading style.
- **Use in-chart buttons** to adjust risk and thresholds on-the-fly.
- **Monitor chart diagnostics** for regime, prediction, win rate, and performance.
- **Enable/disable features** such as volume spike, imbalance, or order flow as needed.
- **No external files required:** All learning and stats are kept in RAM for speed and privacy.

---

## Notes
- **Neural network and ensemble logic require proper initialization.**
- **Walk-forward/genetic optimization is periodic and does not interfere with live trading.**
- **Partial take-profits and adaptive trailing stops are supported.**
- **Code is modular and can be extended for new features or strategies.**

---

## Extending the System
- **Add new features** to `GetFeatures` and `BuildTradeFeatureVector`.
- **Integrate additional indicators** or pattern recognition modules.
- **Expand regime logic** for more nuanced market state detection.
- **Refine neural training** for better online adaptation.

---

## Disclaimer
This EA is for research and educational purposes. Live trading involves risk. Test thoroughly before deploying on a real account.


I've implemented comprehensive safety features and best practices for your ScalperV3 trading bot to make it robust for live trading. Here's a summary of all the improvements:

1. Risk Management & Position Sizing
Added comprehensive validation for lot size calculations with fallbacks
Capped maximum risk per trade at 3% of account balance
Added proper error handling for invalid tick values and pricing
Implemented lot size validation ensuring broker compliance
2. Trade Execution Safety
Added ValidateStopLevel and ValidateTakeProfitLevel functions to ensure SL/TP levels meet broker requirements
Implemented retry logic for failed orders with intelligent parameter adjustment
Added error handling with specific responses for different error types
Added slippage control via deviation settings
3. Market Condition Monitoring
Implemented IsSafeToTrade() function to check multiple safety conditions
Added spread monitoring with moving average calculation
Added volatility checks to avoid trading during extreme conditions
Added terminal connection check to prevent trading during disconnections
4. Additional Safety Features
Added trading pause after consecutive losses
Added drawdown monitoring and automatic trading pause
Added daily loss limit with automatic trading pause
Added protection against high spread conditions
Added minimum time between trades to prevent overtrading
5. Recovery & Diagnostics
Added comprehensive logging of trading decisions and adjustments
Added fallback mechanisms for all critical calculations
Added connection status tracking for reliable operation
Usage Tips for Live Trading:
Start with small position sizes - The bot now has a 3% maximum risk cap, but consider lowering this further during initial live testing.
Monitor the logs - Look for any [WARNING] or [ERROR] messages to identify issues.
If trading stops automatically due to safety conditions (drawdown, consecutive losses, etc.), you'll need to manually reset the tradingStopped flag.
Adjust the safety parameters in the inputs section based on your broker and risk tolerance.