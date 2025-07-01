//+------------------------------------------------------------------+
//| ScalperV3 - Advanced Algorithmic Trading System                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "3.0"
#property strict

#include <Trade/Trade.mqh>
// Keep everything in a single file as requested

// Define trading error constants if not already defined
#ifndef ERR_NOT_ENOUGH_MONEY
#define ERR_NOT_ENOUGH_MONEY 4109
#endif

#ifndef ERR_TRADE_DISABLED
#define ERR_TRADE_DISABLED 4062
#endif

#ifndef ERR_INVALID_STOPS
#define ERR_INVALID_STOPS 4063
#endif

#ifndef ERR_INVALID_TRADE_VOLUME
#define ERR_INVALID_TRADE_VOLUME 4064
#endif

// Trailing TP configuration
input bool   useTrailingTakeProfit = true;    // Enable Trailing Take Profit functionality
input double tpExtensionFactor = 1.3;         // Factor to extend TP after a TP hit (reduced from 1.5)
input double profitStepMultiplier = 0.7;      // Multiplier for calculating next TP step (increased from 0.6)
input int    maxTPTrailCount = 0;             // Maximum number of take profit trail steps (0 = unlimited)

// Entry filter improvements for high-frequency trading
input bool   useConfirmationFilter = true;   // Use additional confirmation filters for entries
input double minimumPredictionThreshold = 0.60; // Minimum prediction threshold for entry (increased)
input int    minimumSignalStrength = 3;      // Minimum confirming signals (increased from 2)
input bool   waitForCandleClose = false;     // Disabled for HFT
input bool   useMarketStructureFilter = true; // Use market structure alignment
input bool   useVolatilityFilter = true;     // Filter out high volatility periods
input double volatilityThreshold = 1.5;      // Maximum volatility multiplier for entries
input bool   useMomentumFilter = true;       // Use momentum confirmation
input bool   avoidChoppy = true;             // Avoid trading in choppy market conditions

// Risk management inputs
input double maxKellyFraction = 0.1; // Maximum Kelly fraction to use
input bool useKellySizing = true;  // Use Kelly criterion for position sizing
input double autoTPFactor = 1.5;   // Auto TP factor
input double autoSLFactor = 1.0;   // Auto SL factor
input double maxDrawdownPct = 5.0; // Maximum drawdown percentage allowed
input double maxDailyLossPct = 2.0; // Maximum daily loss percentage allowed
input int regimePersistBars = 8;   // Minimum bars to confirm a regime (reduced from 10)
input double regimeWinLo = 0.4;     // Threshold for tightening risk
input double regimeWinHi = 0.6;     // Threshold for loosening risk

// High-frequency trading parameters and safety features
input int minSecondsBetweenTrades = 15;   // Reduced from 30 for HFT, but still safer than 5
input double maxSpreadFactor = 0.25;      // Maximum spread as a factor of ATR
input bool enableSpreadProtection = true;  // Enable spread protection
input bool enableNewsFilter = true;        // Avoid trading during high-impact news
input int newsFilterMinutes = 15;          // Minutes to avoid trading before/after news
input double maxSlippagePips = 2.0;        // Maximum allowed slippage in pips
input int maxConsecutiveLosses = 3;        // Maximum consecutive losses before stopping
input int maxPositionsPerSymbol = 1;       // Maximum positions per symbol
input double slMultiplier = 0.6;           // SL multiplier for ATR (reduced from 0.8 for HFT)
input double tpMultiplier = 1.0;           // TP multiplier for ATR (reduced from 1.2 for HFT)
input double riskRewardRatio = 1.67;       // Target risk-reward ratio (TP/SL) (5:3 ratio)
input double minStopLoss = 12.0;           // Minimum stop loss in points (reduced for HFT)
input double maxStopLoss = 25.0;           // Maximum stop loss in points (reduced for HFT)
input double minTakeProfit = 20.0;         // Minimum take profit in points (reduced for HFT)
input double maxTakeProfit = 42.0;         // Maximum take profit in points (reduced for HFT)
input bool useAggressiveTrailing = true;  // Use aggressive trailing stops
input double trailingActivationPct = 0.75; // Activate trailing at % of TP reached (increased)
input double scalingFactor = 0.8;         // Position scaling factor for multiple positions (increased from 0.7)
input double maxPortfolioRiskPct = 0.8;   // Maximum portfolio risk percentage (increased from 0.6)
input double trailingStopPoints = 100; // Trailing stop in points

//+------------------------------------------------------------------+
//| Constants and Feature Definitions                                |
//+------------------------------------------------------------------+
#define MAX_FEATURES 15
#define METRIC_WINDOW 50
#define ACCURACY_WINDOW 50
#define PARAM_POP 5
#define PARAM_WINDOW 50
#define K_CLUSTERS 5
#define REGIME_COUNT 9  // Updated to match all implemented regimes
#define PATTERN_CLUSTER_SIZE 10
#define PATTERN_BULL 1
#define PATTERN_BEAR -1
#define PATTERN_NONE 0
#define RSI_PERIOD 14
#define MOMENTUM_PERIOD 14
#define ATR_PERIOD 14
#define MA_PERIOD 20
#define TRENDING_UP 0
#define TRENDING_DOWN 1
#define HIGH_VOLATILITY 2
#define LOW_VOLATILITY 3
#define RANGING_NARROW 4
#define RANGING_WIDE 5
#define BREAKOUT 6
#define REVERSAL 7
#define CHOPPY 8

// Feature toggle inputs for building feature vectors
input bool usePattern = true;      // Use pattern recognition
input bool useRegime = true;       // Use regime detection
input bool useProfit = true;       // Use profit history
input bool useDuration = true;     // Use trade duration
input bool useATR = true;          // Use volatility (ATR)
input bool useSharpe = true;       // Use Sharpe ratio
input bool useVolumeSpike = false; // Use volume spike detection
input bool useImbalance = false;   // Use order book imbalance
input bool useOrderFlow = false;   // Use order flow analysis
input bool useEnsemble = true;     // Use ensemble prediction

//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
// Trade object
CTrade trade;

// Indicator buffers
double atrBuffer[];
double maBuffer[];
double volBuffer[];
double skewBuffer[];

// Runtime variables
double runtimeRisk = 0.02;
double dynamicBuyThresh = 0.52;  // Further lowered from 0.55 to make buying easier
double dynamicSellThresh = 0.48;  // Further raised from 0.45 to make selling easier

// Trade and statistics counters
int tradePtr = 0;
int predictionCount = 0;
int regimeBarCount = 0;
int lastRegime = -1;
int dailyTradeCount = 0;
int trainSampleCount = 0;
double lastTradeProfit = 0.0;
int winStreak = 0;
int lossStreak = 0;

// Regime statistics arrays
int regimeWins[];
int regimeLosses[];
double regimeProfit[];
double regimeAccuracy[];
double regimeRisk[];

// Performance metrics arrays
double tradeProfits[];
double tradeLosses[];
double tradeReturns[];
double tradeEquity[];
double regimeProfitFactor[];
double regimeSharpe[];
double regimeDrawdown[];
double globalEquity[];
double predictionResults[];
double regimePredictionResults[];
double tradeResults[];
double clusterProfit[];
double clusterWinRate[];
double regimeDynamicRisk[];
double regimeDynamicBuyThresh[];
double regimeDynamicSellThresh[];

// Safety tracking variables
datetime lastTradeTime = 0;          // Time of last trade
datetime lastSpreadCheck = 0;        // Time of last spread check
double spreadHistory[20];            // Recent spread history
double avgSpread = 0;                // Average spread
int spreadHistoryIndex = 0;          // Index for spread history
bool tradingStopped = false;         // Flag to stop trading on critical issues
int failedOrderAttempts = 0;         // Count of consecutive failed order attempts
bool terminalConnected = false;      // MT5 terminal connection status
int prevPosTotal = 0;                // Previous position count for recovery
double dailyProfit = 0.0;            // Track daily profit for risk management

// Machine learning arrays
double trainFeatures[PARAM_WINDOW][MAX_FEATURES];
double trainTargets[PARAM_WINDOW];
double paramPerf[];   // Performance tracking for parameter sets

// Current regime and volatility
int currentRegime = 0;
double atr = 0.0;
double regimeRiskMin = 0.01;
double regimeRiskMax = 1.0;

// Parameter set structure
struct ParamSet {
    double risk;
    double buyThresh;
    double sellThresh;
    double patternWeight;
    double perf;
};
ParamSet paramSets[];
int currentParam = 0;
int paramPtr = 0;

// Pattern arrays
double patternWin[];
double patternProfit[];
double patternType[];
double _adaptiveBuyThresh[];
double _adaptiveSellThresh[];

// Additional inputs
input string correlatedGroups = "EURUSD,GBPUSD;AUDUSD,NZDUSD;USDJPY,CHFJPY"; // Correlated pairs
input int correlationFilterMode = 1;  // 0=off, 1=block, 2=reduce size
input int InpOrderDeviation = 10;     // Order deviation (slippage) in points
input ulong InpMagicNumber = 32042025; // Unique magic number for this EA instance

