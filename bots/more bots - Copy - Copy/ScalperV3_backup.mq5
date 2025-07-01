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

// Risk management inputs
input double maxKellyFraction = 0.1; // Maximum Kelly fraction to use
input bool useKellySizing = true;  // Use Kelly criterion for position sizing
input double autoTPFactor = 1.5;   // Auto TP factor
input double autoSLFactor = 1.0;   // Auto SL factor
input double maxDrawdownPct = 5.0; // Maximum drawdown percentage allowed
input double maxDailyLossPct = 2.0; // Maximum daily loss percentage allowed
input int regimePersistBars = 10;   // Minimum bars to confirm a regime
input double regimeWinLo = 0.4;     // Threshold for tightening risk
input double regimeWinHi = 0.6;     // Threshold for loosening risk

// High-frequency trading parameters and safety features
input int minSecondsBetweenTrades = 5;   // Minimum seconds between trades (avoid overtrading)
input double maxSpreadFactor = 0.3;      // Maximum spread as a factor of ATR
input bool enableSpreadProtection = true; // Enable spread protection
input bool enableNewsFilter = true;      // Avoid trading during high-impact news
input int newsFilterMinutes = 30;        // Minutes to avoid trading before/after news
input double maxSlippagePips = 3.0;      // Maximum allowed slippage in pips
input int maxConsecutiveLosses = 5;      // Maximum consecutive losses before stopping
input int maxPositionsPerSymbol = 3;     // Maximum positions per symbol
input double slMultiplier = 1.2;      // SL multiplier for ATR
input double tpMultiplier = 1.8;      // TP multiplier for ATR
input double minStopLoss = 10.0;      // Minimum stop loss in points
input double minTakeProfit = 15.0;    // Minimum take profit in points
input bool useAggressiveTrailing = true; // Use aggressive trailing stops
input double trailingActivationPct = 0.3; // Activate trailing at % of TP reached
input double scalingFactor = 0.7;     // Position scaling factor for multiple positions
input double maxPortfolioRiskPct = 0.6; // Maximum portfolio risk percentage
input string correlatedGroups = "EURUSD,GBPUSD;AUDUSD,NZDUSD;USDJPY,CHFJPY"; // Correlated pairs
input int correlationFilterMode = 1;  // 0=off, 1=block, 2=reduce size
input int InpOrderDeviation = 10;     // Order deviation (slippage) in points
input ulong InpMagicNumber = 32042025; // Unique magic number for this EA instance
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
double dynamicBuyThresh = 0.65;
double dynamicSellThresh = 0.35;

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