//+------------------------------------------------------------------+
//| Safety check function for spread, news and connectivity          |
//+------------------------------------------------------------------+
bool IsSafeToTrade() {
    // SAFETY: Stop trading if manually disabled
    if(tradingStopped) {
        Print("[SAFETY] Trading has been stopped due to critical issues. Reset EA to resume.");
        return false;
    }
    
    // SAFETY: Check for terminal connection
    terminalConnected = TerminalInfoInteger(TERMINAL_CONNECTED);
    if(!terminalConnected) {
        Print("[SAFETY] Terminal is not connected to broker. Skipping trade.");
        return false;
    }
    
    // SAFETY: Check consecutive losses
    if(lossStreak >= maxConsecutiveLosses) {
        Print("[SAFETY] Maximum consecutive losses reached (", maxConsecutiveLosses, "). Trading paused.");
        tradingStopped = true;
        return false;
    }
    
    // SAFETY: Check for drawdown limit - use a more relaxed approach for scalping
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double drawdownPct = 100 * (1 - equity / balance);
    if(drawdownPct > maxDrawdownPct * 1.2) { // Allow 20% more drawdown for scalping
        Print("[SAFETY] Maximum drawdown reached: ", drawdownPct, "%. Trading paused.");
        tradingStopped = true;
        return false;
    }
    
    // SAFETY: Check for daily loss limit - use a more relaxed approach for scalping
    if(dailyTradeCount > 0 && dailyProfit < 0 && MathAbs(dailyProfit)/balance*100 > maxDailyLossPct * 1.2) {
        Print("[SAFETY] Maximum daily loss reached: ", MathAbs(dailyProfit)/balance*100, "%. Trading paused.");
        tradingStopped = true;
        return false;
    }
    
    // SAFETY: Check trading frequency - already reduced to 1 second
    if(TimeCurrent() - lastTradeTime < minSecondsBetweenTrades) {
        // Not an error, just skipping this tick
        return false;
    }
    
    // SAFETY: Calculate and monitor spread - using relaxed settings
    double currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // Update spread history for monitoring
    if(TimeCurrent() - lastSpreadCheck > 60) { // Once per minute
        spreadHistory[spreadHistoryIndex] = currentSpread;
        spreadHistoryIndex = (spreadHistoryIndex + 1) % 20; // Circular buffer of last 20 checks
        
        // Calculate average spread
        avgSpread = 0;
        int count = 0;
        for(int i=0; i<20; i++) {
            if(spreadHistory[i] > 0) {
                avgSpread += spreadHistory[i];
                count++;
            }
        }
        if(count > 0) avgSpread /= count;
        lastSpreadCheck = TimeCurrent();
    }
    
    // SAFETY: Check if spread is too high - relaxed for scalping
    if(enableSpreadProtection && avgSpread > 0) {
        double maxSpread = avgSpread * maxSpreadFactor * 1.2; // Allow 20% higher spread
        if(currentSpread > maxSpread) {
            Print("[SAFETY] Current spread too high: ", currentSpread, 
                  " > max allowed: ", maxSpread, ". Skipping trade.");
            return false;
        }
    }
    
    // SAFETY: Check for high volatility - relaxed for scalping
    double currentATR = GetATR(_Symbol, PERIOD_M5, 14);
    double dayATR = GetATR(_Symbol, PERIOD_D1, 14);
    if(currentATR > dayATR * 2.5) { // Relaxed from 2.0 to 2.5
        Print("[SAFETY] Current volatility too high (", currentATR, " > ", dayATR * 2.5, "). Skipping trade.");
        return false;
    }
    
    // All checks passed
    return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Set up trade object
    trade.SetDeviationInPoints(InpOrderDeviation);
    trade.SetExpertMagicNumber(InpMagicNumber);
    
    // Initialize indicator buffers
    ArrayResize(atrBuffer, 100); 
    for(int i=0; i<100; i++) atrBuffer[i] = 0.0;
    
    ArrayResize(maBuffer, 100); 
    for(int i=0; i<100; i++) maBuffer[i] = 0.0;
    
    ArrayResize(volBuffer, 100); 
    for(int i=0; i<100; i++) volBuffer[i] = 0.0;
    
    ArrayResize(skewBuffer, 100); 
    for(int i=0; i<100; i++) skewBuffer[i] = 0.0;
    
    // Initialize regime arrays
    ArrayResize(regimeWins, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeWins[i] = 0;
    
    ArrayResize(regimeLosses, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeLosses[i] = 0;
    
    ArrayResize(regimeProfit, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeProfit[i] = 0.0;
    
    ArrayResize(regimeAccuracy, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeAccuracy[i] = 0.0;
    
    ArrayResize(regimeRisk, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeRisk[i] = 0.0;
    
    ArrayResize(regimeDynamicRisk, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeDynamicRisk[i] = 0.02;
    
    ArrayResize(regimeDynamicBuyThresh, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeDynamicBuyThresh[i] = 0.65;
    
    ArrayResize(regimeDynamicSellThresh, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeDynamicSellThresh[i] = 0.35;
    
    ArrayResize(regimeProfitFactor, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeProfitFactor[i] = 1.0;
    
    ArrayResize(regimeSharpe, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeSharpe[i] = 0.0;
    
    ArrayResize(regimeDrawdown, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) regimeDrawdown[i] = 0.0;
    
    // Initialize performance metric arrays
    // Initialize arrays with loops instead of ArrayInitialize
    ArrayResize(predictionResults, ACCURACY_WINDOW); 
    for(int i=0; i<ACCURACY_WINDOW; i++) predictionResults[i] = 0;
    
    ArrayResize(tradeProfits, METRIC_WINDOW); 
    for(int i=0; i<METRIC_WINDOW; i++) tradeProfits[i] = 0.0;
    
    ArrayResize(tradeLosses, METRIC_WINDOW); 
    for(int i=0; i<METRIC_WINDOW; i++) tradeLosses[i] = 0.0;
    
    ArrayResize(tradeReturns, METRIC_WINDOW); 
    for(int i=0; i<METRIC_WINDOW; i++) tradeReturns[i] = 0.0;
    
    ArrayResize(tradeEquity, METRIC_WINDOW); 
    for(int i=0; i<METRIC_WINDOW; i++) tradeEquity[i] = 0.0;
    
    ArrayResize(globalEquity, METRIC_WINDOW); 
    for(int i=0; i<METRIC_WINDOW; i++) globalEquity[i] = 0.0;
    
    ArrayResize(paramPerf, PARAM_POP); 
    for(int i=0; i<PARAM_POP; i++) paramPerf[i] = 0.0;
    
    ArrayResize(tradeResults, PARAM_WINDOW); 
    for(int i=0; i<PARAM_WINDOW; i++) tradeResults[i] = 0.0;
    
    ArrayResize(clusterProfit, K_CLUSTERS); 
    for(int i=0; i<K_CLUSTERS; i++) clusterProfit[i] = 0.0;
    
    ArrayResize(clusterWinRate, K_CLUSTERS); 
    for(int i=0; i<K_CLUSTERS; i++) clusterWinRate[i] = 0.0;
    
    // Initialize pattern arrays
    ArrayResize(patternWin, PATTERN_CLUSTER_SIZE); 
    for(int i=0; i<PATTERN_CLUSTER_SIZE; i++) patternWin[i] = 0.0;
    
    ArrayResize(patternProfit, PATTERN_CLUSTER_SIZE); 
    for(int i=0; i<PATTERN_CLUSTER_SIZE; i++) patternProfit[i] = 0.0;
    
    ArrayResize(patternType, PATTERN_CLUSTER_SIZE); 
    for(int i=0; i<PATTERN_CLUSTER_SIZE; i++) patternType[i] = 0.0;
    
    ArrayResize(_adaptiveBuyThresh, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) _adaptiveBuyThresh[i] = 0.6;
    
    ArrayResize(_adaptiveSellThresh, REGIME_COUNT); 
    for(int i=0; i<REGIME_COUNT; i++) _adaptiveSellThresh[i] = 0.4;
    
    // Initialize parameter sets
    ArrayResize(paramSets, PARAM_POP);
    for(int i=0; i<PARAM_POP; i++) {
        paramSets[i].risk = 0.02 + 0.01*i;
        paramSets[i].buyThresh = 0.65 - 0.02*i;
        paramSets[i].sellThresh = 0.35 + 0.02*i;
        paramSets[i].patternWeight = 0.1 + 0.05*i;
        paramSets[i].perf = 0.0;
    }
    
    // Reset counters
    tradePtr = 0;
    paramPtr = 0;
    predictionCount = 0;
    regimeBarCount = 0;
    lastRegime = -1;
    trainSampleCount = 0;
    
    Print("[Init] ScalperV3 initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clean up any objects created by the EA
    ObjectsDeleteAll(0, "ScalperV3_");
    
    // Log performance statistics
    double totalProfit = 0.0;
    for(int i=0; i<REGIME_COUNT; i++) {
        totalProfit += regimeProfit[i];
    }
    
    // Calculate overall win rate
    int totalWins = 0;
    int totalLosses = 0;
    for(int i=0; i<REGIME_COUNT; i++) {
        totalWins += ::regimeWins[i];
        totalLosses += ::regimeLosses[i];
    }
    double winRate = (totalWins + totalLosses > 0) ? (double)totalWins/(totalWins + totalLosses) : 0;
    
    // Log final statistics
    Print("[Deinit] ScalperV3 terminated. Reason code: ", reason);
    Print("[Deinit] Total profit: ", totalProfit);
    Print("[Deinit] Win rate: ", winRate);
    Print("[Deinit] Total trades: ", totalWins + totalLosses);
}

//+------------------------------------------------------------------+
//| Market Regime Detection Function                                 |
//+------------------------------------------------------------------+
int DetectRegime(string symbol, ENUM_TIMEFRAMES tf) {
    // This function is now deprecated in favor of FastRegimeDetection
    // But we'll update it to handle all 9 regimes for backward compatibility
    
    // Get indicators for regime detection
    double atr = GetATR(symbol, tf, ATR_PERIOD);
    double ma = GetMA(symbol, tf, MA_PERIOD, MODE_EMA);
    double price = SymbolInfoDouble(symbol, SYMBOL_LAST);
    double vol = GetVolatility(symbol, tf);
    
    // Store in buffers for later use
    for(int i=99; i>0; i--) {
        atrBuffer[i] = atrBuffer[i-1];
        maBuffer[i] = maBuffer[i-1];
        volBuffer[i] = volBuffer[i-1];
    }
    atrBuffer[0] = atr;
    maBuffer[0] = ma;
    volBuffer[0] = vol;
    
    // Calculate trend direction
    bool isTrendUp = price > ma;
    
    // Calculate volatility state
    double avgVol = 0;
    for(int i=0; i<10; i++) {
        avgVol += volBuffer[i];
    }
    avgVol /= 10;
    bool isHighVol = vol > avgVol * 1.2; // 20% higher than average
    
    // Get the current regime using FastRegimeDetection for more accurate detection with all 9 regimes
    int regime = FastRegimeDetection(symbol);
    
    // Update regime stats if regime changed
    if(regime != lastRegime) {
        regimeBarCount = 0;
        lastRegime = regime;
    } else {
        regimeBarCount++;
    }
    
    // Update dynamic thresholds based on regime
    dynamicBuyThresh = regimeDynamicBuyThresh[regime];
    dynamicSellThresh = regimeDynamicSellThresh[regime];
    runtimeRisk = regimeDynamicRisk[regime];
    
    return regime;
}

//+------------------------------------------------------------------+
//| Global Constants and Input Parameters                           |
//+------------------------------------------------------------------+
#define METRIC_WINDOW (50)
#define ACCURACY_WINDOW (50)
#define PARAM_POP (5)
#define PARAM_WINDOW (50)
#define K_CLUSTERS 5
#define PATTERN_CLUSTER_SIZE 10

// Note: REGIME_COUNT is already defined at the top of the file

//+------------------------------------------------------------------+
//| Utility functions for indicator values                          |
//+------------------------------------------------------------------+
// Overloaded version with default shift=0
double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period) {
    return GetATR(symbol, tf, period, 0);
}

double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period, int shift) {
    int handle = iATR(symbol, tf, period);
    double buffer[];
    if(handle != INVALID_HANDLE && CopyBuffer(handle, 0, shift, 1, buffer) == 1) {
        IndicatorRelease(handle);
        return buffer[0];
    }
    if(handle != INVALID_HANDLE) IndicatorRelease(handle);
    return 0.0;
}

double GetADX(string symbol, ENUM_TIMEFRAMES tf, int period, int shift) {
    int handle = iADX(symbol, tf, period);
    double buffer[];
    if(handle != INVALID_HANDLE && CopyBuffer(handle, 0, shift, 1, buffer) == 1) {
        IndicatorRelease(handle);
        return buffer[0];
    }
    if(handle != INVALID_HANDLE) IndicatorRelease(handle);
    return 0.0;
}

// Simplified version with defaults
double GetMA(string symbol, ENUM_TIMEFRAMES tf, int period, ENUM_MA_METHOD ma_method = MODE_EMA) {
    return GetMA(symbol, tf, period, 0, ma_method, PRICE_CLOSE, 0);
}

double GetMA(string symbol, ENUM_TIMEFRAMES tf, int period, int ma_shift, ENUM_MA_METHOD ma_method, ENUM_APPLIED_PRICE applied_price, int shift) {
    int handle = iMA(symbol, tf, period, ma_shift, ma_method, applied_price);
    double buffer[];
    if(handle != INVALID_HANDLE && CopyBuffer(handle, 0, shift, 1, buffer) == 1) {
        IndicatorRelease(handle);
        return buffer[0];
    }
    if(handle != INVALID_HANDLE) IndicatorRelease(handle);
    return 0.0;
}

// Define Bollinger Bands buffer indices
#define BANDS_BASE 0
#define BANDS_UPPER 1
#define BANDS_LOWER 2

double GetBands(string symbol, ENUM_TIMEFRAMES tf, int period, double deviation, int bands_shift, ENUM_APPLIED_PRICE applied_price, int mode, int shift) {
    int handle = iBands(symbol, tf, period, deviation, bands_shift, applied_price);
    double buffer[];
    if(handle != INVALID_HANDLE && CopyBuffer(handle, mode, shift, 1, buffer) == 1) {
        IndicatorRelease(handle);
        return buffer[0];
    }
    if(handle != INVALID_HANDLE) IndicatorRelease(handle);
    return 0.0;
}

// Add missing GetVolatility function
double GetVolatility(string symbol, ENUM_TIMEFRAMES tf) {
    // Calculate volatility as normalized ATR
    double atr = GetATR(symbol, tf, 14);
    double price = SymbolInfoDouble(symbol, SYMBOL_LAST);
    
    // Avoid division by zero
    if(price <= 0) return 0.0;
    
    // Return ATR as percentage of price
    return atr / price * 100.0;
}

double GetImbalance(string symbol, ENUM_TIMEFRAMES tf) {
    MqlTick ticks[100];
    int copied = CopyTicks(symbol, ticks, COPY_TICKS_ALL, 0, 100);
    if(copied <= 0) return 0.0;
    
    double buyVolume = 0.0, sellVolume = 0.0;
    for(int i=0; i<copied; i++) {
        if((ticks[i].flags & TICK_FLAG_BUY) != 0) buyVolume += (double)ticks[i].volume;
        else if((ticks[i].flags & TICK_FLAG_SELL) != 0) sellVolume += (double)ticks[i].volume;
    }
    
    double totalVolume = buyVolume + sellVolume;
    if(totalVolume <= 0) return 0.0;
    
    return (buyVolume - sellVolume) / totalVolume; // Returns -1.0 to 1.0 for sell/buy imbalance
}

// Overloaded version with default shift=0
double GetMomentum(string symbol, ENUM_TIMEFRAMES tf, int period) {
    return GetMomentum(symbol, tf, period, 0);
}

double GetMomentum(string symbol, ENUM_TIMEFRAMES tf, int period, int shift) {
    int handle = iMomentum(symbol, tf, period, PRICE_CLOSE);
    double buffer[];
    if(handle != INVALID_HANDLE && CopyBuffer(handle, 0, shift, 1, buffer) == 1) {
        IndicatorRelease(handle);
        return buffer[0];
    }
    if(handle != INVALID_HANDLE) IndicatorRelease(handle);
    return 0.0;
}

// Overloaded version with default shift=0
double GetRSI(string symbol, ENUM_TIMEFRAMES tf, int period) {
    return GetRSI(symbol, tf, period, 0);
}

double GetRSI(string symbol, ENUM_TIMEFRAMES tf, int period, int shift) {
    int handle = iRSI(symbol, tf, period, PRICE_CLOSE);
    double buffer[];
    if(handle != INVALID_HANDLE && CopyBuffer(handle, 0, shift, 1, buffer) == 1) {
        IndicatorRelease(handle);
        return buffer[0];
    }
    if(handle != INVALID_HANDLE) IndicatorRelease(handle);
    return 0.0;
}

//+------------------------------------------------------------------+
//| Advanced Performance Metrics: Profit Factor, Sharpe, Drawdown    |
//+------------------------------------------------------------------+

double CalculateSharpe(int regime) {
    double mean=0, stdev=0, n=0;
    if(ArraySize(tradeReturns) < METRIC_WINDOW) ArrayResize(tradeReturns, METRIC_WINDOW);
    for(int i=0; i<ArraySize(tradeReturns); i++) {
        mean += tradeReturns[i];
        if(tradeReturns[i]!=0) n++;
    }
    if(n==0) return 0.0;
    mean /= n;
    for(int i=0; i<ArraySize(tradeReturns); i++) {
        if(tradeReturns[i]!=0) stdev += MathPow(tradeReturns[i]-mean,2);
    }
    stdev = (n>1) ? MathSqrt(stdev/(n-1)) : 0.0;
    if(stdev>0)
        return mean/stdev;
    else
        return mean;
}

double CalculateMaxDrawdown(int regime) {
    double peak = -1e10, maxDD = 0;
    if(ArraySize(tradeEquity) < METRIC_WINDOW) ArrayResize(tradeEquity, METRIC_WINDOW);
    for(int i=0; i<ArraySize(tradeEquity); i++) {
        double eq = tradeEquity[i];
        if(eq > peak) peak = eq;
        double dd = (peak - eq);
        if(dd > maxDD) maxDD = dd;
    }
    return maxDD;
}

//+------------------------------------------------------------------+
//| Neural Prediction System                                         |
//+------------------------------------------------------------------+
// Global weights and bias for the neural network
static double nn_weights[MAX_FEATURES] = {0.1, -0.2, 0.3, 0.4, -0.1, 0.2, 0.5, -0.3, 0.1, 0.2, 0.3, -0.4, 0.1, 0.2, 0.3};
static double nn_bias = 0.1;

double NeuralPredict() {
    double localFeatures[MAX_FEATURES];
    double output = 0.0;
    GetFeatures(localFeatures);
    for (int i = 0; i < MAX_FEATURES; i++) {
        output += localFeatures[i] * nn_weights[i];
    }
    output += nn_bias;
    output = 1.0 / (1.0 + MathExp(-output));
    return output; // Returns a probability between 0 and 1
}

//+------------------------------------------------------------------+
//| Kelly/Optimal F Position Sizing                                  |
//+------------------------------------------------------------------+
// maxKellyFraction and useKellySizing are already defined above

double CalculateKellyFraction(int regime) {
    // Use rolling stats
    double winRate = regimeAccuracy[regime];
    double avgWin = 0, avgLoss = 0;
    int wins=0, losses=0;
    for(int i=0; i<METRIC_WINDOW; i++) {
        double p = tradeProfits[i];
        double l = tradeLosses[i];
        if(p > 0) { avgWin += p; wins++; }
        if(l < 0) { avgLoss += l; losses++; }
    }
    avgWin = (wins>0) ? avgWin/wins : 0.0;
    avgLoss = (losses>0) ? avgLoss/losses : 0.0;
    double b = (avgLoss != 0) ? MathAbs(avgWin/avgLoss) : 1.0;
    double q = 1.0 - winRate;
    double kelly = (b*winRate - q) / b;
    if(kelly < 0) kelly = 0.01;
    kelly = MathMin(maxKellyFraction, kelly);
    return kelly;
}

double CalculateOptimalF(int regime) {
    double maxWin = 0, maxLoss = 0;
    for(int i=0; i<METRIC_WINDOW; i++) {
        if(::tradeProfits[i]>maxWin) maxWin = ::tradeProfits[i];
        if(::tradeLosses[i]<maxLoss) maxLoss = ::tradeLosses[i];
    }
    double f = (maxWin > 0 && maxLoss < 0) ? 0.5 * (maxWin/(-maxLoss)) : 0.01;
    f = MathMin(maxKellyFraction, f);
    if(f < 0.01) f = 0.01;
    return f;
}

//+------------------------------------------------------------------+
//| Validate stop loss levels with broker requirements               |
//+------------------------------------------------------------------+
double ValidateStopLevel(double stopLevel, bool isBuy) {
    // SAFETY: Ensure the stop level is positive and within a reasonable range
    if(stopLevel <= 0) {
        Print("[ERROR] Invalid stop level (negative or zero): ", stopLevel);
        // Return a default safe stop level based on direction
        double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        return isBuy ? currentPrice * 0.99 : currentPrice * 1.01; // Default 1% away
    }
    
    // SAFETY: Get the minimum stop level from broker
    long stopLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    if(stopLevelPoints <= 0) stopLevelPoints = 10; // Default to 10 points if not specified
    
    double minStopLoss = stopLevelPoints * _Point;
    
    // SAFETY: Get current prices (double check to make sure they're valid)
    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    if(currentBid <= 0 || currentAsk <= 0) {
        Print("[ERROR] Invalid current prices: Bid=", currentBid, " Ask=", currentAsk);
        return 0; // Cannot proceed with invalid prices
    }
    
    // Use the correct price based on order direction
    double currentPrice = isBuy ? currentBid : currentAsk;
    
    // SAFETY: Validate the stop is on the correct side of the price
    if((isBuy && stopLevel > currentPrice) || (!isBuy && stopLevel < currentPrice)) {
        Print("[ERROR] Stop loss is on wrong side of current price. Current=", currentPrice, ", SL=", stopLevel);
        // Return a corrected stop on the right side
        return isBuy ? currentPrice * 0.99 : currentPrice * 1.01; // Default 1% away on correct side
    }
    
    // SAFETY: Validate distance from current price
    double distance = isBuy ? currentPrice - stopLevel : stopLevel - currentPrice;
    
    // Handle possibly negative distance (shouldn't happen after above checks but just in case)
    if(distance < 0) {
        Print("[ERROR] Negative distance calculated between price and stop: ", distance);
        return isBuy ? currentPrice * 0.99 : currentPrice * 1.01; // Safe fallback
    }
    
    // Check if stop is too close
    if(distance < minStopLoss) {
        Print("[WARNING] Stop level too close to current price (", distance, " < ", minStopLoss, "). Adjusting.");
        return isBuy ? currentPrice - minStopLoss * 1.1 : currentPrice + minStopLoss * 1.1;
    }
    
    // Check if stop is too far (greater than 5% away)
    double maxDistance = currentPrice * 0.05;
    if(distance > maxDistance) {
        Print("[WARNING] Stop level too far from current price (", distance, " > ", maxDistance, "). Adjusting.");
        return isBuy ? currentPrice * 0.95 : currentPrice * 1.05;
    }
    
    // Stop level is valid
    return stopLevel;
}

//+------------------------------------------------------------------+
//| Validate take profit levels with broker requirements             |
//+------------------------------------------------------------------+
double ValidateTakeProfitLevel(double tpLevel, bool isBuy) {
    // SAFETY: Ensure the take profit level is positive and within a reasonable range
    if(tpLevel <= 0) {
        Print("[ERROR] Invalid take profit level (negative or zero): ", tpLevel);
        // Return a default safe take profit level based on direction
        double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        return isBuy ? currentPrice * 1.01 : currentPrice * 0.99; // Default 1% away
    }
    
    // SAFETY: Get the minimum stop level from broker
    long stopLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    if(stopLevelPoints <= 0) stopLevelPoints = 10; // Default to 10 points if not specified
    
    double minTpDistance = stopLevelPoints * _Point;
    
    // SAFETY: Get current prices (double check to make sure they're valid)
    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    if(currentBid <= 0 || currentAsk <= 0) {
        Print("[ERROR] Invalid current prices: Bid=", currentBid, " Ask=", currentAsk);
        return 0; // Cannot proceed with invalid prices
    }
    
    // Use the correct price based on order direction
    double currentPrice = isBuy ? currentBid : currentAsk;
    
    // SAFETY: Validate the TP is on the correct side of the price
    if((isBuy && tpLevel < currentPrice) || (!isBuy && tpLevel > currentPrice)) {
        Print("[ERROR] Take profit is on wrong side of current price. Current=", currentPrice, ", TP=", tpLevel);
        // Return a corrected TP on the right side
        return isBuy ? currentPrice * 1.01 : currentPrice * 0.99; // Default 1% away on correct side
    }
    
    // SAFETY: Validate distance from current price
    double distance = isBuy ? tpLevel - currentPrice : currentPrice - tpLevel;
    
    // Handle possibly negative distance (shouldn't happen after above checks but just in case)
    if(distance < 0) {
        Print("[ERROR] Negative distance calculated between price and take profit: ", distance);
        return isBuy ? currentPrice * 1.01 : currentPrice * 0.99; // Safe fallback
    }
    
    // Check if TP is too close
    if(distance < minTpDistance) {
        Print("[WARNING] Take profit too close to current price (", distance, " < ", minTpDistance, "). Adjusting.");
        return isBuy ? currentPrice + minTpDistance * 1.1 : currentPrice - minTpDistance * 1.1;
    }
    
    // Check if TP is too far (greater than 5% away)
    double maxDistance = currentPrice * 0.05;
    if(distance > maxDistance) {
        Print("[WARNING] Take profit too far from current price (", distance, " > ", maxDistance, "). Adjusting.");
        return isBuy ? currentPrice * 1.05 : currentPrice * 0.95;
    }
    
    // Take profit level is valid
    return tpLevel;
}

//+------------------------------------------------------------------+
//| Get valid lot size for any symbol with comprehensive checks      |
//+------------------------------------------------------------------+
double GetValidLotSize(string symbol, double requestedLotSize) {
    // CRITICAL FIX: For these problematic symbols, immediately override to 0.1
    if(symbol == "EURUSDz" || symbol == "GBPUSDz" || symbol == "XAUUSDz") {
        // Direct hardcoded override for these specific symbols
        Print("[VOLUME OVERRIDE] Symbol=", symbol, " needs specific volume treatment. Using 0.1 lots.");
        return 0.1; // Fixed lot size that works with this broker
    }
    
    // Get symbol volume specifications for other symbols
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    // Safety checks with detailed logging
    if(minLot <= 0 || maxLot <= 0 || lotStep <= 0) {
        Print("[VOLUME WARNING] Symbol ", symbol, " has invalid volume parameters from broker: ",
              "Min=", minLot, " Max=", maxLot, " Step=", lotStep);
              
        // Apply safe defaults
        if(minLot <= 0) minLot = 0.01;
        if(maxLot <= 0) maxLot = 100.0;
        if(lotStep <= 0) lotStep = 0.01;
        
        Print("[VOLUME WARNING] Using safe defaults: Min=", minLot, " Max=", maxLot, " Step=", lotStep);
    }
    
    // Basic bounds check
    double result = requestedLotSize;
    if(result < minLot) result = minLot;
    if(result > maxLot) result = maxLot;
    
    // Ensure it's a multiple of the step size
    int steps = (int)MathRound((result - minLot) / lotStep);
    result = minLot + steps * lotStep;
    
    // Final sanity check
    if(result < minLot) result = minLot;
    
    // Log if we changed the requested size
    if(result != requestedLotSize) {
        Print("[VOLUME] Adjusted lot size for ", symbol, " from ", requestedLotSize, " to ", result,
              " (Min=", minLot, " Max=", maxLot, " Step=", lotStep, ")");
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Calculate position size with comprehensive safety checks         |
//+------------------------------------------------------------------+
double CalculateDynamicSize() {
    // SAFETY: Get account and symbol information with validation
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0) {
        Print("[ERROR] Invalid account balance: ", balance, ". Using minimum size.");
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); // Fallback to minimum
    }
    
    // SAFETY: Validate minimum/maximum lot sizes and steps
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(minLot <= 0 || maxLot <= 0 || lotStep <= 0) {
        Print("[ERROR] Invalid lot parameters for ", _Symbol, ": min=", minLot, " max=", maxLot, " step=", lotStep);
        return 0.01; // Return standard minimum as fallback
    }
    
    // SAFETY: Get stop loss with validation
    double sl = CalculateDynamicSL();
    if(sl <= 0) {
        Print("[WARNING] Invalid SL calculated: ", sl, ". Using default.");
        sl = 20 * _Point; // Use default 20 points as fallback
    }
    
    // SAFETY: Validate tick values
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tickSize <= 0) {
        Print("[WARNING] Invalid tick size. Using point size as fallback.");
        tickSize = _Point; // Fallback
    }
    if(tickValue <= 0) {
        Print("[WARNING] Invalid tick value. Using 0.0001 as fallback.");
        tickValue = 0.0001; // Fallback
    }
    
    // SAFETY: Calculate risk with sensible bounds
    int regime = GetRegimeIndex(currentRegime);
    double kellyFrac = CalculateKellyFraction(regime);
    double optF = CalculateOptimalF(regime);
    double useFrac = useKellySizing ? kellyFrac : optF;
    
    // SAFETY: Cap maximum risk per trade (never risk more than 3%)
    useFrac = MathMin(useFrac, 0.03); 
    
    // SAFETY: Ensure minimum risk isn't too small
    if(useFrac < 0.001) {
        Print("[WARNING] Risk fraction too small: ", useFrac, ". Setting to 0.001.");
        useFrac = 0.001;
    }
    
    // Calculate risk amount and lot size
    double riskAmount = balance * useFrac;
    double lotSize = 0.01; // Default fallback
    
    // SAFETY: Calculate lot size with division by zero protection
    if(sl > 0 && tickValue > 0 && tickSize > 0) {
        lotSize = riskAmount / (sl / tickSize * tickValue);
    } else {
        Print("[ERROR] Cannot calculate lot size, using minimum.");
    }
    
    // SAFETY: Round to valid lot size and validate
    lotSize = MathMax(minLot, MathMin(maxLot, MathFloor(lotSize / lotStep) * lotStep));
    
    // SAFETY: Final validation - ensure lot is within allowed range and is a multiple of lotStep
    if(lotSize < minLot) {
        Print("[WARNING] Calculated lot size below minimum. Using minimum: ", minLot);
        lotSize = minLot;
    }
    if(lotSize > maxLot) {
        Print("[WARNING] Calculated lot size above maximum. Using maximum: ", maxLot);
        lotSize = maxLot;
    }
    
    // SAFETY: Ensure lot is a proper multiple of lotStep
    double lotRemainder = MathMod(lotSize - minLot, lotStep);
    if(lotRemainder != 0) {
        double newLotSize = minLot + MathFloor((lotSize - minLot) / lotStep) * lotStep;
        Print("[WARNING] Adjusting lot size from ", lotSize, " to valid step: ", newLotSize);
        lotSize = newLotSize;
    }
    
    // SAFETY: Final log with all parameters for transparency
    Print("[Sizing] Symbol=", _Symbol, " Regime=", regime, " Kelly=", kellyFrac, 
          " OptF=", optF, " UseFrac=", useFrac, " Risk$=", riskAmount,
          " Lot=", lotSize, " (min=", minLot, ", max=", maxLot, ", step=", lotStep, ")");
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Dynamic SL Wrapper                                              |
//+------------------------------------------------------------------+
double CalculateDynamicSL() {
    double localAtr = GetATR(_Symbol, PERIOD_M5, 14);
    return CalculateDynamicSL(currentRegime, localAtr, autoSLFactor);
}

double CalculateDynamicSL(int regime, double localAtr, double slFactor) {
    double volatilityRatio = localAtr / (GetATR(_Symbol, PERIOD_D1, 14, 0) + 0.00001);
    return slFactor * (1 + volatilityRatio) * localAtr;
}

//+------------------------------------------------------------------+
//| Trade Result Feedback for Performance Tracking                   |
//+------------------------------------------------------------------+
// --- Utility/statistics functions ---
double GetPredictionAccuracy() {
    int correct = 0;
    int window = MathMin(::predictionCount, ACCURACY_WINDOW);
    if(window == 0) return 0.0;
    for(int i=0; i<window; i++) correct += ::predictionResults[i];
    return (double)correct / window;
}

void UpdatePredictionStats(double prediction, double profit) {
    int idx = ::predictionCount % ACCURACY_WINDOW;
    bool correct = (profit > 0 && prediction > 0.5) || (profit < 0 && prediction < 0.5);
    ::predictionResults[idx] = correct ? 1 : 0;
    ::predictionCount++;
    double acc = GetPredictionAccuracy();
    // Auto-calibrate thresholds
    if(acc > 0.7 && ::predictionCount >= ACCURACY_WINDOW) {
        dynamicBuyThresh = MathMax(0.60, dynamicBuyThresh - 0.01);
        dynamicSellThresh = MathMin(0.40, dynamicSellThresh + 0.01);
    } else if(acc < 0.55 && ::predictionCount >= ACCURACY_WINDOW) {
        dynamicBuyThresh = MathMin(0.75, dynamicBuyThresh + 0.01);
        dynamicSellThresh = MathMax(0.25, dynamicSellThresh - 0.01);
    }
    Print("[NeuralAcc] accuracy=", acc, " dynBuy=", dynamicBuyThresh, " dynSell=", dynamicSellThresh);
}

// GetRegimeIndex is now implemented above with support for all 9 regimes

// Helper function to get array index for a regime
int GetRegimeIndex(int regime) {
    // Ensure regime is within valid range
    if(regime < 0 || regime >= REGIME_COUNT) {
        Print("[Warning] Invalid regime: ", regime, ", defaulting to LOW_VOLATILITY");
        return LOW_VOLATILITY;
    }
    return regime;
}

void UpdateRegimeStats(int regime, double prediction, double tradeProfit) {
    int idx = GetRegimeIndex(regime);
    if(tradeProfit > 0) ::regimeWins[idx]++;
    else ::regimeLosses[idx]++;
    ::regimeProfit[idx] += tradeProfit;
    int total = ::regimeWins[idx] + ::regimeLosses[idx];
    if(total > 0) ::regimeAccuracy[idx] = (double)::regimeWins[idx] / total;
    // Dynamic risk adjustment
    if(total >= 10) {
        if(::regimeAccuracy[idx] > 0.7) ::regimeRisk[idx] = MathMin(::regimeRisk[idx] + 0.05, 1.0);
        else if(::regimeAccuracy[idx] < 0.5) ::regimeRisk[idx] = MathMax(::regimeRisk[idx] - 0.05, 0.1);
    }
    Print("[RegimeStats] regime=", idx, " acc=", ::regimeAccuracy[idx], " wins=", ::regimeWins[idx], " losses=", ::regimeLosses[idx], " profit=", ::regimeProfit[idx], " risk=", ::regimeRisk[idx]);
    // Auto-reset thresholds if regime accuracy drops too low
    if(total >= 20 && ::regimeAccuracy[idx] < 0.4) {
        dynamicBuyThresh = 0.7;
        dynamicSellThresh = 0.3;
        Print("[RegimeStats] regime=", idx, " accuracy low, recalibrating thresholds.");
    }
}

void UpdateDailyStats(double tradeProfit) {
    dailyTradeCount++;
    Print("[Stats] Updated daily stats. Trades today: ", dailyTradeCount, " Last profit: ", tradeProfit);
}

void GetFeatures(double &features[]) {
    int featCount = 0;
    features[featCount++] = iClose(_Symbol, PERIOD_M1, 1) - iOpen(_Symbol, PERIOD_M1, 1);
    features[featCount++] = GetATR(_Symbol, PERIOD_M1, 14);
    features[featCount++] = GetRSI(_Symbol, PERIOD_M1, 14) / 100.0;
    features[featCount++] = GetMA(_Symbol, PERIOD_M1, 10, 0, MODE_SMA, PRICE_CLOSE, 0) - GetMA(_Symbol, PERIOD_M1, 20, 0, MODE_SMA, PRICE_CLOSE, 0);
    double bands_upper = GetBands(_Symbol, PERIOD_M1, 20, 2.0, 0, PRICE_CLOSE, 1, 0);
    double bands_lower = GetBands(_Symbol, PERIOD_M1, 20, 2.0, 0, PRICE_CLOSE, 2, 0);
    features[featCount++] = (bands_upper - bands_lower) / GetATR(_Symbol, PERIOD_M1, 14);
    features[featCount++] = GetMomentum(_Symbol, PERIOD_M1, 14, 0) / 100.0;
    if(useVolumeSpike) features[featCount++] = IsVolumeSpike(_Symbol, PERIOD_M1) ? 1.0 : 0.0;
    if(useImbalance) features[featCount++] = GetImbalance(_Symbol, PERIOD_M1);
    if(useOrderFlow) features[featCount++] = GetOrderFlowSignal(_Symbol) ? 1.0 : 0.0;
    for(int i=0; i<featCount; i++) features[i] = MathMax(-1.0, MathMin(1.0, features[i]));
    for(int i=featCount; i<MAX_FEATURES; i++) features[i] = 0.0;
}

void StoreTradeSample(double &features[], double outcome) {
    int idx = trainSampleCount % PARAM_WINDOW;
    for(int i=0;i<MAX_FEATURES;i++) trainFeatures[idx][i] = features[i];
    trainTargets[idx] = outcome;
    trainSampleCount++;
    Print("[Sample] Stored trade sample idx=", idx, " outcome=", outcome);
}

//+------------------------------------------------------------------+
//| Handle trade transactions                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result) {
    // Only process completed deals
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && 
       (trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)) {
        
        // Get deal profit properly
        double dealProfit = 0.0;
        if(HistoryDealSelect(trans.deal)) {
            dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
        }
        
        // Update trade statistics
        lastTradeProfit = dealProfit;
        
        // ... rest of your existing code remains the same ...
        
        // Log trade result
        Print("[TradeResult] profit=", dealProfit, 
              " winStreak=", winStreak, 
              " lossStreak=", lossStreak);
    }
}

//+------------------------------------------------------------------+
//| Ensemble Prediction Function                                     |
//+------------------------------------------------------------------+
double InternalEnsemblePrediction(string symbol, ENUM_TIMEFRAMES tf) {
    // Get indicator values
    double rsi = GetRSI(symbol, tf, RSI_PERIOD);
    double momentum = GetMomentum(symbol, tf, MOMENTUM_PERIOD);
    double atr = GetATR(symbol, tf, ATR_PERIOD);
    double imbalance = GetImbalance(symbol, tf);
    double ma = GetMA(symbol, tf, MA_PERIOD, MODE_EMA);
    double price = SymbolInfoDouble(symbol, SYMBOL_LAST);
    
    // Detect current market regime
    currentRegime = DetectRegime(symbol, tf);
    
    // Calculate base prediction from indicators
    double prediction = 0.5; // Start with neutral prediction
    
    // RSI component (0-100 scale to 0-1 scale)
    double rsiComponent = rsi / 100.0;
    
    // Momentum component (normalize to 0-1 scale)
    double momentumComponent = 0.5;
    if(momentum > 0) {
        momentumComponent = 0.5 + MathMin(momentum / 100.0, 0.5);
    } else {
        momentumComponent = 0.5 - MathMin(MathAbs(momentum) / 100.0, 0.5);
    }
    
    // Imbalance component (already in 0-1 scale)
    double imbalanceComponent = imbalance;
    
    // MA trend component
    double maComponent = 0.5;
    if(price > ma) {
        maComponent = 0.65; // Bullish
    } else if(price < ma) {
        maComponent = 0.35; // Bearish
    }
    
    // Combine components with weights based on regime
    switch(currentRegime) {
        case TRENDING_UP:
            // In uptrend, emphasize momentum and MA cross
            prediction = 0.15*rsiComponent + 0.35*momentumComponent + 0.20*imbalanceComponent + 0.30*maComponent;
            break;
            
        case TRENDING_DOWN:
            // In downtrend, emphasize momentum and MA cross
            prediction = 0.15*rsiComponent + 0.35*momentumComponent + 0.20*imbalanceComponent + 0.30*maComponent;
            break;
            
        case HIGH_VOLATILITY:
            // In high volatility, emphasize volume imbalance and reduce momentum importance
            prediction = 0.10*rsiComponent + 0.15*momentumComponent + 0.55*imbalanceComponent + 0.20*maComponent;
            break;
            
        case LOW_VOLATILITY:
            // In low volatility, emphasize RSI and MA cross
            prediction = 0.35*rsiComponent + 0.15*momentumComponent + 0.15*imbalanceComponent + 0.35*maComponent;
            break;
            
        default:
            prediction = 0.25*rsiComponent + 0.25*momentumComponent + 0.25*imbalanceComponent + 0.25*maComponent;
    }
    
    // Apply pattern recognition if available
    int pattern = RecognizePattern(symbol, tf);
    if(pattern != PATTERN_NONE) {
        double patternWeight = paramSets[currentParam].patternWeight;
        if(pattern == PATTERN_BULL) {
            prediction = (1.0 - patternWeight) * prediction + patternWeight * 0.8; // Bullish pattern
        } else if(pattern == PATTERN_BEAR) {
            prediction = (1.0 - patternWeight) * prediction + patternWeight * 0.2; // Bearish pattern
        }
    }
    
    // Ensure prediction is in valid range [0,1]
    prediction = MathMax(0.0, MathMin(1.0, prediction));
    
    return prediction;
}

//+------------------------------------------------------------------+
//| Pattern Recognition Function                                     |
//+------------------------------------------------------------------+
int RecognizePattern(string symbol, ENUM_TIMEFRAMES tf) {
    // Get recent price data
    double close1 = iClose(symbol, tf, 1);
    double close2 = iClose(symbol, tf, 2);
    double close3 = iClose(symbol, tf, 3);
    double open1 = iOpen(symbol, tf, 1);
    double open2 = iOpen(symbol, tf, 2);
    double open3 = iOpen(symbol, tf, 3);
    double high1 = iHigh(symbol, tf, 1);
    double high2 = iHigh(symbol, tf, 2);
    double high3 = iHigh(symbol, tf, 3);
    double low1 = iLow(symbol, tf, 1);
    double low2 = iLow(symbol, tf, 2);
    double low3 = iLow(symbol, tf, 3);
    
    // Calculate candle sizes
    double body1 = MathAbs(close1 - open1);
    double body2 = MathAbs(close2 - open2);
    double body3 = MathAbs(close3 - open3);
    double range1 = high1 - low1;
    double range2 = high2 - low2;
    double range3 = high3 - low3;
    
    // Check for bullish engulfing pattern
    if(close1 > open1 && close2 < open2 && body1 > body2 && close1 > open2 && open1 < close2) {
        return PATTERN_BULL;
    }
    
    // Check for bearish engulfing pattern
    if(close1 < open1 && close2 > open2 && body1 > body2 && close1 < open2 && open1 > close2) {
        return PATTERN_BEAR;
    }
    
    // Check for bullish hammer
    if(close1 > open1 && body1 < range1 * 0.3 && (high1 - close1) < (close1 - low1) * 0.3) {
        return PATTERN_BULL;
    }
    
    // Check for bearish shooting star
    if(close1 < open1 && body1 < range1 * 0.3 && (close1 - low1) < (high1 - close1) * 0.3) {
        return PATTERN_BEAR;
    }
    
    // Check for morning star (bullish)
    if(close3 < open3 && body3 > body2 && close1 > open1 && body1 > body2 && 
       ((close2 < open2 && close2 > low3) || (close2 > open2 && open2 > low3))) {
        return PATTERN_BULL;
    }
    
    // Check for evening star (bearish)
    if(close3 > open3 && body3 > body2 && close1 < open1 && body1 > body2 && 
       ((close2 > open2 && close2 < high3) || (close2 < open2 && open2 < high3))) {
        return PATTERN_BEAR;
    }
    
    // No recognized pattern
    return PATTERN_NONE;
}

//+------------------------------------------------------------------+
//| Adaptive Risk Management System                                  |
//+------------------------------------------------------------------+
// Stub for missing functions
bool IsVolumeSpike(string symbol, ENUM_TIMEFRAMES tf) { return false; }
bool GetOrderFlowSignal(string symbol) { return false; }
double CalculateDynamicTP() { 
    double localAtr = GetATR(_Symbol, PERIOD_M5, 14);
    double volatilityRatio = localAtr / (GetATR(_Symbol, PERIOD_D1, 14, 0) + 0.00001);
    return autoTPFactor * (1 + volatilityRatio) * localAtr;
}
void ManageOpenPositions() {}
// Duplicate input declarations removed - these are already defined above

//+------------------------------------------------------------------+
//| Fast Trading Functions for High-Frequency Trading                 |
//+------------------------------------------------------------------+

// Fast ATR calculation optimized for speed
double FastATR(string symbol) {
    double highLow[3] = {0,0,0};
    double closePrev[3] = {0,0,0};
    
    for(int i=0; i<3; i++) {
        highLow[i] = iHigh(symbol, PERIOD_M1, i) - iLow(symbol, PERIOD_M1, i);
        if(i > 0) {
            closePrev[i] = MathAbs(iClose(symbol, PERIOD_M1, i) - iClose(symbol, PERIOD_M1, i+1));
        }
    }
    
    // Simple average of recent ranges (faster than full ATR calculation)
    double trueRanges[5];
    trueRanges[0] = highLow[0];
    trueRanges[1] = highLow[1];
    trueRanges[2] = closePrev[1];
    trueRanges[3] = highLow[2];
    trueRanges[4] = closePrev[2];
    
    // Sort and remove extremes for more stable result
    ArraySort(trueRanges);
    return (trueRanges[1] + trueRanges[2] + trueRanges[3]) / 3.0;
}

// Advanced market condition detection for adaptive trading
int FastRegimeDetection(string symbol) {
    // Get price data for multiple timeframes - focus on very recent data for scalping
    double close0 = iClose(symbol, PERIOD_M1, 0);
    double close1 = iClose(symbol, PERIOD_M1, 1);
    double close3 = iClose(symbol, PERIOD_M1, 3);  // Reduced from 5 to 3
    double close5 = iClose(symbol, PERIOD_M1, 5);  // Reduced from 10 to 5
    double close10 = iClose(symbol, PERIOD_M1, 10); // Reduced from 20 to 10
    
    // Get high/low data
    double high0 = iHigh(symbol, PERIOD_M1, 0);
    double high1 = iHigh(symbol, PERIOD_M1, 1);
    double high3 = iHigh(symbol, PERIOD_M1, 3);  // Reduced from 5 to 3
    double low0 = iLow(symbol, PERIOD_M1, 0);
    double low1 = iLow(symbol, PERIOD_M1, 1);
    double low3 = iLow(symbol, PERIOD_M1, 3);  // Reduced from 5 to 3
    
    // Calculate multiple moving averages for trend detection - use shorter periods for scalping
    double ma3 = 0, ma5 = 0, ma10 = 0, ma20 = 0;
    for(int i=0; i<3; i++) ma3 += iClose(symbol, PERIOD_M1, i);
    for(int i=0; i<5; i++) ma5 += iClose(symbol, PERIOD_M1, i);
    for(int i=0; i<10; i++) ma10 += iClose(symbol, PERIOD_M1, i);
    for(int i=0; i<20; i++) ma20 += iClose(symbol, PERIOD_M1, i);
    ma3 /= 3;
    ma5 /= 5;
    ma10 /= 10;
    ma20 /= 20;
    
    // Calculate volatility metrics
    double quickAtr = FastATR(symbol);
    double avgRange = 0;
    for(int i=0; i<5; i++) {  // Reduced from 10 to 5 for faster response
        avgRange += MathAbs(iHigh(symbol, PERIOD_M1, i) - iLow(symbol, PERIOD_M1, i));
    }
    avgRange /= 5;
    
    // Calculate price range over different periods
    double range3 = MathMax(high0, high1) - MathMin(low0, low1);
    double range10 = 0;
    double highestHigh = iHigh(symbol, PERIOD_M1, iHighest(symbol, PERIOD_M1, MODE_HIGH, 10, 0));  // Reduced from 20 to 10
    double lowestLow = iLow(symbol, PERIOD_M1, iLowest(symbol, PERIOD_M1, MODE_LOW, 10, 0));  // Reduced from 20 to 10
    range10 = highestHigh - lowestLow;
    
    // Calculate momentum and direction changes
    double momentum3 = close0 - close3;  // Reduced from 5 to 3
    double momentum5 = close0 - close5;  // Reduced from 10 to 5
    double momentum10 = close0 - close10;  // Reduced from 20 to 10
    
    // Count direction changes (choppiness)
    int directionChanges = 0;
    for(int i=1; i<5; i++) {  // Reduced from 10 to 5
        if((iClose(symbol, PERIOD_M1, i) > iClose(symbol, PERIOD_M1, i+1) && 
            iClose(symbol, PERIOD_M1, i-1) < iClose(symbol, PERIOD_M1, i)) ||
           (iClose(symbol, PERIOD_M1, i) < iClose(symbol, PERIOD_M1, i+1) && 
            iClose(symbol, PERIOD_M1, i-1) > iClose(symbol, PERIOD_M1, i))) {
            directionChanges++;
        }
    }
    
    // Calculate Bollinger Band width (for range detection)
    double bbUpper = GetBands(symbol, PERIOD_M1, 20, 2.0, 0, PRICE_CLOSE, 1, 0);
    double bbLower = GetBands(symbol, PERIOD_M1, 20, 2.0, 0, PRICE_CLOSE, 2, 0);
    double bbWidth = (bbUpper - bbLower) / ma20;
    
    // Check for breakouts
    bool breakoutUp = close0 > bbUpper && close1 <= bbUpper;
    bool breakoutDown = close0 < bbLower && close1 >= bbLower;
    bool insideBands = close0 > bbLower && close0 < bbUpper;
    
    // Check for reversals - more sensitive for scalping
    bool potentialReversal = (momentum3 * momentum10 < 0) && MathAbs(momentum3) > quickAtr * 0.3;  // Reduced threshold from 0.5 to 0.3
    
    // Detect market conditions - adjusted thresholds for scalping
    bool isVolatile = quickAtr > avgRange * 1.2;  // Reduced from 1.3 to 1.2
    bool isVeryVolatile = quickAtr > avgRange * 1.8;  // Reduced from 2.0 to 1.8
    bool isTrendingUp = ma3 > ma5 && ma5 > ma10 && momentum5 > 0;  // Using shorter MAs and momentum
    bool isTrendingDown = ma3 < ma5 && ma5 < ma10 && momentum5 < 0;  // Using shorter MAs and momentum
    bool isChoppy = directionChanges >= 3;  // Reduced from 5 to 3 for shorter timeframe
    bool isRangingNarrow = bbWidth < 0.01 && !isVolatile && insideBands;
    bool isRangingWide = bbWidth >= 0.01 && bbWidth < 0.03 && insideBands;
    
    // Determine market regime based on all factors
    if(breakoutUp || breakoutDown) {
        Print("[Regime] Breakout detected");
        return BREAKOUT;
    }
    
    if(potentialReversal) {
        Print("[Regime] Potential reversal detected");
        return REVERSAL;
    }
    
    if(isChoppy) {
        Print("[Regime] Choppy market detected");
        return CHOPPY;
    }
    
    if(isRangingNarrow) {
        Print("[Regime] Narrow ranging market detected");
        return RANGING_NARROW;
    }
    
    if(isRangingWide) {
        Print("[Regime] Wide ranging market detected");
        return RANGING_WIDE;
    }
    
    if(isTrendingUp && !isVeryVolatile) {
        Print("[Regime] Uptrend detected");
        return TRENDING_UP;
    }
    
    if(isTrendingDown && !isVeryVolatile) {
        Print("[Regime] Downtrend detected");
        return TRENDING_DOWN;
    }
    
    if(isVolatile) {
        Print("[Regime] High volatility detected");
        return HIGH_VOLATILITY;
    }
    
    Print("[Regime] Low volatility detected");
    return LOW_VOLATILITY;
}

// Fast prediction function optimized for speed
double FastPrediction(string symbol) {
    // Get key indicators quickly
    double rsi = GetRSI(symbol, PERIOD_M1, 14);
    
    // Calculate momentum
    double momentum = iClose(symbol, PERIOD_M1, 0) - iClose(symbol, PERIOD_M1, 5); // Reduced from 10 to 5 bars for faster response
    
    // Calculate fast MA cross
    double ma5 = 0, ma10 = 0;
    for(int i=0; i<5; i++) ma5 += iClose(symbol, PERIOD_M1, i);
    for(int i=0; i<10; i++) ma10 += iClose(symbol, PERIOD_M1, i);
    ma5 /= 5;
    ma10 /= 10;
    
    // Get volume imbalance
    double buyVolume = 0, sellVolume = 0;
    MqlTick ticks[10]; // Reduced from 20 to 10 for faster processing
    int copied = CopyTicks(symbol, ticks, COPY_TICKS_TRADE, 0, 10);
    
    if(copied > 0) {
        for(int i=0; i<copied; i++) {
            if(ticks[i].flags & TICK_FLAG_BUY) buyVolume += ticks[i].volume;
            else if(ticks[i].flags & TICK_FLAG_SELL) sellVolume += ticks[i].volume;
        }
    }
    
    double volumeImbalance = (buyVolume + sellVolume > 0) ? 
                            buyVolume / (buyVolume + sellVolume) : 0.5;
    
    // Normalize RSI to 0-1 range
    double rsiNorm = rsi / 100.0;
    
    // Normalize momentum
    double close0 = iClose(symbol, PERIOD_M1, 0);
    double momentumNorm = 0.5;
    if(MathAbs(momentum) > 0) {
        double range = MathMax(0.0001, FastATR(symbol) * 3); // Reduced from 5 to 3 for more sensitivity
        momentumNorm = 0.5 + (momentum / range) * 0.5;
        momentumNorm = MathMax(0, MathMin(1, momentumNorm));
    }
    
    // MA cross signal
    double maCross = (ma5 > ma10) ? 0.7 : 0.3;
    
    // Combine signals with regime-specific weights
    double prediction = 0.5;
    
    switch(currentRegime) {
        case TRENDING_UP:
            // In uptrend, emphasize momentum and MA cross
            prediction = 0.15*rsiNorm + 0.35*momentumNorm + 0.20*volumeImbalance + 0.30*maCross;
            break;
            
        case TRENDING_DOWN:
            // In downtrend, emphasize momentum and MA cross
            prediction = 0.15*rsiNorm + 0.35*momentumNorm + 0.20*volumeImbalance + 0.30*maCross;
            break;
            
        case HIGH_VOLATILITY:
            // In high volatility, emphasize volume imbalance and reduce momentum importance
            prediction = 0.10*rsiNorm + 0.15*momentumNorm + 0.55*volumeImbalance + 0.20*maCross;
            break;
            
        case LOW_VOLATILITY:
            // In low volatility, emphasize RSI and MA cross
            prediction = 0.35*rsiNorm + 0.15*momentumNorm + 0.15*volumeImbalance + 0.35*maCross;
            break;
            
        case RANGING_NARROW:
            {
                // In narrow range, focus on RSI mean reversion
                // Invert RSI for mean reversion (high RSI = sell, low RSI = buy)
                double invertedRsi = 1.0 - rsiNorm;
                prediction = 0.60*invertedRsi + 0.10*momentumNorm + 0.20*volumeImbalance + 0.10*maCross;
            }
            break;
            
        case RANGING_WIDE:
            {
                // In wide range, use both RSI mean reversion and volume
                double rangeRsi = 1.0 - rsiNorm; // Invert for mean reversion
                prediction = 0.40*rangeRsi + 0.15*momentumNorm + 0.30*volumeImbalance + 0.15*maCross;
            }
            break;
            
        case BREAKOUT:
            // In breakout, emphasize momentum and volume
            prediction = 0.10*rsiNorm + 0.40*momentumNorm + 0.40*volumeImbalance + 0.10*maCross;
            break;
            
        case REVERSAL:
            {
                // In reversal, use momentum but invert it (reversal = opposite of recent momentum)
                double invertedMomentum = 1.0 - momentumNorm;
                prediction = 0.25*rsiNorm + 0.40*invertedMomentum + 0.25*volumeImbalance + 0.10*maCross;
            }
            break;
            
        case CHOPPY:
            // In choppy markets, be more conservative and emphasize volume imbalance
            prediction = 0.20*rsiNorm + 0.10*momentumNorm + 0.60*volumeImbalance + 0.10*maCross;
            break;
            
        default:
            // Balanced approach for undefined regimes
            prediction = 0.25*rsiNorm + 0.25*momentumNorm + 0.25*volumeImbalance + 0.25*maCross;
    }
    
    // Adjust prediction to favor trading (bias toward action)
    if(prediction > 0.45 && prediction < 0.55) {
        // If we're in the "uncertain" middle zone, push toward the nearest threshold
        prediction = (prediction >= 0.5) ? MathMin(0.58, prediction + 0.05) : MathMax(0.42, prediction - 0.05);
    }
    
    // Ensure prediction is in valid range
    return MathMax(0.0, MathMin(1.0, prediction));
}

// Fast position sizing optimized for quick calculation
double FastPositionSizing() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    // Quick ATR for risk calculation
    double quickAtr = FastATR(_Symbol);
    double riskAmount = balance * runtimeRisk;
    
    // Calculate lot size based on ATR
    double pointValue = tickValue / tickSize;
    double riskPoints = quickAtr * slMultiplier / Point();
    double lotSize = riskAmount / (riskPoints * pointValue);
    
    // Normalize to valid lot size
    lotSize = MathMax(minLot, MathMin(maxLot, MathFloor(lotSize / lotStep) * lotStep));
    
    return lotSize;
}

// Quick risk check for fast decision making
bool QuickRiskCheck() {
    // Check account health
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    
    // Quick drawdown check
    double drawdown = (balance > 0) ? (balance - equity) / balance : 0;
    if(drawdown > maxDrawdownPct / 100.0) {
        return false;
    }
    
    // Margin level check
    double marginLevel = (margin > 0) ? equity / margin * 100 : 0;
    if(marginLevel < 200 && margin > 0) { // Require at least 200% margin level
        return false;
    }
    
    // Check recent performance
    if(lossStreak >= 5) {
        return false; // Stop after 5 consecutive losses
    }
    
    // Quick time check - avoid trading during major news times
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    
    // Avoid trading around typical news release times
    if((timeStruct.hour == 8 && timeStruct.min >= 25 && timeStruct.min <= 35) || // Major European news
       (timeStruct.hour == 14 && timeStruct.min >= 25 && timeStruct.min <= 35)) { // US news
        return false;
    }
    
    return true;
}

// Count current positions for this symbol and magic number
int CountPositions() {
    int count = 0;
    int total = PositionsTotal();
    
    for(int i=0; i<total; i++) {
        if(PositionGetSymbol(i) == _Symbol && 
           PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            count++;
        }
    }
    
    return count;
}

// Aggressively manage open positions with smart trailing stops
void ManageOpenPositionsAggressively() {
    if(!useAggressiveTrailing) return;
    
    int total = PositionsTotal();
    for(int i=total-1; i>=0; i--) {
        if(PositionGetSymbol(i) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
        
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double stopLoss = PositionGetDouble(POSITION_SL);
        double takeProfit = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        // Calculate profit in points
        double profitPoints = 0;
        if(posType == POSITION_TYPE_BUY) {
            profitPoints = (currentPrice - openPrice) / Point();
        } else {
            profitPoints = (openPrice - currentPrice) / Point();
        }
        
        // Calculate target profit for trailing activation
        double targetProfit = MathAbs(takeProfit - openPrice) * trailingActivationPct;
        
        // Only activate trailing once we've reached the activation threshold
        bool shouldTrail = false;
        double newSL = 0;
        
        if(posType == POSITION_TYPE_BUY) {
            shouldTrail = (currentPrice - openPrice >= targetProfit) && 
                         (stopLoss < currentPrice - FastATR(_Symbol) * 0.8);
            if(shouldTrail) {
                newSL = currentPrice - FastATR(_Symbol) * 0.8;
                if(newSL > stopLoss) {
                    trade.PositionModify(ticket, newSL, takeProfit);
                }
            }
        } else { // POSITION_TYPE_SELL
            shouldTrail = (openPrice - currentPrice >= targetProfit) && 
                         (stopLoss > currentPrice + FastATR(_Symbol) * 0.8 || stopLoss == 0);
            if(shouldTrail) {
                newSL = currentPrice + FastATR(_Symbol) * 0.8;
                if(newSL < stopLoss || stopLoss == 0) {
                    trade.PositionModify(ticket, newSL, takeProfit);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Advanced Adaptive Learning System                                 |
//+------------------------------------------------------------------+
void UpdateRegimeLearning() {
    // Update regime-specific parameters based on performance
    for(int i=0; i<REGIME_COUNT; i++) {
        int totalTrades = ::regimeWins[i] + ::regimeLosses[i];
        if(totalTrades < 5) continue; // Need minimum sample size
        
        // Calculate win rate and adjust thresholds
        double winRate = (::regimeWins[i] + ::regimeLosses[i] > 0) ? 
                        (double)::regimeWins[i] / (::regimeWins[i] + ::regimeLosses[i]) : 0.5;
        
        // Adaptive threshold adjustment
        if(winRate > 0.65) {
            // Good performance - relax thresholds slightly to trade more
            regimeDynamicBuyThresh[i] = MathMax(0.55, regimeDynamicBuyThresh[i] - 0.01);
            regimeDynamicSellThresh[i] = MathMin(0.45, regimeDynamicSellThresh[i] + 0.01);
        } else if(winRate < 0.45) {
            // Poor performance - tighten thresholds to trade less
            regimeDynamicBuyThresh[i] = MathMin(0.80, regimeDynamicBuyThresh[i] + 0.02);
            regimeDynamicSellThresh[i] = MathMax(0.20, regimeDynamicSellThresh[i] - 0.02);
        }
        
        // Adaptive risk adjustment
        if(winRate > 0.60 && regimeProfitFactor[i] > 1.5) {
            // Increase risk slightly when performing well
            regimeDynamicRisk[i] = MathMin(regimeRiskMax, regimeDynamicRisk[i] * 1.05);
        } else if(winRate < 0.50 || regimeProfitFactor[i] < 1.0) {
            // Decrease risk when performing poorly
            regimeDynamicRisk[i] = MathMax(regimeRiskMin, regimeDynamicRisk[i] * 0.90);
        }
        
        // Update profit factor
        double totalProfit = 0, totalLoss = 0;
        for(int j=0; j<METRIC_WINDOW; j++) {
            if(tradeProfits[j] > 0) totalProfit += tradeProfits[j];
            if(tradeLosses[j] < 0) totalLoss += MathAbs(tradeLosses[j]);
        }
        regimeProfitFactor[i] = (totalLoss > 0) ? totalProfit / totalLoss : 1.0;
    }
}

void UpdateAdaptiveThresholds() {
    // Global performance metrics
    double accuracy = GetPredictionAccuracy();
    double profitFactor = CalculateProfitFactor();
    
    // Market volatility adjustment
    double currentVol = GetATR(_Symbol, PERIOD_M5, 14);
    double avgVol = 0;
    for(int i=0; i<10; i++) avgVol += volBuffer[i];
    avgVol /= 10;
    
    // Volatility-based threshold adjustment
    if(currentVol > avgVol * 1.5) {
        // High volatility - be more conservative
        dynamicBuyThresh = MathMin(0.75, dynamicBuyThresh + 0.01);
        dynamicSellThresh = MathMax(0.25, dynamicSellThresh - 0.01);
    } else if(currentVol < avgVol * 0.7 && accuracy > 0.55) {
        // Low volatility and good accuracy - be more aggressive
        dynamicBuyThresh = MathMax(0.60, dynamicBuyThresh - 0.005);
        dynamicSellThresh = MathMin(0.40, dynamicSellThresh + 0.005);
    }
    
    // Consecutive loss protection
    if(lossStreak >= 3) {
        // After 3 consecutive losses, become more conservative
        dynamicBuyThresh = MathMin(0.80, dynamicBuyThresh + 0.03 * lossStreak);
        dynamicSellThresh = MathMax(0.20, dynamicSellThresh - 0.03 * lossStreak);
        runtimeRisk *= 0.8; // Reduce risk after consecutive losses
    }
    
    // Profit factor based adjustment
    if(profitFactor < 1.2 && predictionCount >= ACCURACY_WINDOW) {
        // Poor profit factor - tighten thresholds
        dynamicBuyThresh = MathMin(0.75, dynamicBuyThresh + 0.01);
        dynamicSellThresh = MathMax(0.25, dynamicSellThresh - 0.01);
    }
}

double CalculateProfitFactor() {
    double totalProfit = 0, totalLoss = 0;
    for(int i=0; i<METRIC_WINDOW; i++) {
        if(tradeProfits[i] > 0) totalProfit += tradeProfits[i];
        if(tradeLosses[i] < 0) totalLoss += MathAbs(tradeLosses[i]);
    }
    return (totalLoss > 0) ? totalProfit / totalLoss : 1.0;
}

bool IsTradingAllowed() {
    // Check time-based trading restrictions
    datetime currentTime = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(currentTime, timeStruct);
    
    // Avoid trading during major news or high-impact events
    if(timeStruct.hour == 14 && timeStruct.min >= 25 && timeStruct.min <= 35) {
        return false; // Avoid trading during typical news releases
    }
    
    // Avoid trading during low liquidity periods
    if((timeStruct.hour >= 22 || timeStruct.hour <= 2) && 
       (timeStruct.day_of_week == 5 || timeStruct.day_of_week == 1)) {
        return false; // Avoid weekend transitions
    }
    
    // Check for extreme volatility
    double currentATR = GetATR(_Symbol, PERIOD_M5, 14);
    double dailyATR = GetATR(_Symbol, PERIOD_D1, 14);
    if(currentATR > dailyATR * 0.3) { // If 5-min ATR is more than 30% of daily ATR
        return false; // Market too volatile
    }
    
    // Check for consecutive losses protection
    if(lossStreak >= 5) {
        return false; // Stop after 5 consecutive losses
    }
    
    return CheckDrawdownLimit();
}

bool CheckDrawdownLimit() {
    // Calculate current drawdown
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double drawdown = (balance > 0) ? (balance - equity) / balance : 0;
    
    // Stop trading if drawdown exceeds limit
    if(drawdown > maxDrawdownPct / 100.0) {
        Print("[Risk] Trading halted - Drawdown limit reached: ", drawdown * 100, "% (max: ", maxDrawdownPct, "%)");
        return false;
    }
    
    // Check daily loss limit
    double dailyProfit = 0;
    for(int i=0; i<dailyTradeCount; i++) {
        int idx = (tradePtr - i - 1 + METRIC_WINDOW) % METRIC_WINDOW;
        if(idx >= 0 && idx < METRIC_WINDOW) {
            dailyProfit += tradeProfits[idx];
            dailyProfit += tradeLosses[idx];
        }
    }
    
    if(dailyProfit < -maxDailyLossPct * balance / 100.0) {
        Print("[Risk] Trading halted - Daily loss limit reached: ", dailyProfit, " (max: ", -maxDailyLossPct * balance / 100.0, ")");
        return false;
    }
    
    return true;
}

void ShowDiagnostics(double prediction) {
    // Default thresholds if not in a trade evaluation context
    double buyThresh = 0.6;
    double sellThresh = 0.4;
    
    // Get current regime-specific thresholds if available
    switch(currentRegime) {
        case TRENDING_UP:
            buyThresh = 0.55; sellThresh = 0.35;
            break;
        case TRENDING_DOWN:
            buyThresh = 0.65; sellThresh = 0.45;
            break;
        case HIGH_VOLATILITY:
            buyThresh = 0.65; sellThresh = 0.35;
            break;
        case LOW_VOLATILITY:
            buyThresh = 0.55; sellThresh = 0.45;
            break;
        case RANGING_NARROW:
            buyThresh = 0.55; sellThresh = 0.45;
            break;
        case RANGING_WIDE:
            buyThresh = 0.60; sellThresh = 0.40;
            break;
        case BREAKOUT:
            buyThresh = 0.52; sellThresh = 0.48;
            break;
        case REVERSAL:
            buyThresh = 0.55; sellThresh = 0.45;
            break;
        case CHOPPY:
            buyThresh = 0.70; sellThresh = 0.30;
            break;
    }
    
    string msg = StringFormat(
        "Regime: %d\nPrediction: %.3f\nBuyThresh: %.2f\nSellThresh: %.2f\nTrades: %d\nWinRate: %.2f",
        currentRegime, prediction, buyThresh, sellThresh,
        dailyTradeCount, GetPredictionAccuracy()
    );
    Comment(msg);
}

// Function declarations already defined elsewhere

//+------------------------------------------------------------------+
//| High-Frequency Trading Implementation                            |
//+------------------------------------------------------------------+
void OnTick() {
    // Process on tick level for higher frequency trading
    static datetime lastCheckTime = 0;
    datetime currentTime = TimeCurrent();
    
    // Only check for new trades every few seconds to avoid API overload
    if(currentTime - lastCheckTime < minSecondsBetweenTrades && lastCheckTime > 0) return;
    lastCheckTime = currentTime;
    
    // Quick market regime detection
    currentRegime = FastRegimeDetection(_Symbol);
    
    // Update order blocks and market structure analysis
    FindOrderBlocks(_Symbol, PERIOD_M5);
    AnalyzeMarketStructure(_Symbol, PERIOD_M15);
    
    // Rapid risk assessment
    if(!QuickRiskCheck()) {
        return;
    }
    
    // Manage existing positions with partial profit-taking and adaptive trailing stops
    ManageOpenPositionsAggressivelyImpl();
    
    // Get rapid prediction using optimized indicators
    double prediction = FastPrediction(_Symbol);
    
    // Get current market data
    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double spread = currentAsk - currentBid;
    
    // Quick volatility check
    double quickAtr = FastATR(_Symbol);
    
    // Skip if spread is too high relative to volatility
    if(spread > quickAtr * maxSpreadFactor) {
        return;
    }
    
    // Calculate optimal position size
    double lotSize = FastPositionSizing();
    // Adjust SL/TP levels based on market regime
    double dynamicSL = quickAtr * slMultiplier;
    double dynamicTP = quickAtr * tpMultiplier;
    
    // Regime-specific risk/reward adjustments
    switch(currentRegime) {
        case TRENDING_UP:
        case TRENDING_DOWN:
            // In trends, use slightly wider TP but normal SL for better R:R
            dynamicTP = quickAtr * (tpMultiplier * 1.2);
            break;
            
        case HIGH_VOLATILITY:
            // In high volatility, use slightly wider SL but also wider TP
            dynamicSL = quickAtr * (slMultiplier * 1.2);
            dynamicTP = quickAtr * (tpMultiplier * 1.3);
            break;
            
        case LOW_VOLATILITY:
            // In low volatility, can use tighter SL and TP
            dynamicSL = quickAtr * (slMultiplier * 0.8);
            dynamicTP = quickAtr * (tpMultiplier * 0.9);
            break;
            
        case RANGING_NARROW:
            // In narrow range, use very tight SL/TP
            dynamicSL = quickAtr * (slMultiplier * 0.7);
            dynamicTP = quickAtr * (tpMultiplier * 0.8);
            break;
            
        case RANGING_WIDE:
            // In wide range, use moderate SL/TP
            dynamicSL = quickAtr * slMultiplier;
            dynamicTP = quickAtr * tpMultiplier;
            break;
            
        case BREAKOUT:
            // In breakout, use tight SL and wider TP
            dynamicSL = quickAtr * (slMultiplier * 0.7);
            dynamicTP = quickAtr * (tpMultiplier * 1.5);
            break;
            
        case REVERSAL:
            // In reversal, use moderate SL and TP
            dynamicSL = quickAtr * (slMultiplier * 1.0);
            dynamicTP = quickAtr * (tpMultiplier * 1.1);
            break;
            
        case CHOPPY:
            // In choppy markets, use slightly wider SL and moderate TP
            dynamicSL = quickAtr * (slMultiplier * 1.1);
            dynamicTP = quickAtr * tpMultiplier;
            break;
            
        default:
            // Default parameters
            dynamicSL = quickAtr * 1.0;
            dynamicTP = quickAtr * 1.2;
    }
    
    // Ensure minimum SL/TP values
    dynamicSL = MathMax(dynamicSL, minStopLoss * _Point);
    dynamicTP = MathMax(dynamicTP, minTakeProfit * _Point);
    
    // Ensure maximum SL/TP values for scalping
    dynamicSL = MathMin(dynamicSL, maxStopLoss * _Point);
    
    // Force minimum risk-reward ratio to improve profitability
    dynamicTP = MathMax(dynamicTP, dynamicSL * riskRewardRatio);
    
    // Final cap on TP
    dynamicTP = MathMin(dynamicTP, maxTakeProfit * _Point);
    
    // Convert to points for logging
    double slPoints = dynamicSL / _Point;
    double tpPoints = dynamicTP / _Point;
    
    Print("[SL/TP] SL: ", slPoints, " points, TP: ", tpPoints, " points, Ratio: ", dynamicTP/dynamicSL);
    
    // Position management - allow multiple positions with scaling
    int currentPositions = CountPositions();
    bool canOpenNewPosition = currentPositions < maxPositionsPerSymbol;
    
    // Adjust lot size based on scaling factor if we already have positions
    if(currentPositions > 0) {
        lotSize *= MathPow(scalingFactor, currentPositions);
    }
    
    // Only consider new trades if we can open more positions
    if(canOpenNewPosition) {
        // Show diagnostics for monitoring
        ShowDiagnostics(prediction);
        
        // Get additional confirmation filters
        double rsi = GetRSI(_Symbol, PERIOD_M1, RSI_PERIOD);
        double momentum = GetMomentum(_Symbol, PERIOD_M1, MOMENTUM_PERIOD);
        double atr = FastATR(_Symbol);
        double imbalance = GetImbalance(_Symbol, PERIOD_M1);
        
        // Advanced pattern recognition
        int pattern = RecognizePattern(_Symbol, PERIOD_M1);
        
        // Calculate market noise ratio (Efficiency Ratio)
        double priceChange = MathAbs(iClose(_Symbol, PERIOD_M1, 14) - iClose(_Symbol, PERIOD_M1, 0));
        double sumMovement = 0;
        for(int i=0; i<14; i++) {
            sumMovement += MathAbs(iClose(_Symbol, PERIOD_M1, i) - iClose(_Symbol, PERIOD_M1, i+1));
        }
        double efficiencyRatio = (sumMovement > 0) ? priceChange / sumMovement : 0;
        
        // Adapt entry thresholds based on market regime
        double buyThreshold = 0.6;  // Default threshold
        double sellThreshold = 0.4;  // Default threshold
        int rsiUpperLimit = 75;     // Default RSI upper limit
        int rsiLowerLimit = 25;     // Default RSI lower limit
        
        // Adjust thresholds based on market regime
        switch(currentRegime) {
            case TRENDING_UP:
                // In uptrend, easier to go long, harder to go short
                buyThreshold = 0.48;  // Lowered from 0.50
                sellThreshold = 0.45;  // Raised from 0.40
                rsiUpperLimit = 80;
                rsiLowerLimit = 30;
                break;
                
            case TRENDING_DOWN:
                // In downtrend, easier to go short, harder to go long
                buyThreshold = 0.55;  // Lowered from 0.60
                sellThreshold = 0.52;  // Raised from 0.50
                rsiUpperLimit = 70;
                rsiLowerLimit = 20;
                break;
                
            case HIGH_VOLATILITY:
                // In high volatility, be more selective
                buyThreshold = 0.55;  // Lowered from 0.60
                sellThreshold = 0.45;  // Raised from 0.40
                rsiUpperLimit = 75;
                rsiLowerLimit = 25;
                break;
                
            case LOW_VOLATILITY:
                // In low volatility, be more aggressive
                buyThreshold = 0.48;  // Lowered from 0.50
                sellThreshold = 0.52;  // Raised from 0.50
                rsiUpperLimit = 70;
                rsiLowerLimit = 30;
                break;
                
            case RANGING_NARROW:
                // In narrow range, focus on mean reversion
                buyThreshold = 0.48;  // Lowered from 0.50
                sellThreshold = 0.52;  // Raised from 0.50
                rsiUpperLimit = 70;
                rsiLowerLimit = 30;
                break;
                
            case RANGING_WIDE:
                // In wide range, use both RSI mean reversion and volume
                buyThreshold = 0.52;  // Lowered from 0.55
                sellThreshold = 0.48;  // Raised from 0.45
                rsiUpperLimit = 75;
                rsiLowerLimit = 25;
                break;
                
            case BREAKOUT:
                // In breakout, be more aggressive
                buyThreshold = 0.48;  // Lowered from 0.50
                sellThreshold = 0.52;  // Raised from 0.50
                rsiUpperLimit = 85;
                rsiLowerLimit = 15;
                break;
                
            case REVERSAL:
                // In reversal, be more aggressive
                buyThreshold = 0.48;  // Lowered from 0.50
                sellThreshold = 0.52;  // Raised from 0.50
                rsiUpperLimit = 80;
                rsiLowerLimit = 20;
                break;
                
            case CHOPPY:
                // In choppy markets, be more selective
                buyThreshold = 0.60;  // Lowered from 0.65
                sellThreshold = 0.40;  // Raised from 0.35
                rsiUpperLimit = 70;
                rsiLowerLimit = 30;
                break;
        }
        
        // Apply the adaptive thresholds with confirmation signals
        bool strongBuySignal = prediction > buyThreshold && rsi < rsiUpperLimit &&
                              (momentum > -0.0001 || pattern == PATTERN_BULL || imbalance > 0.5) && // Relaxed confirmation requirements
                              !(rsi > 80 && currentRegime == TRENDING_DOWN); // Only avoid extreme overbought in downtrend
                              // Order block confirmation removed to ensure trades occur
        
        bool strongSellSignal = prediction < sellThreshold && rsi > rsiLowerLimit &&
                                (momentum < 0.0001 || pattern == PATTERN_BEAR || imbalance < 0.5) && // Relaxed confirmation requirements
                                !(rsi < 20 && currentRegime == TRENDING_UP); // Only avoid extreme oversold in uptrend
                                // Order block confirmation removed to ensure trades occur
        // Enhanced buy execution with dynamic parameters
        if(strongBuySignal) {
            // Calculate optimal stop loss and take profit based on volatility and regime
            double sl = dynamicSL;
            double tp = dynamicTP;
            
            // Adjust TP/SL ratio based on regime win rate
            int regimeIdx = GetRegimeIndex(currentRegime);
            double winRate = (::regimeWins[regimeIdx] + ::regimeLosses[regimeIdx] > 0) ? 
                            (double)::regimeWins[regimeIdx] / (::regimeWins[regimeIdx] + ::regimeLosses[regimeIdx]) : 0.5;
            
            // If win rate is high, we can use more aggressive TP/SL ratio
            if(winRate > 0.6) {
                // Increase take profit
                tp *= 1.2; 
            } else if(winRate < 0.4) {
                // Tighter stop loss
                sl *= 0.8; 
                // Need higher reward for the risk
                tp *= 1.5; 
            }
            
            // SAFETY: Validate SL/TP levels before sending order
            double slLevel = ValidateStopLevel(currentBid-sl, true);
            double tpLevel = ValidateTakeProfitLevel(currentBid+tp, true);
            
            // SAFETY: Check for valid SL/TP
            if(slLevel <= 0 || tpLevel <= 0) {
                Print("[ERROR] Invalid SL/TP levels calculated. Skipping trade.");
                return;
            }
            
            // SAFETY: Ensure lot size is valid for this specific symbol
            lotSize = GetValidLotSize(_Symbol, lotSize);
            
            // SAFETY: Set deviation for slippage control
            trade.SetDeviationInPoints((int)(maxSlippagePips * 10));
            
            // SAFETY: Try to execute with comprehensive error handling
            bool result = false;
            for(int attempt=1; attempt<=3; attempt++) { // Allow up to 3 attempts
                // CRITICAL: Force valid lot size immediately before trade execution
                double validLotSize = GetValidLotSize(_Symbol, lotSize);
                Print("[TRADE] Executing BUY order with lotSize=", validLotSize, " (was ", lotSize, ")");
                
                result = trade.Buy(validLotSize, _Symbol, 0, slLevel, tpLevel, "ScalperV3");
                
                if(result) {
                    // Reset failed attempts counter on success
                    failedOrderAttempts = 0;
                    lastTradeTime = TimeCurrent();
                    break;
                } else {
                    // Analyze error
                    int errorCode = GetLastError();
                    failedOrderAttempts++;
                    
                    // Critical errors - stop trying
                    if(errorCode == ERR_NOT_ENOUGH_MONEY || errorCode == ERR_TRADE_DISABLED) {
                        Print("[CRITICAL ERROR] ", errorCode, ": ", ErrorDescription(errorCode), ". Trading stopped.");
                        tradingStopped = true;
                        return;
                    }
                    
                    // Temporary errors - retry with adjusted parameters
                    if(errorCode == ERR_INVALID_STOPS || errorCode == ERR_INVALID_TRADE_VOLUME) {
                        Print("[ERROR] Attempt ", attempt, "/3: ", errorCode, ": ", ErrorDescription(errorCode), ". Retrying with adjusted parameters.");
                        
                        // Adjust parameters for retry
                        double minStopDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
                        if(errorCode == ERR_INVALID_STOPS && minStopDist > 0) {
                            slLevel = currentBid - (minStopDist * 1.2); // Add 20% margin
                            tpLevel = currentBid + (minStopDist * 1.2); // Add 20% margin
                        }
                        else if(errorCode == ERR_INVALID_TRADE_VOLUME || errorCode == 4756) {
                            // Get the exact symbol volume constraints
                            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
                            double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
                            double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                            
                            // Print detailed diagnostic info about volumes
                            Print("[VOLUME INFO] Symbol=", _Symbol, 
                                  " Min=", minLot, 
                                  " Max=", maxLot, 
                                  " Step=", lotStep, 
                                  " Current=", lotSize);
                            
                            // Round to the nearest lot step
                            if(lotStep > 0) {
                                lotSize = MathFloor(minLot / lotStep) * lotStep;
                                if(lotSize < minLot) lotSize = minLot;
                                Print("[VOLUME] Adjusted lot size to: ", lotSize);
                            } else {
                                lotSize = minLot; // Fallback to minimum lot
                            }
                        }
                        Sleep(500); // Wait before retry
                        continue;
                    }
                    
                    // Other errors - log and continue
                    Print("[ERROR] Failed to place BUY order. Error ", errorCode, ": ", ErrorDescription(errorCode));
                }
            }
            
            // Successfully executed order
            if(result) {
                Print("[BUY] prediction=", prediction, " thresh=", dynamicBuyThresh, 
                      " lot=", lotSize, " sl=", sl, " tp=", tp, 
                      " regime=", currentRegime, " winRate=", winRate);
            }
        }
        // Enhanced sell execution with dynamic parameters
        else if(strongSellSignal) {
            // Calculate optimal stop loss and take profit based on volatility and regime
            double sl = dynamicSL;
            double tp = dynamicTP;
            
            // Adjust TP/SL ratio based on regime win rate
            int regimeIdx = GetRegimeIndex(currentRegime);
            double winRate = (::regimeWins[regimeIdx] + ::regimeLosses[regimeIdx] > 0) ? 
                            (double)::regimeWins[regimeIdx] / (::regimeWins[regimeIdx] + ::regimeLosses[regimeIdx]) : 0.5;
            
            // If win rate is high, we can use more aggressive TP/SL ratio
            if(winRate > 0.6) {
                // Increase take profit
                tp *= 1.2; 
            } else if(winRate < 0.4) {
                // Tighter stop loss
                sl *= 0.8; 
                // Need higher reward for the risk
                tp *= 1.5; 
            }
            
            // Validate stop loss and take profit levels
            double slLevel = currentAsk+sl;
            double tpLevel = currentAsk-tp;
            
            // Initialize temp values for SL/TP
            double sellSLLevel = 0.0;
            double sellTPLevel = 0.0;
            
            // SAFETY: Validate SL/TP levels before sending order
            sellSLLevel = ValidateStopLevel(currentAsk+sl, false);
            sellTPLevel = ValidateTakeProfitLevel(currentAsk-tp, false);
            
            // SAFETY: Check for valid SL/TP
            if(sellSLLevel <= 0 || sellTPLevel <= 0) {
                Print("[ERROR] Invalid SL/TP levels calculated for SELL. Skipping trade.");
                return;
            }
            
            // SAFETY: Ensure lot size is valid for this specific symbol
            lotSize = GetValidLotSize(_Symbol, lotSize);
            
            // SAFETY: Set deviation for slippage control
            trade.SetDeviationInPoints((int)(maxSlippagePips * 10));
            
            // SAFETY: Try to execute with comprehensive error handling
            bool result = false;
            for(int attempt=1; attempt<=3; attempt++) { // Allow up to 3 attempts
                // CRITICAL: Force valid lot size immediately before trade execution
                double validLotSize = GetValidLotSize(_Symbol, lotSize);
                Print("[TRADE] Executing SELL order with lotSize=", validLotSize, " (was ", lotSize, ")");
                
                result = trade.Sell(validLotSize, _Symbol, 0, sellSLLevel, sellTPLevel, "ScalperV3");
                
                if(result) {
                    // Order was successful
                    ulong resultOrderID = trade.ResultOrder();
                    Print("[SELL SUCCESS] Order ID: ", resultOrderID, 
                          " Entry: ", DoubleToString(currentAsk, _Digits),
                          " SL: ", DoubleToString(sellSLLevel, _Digits), 
                          " TP: ", DoubleToString(sellTPLevel, _Digits));
                          
                    // Update last trade time for safety
                    lastTradeTime = TimeCurrent();
                    
                    // Reset failed attempts counter on success
                    failedOrderAttempts = 0;
                    
                    // Break out of retry loop
                    break;
                } else {
                    // Order failed
                    int errorCode = GetLastError();
                    Print("[SELL ERROR] Failed to open sell order. Error: ", errorCode, 
                          " (", ErrorDescription(errorCode), ") Attempt: ", attempt);
                          
                    // If error is not retryable, break out of loop
                    if(errorCode != ERR_INVALID_STOPS && errorCode != ERR_INVALID_TRADE_VOLUME) {
                        failedOrderAttempts++;
                        break;
                    }
                    
                    // Wait briefly before retry
                    Sleep(100);
                }
            }
            
            // Successfully executed order
            if(result) {
                Print("[SELL] prediction=", prediction, " thresh=", dynamicSellThresh, 
                      " lot=", lotSize, " sl=", sl, " tp=", tp, 
                      " regime=", currentRegime, " winRate=", winRate);
            }
        }
    } // End of hasOpenPosition check
    
    // Retrain neural net every 50 trades or if accuracy drops
    if(trainSampleCount % 50 == 0 && trainSampleCount > 0 && GetPredictionAccuracy() < 0.5) {
        Print("[OnTick] Would retrain neural network here - accuracy: ", GetPredictionAccuracy());
    }
}  // End of OnTick function

//+------------------------------------------------------------------+
//| Advanced Position Management with Partial Profit-Taking         |
//+------------------------------------------------------------------+
void ManageOpenPositionsAggressivelyImpl() {
    CTrade trade;
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpOrderDeviation);
    
    // Input parameters for partial profit-taking
    const double firstTakeProfitPct = 0.5;    // Take 50% profit at first target
    const double secondTakeProfitPct = 0.3;   // Take 30% profit at second target
    const double finalTakeProfitPct = 0.2;    // Leave 20% for final target
    
    // Adapt trailing parameters based on market regime
    double trailingStopActivationPct = trailingActivationPct; // Default from input parameter
    double trailingStopDistance = 0.0;        // Distance for trailing stop in points
    double breakEvenLevel = 0.0;              // Level for break-even in points
    
    // Adjust trailing parameters based on market regime
    switch(currentRegime) {
        case TRENDING_UP:
        case TRENDING_DOWN:
            // In trends, more aggressive trailing to lock in profits
            trailingStopActivationPct = trailingActivationPct * 0.8; // Activate earlier
            trailingStopDistance = FastATR(_Symbol) * 0.8;  // Tighter trailing
            breakEvenLevel = FastATR(_Symbol) * 0.5;         // Move to break-even sooner
            break;
            
        case HIGH_VOLATILITY:
            // In high volatility, less aggressive trailing to avoid whipsaws
            trailingStopActivationPct = trailingActivationPct * 1.2; // Activate later
            trailingStopDistance = FastATR(_Symbol) * 1.5;  // Wider trailing
            breakEvenLevel = FastATR(_Symbol) * 0.8;         // Move to break-even later
            break;
            
        case BREAKOUT:
            // In breakout, very aggressive trailing to capture momentum
            trailingStopActivationPct = trailingActivationPct * 0.6; // Activate much earlier
            trailingStopDistance = FastATR(_Symbol) * 0.7;  // Tighter trailing
            breakEvenLevel = FastATR(_Symbol) * 0.4;         // Move to break-even quickly
            break;
            
        case RANGING_NARROW:
        case RANGING_WIDE:
            // In ranging markets, moderate trailing to capture swings
            trailingStopActivationPct = trailingActivationPct * 0.9;
            trailingStopDistance = FastATR(_Symbol) * 1.0;
            breakEvenLevel = FastATR(_Symbol) * 0.6;
            break;
            
        case REVERSAL:
            // In reversal, aggressive trailing to protect profits
            trailingStopActivationPct = trailingActivationPct * 0.7;
            trailingStopDistance = FastATR(_Symbol) * 0.8;
            breakEvenLevel = FastATR(_Symbol) * 0.5;
            break;
            
        case CHOPPY:
            // In choppy markets, less aggressive trailing to avoid whipsaws
            trailingStopActivationPct = trailingActivationPct * 1.3;
            trailingStopDistance = FastATR(_Symbol) * 1.6;
            breakEvenLevel = FastATR(_Symbol) * 1.0;
            break;
            
        default:
            // Default parameters
            trailingStopDistance = FastATR(_Symbol) * 1.0;
            breakEvenLevel = FastATR(_Symbol) * 0.7;
    }
    
    // Get current price data
    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Store position tickets first to avoid issues when modifying positions
    ulong tickets[];
    int posCount = 0;
    
    // First pass: collect all position tickets
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
               PositionGetString(POSITION_SYMBOL) == _Symbol) {
                ArrayResize(tickets, posCount + 1);
                tickets[posCount++] = ticket;
            }
        }
    }
    
    // Second pass: process each position safely
    for(int i = 0; i < posCount; i++) {
        if(PositionSelectByTicket(tickets[i])) {
            
            // Get position details
            ulong posTicket = PositionGetInteger(POSITION_TICKET);
            double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double posStopLoss = PositionGetDouble(POSITION_SL);
            double posTakeProfit = PositionGetDouble(POSITION_TP);
            double posVolume = PositionGetDouble(POSITION_VOLUME);
            datetime posOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            // Get position profit in points
            double currentProfit = 0.0;
            if(posType == POSITION_TYPE_BUY) {
                currentProfit = (currentBid - posOpenPrice) / pointSize;
            } else {
                currentProfit = (posOpenPrice - currentAsk) / pointSize;
            }
            
            // Get original TP distance in points (from position comment or calculate)
            double originalTP = 0.0;
            string posComment = PositionGetString(POSITION_COMMENT);
            
            // Try to extract original TP from comment if available
            if(StringFind(posComment, "OrigTP=") >= 0) {
                int startPos = StringFind(posComment, "OrigTP=") + 7;
                int endPos = StringFind(posComment, ";", startPos);
                if(endPos == -1) endPos = StringLen(posComment);
                string tpStr = StringSubstr(posComment, startPos, endPos - startPos);
                originalTP = StringToDouble(tpStr);
            } else {
                // Calculate original TP if not in comment
                if(posType == POSITION_TYPE_BUY) {
                    originalTP = (posTakeProfit > 0) ? (posTakeProfit - posOpenPrice) / pointSize : 0;
                } else {
                    originalTP = (posTakeProfit > 0) ? (posOpenPrice - posTakeProfit) / pointSize : 0;
                }
                
                // If TP is not set, use a default based on ATR
                if(originalTP <= 0) {
                    originalTP = FastATR(_Symbol) * tpMultiplier / pointSize;
                }
            }
            
            // Find TP trail counter from comment
            int tpTrailCount = 0;
            if(StringFind(posComment, "TPTrail=") >= 0) {
                int startPos = StringFind(posComment, "TPTrail=");
                int endPos = StringFind(posComment, ";", startPos);
                if(endPos == -1) endPos = StringLen(posComment);
                string trailStr = StringSubstr(posComment, startPos + 8, endPos - startPos - 8);
                tpTrailCount = (int)StringToInteger(trailStr);
            }
            
            // Check if we've reached the maximum TP trail count (if limit is set)
            bool maxTrailsReached = (maxTPTrailCount > 0 && tpTrailCount >= maxTPTrailCount);
            
            // Check if position has partial profit flags in comment
            bool tpHit = (StringFind(posComment, "TPHit") >= 0);
            int tpHitLevel = 0;
            
            if(StringFind(posComment, "TPHit=") >= 0) {
                int startPos = StringFind(posComment, "TPHit=");
                int endPos = StringFind(posComment, ";", startPos);
                if(endPos == -1) endPos = StringLen(posComment);
                string hitStr = StringSubstr(posComment, startPos + 6, endPos - startPos - 6);
                tpHitLevel = (int)StringToInteger(hitStr);
            }
            
            // Calculate current TP level based on original TP and trail count
            double currentTPLevel = originalTP;
            for(int t=0; t<tpTrailCount; t++) {
                currentTPLevel *= tpExtensionFactor;
            }
            
            // Calculate next TP level (for when current is hit)
            double nextTPLevel = currentTPLevel * tpExtensionFactor;
            
            // Check if we need to apply trailing take profit logic
            if(useTrailingTakeProfit && !maxTrailsReached && currentProfit >= currentTPLevel * 0.75) {
                // Take profit hit or nearly hit (75% of the way there) - trail stop loss and set new take profit
                
                // Calculate new stop loss at a percentage of current profit level
                double newSL = 0.0;
                if(posType == POSITION_TYPE_BUY) {
                    newSL = posOpenPrice + currentProfit * pointSize * 0.5; // Lock in 50% of current profit
                } else {
                    newSL = posOpenPrice - currentProfit * pointSize * 0.5; // Lock in 50% of current profit
                }
                
                // Calculate new take profit
                double newTP = 0.0;
                if(posType == POSITION_TYPE_BUY) {
                    newTP = posOpenPrice + nextTPLevel * pointSize;
                } else {
                    newTP = posOpenPrice - nextTPLevel * pointSize;
                }
                
                // Update position comment
                string newComment;
                tpTrailCount++;
                tpHitLevel++;
                
                if(StringFind(posComment, "OrigTP=") < 0) {
                    newComment = StringFormat("OrigTP=%.1f;TPTrail=%d;TPHit=%d", originalTP, tpTrailCount, tpHitLevel);
                } else {
                    // Replace TPTrail and TPHit values in existing comment
                    if(StringFind(posComment, "TPTrail=") >= 0) {
                        int startPos = StringFind(posComment, "TPTrail=");
                        int endPos = StringFind(posComment, ";", startPos);
                        if(endPos == -1) endPos = StringLen(posComment);
                        string beforeTrail = StringSubstr(posComment, 0, startPos);
                        string afterTrail = (endPos < StringLen(posComment)) ? StringSubstr(posComment, endPos) : "";
                        posComment = beforeTrail + StringFormat("TPTrail=%d", tpTrailCount) + afterTrail;
                    } else {
                        posComment = StringFormat("%s;TPTrail=%d", posComment, tpTrailCount);
                    }
                    
                    if(StringFind(posComment, "TPHit=") >= 0) {
                        int startPos = StringFind(posComment, "TPHit=");
                        int endPos = StringFind(posComment, ";", startPos);
                        if(endPos == -1) endPos = StringLen(posComment);
                        string beforeHit = StringSubstr(posComment, 0, startPos);
                        string afterHit = (endPos < StringLen(posComment)) ? StringSubstr(posComment, endPos) : "";
                        posComment = beforeHit + StringFormat("TPHit=%d", tpHitLevel) + afterHit;
                    } else {
                        posComment = StringFormat("%s;TPHit=%d", posComment, tpHitLevel);
                    }
                    
                    newComment = posComment;
                }
                
                // Modify position with new SL/TP
                if(trade.PositionModify(posTicket, newSL, newTP)) {
                    Print("[Trailing TP] Position ", posTicket, " - TP hit #", tpHitLevel, 
                          " profit: ", NormalizeDouble(currentProfit, 1), " points, New SL: ", 
                          NormalizeDouble(newSL, digits), ", New TP: ", NormalizeDouble(newTP, digits));
                    Print("[Trailing TP] New comment for position ", posTicket, ": ", newComment);
                    
                    // Log trailing take profit activation to a file for verification
                    string logEntry = StringFormat("%s: Position %d - Trailing TP activated at %.1f points, New SL=%.5f, New TP=%.5f", 
                                                TimeToString(TimeCurrent()), posTicket, currentProfit, newSL, newTP);
                    int fileHandle = FileOpen("ScalperV3_TP_Trail_Log.txt", FILE_WRITE|FILE_READ|FILE_SHARE_READ|FILE_SHARE_WRITE);
                    if(fileHandle != INVALID_HANDLE) {
                        FileSeek(fileHandle, 0, SEEK_END);
                        FileWriteString(fileHandle, logEntry + "\r\n");
                        FileClose(fileHandle);
                    }
                } else {
                    int lastError = GetLastError();
                    Print("[ERROR] Failed to modify position with trailing TP. Error: ", lastError, 
                          " (", ErrorDescription(lastError), ")");
                }
            }
            // Apply regular trailing stop if activated and TP hasn't been hit
            else if(!tpHit && currentProfit >= originalTP * trailingStopActivationPct) {
                // Calculate new stop loss based on trailing distance
                double newSL = 0.0;
                
                if(posType == POSITION_TYPE_BUY) {
                    // For buy positions, trail below current price
                    newSL = currentBid - trailingStopDistance * pointSize;
                    
                    // Only modify if new SL is higher than current SL
                    if(newSL > posStopLoss + pointSize) {
                        trade.PositionModify(posTicket, newSL, posTakeProfit);
                        Print("[Trailing] Updated SL for position ", posTicket, " to ", NormalizeDouble(newSL, digits));
                    }
                } else { // POSITION_TYPE_SELL
                    // For sell positions, trail above current price
                    newSL = currentAsk + trailingStopDistance * pointSize;
                    
                    // Only modify if new SL is lower than current SL or current SL is zero
                    if(posStopLoss == 0 || newSL < posStopLoss - pointSize) {
                        trade.PositionModify(posTicket, newSL, posTakeProfit);
                        Print("[Trailing] Updated SL for position ", posTicket, " to ", NormalizeDouble(newSL, digits));
                    }
                }
            }
            // Move to break-even if profit exceeds threshold and not already at break-even
            else if(!tpHit && currentProfit >= breakEvenLevel && 
                    ((posType == POSITION_TYPE_BUY && posStopLoss < posOpenPrice) || 
                     (posType == POSITION_TYPE_SELL && (posStopLoss > posOpenPrice || posStopLoss == 0)))) {
                
                // Calculate break-even stop loss with small buffer
                double newSL = 0.0;
                if(posType == POSITION_TYPE_BUY) {
                    newSL = posOpenPrice + (breakEvenLevel * 0.1) * pointSize; // Small buffer above entry
                } else {
                    newSL = posOpenPrice - (breakEvenLevel * 0.1) * pointSize; // Small buffer below entry
                }
                
                // Update position with break-even stop loss
                trade.PositionModify(posTicket, newSL, posTakeProfit);
                Print("[Break-Even] Updated SL for position ", posTicket, " to ", NormalizeDouble(newSL, digits));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate prediction accuracy based on historical predictions    |
//+------------------------------------------------------------------+
// GetPredictionAccuracy function is already defined above

//+------------------------------------------------------------------+
//| Count open positions function is already defined above          |
//+------------------------------------------------------------------+
// CountPositions function is already defined above

// Function to draw parameter controls on chart
void DrawParameterControls() {
    // CreateButton("BTN_RISK_UP", "+R", 10, 10, clrLime);
    // CreateButton("BTN_RISK_DOWN", "-R", 55, 10, clrRed);
    // CreateButton("BTN_BUY_UP", "+B", 10, 35, clrLime);
    // CreateButton("BTN_BUY_DOWN", "-B", 55, 35, clrRed);
    // CreateButton("BTN_SELL_UP", "+S", 10, 60, clrLime);
    // CreateButton("BTN_SELL_DOWN", "-S", 55, 60, clrRed);
    // CreateButton("BTN_RESET", "Reset", 10, 85, clrYellow);
}

//+------------------------------------------------------------------+
//| Simple Support and Resistance check for scalping                 |
//+------------------------------------------------------------------+
bool CheckSRLevels(bool isBuy) {
    // For scalping we want to allow most trades, so return true by default
    return true;
}

//+------------------------------------------------------------------+
//| Order Block and Market Structure Functions                       |
//+------------------------------------------------------------------+

// Structure to store order block information
struct OrderBlock {
    double high;           // High of the order block
    double low;            // Low of the order block
    double strength;       // Strength of the order block (0-1)
    datetime time;         // Time of order block formation
    bool isBullish;        // True if bullish order block, false if bearish
};

// Structure to store market structure information
struct MarketStructure {
    bool isUptrend;         // True if market structure is uptrend
    bool isDowntrend;       // True if market structure is downtrend
    bool isChanging;        // True if market structure is potentially changing
    double lastHH;          // Last higher high price level
    double lastHL;          // Last higher low price level
    double lastLH;          // Last lower high price level
    double lastLL;          // Last lower low price level
    datetime lastSwingTime; // Time of the last swing point
};

// Global variables for order blocks and market structure
OrderBlock g_bullishOrderBlocks[5];  // Store the last 5 bullish order blocks
OrderBlock g_bearishOrderBlocks[5];  // Store the last 5 bearish order blocks
MarketStructure g_marketStructure;   // Current market structure

//+------------------------------------------------------------------+
//| Find and analyze order blocks                                    |
//+------------------------------------------------------------------+
void FindOrderBlocks(string symbol, ENUM_TIMEFRAMES timeframe) {
    // We need enough price data to identify order blocks
    double highs[30], lows[30], closes[30], opens[30], volumes[30];
    datetime times[30];
    
    // Collect the price data
    for(int i = 0; i < 30; i++) {
        highs[i] = iHigh(symbol, timeframe, i);
        lows[i] = iLow(symbol, timeframe, i);
        closes[i] = iClose(symbol, timeframe, i);
        opens[i] = iOpen(symbol, timeframe, i);
        volumes[i] = iVolume(symbol, timeframe, i);
        times[i] = iTime(symbol, timeframe, i);
    }
    
    // Find bullish order blocks (areas of selling before a bullish move)
    int bullishBlockCount = 0;
    for(int i = 5; i < 25 && bullishBlockCount < 5; i++) {
        // Look for a strong bearish candle followed by bullish momentum
        bool strongBearishCandle = (opens[i] - closes[i]) > (highs[i] - lows[i]) * 0.6;
        bool followedByBullishMove = false;
        
        // Check if followed by bullish momentum
        if(strongBearishCandle) {
            double priorToBlockPrice = closes[i+1];
            double afterBlockPrice = closes[i-3]; // Check price 3 candles after
            followedByBullishMove = afterBlockPrice > priorToBlockPrice;
            
            if(followedByBullishMove) {
                // Found a bullish order block
                g_bullishOrderBlocks[bullishBlockCount].high = highs[i];
                g_bullishOrderBlocks[bullishBlockCount].low = lows[i];
                g_bullishOrderBlocks[bullishBlockCount].time = times[i];
                g_bullishOrderBlocks[bullishBlockCount].isBullish = true;
                
                // Calculate strength based on volume and subsequent price move
                double volumeStrength = volumes[i] / (ArrayMaximum(volumes, i-5, 10) + 0.00001);
                double priceMove = (afterBlockPrice - priorToBlockPrice) / priorToBlockPrice;
                g_bullishOrderBlocks[bullishBlockCount].strength = (volumeStrength * 0.4) + (priceMove * 0.6);
                
                bullishBlockCount++;
            }
        }
    }
    
    // Find bearish order blocks (areas of buying before a bearish move)
    int bearishBlockCount = 0;
    for(int i = 5; i < 25 && bearishBlockCount < 5; i++) {
        // Look for a strong bullish candle followed by bearish momentum
        bool strongBullishCandle = (closes[i] - opens[i]) > (highs[i] - lows[i]) * 0.6;
        bool followedByBearishMove = false;
        
        // Check if followed by bearish momentum
        if(strongBullishCandle) {
            double priorToBlockPrice = closes[i+1];
            double afterBlockPrice = closes[i-3]; // Check price 3 candles after
            followedByBearishMove = afterBlockPrice < priorToBlockPrice;
            
            if(followedByBearishMove) {
                // Found a bearish order block
                g_bearishOrderBlocks[bearishBlockCount].high = highs[i];
                g_bearishOrderBlocks[bearishBlockCount].low = lows[i];
                g_bearishOrderBlocks[bearishBlockCount].time = times[i];
                g_bearishOrderBlocks[bearishBlockCount].isBullish = false;
                
                // Calculate strength based on volume and subsequent price move
                double volumeStrength = volumes[i] / (ArrayMaximum(volumes, i-5, 10) + 0.00001);
                double priceMove = (priorToBlockPrice - afterBlockPrice) / priorToBlockPrice;
                g_bearishOrderBlocks[bearishBlockCount].strength = (volumeStrength * 0.4) + (priceMove * 0.6);
                
                bearishBlockCount++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Analyze market structure (HH, HL, LH, LL)                        |
//+------------------------------------------------------------------+
void AnalyzeMarketStructure(string symbol, ENUM_TIMEFRAMES timeframe) {
    // Get swing points from the last 50 candles
    int swingHighs[10], swingLows[10];
    double highPrices[50], lowPrices[50];
    datetime times[50];
    
    // Fill the price arrays
    for(int i = 0; i < 50; i++) {
        highPrices[i] = iHigh(symbol, timeframe, i);
        lowPrices[i] = iLow(symbol, timeframe, i);
        times[i] = iTime(symbol, timeframe, i);
    }
    
    // Find swing highs (a candle with at least 2 lower highs on each side)
    int highCount = 0;
    for(int i = 2; i < 48 && highCount < 10; i++) {
        if(highPrices[i] > highPrices[i-1] && highPrices[i] > highPrices[i-2] && 
           highPrices[i] > highPrices[i+1] && highPrices[i] > highPrices[i+2]) {
            swingHighs[highCount++] = i;
        }
    }
    
    // Find swing lows (a candle with at least 2 higher lows on each side)
    int lowCount = 0;
    for(int i = 2; i < 48 && lowCount < 10; i++) {
        if(lowPrices[i] < lowPrices[i-1] && lowPrices[i] < lowPrices[i-2] && 
           lowPrices[i] < lowPrices[i+1] && lowPrices[i] < lowPrices[i+2]) {
            swingLows[lowCount++] = i;
        }
    }
    
    // Analyze the market structure if we have enough swing points
    if(highCount >= 3 && lowCount >= 3) {
        // Check for higher highs and higher lows (uptrend)
        bool hasHigherHigh = highPrices[swingHighs[0]] > highPrices[swingHighs[1]] && 
                            highPrices[swingHighs[1]] > highPrices[swingHighs[2]];
        bool hasHigherLow = lowPrices[swingLows[0]] > lowPrices[swingLows[1]] && 
                           lowPrices[swingLows[1]] > lowPrices[swingLows[2]];
        
        // Check for lower highs and lower lows (downtrend)
        bool hasLowerHigh = highPrices[swingHighs[0]] < highPrices[swingHighs[1]] && 
                           highPrices[swingHighs[1]] < highPrices[swingHighs[2]];
        bool hasLowerLow = lowPrices[swingLows[0]] < lowPrices[swingLows[1]] && 
                          lowPrices[swingLows[1]] < lowPrices[swingLows[2]];
        
        // Determine market structure
        g_marketStructure.isUptrend = hasHigherHigh && hasHigherLow;
        g_marketStructure.isDowntrend = hasLowerHigh && hasLowerLow;
        g_marketStructure.isChanging = (hasHigherHigh && !hasHigherLow) || (!hasLowerHigh && hasLowerLow);
        
        // Store the latest swing points
        g_marketStructure.lastHH = hasHigherHigh ? highPrices[swingHighs[0]] : 0;
        g_marketStructure.lastHL = hasHigherLow ? lowPrices[swingLows[0]] : 0;
        g_marketStructure.lastLH = hasLowerHigh ? highPrices[swingHighs[0]] : 0;
        g_marketStructure.lastLL = hasLowerLow ? lowPrices[swingLows[0]] : 0;
        g_marketStructure.lastSwingTime = MathMin(times[swingHighs[0]], times[swingLows[0]]);
    }
}

//+------------------------------------------------------------------+
//| Check if current price is near an order block                     |
//+------------------------------------------------------------------+
bool IsNearOrderBlock(double price, bool lookingForBuy) {
    double atr = GetATR(_Symbol, PERIOD_M5, 14);
    double nearDistance = atr * 0.5; // Define "near" as within 0.5 * ATR
    
    if(lookingForBuy) {
        // Check if price is near a bullish order block
        for(int i = 0; i < 5; i++) {
            if(g_bullishOrderBlocks[i].strength > 0.5 && // Only consider strong blocks
               price >= g_bullishOrderBlocks[i].low - nearDistance && 
               price <= g_bullishOrderBlocks[i].high + nearDistance) {
                return true;
            }
        }
    } else {
        // Check if price is near a bearish order block
        for(int i = 0; i < 5; i++) {
            if(g_bearishOrderBlocks[i].strength > 0.5 && // Only consider strong blocks
               price >= g_bearishOrderBlocks[i].low - nearDistance && 
               price <= g_bearishOrderBlocks[i].high + nearDistance) {
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if trade aligns with market structure                      |
//+------------------------------------------------------------------+
bool AlignedWithMarketStructure(bool isBuySignal) {
    // In an uptrend, prefer buy signals; in a downtrend, prefer sell signals
    if(isBuySignal && g_marketStructure.isUptrend) return true;
    if(!isBuySignal && g_marketStructure.isDowntrend) return true;
    
    // In a changing market structure, be more selective
    if(g_marketStructure.isChanging) {
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
        
        // For buy signals in a potentially forming uptrend
        if(isBuySignal && !g_marketStructure.isUptrend && !g_marketStructure.isDowntrend) {
            return currentPrice > g_marketStructure.lastHL && g_marketStructure.lastHL > 0;
        }
        
        // For sell signals in a potentially forming downtrend
        if(!isBuySignal && !g_marketStructure.isUptrend && !g_marketStructure.isDowntrend) {
            return currentPrice < g_marketStructure.lastLH && g_marketStructure.lastLH > 0;
        }
    }
    
    // By default, be more conservative
    return false;
}

//+------------------------------------------------------------------+
//| Calculate Dynamic Stop Loss with Order Block Enhancement         |

//+------------------------------------------------------------------+
//| Function to count confirmation signals for trade direction       |
//+------------------------------------------------------------------+
int CountConfirmationSignals(bool isBuySignal, string symbol) {
    int confirmationCount = 0;
    
    // Get various indicator readings
    double rsi = GetRSI(symbol, PERIOD_M1, RSI_PERIOD);
    double atr = FastATR(symbol);
    double maFast = GetMA(symbol, PERIOD_M1, 10, MODE_EMA);
    double maSlow = GetMA(symbol, PERIOD_M1, 20, MODE_EMA);
    double matrend = GetMA(symbol, PERIOD_M5, 50, MODE_EMA);
    double currentPrice = SymbolInfoDouble(symbol, SYMBOL_LAST);
    
    // RSI confirmation
    if((isBuySignal && rsi > 50) || (!isBuySignal && rsi < 50))
        confirmationCount++;
    
    // Moving average confirmation
    if((isBuySignal && maFast > maSlow) || (!isBuySignal && maFast < maSlow))
        confirmationCount++;
    
    // Price relative to longer-term trend
    if((isBuySignal && currentPrice > matrend) || (!isBuySignal && currentPrice < matrend))
        confirmationCount++;
    
    // Momentum confirmation
    double momentum = GetMomentum(symbol, PERIOD_M1, MOMENTUM_PERIOD);
    double momentumPrev = GetMomentum(symbol, PERIOD_M1, MOMENTUM_PERIOD, 1);
    if((isBuySignal && momentum > momentumPrev) || (!isBuySignal && momentum < momentumPrev))
        confirmationCount++;
    
    // Check recent candle patterns
    int pattern = RecognizePattern(symbol, PERIOD_M1);
    if((isBuySignal && pattern == PATTERN_BULL) || (!isBuySignal && pattern == PATTERN_BEAR))
        confirmationCount++;
    
    return confirmationCount;
}

// If errordescription.mqh is not available, define our own function
#ifndef ERROR_DESCRIPTION_DEFINED
#define ERROR_DESCRIPTION_DEFINED
string ErrorDescription(int error_code) {
    switch(error_code) {
        case 0: return "No error";
        case 4051: return "Invalid function parameter value";
        case 4062: return "ERR_TRADE_DISABLED";
        case 4063: return "ERR_INVALID_STOPS";
        case 4064: return "ERR_INVALID_TRADE_VOLUME";
        case 4109: return "ERR_NOT_ENOUGH_MONEY";
        case 4073: return "Invalid volume";
        case 4756: return "Invalid volume for symbol";
        default: return "Error #" + (string)error_code;
    }
    return "";
}
#endif

//+------------------------------------------------------------------+
//| Constants and Pattern Definitions                                |
//+------------------------------------------------------------------+
#define PATTERN_BULL (1)
#define PATTERN_BEAR (-1)
#define PATTERN_NONE (0)
#ifndef OBJPROP_HEIGHT
#define OBJPROP_HEIGHT (133)
#endif

//+------------------------------------------------------------------+
//| Enhanced HFT Entry Validation                                    |
//+------------------------------------------------------------------+
bool IsValidHFTEntry(bool isBuySignal, string symbol) {
    // Check for minimum signal strength through confirmation
    int confirmations = CountConfirmationSignals(isBuySignal, symbol);
    if(useConfirmationFilter && confirmations < minimumSignalStrength) {
        Print("[HFT Filter] Insufficient confirmation signals: ", confirmations, "/", minimumSignalStrength);
        return false;
    }
    
    // Current market regime
    int currentRegime = FastRegimeDetection(symbol);
    
    // Avoid choppy markets if enabled
    if(avoidChoppy && currentRegime == CHOPPY) {
        Print("[HFT Filter] Avoiding choppy market conditions");
        return false;
    }
    
    // Check market structure alignment
    if(useMarketStructureFilter) {
        // Determine trend using MA comparison
        double ma20 = GetMA(symbol, PERIOD_M5, 20, MODE_EMA);
        double ma50 = GetMA(symbol, PERIOD_M5, 50, MODE_EMA);
        double ma100 = GetMA(symbol, PERIOD_M5, 100, MODE_EMA);
        
        // Uptrend: shorter MAs above longer MAs
        bool isUptrend = (ma20 > ma50 && ma50 > ma100);
        
        // Downtrend: shorter MAs below longer MAs
        bool isDowntrend = (ma20 < ma50 && ma50 < ma100);
        
        if(isBuySignal && !isUptrend && isDowntrend) {
            Print("[HFT Filter] Buy signal rejected - downtrend market structure");
            return false;
        }
        if(!isBuySignal && !isDowntrend && isUptrend) {
            Print("[HFT Filter] Sell signal rejected - uptrend market structure");
            return false;
        }
    }
    
    // Check volatility conditions
    if(useVolatilityFilter) {
        double atr = FastATR(symbol);
        double avgATR = 0;
        
        // Calculate average ATR over last 10 bars
        for(int i=1; i<=10; i++) {
            avgATR += GetATR(symbol, PERIOD_M1, ATR_PERIOD, i);
        }
        avgATR /= 10;
        
        // Check if current volatility is too high
        if(atr > avgATR * volatilityThreshold) {
            Print("[HFT Filter] Volatility too high: current=", 
                  NormalizeDouble(atr, 5), ", avg=", NormalizeDouble(avgATR, 5), 
                  ", threshold=", volatilityThreshold);
            return false;
        }
    }
    
    // Check momentum alignment
    if(useMomentumFilter) {
        double momentum = GetMomentum(symbol, PERIOD_M1, MOMENTUM_PERIOD);
        double momentumPrev = GetMomentum(symbol, PERIOD_M1, MOMENTUM_PERIOD, 1);
        double momentumChange = momentum - momentumPrev;
        
        if(isBuySignal && momentumChange < 0) {
            Print("[HFT Filter] Buy signal rejected - momentum decreasing");
            return false;
        }
        if(!isBuySignal && momentumChange > 0) {
            Print("[HFT Filter] Sell signal rejected - momentum increasing");
            return false;
        }
    }
    
    // If all filters pass, this is a valid entry
    return true;
}
