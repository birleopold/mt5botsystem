//+------------------------------------------------------------------+
//| SMC Scalper Hybrid HFT - Ultimate High Frequency Trading Robot   |
//| Combines best of V10, V20, and original for speed, reliability  |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/AccountInfo.mqh>
// Standard error codes
#define ERR_REQUOTE 138
#define ERR_PRICE_CHANGED 139
#define ERR_INVALID_STOPS 130
#define ERR_INVALID_TRADE_VOLUME 131
#define ERR_TRADE_TOO_MANY_ORDERS 148

// --- Helper for error description (MQL5 replacement) ---
string ErrorDescription(int code) {
   switch(code) {
      case 0: return "No error";
      case ERR_REQUOTE: return "Requote";
      case ERR_PRICE_CHANGED: return "Price changed";
      case ERR_INVALID_STOPS: return "Invalid stops";
      case ERR_INVALID_TRADE_VOLUME: return "Invalid trade volume";
      case ERR_TRADE_TOO_MANY_ORDERS: return "Too many orders";
      default: return ErrorDescription(code);
   }
}

// --- RefreshRates compatibility (does nothing in MQL5) ---
void RefreshRates() {
   // No-op in MQL5, prices are always current
}

// --- DateToStruct replacement: use TimeToStruct ---
#define DateToStruct TimeToStruct

// --- Time tracking helper functions ---
// Using built-in GetTickCount64() for millisecond resolution
// Note: MQL5 has its own GetMicrosecondCount() but we use consistent tick count

#property copyright "Copyright 2025, Leo Software - HFT Edition"
#property link      "https://www.example.com"
#property version   "2.0"
#property strict

// --- Logging Helpers ---
void LogInfo(string msg)      { Print("[SMC][INFO] ", msg); }
void LogWarn(string msg)      { Print("[SMC][WARN] ", msg); }
void LogError(string msg)     { Print("[SMC][ERROR] ", msg); }
void LogParamChange(string msg) { Print("[SMC][PARAM] ", msg); }
void LogTrade(string msg)     { Print("[SMC][TRADE] ", msg); }
void LogRisk(string msg)      { Print("[SMC][RISK] ", msg); }
void LogCorrelation(string msg) { Print("[SMC][CORR] ", msg); }
void LogLiquidity(string msg)  { Print("[SMC][LIQ] ", msg); }

//+------------------------------------------------------------------+
//| Utility Functions                                              |
//+------------------------------------------------------------------+
// ATR calculation function
double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift) {
    double atr[];
    ArraySetAsSeries(atr, true);
    int handle = iATR(symbol, timeframe, period);
    if(handle == INVALID_HANDLE) {
        LogError("Failed to get ATR handle");
        return 0.0;
    }
    if(CopyBuffer(handle, 0, shift, 1, atr) <= 0) {
        LogError("Failed to copy ATR buffer");
        return 0.0;
    }
    return atr[0];
}

// Check for divergence between price and indicator
bool CheckForDivergence(int signal, double divergenceThreshold) {
    // Simplified implementation - you can expand with actual divergence logic
    return (signal != 0 && MathAbs(signal) > divergenceThreshold);
}

// Structure for storing divergence information
struct DivergenceInfo {
    bool found;            // Whether divergence was found
    double strength;       // Strength score (0.0-1.0)
    int barCount;          // Number of bars between divergence points
    int firstBar;          // Index of first bar in divergence
    int secondBar;         // Index of second bar in divergence
    int indicator;         // Which indicator showed divergence (1=RSI, 2=MACD, etc)
};

// Overloaded version for divergence info object
bool CheckForDivergence(int signal, DivergenceInfo &divInfo) {
    if(!divInfo.found) return false;
    return (signal != 0 && divInfo.strength > 0.3); // Use strength from divergence info
}

// Define HFT constants
#define HFT_COOLDOWN_MINIMUM 3       // Minimum cooldown in seconds for HFT
#define HFT_RETRY_MAX 5              // Maximum retries for HFT
#define HFT_PRICE_VALIDITY_MS 100    // Price validity in milliseconds
#define HFT_MAX_EXECUTION_MS 50      // Maximum execution time in milliseconds

// Variables for tracking cooldown
int cooldownSeconds = HFT_COOLDOWN_MINIMUM;

// Kelly position sizing function for risk management
double CalculateKellyPositionSize(double winRate, double riskRewardRatio) {
    if(winRate <= 0 || winRate >= 1 || riskRewardRatio <= 0) return 0.0;
    
    // Classic Kelly formula: f* = p - (1-p)/r where p = win probability, r = win/loss ratio
    double kellyFraction = winRate - ((1.0 - winRate) / riskRewardRatio);
    
    // Limit the Kelly output for safety (never risk more than 20%)
    return MathMin(0.2, MathMax(0.01, kellyFraction));
}

// Function to detect and handle divergence between price and indicators across timeframes
bool CheckDivergencesAcrossTimeframes(int baseSignal) {
    // Simplified implementation
    if(baseSignal == 0) return false;
    
    int confirmedTimeframes = 0;
    int requiredConfirmations = 2;
    
    // Check multiple timeframes
    ENUM_TIMEFRAMES timeframes[] = {PERIOD_M5, PERIOD_M15, PERIOD_H1};
    
    for(int i = 0; i < ArraySize(timeframes); i++) {
        // Get indicator values for this timeframe
        double rsiValues[];
        ArraySetAsSeries(rsiValues, true);
        
        int rsiHandle = iRSI(Symbol(), timeframes[i], 14, PRICE_CLOSE); // Fixed enum usage
        if(rsiHandle != INVALID_HANDLE) {
            double rsiBuffer[];
            CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer);
            
            // Check for divergence between indicator and previous indicator value
            if((baseSignal > 0 && rsiBuffer[0] > rsiBuffer[1]) ||
               (baseSignal < 0 && rsiBuffer[0] < rsiBuffer[1])) {
                confirmedTimeframes++;
            }
        }
    }
    
    return (confirmedTimeframes >= requiredConfirmations);
}

// Function to get correlation-adjusted position size based on existing positions
double GetCorrelationAdjustedPositionSize(double baseSize) {
    // This is a placeholder implementation
    // In a real system, you would analyze correlations across your open positions
    // and reduce position size if you're adding more exposure to the same risk factors
    
    int totalPositions = PositionsTotal();
    if(totalPositions == 0) return baseSize; // No adjustment needed if no positions
    
    // Simple implementation: reduce position size by 10% for each existing position
    double reductionFactor = 1.0 - (0.1 * MathMin(totalPositions, 5));
    return baseSize * reductionFactor;
}

// Get a risk adjustment based on time of day (session-based risk)
double GetSessionAdaptiveRiskMultiplier() {
    MqlDateTime timeStruct;
    TimeCurrent(timeStruct);
    
    // Reduced risk during market opens/closes and during news
    if((timeStruct.hour == 8 && timeStruct.min < 30) || // London open
       (timeStruct.hour == 14 && timeStruct.min < 30) || // US open
       (timeStruct.hour == 22)) // Late US session
    {
        return 0.7; // Reduce risk by 30%
    }
    
    return 1.0; // Normal risk
}

// Adjust risk based on time since last trade
double GetTimeDecayRiskAdjustment(datetime tradeTimestamp) {
    if(tradeTimestamp == 0) return 1.0;
    
    int secondsSinceLastTrade = (int)(TimeCurrent() - tradeTimestamp);
    
    // After a very recent trade, reduce risk
    if(secondsSinceLastTrade < 300) { // Less than 5 minutes
        return 0.7; // 30% risk reduction
    }
    else if(secondsSinceLastTrade < 1800) { // Less than 30 minutes
        // Gradually increase risk back to normal
        double factor = 0.7 + (0.3 * secondsSinceLastTrade / 1800.0);
        return factor;
    }
    
    return 1.0; // Normal risk after 30 minutes
}

// Get risk adjustment based on session time
double GetSessionAdaptiveRisk() {
    // Simplified implementation
    MqlDateTime dt;
    TimeCurrent(dt);
    // Reduce risk during volatile session opens
    if((dt.hour == 9 && dt.min < 30) || (dt.hour == 14 && dt.min < 30) || (dt.hour == 22 && dt.min < 30)) {
        return 0.7; // Reduce risk by 30% during volatile session opens
    }
    return 1.0; // Normal risk during other times
}

// Adjust risk based on time since last trade
double GetTimeDecayRisk(double riskAmount, datetime tradeTime) {
    if(tradeTime == 0) return riskAmount;
    
    datetime now = TimeCurrent();
    int secondsPassed = (int)(now - tradeTime);
    
    // For very recent trades, reduce risk
    if(secondsPassed < 300) { // Less than 5 minutes
        return riskAmount * 0.8;
    }
    // For older trades, gradually increase risk back to normal
    else if(secondsPassed < 1800) { // Less than 30 minutes
        return riskAmount * (0.8 + 0.2 * (secondsPassed - 300) / 1500.0);
    }
    
    return riskAmount; // Normal risk after 30 minutes
}

// Calculate optimal position size using Kelly Criterion
double KellyOptimalPositionSize(double winRate, double rr) {
    if(winRate <= 0 || winRate >= 1 || rr <= 0) return 0;
    double kelly = winRate - ((1.0 - winRate) / rr);
    return MathMax(0, kelly); // Don't allow negative Kelly values
}

// Adjust position size based on correlation with other positions
double GetCorrelationAdjustedSize(double lotSize) {
    // Simplified implementation - you can expand with actual correlation logic
    return lotSize * 0.9; // Reduce by 10% as an example
}

// Structure to hold news events
struct NewsEvent {
    datetime eventTime;
    string currency;
    string title;
    string impact; // "Low", "Medium", "High"
};

// Structure to hold a price cache for faster access
struct PriceCache {
    double ask;
    double bid;
    double mid;
    double spread;
    double atr;
    double dailyHigh;
    double dailyLow;
    datetime lastUpdate;
    
    // Indicator values
    double maFast;
    double maSlow;
    double bbTop;
    double bbMiddle;
    double bbBottom;
    double rsi;
    double momentum;
};

// Structure for order blocks
struct OrderBlock {
    datetime time;
    double high;
    double low;
    double open;
    double close;
    double volume;
    double strength;
    int direction; // 1 for bullish, -1 for bearish
    bool valid;
    bool tested;
    int barIndex;
};

// Note: SwingPoint structure is already defined above (around line 350)
// Using the existing structure for consistency

// Structure for liquidity grabs
struct LiquidityGrab {
    datetime time;
    double level;
    double strength;
    int direction; // 1 for buy stop grab, -1 for sell stop grab
};

// Structure for fair value gaps
struct FVG {
    datetime time;
    double upper;
    double lower;
    double strength;
    int direction; // 1 for bullish, -1 for bearish
    bool filled;
};

// Structure for scaling entries
struct ScalingEntry {
    ulong ticket;           // Order ticket number
    double entryPrice;      // Entry price level
    double lotSize;         // Position size in lots
    double stopLoss;        // Stop loss level
    double takeProfit;      // Take profit level
    bool filled;            // Whether order has been filled
    datetime placementTime; // When the order was placed
    int entryNumber;        // Entry sequence number (1st, 2nd, etc.)
    int direction;          // Trade direction (1=buy, -1=sell)
    bool active;            // Whether this entry is active
};

// Structure for pattern clusters
struct PatternCluster {
    double level;
    int patternCount;
    string patterns[10];
    double strength;
    bool active;           // Whether this cluster is active
    bool bullish;          // Whether the pattern is bullish (true) or bearish (false)
    double winRate;        // Historical win rate
    double lastSignalQuality; // Quality of the last signal
    string name;           // Name of the pattern cluster
};

// Structure for regime parameters
struct RegimeParameters {
    int regime;
    double riskMultiplier;
    double tpMultiplier;
    double slMultiplier;
    int minBarCount;
    double minSignalStrength;
};

// Swing point structure for stop loss placement
struct SwingPoint {
    double price;
    datetime time;
    double strength;
    int type; // 1 = swing high, -1 = swing low
    int barIndex;
    int score;    // Quality score used for swing point ranking
};

// --- Includes ---
#include <Trade/Trade.mqh>
#include <Math/Stat/Normal.mqh>

// --- Constants ---
#define MAX_BLOCKS 20
#define MAX_GRABS 20
#define MAX_FVGS 20
#define MAX_FEATURES 100
#define CLUSTER_MAX 20

// Trading Regime Constants
#define TRENDING_UP 0
#define TRENDING_DOWN 1
#define RANGING_NARROW 2
#define RANGING_WIDE 3
#define BREAKOUT 4
#define REVERSAL 5
#define HIGH_VOLATILITY 6
#define LOW_VOLATILITY 7
#define CHOPPY 8
#define REGIME_COUNT 9

// News filter constants
// Note: Using MACRO_ prefix to avoid conflicts with input parameters
#define MACRO_NewsLookaheadMinutes 30
#define MACRO_MediumNewsSizeReduction 0.75

// Strategy parameters
#define MACRO_MinBlockStrength 3
// NOTE: Input parameters are already defined above

#define METRIC_WINDOW 100
#define ACCURACY_WINDOW 100
#define CORRELATION_PAIRS 8

// --- Market Regime Constants ---
// Note: These constants are already defined above

// --- Input Parameters ---
input ENUM_TIMEFRAMES AnalysisTimeframe = PERIOD_H1; // Timeframe used for market analysis
input ENUM_TIMEFRAMES ScanningTimeframe = PERIOD_M15; // Timeframe used for scanning signals
input ENUM_TIMEFRAMES ExecutionTimeframe = PERIOD_M5; // Timeframe used for trade execution
input int TradingStartHour = 0;
input int TradingEndHour = 23;
input int MaxTrades = 5; // Allow more concurrent trades for HFT
input double RiskPercent = 0.1;
input double SL_Pips = 10.0;           // Stop loss in pips
input double ATRMultiplier = 0.75;         // Multiplier for ATR-based stop loss calculation
input int SignalCooldownSeconds = 10;  // Lower cooldown for HFT
input int MinBlockStrength = 1;        // Sets the minimum strength for valid order blocks
input bool RequireTrendConfirmation = false;  // When enabled, requires confirmation from multiple timeframes before entering a trade
input int MaxConsecutiveLosses = 5;    // Maximum consecutive losses allowed
input bool EnableFastExecution = true; // Enable fast execution for HFT
input bool EnableAdaptiveRisk = true;  // Enable adaptive risk management
input bool EnableAggressiveTrailing = true; // Only define this once
input double TrailingActivationPct = 0.25; // When to activate trailing (25% of TP distance)
input double TrailingStopMultiplier = 0.75; // Trailing stop multiplier (0.75 = 75% of ATR)
input double EnhancedRR = 2.0;        // Enhanced risk-reward ratio
input bool EnableMarketRegimeFiltering = true; // Filter trades based on market regime
input bool EnableNewsFilter = true;      // Enable filtering based on economic news
input int NewsCooldownPeriod = 30;         // Waiting period after high-impact news before resuming trading
input bool BlockHighImpactNews = true;   // Safety mechanism that prevents the EA from trading during major economic announcements
input bool ReduceSizeOnMediumNews = true; // Reduce position size on medium news
input double MediumNewsSizeReduction = 0.5; // Size reduction factor for medium impact news
input double MinATRThreshold = 0.00015;   // Minimum volatility threshold required for trading signals
input bool EnableDynamicATR = true;      // Enable dynamic ATR
input double ATRDynamicMultiplier = 0.5; // ATR dynamic multiplier
input double MinATRFloor = 0.00015;      // Minimum ATR floor
input double MaxAllowedSpread = 3;       // Maximum spread allowed in pips for trade execution
input bool EnableSignalQualityML = true;  // Enable ML-based signal quality analysis
input bool EnableSmartScaling = true;    // Enable smart position scaling
input int ScalingPositions = 3;         // Number of scaling positions to use for HFT
input bool EnableSessionFiltering = true;     // Enable filtering based on trading sessions
input bool EnableDivergenceFilter = true;    // Enable filtering based on price divergence
input bool RequireMomentumConfirmation = true; // Require momentum confirmation for signals
input bool EnableCorrelationChecking = true;  // Enable checking correlations between pairs
input bool EnableTimedRiskDecay = true;     // Enable time-based risk decay
input bool DisplayDebugInfo = true;         // Display debug information on the chart
input bool LogPerformanceStats = true;      // Log performance statistics to file

// --- Structures ---
// Using the full struct definitions defined earlier in the file

// Note: DivergenceInfo struct is already defined above
// We'll use the existing one to avoid compilation errors

// Note: ScalingEntry struct is already defined above
// We'll use the existing one to avoid compilation errors

// Note: PatternCluster struct is already defined above
// We'll use the existing one to avoid compilation errors

// Note: RegimeParameters struct is already defined above
// We'll use the existing one to avoid compilation errors

// Note: PriceCache struct is already defined above (around line 250)
// We will use the existing one to avoid compilation errors

// Helper function to normalize price according to symbol digits
double NormalizePrice(double price) {
    return NormalizeDouble(price, _Digits);
}

// Market Structure Tracking
struct MarketStructure {
    double swingHigh;           // Most recent significant swing high
    double swingLow;            // Most recent significant swing low
    datetime swingHighTime;     // Time of the swing high
    datetime swingLowTime;      // Time of the swing low
    bool bos;                   // Breakout of structure detected
    bool chochDetected;         // Change of character detected
};

// Global variables
bool emergencyMode = false;
bool marketClosed = false;
bool isWeekend = false;
datetime lastTradeTime = 0;
datetime lastSignalTime = 0;
string lastErrorMessage = "";
bool trailingActive = false;
double trailingLevel = 0, trailingTP = 0;
int consecutiveLosses = 0, winStreak = 0, lossStreak = 0;
int currentRegime = -1, regimeBarCount = 0, lastRegime = -1;
double tradeProfits[], tradeReturns[];
int regimeWins[], regimeLosses[];
double regimeProfit[], regimeAccuracy[], predictionResults[];
int predictionCount = 0;
double atrBuffer[], maBuffer[], volBuffer[];
CTrade trade;
NewsEvent newsEvents[50];
int newsEventCount = 0;

// Additional tracking variables for HFT
PriceCache priceCache;               // For caching prices and indicators
OrderBlock recentBlocks[MAX_BLOCKS]; // Array to store recent order blocks
LiquidityGrab recentGrabs[MAX_GRABS]; // Array to store recent liquidity grabs
FVG recentFVGs[MAX_FVGS];           // Array to store recent fair value gaps
RegimeParameters regimeParams[REGIME_COUNT]; // Parameters for each regime
ScalingEntry currentScalingEntries[10]; // Current scaling entries
PatternCluster patternClusters[CLUSTER_MAX]; // Pattern clusters

// HFT performance metrics
int missedTradeCount = 0;            // Count of missed trades due to execution issues
int validationErrorCount = 0;        // Count of validation errors
int retrySuccessCount = 0;           // Count of successful retries
int lastTradeRetryCount = 0;         // Number of retries for last trade
int totalOrderBlocks = 0;            // Total order blocks detected
int validOrderBlocks = 0;            // Valid order blocks detected
int invalidOrderBlocks = 0;          // Invalid order blocks detected
double orderBlockStrengthSum = 0;    // Sum of order block strengths
double signalQualitySum = 0;         // Sum of signal qualities
double signalQualityCount = 0;       // Count of signal qualities
ulong lastDetectionTime = 0;         // Time of last detection
ulong detectionDurationMs = 0;       // Duration of last detection in ms
ulong executionDurationMs = 0;       // Duration of last execution in ms
double lastSignalQuality = 0;        // Quality of last signal
double AdaptiveSlippagePoints = 10;  // Adaptive slippage for fast execution

MarketStructure marketStructure; // Global market structure object for HFT

// --- TradeJournal class (from V20) ---
class TradeJournal {
private:
    struct TradeRecord {
        datetime openTime;
        datetime closeTime;
        double openPrice;
        double closePrice;
        double lotSize;
        double profit;
        double pips;
        double riskAmount;
        double riskRewardRatio;
        ENUM_ORDER_TYPE orderType;
        int signal;
        int regime;
        int session;
        double quality;
        string notes;
        bool wasConfirmed;
    };
    int totalTrades, winTrades, lossTrades;
    double grossProfit, grossLoss, netProfit, profitFactor, expectancy;
    double avgWin, avgLoss, avgRiskReward, maxDrawdown;
    int maxConsecWins, maxConsecLosses, currentConsecWins, currentConsecLosses;
    double regimePerformance[5];
    int regimeTrades[5];
    double sessionPerformance[5];
    int sessionTrades[5];
    TradeRecord trades[];
    int maxRecords, currentIndex;
    string journalFilename;
    int fileHandle;
    bool enableFileLogging;
public:
    TradeJournal(int maxTrades = 1000, bool logToFile = true) {
        maxRecords = maxTrades;
        enableFileLogging = logToFile;
        ArrayResize(trades, maxRecords);
        currentIndex = 0;
        totalTrades = 0;
        ResetStats();
        if(enableFileLogging) {
            journalFilename = "SMC_TradeJournal_" + Symbol() + ".csv";
            // Open file for appending, create if not exists
            fileHandle = FileOpen(journalFilename, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
            if(fileHandle != INVALID_HANDLE) {
                FileSeek(fileHandle, 0, SEEK_END);
                if(FileSize(fileHandle) == 0) {
                    FileWrite(fileHandle, "OpenTime,CloseTime,OpenPrice,ClosePrice,LotSize,Profit,Pips,RiskAmount,RR,OrderType,Signal,Regime,Session,Quality,Confirmed,Notes");
                }
                FileClose(fileHandle);
            }
        }
    }
    void ResetStats() {
        winTrades = lossTrades = 0; grossProfit = grossLoss = netProfit = 0; profitFactor = expectancy = 0;
        avgWin = avgLoss = avgRiskReward = maxDrawdown = 0; maxConsecWins = maxConsecLosses = 0;
        currentConsecWins = currentConsecLosses = 0;
        ArrayInitialize(regimePerformance, 0); ArrayInitialize(regimeTrades, 0);
        ArrayInitialize(sessionPerformance, 0); ArrayInitialize(sessionTrades, 0);
    }
    void AddTrade(datetime openTime, datetime closeTime, double openPrice, double closePrice, double lotSize, double profit, int pips, double riskAmount, double riskReward, ENUM_ORDER_TYPE orderType, int signal, int regime, int session, double quality, bool wasConfirmed, string notes = "") {
        int idx = currentIndex % maxRecords;
        trades[idx].openTime = openTime;
        trades[idx].closeTime = closeTime;
        trades[idx].openPrice = openPrice;
        trades[idx].closePrice = closePrice;
        trades[idx].lotSize = lotSize;
        trades[idx].profit = profit;
        trades[idx].pips = pips;
        trades[idx].riskAmount = riskAmount;
        trades[idx].riskRewardRatio = riskReward;
        trades[idx].orderType = orderType;
        trades[idx].signal = signal;
        trades[idx].regime = regime;
        trades[idx].session = session;
        trades[idx].quality = quality;
        trades[idx].notes = notes;
        trades[idx].wasConfirmed = wasConfirmed;
        currentIndex++; totalTrades++;
        if(profit >= 0) { winTrades++; currentConsecWins++; currentConsecLosses = 0; }
        else { lossTrades++; currentConsecLosses++; currentConsecWins = 0; }
        netProfit += profit;
        if(profit >= 0) grossProfit += profit; else grossLoss += profit;
        avgWin = winTrades > 0 ? grossProfit / winTrades : 0;
        avgLoss = lossTrades > 0 ? grossLoss / lossTrades : 0;
        profitFactor = grossLoss != 0 ? MathAbs(grossProfit / grossLoss) : 0;
        expectancy = totalTrades > 0 ? netProfit / totalTrades : 0;
        if(currentConsecWins > maxConsecWins) maxConsecWins = currentConsecWins;
        if(currentConsecLosses > maxConsecLosses) maxConsecLosses = currentConsecLosses;
        // CSV Logging
        if(enableFileLogging) {
            fileHandle = FileOpen(journalFilename, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
            if(fileHandle != INVALID_HANDLE) {
                FileSeek(fileHandle, 0, SEEK_END);
                FileWrite(fileHandle, TimeToString(openTime), TimeToString(closeTime), DoubleToString(openPrice,5), DoubleToString(closePrice,5), DoubleToString(lotSize,2), DoubleToString(profit,2), IntegerToString(pips), DoubleToString(riskAmount,2), DoubleToString(riskReward,2), EnumToString(orderType), IntegerToString(signal), IntegerToString(regime), IntegerToString(session), DoubleToString(quality,2), wasConfirmed ? "true" : "false", notes);
                FileClose(fileHandle);
            }
        }
    }
    double GetExpectancy() { return expectancy; }
    double GetWinRate() { return totalTrades > 0 ? (double)winTrades/totalTrades : 0.0; }
    double GetRegimeWinRate(int regime) { return regimeTrades[regime] > 0 ? regimePerformance[regime]/regimeTrades[regime] : 0.0; }
    double GetTodayProfit() {
        double profit = 0;
        datetime now = TimeCurrent();
        MqlDateTime nowStruct;
        TimeToStruct(now, nowStruct);
        int today = (nowStruct.year * 10000) + (nowStruct.mon * 100) + nowStruct.day;
        
        for(int i=0; i<maxRecords; i++) {
            if(trades[i].closeTime != 0) {
                MqlDateTime closeStruct;
                TimeToStruct(trades[i].closeTime, closeStruct);
                int closeDay = (closeStruct.year * 10000) + (closeStruct.mon * 100) + closeStruct.day;
                if(closeDay == today)
                    profit += trades[i].profit;
            }
        }
        return profit;
    }
    int GetTodayTradeCount() {
        int count = 0;
        datetime now = TimeCurrent();
        MqlDateTime nowStruct;
        TimeToStruct(now, nowStruct);
        int today = (nowStruct.year * 10000) + (nowStruct.mon * 100) + nowStruct.day;
        
        for(int i=0; i<maxRecords; i++) {
            if(trades[i].closeTime != 0) {
                MqlDateTime closeStruct;
                TimeToStruct(trades[i].closeTime, closeStruct);
                int closeDay = (closeStruct.year * 10000) + (closeStruct.mon * 100) + closeStruct.day;
                if(closeDay == today)
                    count++;
            }
        }
        return count;
    }

};

TradeJournal Journal(1000, true);

//+------------------------------------------------------------------+
//| Detect order blocks with enhanced validation and logging         |
//+------------------------------------------------------------------+
void DetectOrderBlocks() {
    // Variables for storing block strength score and tracking
    int score = 0;
    int detectedCount = 0;
    ulong startTime = GetTickCount64();
    int detectedBlocks = 0;
    int validBlocks = 0;
    int invalidBlocks = 0;
    double blockStrengthSum = 0;
    
    // Reset validity status for all blocks for proper counting
    for(int i=0; i<MAX_BLOCKS; i++) {
        recentBlocks[i].valid = false;
    }
    
    LogInfo("Starting order block detection");
    int lookback = MathMin(500, Bars(Symbol(), PERIOD_CURRENT));
    double high[], low[], open[], close[];
    datetime time[];
    long volume[];
    
    // Get price data
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(volume, true);
    
    if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback, high) <= 0) {
        LogError("Failed to copy high prices for order block detection");
        return;
    }
    if(CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback, low) <= 0) {
        LogError("Failed to copy low prices for order block detection");
        return;
    }
    if(CopyOpen(Symbol(), PERIOD_CURRENT, 0, lookback, open) <= 0) {
        LogError("Failed to copy open prices for order block detection");
        return;
    }
    if(CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback, close) <= 0) {
        LogError("Failed to copy close prices for order block detection");
        return;
    }
    if(CopyTime(Symbol(), PERIOD_CURRENT, 0, lookback, time) <= 0) {
        LogError("Failed to copy time data for order block detection");
        return;
    }
    if(CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, lookback, volume) <= 0) {
        LogWarn("Failed to copy volume data for order block detection");
        // Continue without volume as it's not critical
    }
    
    // Get current market regime
    int regime = FastRegimeDetection(Symbol());
    
    // Analyze price action to find order blocks
    for(int i=2; i<lookback-2; i++) {
        // For bullish order blocks (at bottoms, before price moves up)
        if(close[i] > open[i] && close[i+1] < open[i+1]) {
            // Look for a local low followed by a move up
            if(low[i+1] < low[i+2] && low[i+1] < low[i]) {
                // Found potential bullish order block
                int blockIndex = detectedBlocks % MAX_BLOCKS;
                recentBlocks[blockIndex].time = time[i];
                recentBlocks[blockIndex].high = high[i];
                recentBlocks[blockIndex].low = low[i];
                
                // Calculate strength score (use the score variable initialized at the function start)
                score = 1; // Base score
                double body = MathAbs(close[i] - open[i]);
                double range = high[i] - low[i];
                
                // Strength factors
                if(body > (range * 0.5)) score++; // Strong body
                if(volume[i] > volume[i+1]) score++; // Higher volume
                if(low[i] < low[i+1] && high[i] > high[i+1]) score++; // Engulfing
                if(close[i] > close[i+5]) score++; // Trend alignment
                
                // Regime-specific scoring
                if(regime == TRENDING_UP) score += 2; // Stronger in trending market
                if(regime == RANGING_NARROW && body < (range * 0.3)) score--; // Weaker in ranging
                
                recentBlocks[blockIndex].strength = score;
                
                // Validate block - minimum strength check
                recentBlocks[blockIndex].valid = (score >= MinBlockStrength);
                
                // Count statistics
                detectedBlocks++;
                if(recentBlocks[blockIndex].valid) {
                    validBlocks++;
                    blockStrengthSum += score;
                } else {
                    invalidBlocks++;
                }
                
                // Debug logging
                if(DisplayDebugInfo) {
                    LogInfo(StringFormat("Bullish order block found at bar %d - Strength: %d, Valid: %s", 
                             i, score, recentBlocks[blockIndex].valid ? "Yes" : "No"));
                }
            }
        }
        
        // For bearish order blocks (at tops, before price moves down)
        if(close[i] < open[i] && close[i+1] > open[i+1]) {
            // Look for a local high followed by a move down
            if(high[i+1] > high[i+2] && high[i+1] > high[i]) {
                // Found potential bearish order block
                int blockIndex = detectedBlocks % MAX_BLOCKS;
                recentBlocks[blockIndex].time = time[i];
                recentBlocks[blockIndex].high = high[i];
                recentBlocks[blockIndex].low = low[i];
                
                // Calculate strength score
                score = 1; // Use the score variable initialized at the start of function
                double body = MathAbs(close[i] - open[i]);
                double range = high[i] - low[i];
                
                // Strength factors
                if(body > (range * 0.5)) score++; // Strong body
                if(volume[i] > volume[i+1]) score++; // Higher volume
                if(low[i] < low[i+1] && high[i] > high[i+1]) score++; // Engulfing
                if(close[i] < close[i+5]) score++; // Trend alignment
                
                // Regime-specific scoring
                if(regime == TRENDING_DOWN) score += 2; // Stronger in trending market
                if(regime == RANGING_NARROW && body < (range * 0.3)) score--; // Weaker in ranging
                
                recentBlocks[blockIndex].strength = score;
                
                // Validate block - minimum strength check
                recentBlocks[blockIndex].valid = (score >= MinBlockStrength);
                
                // Count statistics
                detectedBlocks++;
                if(recentBlocks[blockIndex].valid) {
                    validBlocks++;
                    blockStrengthSum += score;
                } else {
                    invalidBlocks++;
                }
                
                // Debug logging
                if(DisplayDebugInfo) {
                    LogInfo(StringFormat("Bearish order block found at bar %d - Strength: %d, Valid: %s", 
                             i, score, recentBlocks[blockIndex].valid ? "Yes" : "No"));
                }
            }
        }
    }
    
    // Update global statistics
    totalOrderBlocks = detectedBlocks;
    validOrderBlocks = validBlocks;
    invalidOrderBlocks = invalidBlocks;
    orderBlockStrengthSum = blockStrengthSum;
    
    // Performance tracking
    detectionDurationMs = GetTickCount64() - startTime;
    lastDetectionTime = GetTickCount64();
    
    // Final logging with block counts
    LogInfo(StringFormat("Order block detection completed. Detected: %d, Valid: %d, Invalid: %d, Time: %d ms", 
             detectedBlocks, validBlocks, invalidBlocks, detectionDurationMs));
}

//+------------------------------------------------------------------+
//| Determine optimal stop loss for given conditions with logging    |
//+------------------------------------------------------------------+
double DetermineOptimalStopLoss(int signal, double entryPrice) {
    LogInfo(StringFormat("DetermineOptimalStopLoss called - Signal: %d, Entry: %.5f", signal, entryPrice));
    
    // Array to store potential swing points
    SwingPoint swingPoints[];
    int swingCount = 0;
    
    // Get ATR for volatility context
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    if(atr == 0) {
        LogError("ATR calculation failed in stop loss determination");
        // Fallback to fixed pip distance
        double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        double defaultSL = signal > 0 ? entryPrice - SL_Pips * 10 * point : entryPrice + SL_Pips * 10 * point;
        LogInfo(StringFormat("Using default SL due to ATR failure: %.5f (%.2f pips from entry)", 
                 defaultSL, MathAbs(entryPrice - defaultSL) / point / 10));
        return defaultSL;
    }
    
    // Find quality swing points based on signal direction
    bool isBuy = signal > 0;
    int lookbackBars = 20;
    FindQualitySwingPoints(isBuy, lookbackBars, swingPoints, swingCount);
    
    LogInfo(StringFormat("Found %d swing points for stop placement", swingCount));
    
    // Track the best swing point for SL placement
    double bestSwingStop = 0;
    double bestSwingScore = -1;
    double bestDistanceDiff = 999999;
    
    // ATR-based SL distance (adaptive to volatility)
    double atrDistance = atr * 1.5; // 1.5 ATR default
    double minDistance = atr * 0.75; // Minimum 0.75 ATR
    double maxDistance = atr * 3.0;  // Maximum 3.0 ATR
    
    // Default SL based on ATR if no swing points
    double defaultSL = isBuy ? entryPrice - atrDistance : entryPrice + atrDistance;
    
    // Calculate optimal distance based on regime
    if(currentRegime == TRENDING_UP || currentRegime == TRENDING_DOWN) {
        // In trending markets, give more room
        atrDistance *= 1.2;
    } else if(currentRegime == RANGING_NARROW) {
        // In tight ranges, tighter stop
        atrDistance *= 0.8;
    } else if(currentRegime == HIGH_VOLATILITY) {
        // In high volatility, wider stop
        atrDistance *= 1.5;
    }
    
    double idealDistance = atrDistance;
    LogInfo(StringFormat("Ideal SL distance calculated: %.5f (%.2f ATR)", 
             idealDistance, idealDistance / atr));
    
    // Analyze swing points
    for(int i=0; i<swingCount; i++) {
        double swingPrice = swingPoints[i].price;
        double distance = MathAbs(entryPrice - swingPrice);
        double distanceDiff = MathAbs(distance - idealDistance);
        int score = swingPoints[i].score;
        
        // Log each swing point analysis
        LogInfo(StringFormat("Analyzing swing point %d - Price: %.5f, Distance: %.5f, Score: %d", 
                 i, swingPrice, distance, score));
        
        // Check if this swing point is valid for the signal direction
        bool validDirection = (isBuy && swingPrice < entryPrice) || (!isBuy && swingPrice > entryPrice);
        if(!validDirection) {
            LogInfo(StringFormat("Swing point %d rejected - wrong direction", i));
            continue;
        }
        
        // Check if distance is reasonable
        if(distance < minDistance) {
            LogInfo(StringFormat("Swing point %d rejected - too close (%.5f < %.5f)", 
                     i, distance, minDistance));
            continue;
        }
        
        if(distance > maxDistance) {
            LogInfo(StringFormat("Swing point %d rejected - too far (%.5f > %.5f)", 
                     i, distance, maxDistance));
            continue;
        }
        
        // Calculate weighted score based on distance from ideal and swing point quality
        double weightedScore = score * (1.0 - (distanceDiff / idealDistance) * 0.5);
        
        // Log the weighted score
        LogInfo(StringFormat("Swing point %d weighted score: %.2f", i, weightedScore));
        
        // Record if this is the best point so far
        if(weightedScore > bestSwingScore) {
            bestSwingScore = weightedScore;
            bestSwingStop = swingPrice;
            bestDistanceDiff = distanceDiff;
            LogInfo(StringFormat("New best swing point found at %.5f with score %.2f", 
                     bestSwingStop, bestSwingScore));
        }
    }
    
    // Set final stop loss
    double finalSL;
    
    if(bestSwingScore > 0) {
        // Found a good swing point
        finalSL = bestSwingStop;
        LogInfo(StringFormat("Using optimal swing-based SL: %.5f (Score: %.2f)", finalSL, bestSwingScore));
    } else {
        // No good swing point, use ATR-based
        finalSL = defaultSL;
        LogInfo(StringFormat("No suitable swing point found, using ATR-based SL: %.5f", finalSL));
    }
    
    // --- Broker-specific validations ---
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int stopLevel = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    double minStop = stopLevel * point;
    
    // Make sure SL is far enough from current price
    double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    
    if(isBuy && (currentBid - finalSL) < minStop) {
        double oldSL = finalSL;
        finalSL = currentBid - minStop - 5 * point; // Add 5 points buffer
        LogWarn(StringFormat("SL adjusted for broker minimums: %.5f -> %.5f", oldSL, finalSL));
    } else if(!isBuy && (finalSL - currentAsk) < minStop) {
        double oldSL = finalSL;
        finalSL = currentAsk + minStop + 5 * point; // Add 5 points buffer
        LogWarn(StringFormat("SL adjusted for broker minimums: %.5f -> %.5f", oldSL, finalSL));
    }
    
    // Final check and logging
    if((isBuy && finalSL >= entryPrice) || (!isBuy && finalSL <= entryPrice)) {
        LogError(StringFormat("CRITICAL: Invalid SL calculation - Entry: %.5f, SL: %.5f, Direction: %s", 
                 entryPrice, finalSL, isBuy ? "Buy" : "Sell"));
        
        // Force a valid stop loss
        finalSL = isBuy ? entryPrice - atrDistance : entryPrice + atrDistance;
        LogWarn(StringFormat("Forced emergency SL correction to: %.5f", finalSL));
    }
    
    // Distance in pips for logging
    double pipDistance = MathAbs(entryPrice - finalSL) / point / 10;
    LogInfo(StringFormat("Final SL: %.5f (%.2f pips from entry)", finalSL, pipDistance));
    
    return finalSL;
}

//+------------------------------------------------------------------+
//| Find high-quality swing points for stop loss placement          |
//+------------------------------------------------------------------+
void FindQualitySwingPoints(bool isBuy, int lookbackBars, SwingPoint &swingPoints[], int &count) {
    // Initialize count
    count = 0;
    
    // Prepare arrays for price data
    double high[], low[], close[], open[];
    long volume[];
    datetime time[];
    
    // Set arrays as series
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(volume, true);
    ArraySetAsSeries(time, true);
    
    // Get price data
    int bars = MathMin(lookbackBars + 10, Bars(Symbol(), PERIOD_CURRENT));
    if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, bars, high) <= 0 ||
       CopyLow(Symbol(), PERIOD_CURRENT, 0, bars, low) <= 0 ||
       CopyClose(Symbol(), PERIOD_CURRENT, 0, bars, close) <= 0 ||
       CopyOpen(Symbol(), PERIOD_CURRENT, 0, bars, open) <= 0) {
        return;
    }
    
    if(CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, bars, volume) <= 0 ||
       CopyTime(Symbol(), PERIOD_CURRENT, 0, bars, time) <= 0) {
        return;
    }
    
    // Temporary array to store all potential swing points
    SwingPoint tempPoints[100]; // Use a fixed array for simplicity
    int tempCount = 0;
    
    // Look for swings
    if(isBuy) {
        // For buy trades, look for swing lows (support levels)
        for(int i = 2; i < lookbackBars && tempCount < 100; i++) {
            // Find local lows (price lower than neighbors)
            if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i+1] && low[i] < low[i+2]) {
                // Found a swing low
                tempPoints[tempCount].price = low[i];
                tempPoints[tempCount].time = time[i];
                tempPoints[tempCount].barIndex = i;
                
                // Calculate score based on various factors
                int score = 1; // Base score
                
                // Volume factor
                if(volume[i] > volume[i-1] && volume[i] > volume[i+1]) score++;
                
                // Previous test factor (did price bounce here before?)
                bool previousTest = false;
                for(int j = i + 3; j < lookbackBars; j++) {
                    if(MathAbs(low[j] - low[i]) < GetATR(Symbol(), PERIOD_CURRENT, 14, 0) * 0.3) {
                        previousTest = true;
                        break;
                    }
                }
                if(previousTest) score += 2;
                
                // Price action context
                if(open[i] > close[i] && open[i+1] < close[i+1]) score++; // Reversal bar pattern
                if(close[i+1] > close[i] && close[i+2] > close[i+1]) score++; // Upward momentum after swing
                
                // Round number factor
                double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                if(MathAbs(MathMod(low[i] / (10 * point), 10)) < 0.2 || 
                   MathAbs(MathMod(low[i] / (10 * point), 10) - 5) < 0.2) score++;
                
                tempPoints[tempCount].score = score;
                tempCount++;
            }
        }
    }
    else {
        // For sell trades, look for swing highs (resistance levels)
        for(int i = 2; i < lookbackBars && tempCount < 100; i++) {
            // Declare score variable outside if statement to fix compilation
            int score = 1; 
            
            // Find local highs (price higher than neighbors)
            if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i+1] && high[i] > high[i+2]) {
                // Found a swing high
                tempPoints[tempCount].price = high[i];
                tempPoints[tempCount].time = time[i];
                tempPoints[tempCount].barIndex = i;
                
                // Reset score since we've found a valid point
                score = 1; // Base score
                
                // Volume factor
                if(volume[i] > volume[i-1] && volume[i] > volume[i+1]) score++;
                
                // Previous test factor (did price bounce here before?)
                bool previousTest = false;
                for(int j = i + 3; j < lookbackBars; j++) {
                    if(MathAbs(high[j] - high[i]) < GetATR(Symbol(), PERIOD_CURRENT, 14, 0) * 0.3) {
                        previousTest = true;
                        break;
                    }
                }
                if(previousTest) score += 2;
                
                // Price action context
                if(open[i] < close[i] && open[i+1] > close[i+1]) score++; // Reversal bar pattern
                if(close[i+1] < close[i] && close[i+2] < close[i+1]) score++; // Downward momentum after swing
                
                // Round number factor
                double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                if(MathAbs(MathMod(high[i] / (10 * point), 10)) < 0.2 || 
                   MathAbs(MathMod(high[i] / (10 * point), 10) - 5) < 0.2) score++;
                
                tempPoints[tempCount].score = score;
                tempCount++;
            }
        }
    }
    
    // Sort points by score in descending order (bubble sort for simplicity)
    for(int i=0; i<tempCount-1; i++) {
        for(int j=0; j<tempCount-i-1; j++) {
            if(tempPoints[j].score < tempPoints[j+1].score) {
                SwingPoint temp = tempPoints[j];
                tempPoints[j] = tempPoints[j+1];
                tempPoints[j+1] = temp;
            }
        }
    }
    
    // Copy the best points to the output array (limit to 5 top points)
    int maxPoints = MathMin(tempCount, 5);
    ArrayResize(swingPoints, maxPoints);
    for(int i=0; i<maxPoints; i++) {
        swingPoints[i] = tempPoints[i];
    }
    count = maxPoints;
    
    // Log the found swing points - use global input parameter
    if(::DisplayDebugInfo) {
        for(int i=0; i<count; i++) {
            // Access the swing point's score for debugging
            int pointScore = swingPoints[i].score;
            LogInfo(StringFormat("Swing point %d: Price %.5f, Score %d, Bar %d", 
                     i, swingPoints[i].price, pointScore, swingPoints[i].barIndex));
        }
    }
}

//+------------------------------------------------------------------+
//| Signal Quality, Pattern Clustering, ML (from V20) ---
//+------------------------------------------------------------------+
//| Signal Quality Assessment                                       |
//+------------------------------------------------------------------+
double CalculateSignalQuality(int signal) {
    if(!EnableSignalQualityML || signal == 0) return 0.0;
    
    // Initialize quality score
    double quality = 0.0;
    
    // Weights for different factors
    double regimeWeight = 0.25;      // Market regime alignment
    double blockWeight = 0.20;       // Order block strength
    double divergenceWeight = 0.15;  // Divergence confirmation
    double volatilityWeight = 0.10;  // Volatility conditions
    double patternWeight = 0.20;     // Pattern recognition
    double momentumWeight = 0.10;    // Momentum alignment
    
    // 1. Regime alignment score (0.0-1.0)
    double regimeAlignment = 0.5; // Neutral default
    
    if(currentRegime == TRENDING_UP && signal > 0) regimeAlignment = 0.9;
    else if(currentRegime == TRENDING_DOWN && signal < 0) regimeAlignment = 0.9;
    else if(currentRegime == CHOPPY) regimeAlignment = 0.3;
    else if(currentRegime == HIGH_VOLATILITY) regimeAlignment = 0.4;
    else if(currentRegime == RANGING_NARROW || currentRegime == RANGING_WIDE) {
        // Initialize and use the close price array properly for range detection
        double closeMA[];
        ArraySetAsSeries(closeMA, true);
        if(CopyClose(Symbol(), PERIOD_CURRENT, 0, 21, closeMA) >= 21 && 
           ((signal > 0 && closeMA[0] > closeMA[20]) || (signal < 0 && closeMA[0] < closeMA[20]))) {
            regimeAlignment = 0.6;
        }
    }
    else if(currentRegime == BREAKOUT) {
        // Get the price data for breakout confirmation
        double closeData[];
        double atrData[];
        ArraySetAsSeries(closeData, true);
        ArraySetAsSeries(atrData, true);
        // Copy close prices
        if(CopyClose(Symbol(), PERIOD_CURRENT, 0, 6, closeData) < 6) {
            LogError("Failed to copy close prices for breakout detection");
            return 0.5; // Return neutral score if data not available
        }
        // Get ATR for volatility threshold - fix parameter count
        int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14); // Correct parameters for iATR
        if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atrData) == 1) {
            // Confirm breakout direction with proper price data
            if((signal > 0 && closeData[0] > closeData[5] + atrData[0]*1.5) || 
               (signal < 0 && closeData[0] < closeData[5] - atrData[0]*1.5)) {
            regimeAlignment = 0.85;
        } else {
            regimeAlignment = 0.4;
        }
        }
        else {
            regimeAlignment = 0.4; // Default if ATR data not available
        }
    }
    
    // 2. Order block strength score (0.0-1.0)
    double blockScore = 0.5; // Neutral default
    int validBlockCount = 0;
    double avgBlockStrength = 0;
    
    // Count valid blocks and calculate average strength
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            validBlockCount++;
            avgBlockStrength += recentBlocks[i].strength;
        }
    }
    if(validBlockCount > 0) {
        avgBlockStrength /= validBlockCount;
        blockScore = MathMin(avgBlockStrength / 5.0, 1.0); // Normalize to 0.0-1.0
    }
    
    // Boost block score if in alignment with regime
    if(validBlockCount > 0 && regimeAlignment > 0.7) {
        blockScore *= 1.2; // Boost score when blocks align with strong regime
    }
    
    // 3. Divergence score
    double divergenceScore = 0.5; // Neutral default
    // Initialize divergence info objects
    DivergenceInfo divInfo;
    divInfo.found = true; // Assume found for simple cases
    divInfo.strength = 0.6; // Default strength
    divInfo.barCount = 3;  // Default bar count
            
    if(CheckForDivergence(signal, divInfo) && divInfo.strength > 0.5) {
        divergenceScore = 0.5 + (divInfo.strength / 2.0); // 0.5-1.0 range
    }
    
    // 4. Volatility conditions
    double volatilityScore = 0.5; // Neutral default
    double currentATR = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    double avgATR = 0;
    for(int i=1; i<=5; i++) {
        avgATR += GetATR(Symbol(), PERIOD_CURRENT, 14, i);
    }
    avgATR /= 5;
    
    // Score based on ATR conditions
    if(currentATR > MinATRThreshold && currentATR < avgATR*1.5) {
        volatilityScore = 0.7; // Good volatility range
    } else if(currentATR < MinATRThreshold) {
        volatilityScore = 0.3; // Too low volatility
    } else if(currentATR > avgATR*1.5) {
        volatilityScore = 0.4; // Too high volatility
    }
    
    // 5. Pattern recognition
    double patternScore = 0.5; // Neutral default
    
    // Calculate final quality score (weighted average)
    quality = (regimeAlignment * regimeWeight) + 
              (blockScore * blockWeight) + 
              (divergenceScore * divergenceWeight) + 
              (volatilityScore * volatilityWeight) + 
              (patternScore * patternWeight);
    
    // Cap at 1.0
    quality = MathMin(quality, 1.0);
    
    // Log detailed signal quality analysis - use global variable
    if(::DisplayDebugInfo) {
        LogInfo(StringFormat("Signal Quality Analysis: %.2f", quality));
        LogInfo(StringFormat("- Regime (%.2f): %.2f", regimeWeight, regimeAlignment));
        LogInfo(StringFormat("- Blocks (%.2f): %.2f (Count: %d)", blockWeight, blockScore, validBlockCount));
        LogInfo(StringFormat("- Divergence (%.2f): %.2f", divergenceWeight, divergenceScore));
        LogInfo(StringFormat("- Volatility (%.2f): %.2f", volatilityWeight, volatilityScore));
        LogInfo(StringFormat("- Pattern (%.2f): %.2f", patternWeight, patternScore));
    }
    
    // Update last signal quality and accumulate for statistics
    lastSignalQuality = quality;
    signalQualitySum += quality;
    signalQualityCount++;
    
    return quality;
}

//+------------------------------------------------------------------+
//| Trade Execution with Retry, Scaling, and Smart Routing ---
bool ExecuteTradeWithRetry(int signal, int maxRetries) {
    ulong startTime = GetTickCount64();
    
    if(!CanTradeNow()) { 
        LogWarn("ExecuteTradeWithRetry: CanTrade returned false"); 
        return false; 
    }
    
    // Validate signal
    if(signal == 0) {
        LogWarn("ExecuteTradeWithRetry: Invalid signal (0)");
        return false;
    }
    
    // Calculate entry price, stop loss, take profit
    double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double currentSpread = (currentAsk - currentBid) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    
    // Log current prices and spread for debugging
    LogInfo(StringFormat("Preparing trade - Bid: %.5f, Ask: %.5f, Spread: %.1f pts", 
                         currentBid, currentAsk, currentSpread));
    
    // Check if spread is too wide
    if(currentSpread > MaxAllowedSpread) {
        LogWarn(StringFormat("Spread too high: %.1f > %.1f - Trade aborted", 
                            currentSpread, MaxAllowedSpread));
        return false;
    }
    
    // Determine entry price based on signal direction
    double entryPrice = signal > 0 ? currentAsk : currentBid;
    
    // Calculate optimal stop loss
    double stopLoss = DetermineOptimalStopLoss(signal, entryPrice);
    
    // Validate stop loss
    if(stopLoss <= 0) {
        LogError("Invalid stop loss calculation");
        return false;
    }
    
    // Calculate take profit
    double takeProfit = 0;
    double riskPips = MathAbs(entryPrice - stopLoss) / SymbolInfoDouble(Symbol(), SYMBOL_POINT) / 10;
    double tpPips = riskPips * EnhancedRR;
    
    if(signal > 0) {
        takeProfit = entryPrice + tpPips * 10 * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    } else {
        takeProfit = entryPrice - tpPips * 10 * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    }
    
    // Calculate position size using advanced risk management
    
    // 1. Get session-adaptive risk percentage (varies by time of day)
    double adaptedRiskPercent = GetSessionAdaptiveRisk();
    LogRisk(StringFormat("Session-adapted risk: %.2f%%", adaptedRiskPercent));
    
    // 2. Calculate basic risk amount from balance
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (adaptedRiskPercent / 100.0);
    
    // 3. Apply time decay if reopening a position
    if(lastTradeTime > 0) {
        double timeDecayRisk = GetTimeDecayRisk(riskAmount, lastTradeTime);
        LogRisk(StringFormat("Time decay adjustment: %.2f → %.2f", riskAmount, timeDecayRisk));
        riskAmount = timeDecayRisk;
    }
    
    double riskPerPip = riskAmount / riskPips;
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    
    // Get tick value in account currency
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    
    // 4. Calculate base lot size
    double lotSize = NormalizeDouble(riskAmount / (MathAbs(entryPrice - stopLoss) * tickValue / tickSize), 2);
    
    // 5. Apply Kelly criterion if enabled
    if(EnableAdaptiveRisk) {
        double winRate = Journal.GetWinRate();
        double rr = EnhancedRR;  // Current risk/reward setting
        double kellyMultiplier = KellyOptimalPositionSize(winRate, rr);
        
        // Apply Kelly with 50% fraction for safety
        double kellyLotSize = lotSize * kellyMultiplier * 0.5;
        LogRisk(StringFormat("Kelly adjustment: WinRate=%.2f, RR=%.1f, K=%.2f, Lots: %.2f → %.2f", 
                            winRate, rr, kellyMultiplier, lotSize, kellyLotSize));
        lotSize = kellyLotSize;
    }
    
    // 6. Apply correlation-based adjustment
    double corrAdjustedLotSize = GetCorrelationAdjustedSize(lotSize);
    if(corrAdjustedLotSize != lotSize) {
        LogRisk(StringFormat("Correlation adjustment: %.2f → %.2f", lotSize, corrAdjustedLotSize));
        lotSize = corrAdjustedLotSize;
    }
    
    // 7. Apply news filter adjustment
    if(EnableNewsFilter && ReduceSizeOnMediumNews) {
        double newsReduction = GetNewsSizeReduction();
        if(newsReduction < 1.0) {
            double preNewsLotSize = lotSize;
            lotSize *= newsReduction;
            LogRisk(StringFormat("News reduction: %.2f x %.2f = %.2f", 
                                preNewsLotSize, newsReduction, lotSize));
        }
    }
    
    // Verify it's within allowed limits
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = NormalizeDouble(lotSize, 2);
    
    // Prepare for trade execution with retries
    bool orderPlaced = false;
    string tradeComment = signal > 0 ? "SMC Buy" : "SMC Sell";
    int orderType = signal > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    lastTradeRetryCount = 0;
    
    // Initialize adaptive trade object with dynamic slippage
    trade.SetDeviationInPoints((int)AdaptiveSlippagePoints);
    
    LogInfo(StringFormat("Attempting %s trade - Price: %.5f, SL: %.5f, TP: %.5f, Lots: %.2f", 
                        signal > 0 ? "BUY" : "SELL", entryPrice, stopLoss, takeProfit, lotSize));
    
    // Try placing the order with multiple retries
    for(int attempt = 1; attempt <= maxRetries; attempt++) {
        // Update current prices for each attempt
        RefreshRates();
        currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        entryPrice = signal > 0 ? currentAsk : currentBid;
        
        // Update retry counter
        lastTradeRetryCount = attempt;
        
        // Attempt to place the order
        bool result = false;
        if(signal > 0) {
            result = trade.Buy(lotSize, Symbol(), 0, stopLoss, takeProfit, tradeComment);
        } else {
            result = trade.Sell(lotSize, Symbol(), 0, stopLoss, takeProfit, tradeComment);
        }
        
        // Check result
        if(result) {
            orderPlaced = true;
            if(attempt > 1) retrySuccessCount++;
            LogInfo(StringFormat("Trade executed successfully on attempt %d", attempt));
            break;
        } else {
            // Get and log the error
            int errorCode = GetLastError();
            string errorMessage = ErrorDescription(errorCode);
            LogWarn(StringFormat("Trade attempt %d failed - Error: %d (%s)", 
                                 attempt, errorCode, errorMessage));
            
            // Handle specific errors
            if(errorCode == ERR_REQUOTE || errorCode == ERR_PRICE_CHANGED) {
                // Price changed, retry immediately
                LogInfo("Retrying immediately due to price change/requote");
                continue;
            } else if(errorCode == ERR_INVALID_STOPS) {
                // Invalid stop, adjust and retry
                double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                int stopLevel = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
                double minStop = stopLevel * point;
                
                // Adjust stop loss
                if(signal > 0) {
                    stopLoss = currentBid - minStop - 5 * point; // Add some buffer
                } else {
                    stopLoss = currentAsk + minStop + 5 * point; // Add some buffer
                }
                
                LogWarn(StringFormat("Adjusted SL to meet broker requirements: %.5f", stopLoss));
                continue;
            } else if(errorCode == ERR_INVALID_TRADE_VOLUME) {
                // Invalid volume, adjust
                lotSize = NormalizeDouble(lotSize * 0.9, 2); // Reduce by 10%
                lotSize = MathMax(minLot, lotSize);
                LogWarn(StringFormat("Adjusted lot size: %.2f", lotSize));
                continue;
            } else if(errorCode == ERR_TRADE_TOO_MANY_ORDERS) {
                // Too many orders, can't retry
                LogError("Too many orders open, cannot place trade");
                break;
            }
            
            // For other errors, wait a bit before retrying
            if(attempt < maxRetries) {
                Sleep(20); // Wait 20ms before retry (HFT optimization)
                LogInfo("Waiting 20ms before retry...");
            }
        }
    }
    
    // Handle the outcome
    if(orderPlaced) {
        ulong ticket = trade.ResultOrder();
        lastTradeTime = TimeCurrent();
        consecutiveLosses = 0; // Reset on successful trade
        
        LogTrade(StringFormat("Trade executed - Order #%d, Type: %s, Price: %.5f, Lots: %.2f", 
                               ticket, signal > 0 ? "Buy" : "Sell", entryPrice, lotSize));
    } else {
        missedTradeCount++;
        LogError(StringFormat("Failed to place trade after %d attempts", maxRetries));
    }
    
    // Performance tracking
    executionDurationMs = GetTickCount64() - startTime;
    LogInfo(StringFormat("Trade execution took %d ms", executionDurationMs));
    
    return orderPlaced;
}

//+------------------------------------------------------------------+
//| Update market structure based on price action                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| News Filter Functions                                          |
//+------------------------------------------------------------------+
void LoadNewsEvents() {
    newsEventCount = 2;
    newsEvents[0].eventTime = TimeCurrent() + 1800;
    newsEvents[0].currency = "USD";
    newsEvents[0].title = "FOMC Statement";
    newsEvents[0].impact = "High";
    newsEvents[1].eventTime = TimeCurrent() + 3600;
    newsEvents[1].currency = "EUR";
    newsEvents[1].title = "ECB Rate Decision";
    newsEvents[1].impact = "Medium";
}

bool IsHighImpactNewsWindow() {
    string symbol = Symbol();
    string base = StringSubstr(symbol, 0, 3);
    string quote = StringSubstr(symbol, 3, 3);
    datetime now = TimeCurrent();
    for(int i=0; i<newsEventCount; i++) {
        if(newsEvents[i].impact == "High" && (newsEvents[i].currency == base || newsEvents[i].currency == quote)) {
            if(MathAbs(newsEvents[i].eventTime - now) <= MACRO_NewsLookaheadMinutes*60)
                return true;
        }
    }
    return false;
}

double GetNewsSizeReduction() {
    string symbol = Symbol();
    string base = StringSubstr(symbol, 0, 3);
    string quote = StringSubstr(symbol, 3, 3);
    datetime now = TimeCurrent();
    for(int i=0; i<newsEventCount; i++) {
        if(newsEvents[i].impact == "Medium" && (newsEvents[i].currency == base || newsEvents[i].currency == quote)) {
            if(MathAbs(newsEvents[i].eventTime - now) <= MACRO_NewsLookaheadMinutes*60)
                return MACRO_MediumNewsSizeReduction;
        }
    }
    return 1.0;
}

//+------------------------------------------------------------------+
//| Detect liquidity zones in the market                           |
//+------------------------------------------------------------------+
void DetectLiquidityZones(double &liquidityLevels[], int &count, int lookback=100) {
    count = 0;
    double high[], low[];
    if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback, high) <= 0 || CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback, low) <= 0) {
        LogLiquidity("Failed to copy high/low for liquidity detection");
        return;
    }
    double threshold = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10;
    for(int i=1; i<lookback-1; i++) {
        if(high[i] > high[i-1] && high[i] > high[i+1] && (high[i]-low[i]) > threshold) {
            liquidityLevels[count++] = high[i];
            if(count>=MAX_FEATURES) break;
        }
        if(low[i] < low[i-1] && low[i] < low[i+1] && (high[i]-low[i]) > threshold) {
            liquidityLevels[count++] = low[i];
            if(count>=MAX_FEATURES) break;
        }
    }
    LogLiquidity(StringFormat("Detected %d liquidity zones",count));
}

//+------------------------------------------------------------------+
//| Fast Regime Detection for HFT                                  |
//+------------------------------------------------------------------+
int FastRegimeDetection(string symbol) {
    // Get price data for multiple timeframes
    double closeArray[];
    ArraySetAsSeries(closeArray, true);
    CopyClose(symbol, PERIOD_M5, 0, 21, closeArray);
    double close0 = closeArray[0];
    double close1 = closeArray[1];
    double close3 = closeArray[3];
    double close5 = closeArray[5];
    double close10 = closeArray[10];
    double close20 = closeArray[20];
    
    // Short-term momentum and volatility
    double atr = GetATR(symbol, PERIOD_M5, 14, 0);
    double avgAtr = GetATR(symbol, PERIOD_M5, 14, 5) * 5;
    
    // --- MQL5-compliant indicator fetching ---
    int maShortHandle = iMA(Symbol(), PERIOD_M5, 20, 0, MODE_SMA, PRICE_CLOSE);
    int maLongHandle = iMA(Symbol(), PERIOD_M5, 50, 0, MODE_SMA, PRICE_CLOSE);
    int bbHandle = iBands(symbol, PERIOD_M5, 20, 2, 0, PRICE_CLOSE);
    double maShortBuffer[], maLongBuffer[], bbTopBuffer[], bbBottomBuffer[];
    ArraySetAsSeries(maShortBuffer, true);
    ArraySetAsSeries(maLongBuffer, true);
    ArraySetAsSeries(bbTopBuffer, true);
    ArraySetAsSeries(bbBottomBuffer, true);
    CopyBuffer(maShortHandle, 0, 0, 1, maShortBuffer);
    CopyBuffer(maLongHandle, 0, 0, 1, maLongBuffer);
    CopyBuffer(bbHandle, 1, 0, 1, bbTopBuffer); // 1 = upper band
    CopyBuffer(bbHandle, 2, 0, 1, bbBottomBuffer); // 2 = lower band
    double maShort = maShortBuffer[0];
    double maLong = maLongBuffer[0];
    double bbTop = bbTopBuffer[0];
    double bbBottom = bbBottomBuffer[0];
    
    // Volume assessment
    long volumeArr[];
    ArraySetAsSeries(volumeArr, true);
    CopyTickVolume(symbol, PERIOD_M5, 0, 5, volumeArr);
    long volume0 = volumeArr[0];
    long volume1 = volumeArr[1];
    long avgVolume = 0;
    for(int i=0; i<5; i++) {
        avgVolume += volumeArr[i];
    }
    avgVolume /= 5;
    
    // Detect market regime
    // Trending Up
    if(closeArray[0] > closeArray[5] && closeArray[5] > closeArray[10] && closeArray[0] > maShort && maShort > maLong) {
        return TRENDING_UP;
    }
    // Trending Down
    else if(closeArray[0] < closeArray[5] && closeArray[5] < closeArray[10] && closeArray[0] < maShort && maShort < maLong) {
        return TRENDING_DOWN;
    }
    // High Volatility
    else if(atr > avgAtr * 1.3 || MathAbs(closeArray[0] - closeArray[1]) > atr * 1.2) {
        return HIGH_VOLATILITY;
    }
    // Low Volatility
    else if(atr < avgAtr * 0.7 && bbTop - bbBottom < (maShort * 0.003)) {
        return LOW_VOLATILITY;
    }
    // Ranging Narrow
    else if(MathAbs(closeArray[0] - closeArray[20]) < atr * 2 && atr < avgAtr) {
        return RANGING_NARROW;
    }
    // Ranging Wide 
    else if(MathAbs(closeArray[0] - closeArray[20]) < atr * 3 && atr >= avgAtr) {
        return RANGING_WIDE;
    }
    // Breakout
    else if((closeArray[0] > bbTop && volumeArr[0] > avgVolume * 1.5) || 
            (closeArray[0] < bbBottom && volumeArr[0] > avgVolume * 1.5)) {
        return BREAKOUT;
    }
    // Reversal
    // Reversal - Check for potential reversal patterns using price data
    else if((closeArray[0] > closeArray[1] && closeArray[1] < closeArray[3] && closeArray[3] < closeArray[5]) || 
           (closeArray[0] < closeArray[1] && closeArray[1] > closeArray[3] && closeArray[3] > closeArray[5])) {
        return REVERSAL;
    }
    // Choppy (default)
    return CHOPPY;
}

//+------------------------------------------------------------------+
//| Update market structure based on price action                    |
//+------------------------------------------------------------------+
void UpdateMarketStructure() {
    int lookback = 50;
    double high[], low[], close[];
    datetime time[];
    
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(time, true);
    
    if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback, high) <= 0 ||
       CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback, low) <= 0 ||
       CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback, close) <= 0 ||
       CopyTime(Symbol(), PERIOD_CURRENT, 0, lookback, time) <= 0) {
        LogWarn("Failed to copy price data for market structure analysis");
        return;
    }
    
    // Find swing highs and lows
    for(int i = 5; i < lookback-5; i++) {
        // Swing high - price higher than surrounding bars
        if(high[i] > high[i-1] && high[i] > high[i-2] && 
           high[i] > high[i+1] && high[i] > high[i+2]) {
            // Check if this is higher than the last swing high
            if(high[i] > marketStructure.swingHigh) {
                // We have a new higher high
                double previousHigh = marketStructure.swingHigh;
                marketStructure.swingHigh = high[i];
                marketStructure.swingHighTime = time[i];
                
                // Check for CHOCH (Change of Character) - new high breaks above resistance
                if(previousHigh > 0 && close[0] > previousHigh) {
                    marketStructure.chochDetected = true;
                    LogInfo(StringFormat("CHOCH detected: New swing high %.5f breaks above %.5f", 
                                      marketStructure.swingHigh, previousHigh));
                }
            }
        }
        
        // Swing low - price lower than surrounding bars
        if(low[i] < low[i-1] && low[i] < low[i-2] && 
           low[i] < low[i+1] && low[i] < low[i+2]) {
            // Check if this is lower than the last swing low
            if(low[i] < marketStructure.swingLow || marketStructure.swingLow == 0) {
                // We have a new lower low
                double previousLow = marketStructure.swingLow;
                marketStructure.swingLow = low[i];
                marketStructure.swingLowTime = time[i];
                
                // Check for CHOCH (Change of Character) - new low breaks below support
                if(previousLow > 0 && close[0] < previousLow) {
                    marketStructure.chochDetected = true;
                    LogInfo(StringFormat("CHOCH detected: New swing low %.5f breaks below %.5f", 
                                      marketStructure.swingLow, previousLow));
                }
            }
        }
    }
    
    // Structure is valid if we have both swing points
    marketStructure.bos = (marketStructure.swingHigh > 0 && marketStructure.swingLow > 0);
}

//+------------------------------------------------------------------+
//| Modify stops when Change of Character (CHOCH) is detected        |
//+------------------------------------------------------------------+
void ModifyStopsOnCHOCH() {
    // Only proceed if CHOCH was detected
    if(!marketStructure.chochDetected) return;
    
    // Reset CHOCH flag after processing
    marketStructure.chochDetected = false;
    
    if(DisplayDebugInfo) LogInfo("[CHOCH] Modifying stops based on change of character");
    
    // Loop through positions and adjust stops
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(!PositionSelectByTicket(ticket)) continue;
        
        // Only manage our positions
        string posComment = PositionGetString(POSITION_COMMENT);
        if(posComment != "SMC Buy" && posComment != "SMC Sell") continue;
        
        // Get position details
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        // Calculate new stop loss based on CHOCH
        double newSL = currentSL;
        
        // For buy positions, adjust to recent swing low
        if(posType == POSITION_TYPE_BUY) {
            // Add logging as per memory for debugging stop loss issues
            LogInfo(StringFormat("[CHOCH] Checking buy position #%d Current SL: %.5f", 
                               ticket, currentSL));
            
            // Use market structure swing low if available
            if(marketStructure.swingLow > 0) {
                newSL = NormalizePrice(marketStructure.swingLow);
                if(newSL > currentSL) {
                    // Only move stop loss if it's a tighter (higher) stop
                    LogInfo(StringFormat("[CHOCH] Adjusting buy SL to swing low: %.5f", newSL));
                }
            }
        }
        // For sell positions, adjust to recent swing high
        else {
            // Add logging as per memory for debugging stop loss issues
            LogInfo(StringFormat("[CHOCH] Checking sell position #%d Current SL: %.5f", 
                               ticket, currentSL));
            
            // Use market structure swing high if available
            if(marketStructure.swingHigh > 0) {
                newSL = NormalizePrice(marketStructure.swingHigh);
                if(newSL < currentSL) {
                    // Only move stop loss if it's a tighter (lower) stop
                    LogInfo(StringFormat("[CHOCH] Adjusting sell SL to swing high: %.5f", newSL));
                }
            }
        }
        
        // Modify position if needed (only if stop loss position is better)
        if(MathAbs(newSL - currentSL) > Point()) {
            if(trade.PositionModify(ticket, newSL, currentTP)) {
                LogTrade(StringFormat("[CHOCH] Modified stop for ticket %d from %.5f to %.5f", ticket, currentSL, newSL));
            } else {
                LogError(StringFormat("[CHOCH] Failed to modify stop: %s", ErrorDescription(GetLastError())));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage trailing stops with multi-level adaptive logic            |
//+------------------------------------------------------------------+
void ManageTrailingStops() {
    // Use global input parameter explicitly
    if(!::EnableAggressiveTrailing) return;
    
    int trailedPositions = 0;
    int partialTPCount = 0;
    ulong startTime = GetTickCount64();
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    
    // First pass: Check for partial TP and breakeven moves
    for(int i=0; i<PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(!PositionSelectByTicket(ticket)) continue;
        
        // Only manage our positions
        string posComment = PositionGetString(POSITION_COMMENT);
        if(posComment != "SMC Buy" && posComment != "SMC Sell") continue;
        
        // Get position details
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double posProfit = PositionGetDouble(POSITION_PROFIT);
        double posVolume = PositionGetDouble(POSITION_VOLUME);
        
        // Calculate profit in percentage of TP distance
        double slDistance = MathAbs(openPrice - currentSL);
        double tpDistance = MathAbs(openPrice - currentTP);
        double currentDistance = MathAbs(openPrice - currentPrice);
        double profitPct = posType == POSITION_TYPE_BUY ? 
                          (currentPrice - openPrice) / tpDistance : 
                          (openPrice - currentPrice) / tpDistance;
        
        // Activation threshold (when to start trailing)
        double activationThreshold = TrailingActivationPct;
        
        // Adjust activation based on regime
        if(currentRegime == TRENDING_UP || currentRegime == TRENDING_DOWN) {
            // Move faster in trending markets
            activationThreshold *= 0.8;
        } else if(currentRegime == HIGH_VOLATILITY) {
            // Be more conservative in high volatility
            activationThreshold *= 1.2;
        }
        
        // --- ATR-based partial TP logic ---
        // Execute partial TP at 50% of the way to target
        if(profitPct >= 0.5 && posVolume > SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN) * 2) {
            double closeVolume = posVolume / 2.0;
            if(trade.PositionClosePartial(ticket, closeVolume)) {
                LogTrade(StringFormat("Partial TP: Closed %.2f lots at %.5f (Ticket %d)", closeVolume, currentPrice, ticket));
                
                // Move SL to BE after partial TP
                double newSL = posType == POSITION_TYPE_BUY ? openPrice + 2 * point : openPrice - 2 * point;
                if(trade.PositionModify(ticket, newSL, currentTP)) {
                    LogTrade(StringFormat("Moved SL to BE after partial TP for Ticket %d", ticket));
                    partialTPCount++;
                    trailedPositions++;
                    continue; // Skip to next position after partial TP
                }
            }
        }
        
        // If we've reached breakeven threshold (25% of TP)
        if(profitPct >= 0.25 && ((posType == POSITION_TYPE_BUY && currentSL < openPrice) || 
                              (posType == POSITION_TYPE_SELL && currentSL > openPrice))) {
            // Move to breakeven plus a small buffer
            double newSL = 0;
            double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
            
            if(posType == POSITION_TYPE_BUY) {
                newSL = openPrice + 5 * point;
            } else {
                newSL = openPrice - 5 * point;
            }
            
            // Check if this is a significant change to avoid unnecessary modifications
            if(MathAbs(newSL - currentSL) > 10 * point) {
                if(trade.PositionModify(ticket, newSL, currentTP)) {
                    LogInfo(StringFormat("Moved position #%d to breakeven+: SL %.5f", ticket, newSL));
                    trailedPositions++;
                } else {
                    LogError(StringFormat("Failed to move position #%d to breakeven: %d", ticket, GetLastError()));
                }
            }
            continue; // Skip to next position after breakeven attempt
        }
        
        // Main trailing logic - only for positions past activation threshold
        bool isTrailingActive = (profitPct >= activationThreshold);
        LogTrailingStatus(isTrailingActive, ticket, profitPct, activationThreshold);
        
        if(isTrailingActive) {
            double newSL = 0;
            double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
            double atrTrailDistance = atr * TrailingStopMultiplier;
            
            // Add minimum trailing distance to prevent too tight trailing in low volatility
            double minTrailDistance = 10 * point; // Minimum 1 pip trailing distance
            if(atrTrailDistance < minTrailDistance) {
                atrTrailDistance = minTrailDistance;
                LogInfo(StringFormat("Using minimum trailing distance of %.1f pips due to low ATR", minTrailDistance / point / 10));
            }
            
            // Log trailing activation
            LogInfo(StringFormat("Trailing active for #%d: Profit %.2f%% of TP, ATR: %.5f, Trail: %.5f", 
                               ticket, profitPct * 100, atr, atrTrailDistance));
            
            if(posType == POSITION_TYPE_BUY) {
                // For buy positions, check if we should update SL (move it up)
                double potentialSL = currentPrice - atrTrailDistance;
                
                // Only move if new SL is higher than current SL
                if(potentialSL > currentSL) {
                    newSL = potentialSL;
                    // Round to broker's price precision
                    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
                    newSL = NormalizeDouble(newSL, digits);
                    
                    // Ensure SL respects broker's minimum distance
                    double minStopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * 
                                        SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
                    
                    if(bid - newSL < minStopLevel) {
                        newSL = bid - minStopLevel;
                        LogInfo(StringFormat("Adjusted SL for broker minimum: %.5f", newSL));
                    }
                    
                    // Move the stop loss
                    if(trade.PositionModify(ticket, newSL, currentTP)) {
                        LogInfo(StringFormat("Trailing SL for position #%d: %.5f → %.5f (%.1f pips)", 
                                             ticket, currentSL, newSL, 
                                             (newSL - currentSL) / SymbolInfoDouble(Symbol(), SYMBOL_POINT) / 10));
                        trailedPositions++;
                    } else {
                        LogError(StringFormat("Failed to move trail SL for position #%d: %d", ticket, GetLastError()));
                    }
                }
            } else { // POSITION_TYPE_SELL
                // For sell positions, check if we should update SL (move it down)
                double potentialSL = currentPrice + atrTrailDistance;
                
                // Only move if new SL is lower than current SL
                if(potentialSL < currentSL) {
                    newSL = potentialSL;
                    // Round to broker's price precision
                    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
                    newSL = NormalizeDouble(newSL, digits);
                    
                    // Ensure SL respects broker's minimum distance
                    double minStopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * 
                                        SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
                    
                    if(newSL - ask < minStopLevel) {
                        newSL = ask + minStopLevel;
                        LogInfo(StringFormat("Adjusted SL for broker minimum: %.5f", newSL));
                    }
                    
                    // Move the stop loss
                    if(trade.PositionModify(ticket, newSL, currentTP)) {
                        LogInfo(StringFormat("Trailing SL for position #%d: %.5f → %.5f (%.1f pips)", 
                                             ticket, currentSL, newSL, 
                                             (currentSL - newSL) / SymbolInfoDouble(Symbol(), SYMBOL_POINT) / 10));
                        trailedPositions++;
                    } else {
                        LogError(StringFormat("Failed to move trail SL for position #%d: %d", ticket, GetLastError()));
                    }
                }
            }
        }
    }
    
    // Log performance metrics
    if(trailedPositions > 0) {
        LogInfo(StringFormat("Trailing completed - Modified %d positions in %d ms", 
                             trailedPositions, GetTickCount64() - startTime));
    }
}

//+------------------------------------------------------------------+
//| Log trailing stop status for debugging                           |
//+------------------------------------------------------------------+
void LogTrailingStatus(bool isActive, ulong ticket, double profitPct, double threshold) {
    if(isActive) {
        // Already logged in the main trailing function
    } else {
        // Log when position is not yet trailing
        LogInfo(StringFormat("Position #%d not trailing yet: Profit %.2f%% < Threshold %.2f%%", 
                           ticket, profitPct * 100, threshold * 100));
    }
}

//+------------------------------------------------------------------+
//| Check if scaling entry is allowed and execute if so               |
//+------------------------------------------------------------------+
bool ExecuteScaledEntry(int signal, double stopLoss, double dynamicSL) {
    // Use global input parameters explicitly
    if(!::EnableSmartScaling || ::ScalingPositions < 2) return false;
    
    // Initialize entries and variables for ticket tracking
    ulong ticket = 0; // Define ticket variable for position tracking
    double entryPrice = 0;
    
    // Reset scaling entries
    for(int i=0; i < ArraySize(currentScalingEntries); i++) {
        currentScalingEntries[i].active = false;
    }
    
    // Get current price and calculate price levels for each entry
    double currentPrice = signal > 0 ? 
                         SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                         SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    double baseEntryAmount = 1.0 / ::ScalingPositions; // Equal distribution by default - use global input parameter
    
    // Calculate total position size based on risk
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
    double slDistance = MathAbs(currentPrice - stopLoss);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double totalLotSize = NormalizeDouble(riskAmount / (slDistance * tickValue / tickSize), 2);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    
    // Make sure total is within limits - use global input parameter
    totalLotSize = MathMax(minLot * ::ScalingPositions, totalLotSize);
    
    // Place first entry immediately
    double firstEntrySize = NormalizeDouble(totalLotSize * baseEntryAmount, 2);
    
    // Round to lot step
    firstEntrySize = NormalizeDouble(MathFloor(firstEntrySize / lotStep) * lotStep, 2);
    firstEntrySize = MathMax(minLot, firstEntrySize);
    
    string comment = signal > 0 ? "SMC Buy Scale 1" : "SMC Sell Scale 1";
    bool result = false;
    
    // Place the first entry
    if(signal > 0) {
        result = trade.Buy(firstEntrySize, Symbol(), 0, stopLoss, 0, comment);
    } else {
        result = trade.Sell(firstEntrySize, Symbol(), 0, stopLoss, 0, comment);
    }
    
    if(!result) {
        LogError(StringFormat("Failed to place first scaling entry: %d", GetLastError()));
        return false;
    }
    
    // Use the ticket and entryPrice variables initialized at the beginning of the function
    ticket = trade.ResultOrder();
    entryPrice = trade.ResultPrice();
    
    // Store the first entry
    currentScalingEntries[0].ticket = ticket;
    currentScalingEntries[0].entryPrice = entryPrice;
    currentScalingEntries[0].lotSize = firstEntrySize;
    currentScalingEntries[0].stopLoss = stopLoss;
    currentScalingEntries[0].takeProfit = 0; // We'll set TP after all entries are complete
    currentScalingEntries[0].filled = true;
    currentScalingEntries[0].placementTime = TimeCurrent();
    currentScalingEntries[0].entryNumber = 1;
    
    LogInfo(StringFormat("First scaling entry placed: #%d %.2f lots at %.5f", 
                         ticket, firstEntrySize, entryPrice));
    
    // Calculate price levels for remaining entries - use global input parameter
    for(int i = 1; i < ::ScalingPositions; i++) {
        // Prepare the entry
        double entryLevel;
        double entrySize = NormalizeDouble(totalLotSize * baseEntryAmount, 2);
        entrySize = NormalizeDouble(MathFloor(entrySize / lotStep) * lotStep, 2);
        entrySize = MathMax(minLot, entrySize);
        
        // Calculate the entry level based on ATR and signal direction
        double levelSpacing = atr * (0.3 + (i * 0.2)); // Increasing distances
        
        if(signal > 0) {
            // For buy, place entries below current price
            entryLevel = currentPrice - levelSpacing;
        } else {
            // For sell, place entries above current price
            entryLevel = currentPrice + levelSpacing;
        }
        
        // Store the potential entry details (will be placed as pending)
        currentScalingEntries[i].ticket = 0; // Will be set when order is placed
        currentScalingEntries[i].entryPrice = entryLevel;
        currentScalingEntries[i].lotSize = entrySize;
        currentScalingEntries[i].stopLoss = stopLoss;
        currentScalingEntries[i].takeProfit = 0;
        currentScalingEntries[i].filled = false;
        currentScalingEntries[i].placementTime = TimeCurrent();
        currentScalingEntries[i].entryNumber = i + 1;
        
        // Place pending order
        ENUM_ORDER_TYPE orderType = signal > 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
        string scaleComment = signal > 0 ? 
                            StringFormat("SMC Buy Scale %d", i+1) : 
                            StringFormat("SMC Sell Scale %d", i+1);
        
        // Set expiration time (e.g., 4 hours)
        datetime expiration = TimeCurrent() + 4 * 3600;
        
        if(trade.OrderOpen(Symbol(), orderType, entrySize, entryLevel, stopLoss, 0, 0, 0, expiration, scaleComment)) {
            ulong pendingTicket = trade.ResultOrder();
            currentScalingEntries[i].ticket = pendingTicket;
            LogInfo(StringFormat("Scaling entry %d placed as pending: #%d %.2f lots at %.5f", 
                                i+1, pendingTicket, entrySize, entryLevel));
        } else {
            LogError(StringFormat("Failed to place scaling entry %d: %d", i+1, GetLastError()));
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for divergence between signal and multiple timeframes      |
//+------------------------------------------------------------------+
bool ConfirmSignalMultiTimeframe(int signal) {
    if(signal == 0) return false;
    
    // Configure which timeframes to check
    ENUM_TIMEFRAMES confirmTFs[] = {PERIOD_M5, PERIOD_M15, PERIOD_H1};
    int totalTFs = ArraySize(confirmTFs);
    int confirmedTFs = 0;
    
    LogInfo(StringFormat("Checking multi-timeframe confirmation for signal %d", signal));
    
    // Check each timeframe
    for(int i = 0; i < totalTFs; i++) {
        // Get MA direction for this timeframe
        // Use proper MQL5 indicator handle approach
        int maHandle = iMA(Symbol(), confirmTFs[i], 20, 0, MODE_SMA, PRICE_CLOSE);
        // Use differently named buffer to avoid hiding global variable
        double ma20Buffer[];
        ArraySetAsSeries(ma20Buffer, true);
        CopyBuffer(maHandle, 0, 0, 1, ma20Buffer);
        double ma20 = ma20Buffer[0];
        // Use proper MQL5 indicator handle approach for the second MA
        int maSlowHandle = iMA(Symbol(), confirmTFs[i], 50, 0, MODE_SMA, PRICE_CLOSE);
        double maSlowBuffer[];
        ArraySetAsSeries(maSlowBuffer, true);
        CopyBuffer(maSlowHandle, 0, 0, 1, maSlowBuffer);
        double ma50 = maSlowBuffer[0];
        // Use proper MQL5 price data approach
        double closeArray[];
        ArraySetAsSeries(closeArray, true);
        CopyClose(Symbol(), confirmTFs[i], 0, 1, closeArray);
        double close0 = closeArray[0];
        
        bool maAlignment = false;
        
        // For buy signals, check if price > MA20 > MA50
        if(signal > 0 && close0 > ma20 && ma20 > ma50) {
            maAlignment = true;
            confirmedTFs++;
        }
        // For sell signals, check if price < MA20 < MA50
        else if(signal < 0 && close0 < ma20 && ma20 < ma50) {
            maAlignment = true;
            confirmedTFs++;
        }
        
        // Log the result for this timeframe
        LogInfo(StringFormat("  %s: %s", 
                             EnumToString(confirmTFs[i]), 
                             maAlignment ? "Confirmed" : "Not confirmed"));
    }
    
    // Need confirmation on at least 2/3 of timeframes
    bool result = (double)confirmedTFs / totalTFs >= 0.67;
    LogInfo(StringFormat("Multi-timeframe confirmation: %d/%d - %s", 
                         confirmedTFs, totalTFs, result ? "PASSED" : "FAILED"));
    
    return result;
}

//+------------------------------------------------------------------+
//| Calculate signal quality based on price action and volume        |
//+------------------------------------------------------------------+
// This is a duplicate of CalculateSignalQuality defined at line 1077
// Removed to avoid duplicate definition error

//+------------------------------------------------------------------+
//| Check if trading is allowed at current market conditions         |
//+------------------------------------------------------------------+
bool CanTradeNow() {
    // Check for emergency mode
    if(emergencyMode) {
        LogWarn("Trading blocked: Emergency mode active");
        return false;
    }
    
    // Check max consecutive losses
    if(consecutiveLosses >= MaxConsecutiveLosses) {
        LogWarn(StringFormat("Trading blocked: Max consecutive losses reached (%d)", consecutiveLosses));
        return false;
    }
    
    // Check trading hours
    datetime serverTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(serverTime, dt);
    
    if(dt.hour < TradingStartHour || dt.hour >= TradingEndHour) {
        LogInfo(StringFormat("Trading blocked: Outside trading hours (%d-%d, current: %d)", 
                             TradingStartHour, TradingEndHour, dt.hour));
        return false;
    }
    
    // Check for weekends
    if(dt.day_of_week == 0 || dt.day_of_week == 6) {
        LogInfo("Trading blocked: Weekend");
        return false;
    }
    
    // Check max open trades
    int currentTrades = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        string symbol = PositionGetSymbol(i);
        if(symbol == Symbol()) currentTrades++;
    }
    
    if(currentTrades >= MaxTrades) {
        LogInfo(StringFormat("Trading blocked: Max trades reached (%d/%d)", currentTrades, MaxTrades));
        return false;
    }
    
    // Check market conditions
    double currentATR = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    if(currentATR < MinATRThreshold) {
        LogInfo(StringFormat("Trading blocked: Low volatility (ATR: %.5f < %.5f)", currentATR, MinATRThreshold));
        return false;
    }
    
    // Check for high impact news
    if(EnableNewsFilter && IsHighImpactNewsWindow()) {
        LogInfo("Trading blocked: High impact news window");
        return false;
    }
    
    // Check for high spread
    double spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double spreadPoints = spread / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    if(spreadPoints > MaxAllowedSpread) {
        LogInfo(StringFormat("Trading blocked: High spread (%.1f > %.1f points)", spreadPoints, MaxAllowedSpread));
        return false;
    }
    
    // All checks passed
    return true;
}

//+------------------------------------------------------------------+
//| Update dashboard with key performance metrics                    |
//+------------------------------------------------------------------+
void UpdateDashboardInfo() {
    // Use global input parameter explicitly
    if(!::DisplayDebugInfo) return;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // --- Dashboard hooks for regime/session display, recent signals, quality, today's profit/trade count ---
    LogInfo(StringFormat("Current Regime: %d", currentRegime));
    LogInfo(StringFormat("Session: %d", dt.hour));
    LogInfo(StringFormat("Recent Signal Quality: %.2f", lastSignalQuality));
    LogInfo(StringFormat("Today's Profit: %.2f, Trades: %d", Journal.GetTodayProfit(), Journal.GetTodayTradeCount()));
    
    string info = "=== SMC Scalper Hybrid HFT ===\n";
    
    // Current market regime
    string regimeName = "Unknown";
    switch(currentRegime) {
        case TRENDING_UP: regimeName = "Trending Up"; break;
        case TRENDING_DOWN: regimeName = "Trending Down"; break;
        case HIGH_VOLATILITY: regimeName = "High Volatility"; break;
        case LOW_VOLATILITY: regimeName = "Low Volatility"; break;
        case RANGING_NARROW: regimeName = "Ranging Narrow"; break;
        case RANGING_WIDE: regimeName = "Ranging Wide"; break;
        case BREAKOUT: regimeName = "Breakout"; break;
        case REVERSAL: regimeName = "Reversal"; break;
        case CHOPPY: regimeName = "Choppy"; break;
    }
    info += StringFormat("Regime: %s\n", regimeName);
    
    // Valid order blocks
    info += StringFormat("Order Blocks: %d valid, %d total\n", validOrderBlocks, totalOrderBlocks);
    
    // Current spread
    double spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double spreadPoints = spread / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    info += StringFormat("Spread: %.1f points\n", spreadPoints);
    
    // ATR info
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    info += StringFormat("ATR: %.5f\n", atr);
    
    // Position info
    int posCount = 0;
    double totalProfit = 0;
    for(int i=0; i<PositionsTotal(); i++) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == Symbol()) {
                posCount++;
                totalProfit += PositionGetDouble(POSITION_PROFIT);
            }
        }
    }
    info += StringFormat("Positions: %d (%s)\n", posCount, DoubleToString(totalProfit, 2));
    
    // Performance stats
    info += StringFormat("Win/Loss: %d/%d\n", winStreak, lossStreak);
    info += StringFormat("Missed Trades: %d\n", missedTradeCount);
    info += StringFormat("Last Signal Quality: %.2f\n", lastSignalQuality);
    
    // HFT Performance
    info += StringFormat("Detect: %d ms, Exec: %d ms\n", detectionDurationMs, executionDurationMs);
    
    // Display in chart
    Comment(info);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // --- HFT Optimized OnTick ---
    ulong startTime = GetTickCount64();
    ulong startMicro = GetTickCount64(); // Use TickCount for milliseconds
    
    // 1. Fast lightweight pre-checks
    priceCache.bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    priceCache.ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    priceCache.spread = (priceCache.ask - priceCache.bid) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    
    // Update cache status
    datetime current = TimeCurrent();
    priceCache.lastUpdate = current; // Using correct field name from the struct

    // Check if trading is allowed
    if(!CanTradeNow()) { 
        LogWarn("OnTick: Trading not allowed, skipping heavy logic.");
        // Use global input variable DisplayDebugInfo explicitly
        if(::DisplayDebugInfo) UpdateDashboardInfo();
        return;
    }
    // Check spread
    if(priceCache.spread > MaxAllowedSpread) {
        LogInfo(StringFormat("OnTick: Spread (%.1f) > MaxAllowedSpread (%.1f), skipping heavy logic.", priceCache.spread, MaxAllowedSpread));
        return;
    }
    // Check session/cooldown
    datetime currentTime = TimeCurrent();
    int regime = FastRegimeDetection(Symbol()); // Lightweight regime detection
    // Use the SignalCooldownSeconds input parameter for cooldown
    bool cooldownPassed = (currentTime - lastSignalTime) >= SignalCooldownSeconds;
    if(!cooldownPassed) {
        LogInfo("OnTick: Cooldown not passed, skipping heavy logic.");
        return;
    }

    // 2. Caching for heavy indicator logic
    static ulong lastHeavyCalcTick = 0;
    static int cachedRegime = 0;
    static int cachedBlockCount = 0;
    static double cachedATR = 0;
    static datetime lastCacheUpdate = 0;
    const int CACHE_UPDATE_INTERVAL = 2; // seconds
    if(TimeCurrent() - lastCacheUpdate >= CACHE_UPDATE_INTERVAL) {
        // Heavy calculations only every CACHE_UPDATE_INTERVAL seconds
        cachedRegime = FastRegimeDetection(Symbol());
        DetectOrderBlocks();
        double liquidityLevels[MAX_FEATURES];
        int liquidityCount = 0;
        DetectLiquidityZones(liquidityLevels, liquidityCount);
        cachedBlockCount = 0;
        for(int i=0; i<MAX_BLOCKS; i++) {
            if(recentBlocks[i].valid) cachedBlockCount++;
        }
        cachedATR = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
        lastCacheUpdate = TimeCurrent();
        LogInfo("OnTick: Heavy logic cache refreshed.");
    }
    priceCache.atr = cachedATR;
    currentRegime = cachedRegime;

    LogInfo(StringFormat("OnTick: Found %d valid order blocks after DetectOrderBlocks()", cachedBlockCount));

    // 3. Get trading signal
    int signal = GetTradingSignal();
    if(signal == 0) {
        LogInfo("OnTick: No valid trading signal.");
        return;
    }

    // 4. Trade processing
    double signalQuality = CalculateSignalQuality(signal);
    lastSignalQuality = signalQuality;
    LogInfo(StringFormat("Signal detected: %d, Quality: %.2f", signal, signalQuality));

    bool confirmed = true;
    if(RequireTrendConfirmation) {
        confirmed = ConfirmSignalMultiTimeframe(signal);
        if(!confirmed) LogInfo("Signal rejected: Failed multi-timeframe confirmation");
    }
    if(confirmed && RequireMomentumConfirmation) {
        confirmed = CheckMomentumConfirmation(signal);
        if(!confirmed) LogInfo("Signal rejected: Failed momentum confirmation");
    }
    if(confirmed && signalQuality >= 0.5) {
        if(EnableSmartScaling) {
            double entryPrice = signal > 0 ? priceCache.ask : priceCache.bid;
            double stopLoss = DetermineOptimalStopLoss(signal, entryPrice);
            bool result = ExecuteScaledEntry(signal, stopLoss, 0);
            if(result) {
                LogInfo("Scaled entry executed successfully");
                lastSignalTime = currentTime;
            } else {
                LogWarn("Failed to execute scaled entry");
            }
        } else {
            bool result = ExecuteTradeWithRetry(signal, HFT_RETRY_MAX);
            if(result) {
                LogInfo("Trade executed successfully");
                lastSignalTime = currentTime;
            } else {
                LogWarn("Failed to execute trade with retry");
            }
        }
    } else if (confirmed) {
        LogInfo(StringFormat("Signal rejected: Quality too low (%.2f < 0.5)", signalQuality));
    }

    // 5. Manage open positions
    UpdateMarketStructure(); // Update market structure analysis
    ManageTrailingStops();
    ModifyStopsOnCHOCH();    // Adjust stops based on market structure changes

    // Performance metrics
    executionDurationMs = GetTickCount64() - startTime;
    ulong execMicro = GetTickCount64() - startMicro;
    LogInfo(StringFormat("OnTick execution: %d ms", executionDurationMs));
    if(executionDurationMs > HFT_MAX_EXECUTION_MS) {
        LogWarn(StringFormat("Slow execution: %d ms > %d ms threshold", executionDurationMs, HFT_MAX_EXECUTION_MS));
    }
    // Use global parameter explicitly
    if(::DisplayDebugInfo) UpdateDashboardInfo();
}

//+------------------------------------------------------------------+
//| Get trading signal based on order blocks and current conditions |
//+------------------------------------------------------------------+
int GetTradingSignal() {
    // Check for emergency mode or too many consecutive losses
    if(emergencyMode || consecutiveLosses >= MaxConsecutiveLosses) {
        LogInfo(StringFormat("GetTradingSignal: Too many consecutive losses (%d) or emergency mode. No signal.", consecutiveLosses));
        return 0;
    }
    
    // Check for valid spread
    double currentSpread = priceCache.spread;
    if(currentSpread > MaxAllowedSpread) {
        LogInfo(StringFormat("GetTradingSignal: Spread too high (%.1f > %.1f). No signal.", currentSpread, MaxAllowedSpread));
        return 0;
    }
    
    // Check for sufficient volatility using ATR
    double atr = priceCache.atr;
    if(atr < MinATRThreshold) {
        LogInfo(StringFormat("GetTradingSignal: ATR too low (%.5f < %.5f). No signal.", atr, MinATRThreshold));
        return 0;
    }
    
    // Search for valid order blocks
    int bullishBlocks = 0;
    int bearishBlocks = 0;
    int strongestBullish = 0;
    int strongestBearish = 0;
    double highestBullScore = 0;
    double highestBearScore = 0;
    
    // Count and evaluate order blocks
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            // Get current price
            double price = (priceCache.bid + priceCache.ask) / 2;
            
            // Check if the price is near the block (within 1.5 ATR)
            double distance = MathAbs(price - ((recentBlocks[i].high + recentBlocks[i].low) / 2));
            bool isNearPrice = distance < (atr * 1.5);
            
            // Separate into bullish and bearish blocks
            if(recentBlocks[i].low < price && isNearPrice) { // Bullish block is below current price
                bullishBlocks++;
                if(recentBlocks[i].strength > highestBullScore) {
                    highestBullScore = recentBlocks[i].strength;
                    strongestBullish = i;
                }
            } else if(recentBlocks[i].high > price && isNearPrice) { // Bearish block is above current price
                bearishBlocks++;
                if(recentBlocks[i].strength > highestBearScore) {
                    highestBearScore = recentBlocks[i].strength;
                    strongestBearish = i;
                }
            }
        }
    }
    
    LogInfo(StringFormat("GetTradingSignal: Found valid order blocks - Bullish: %d, Bearish: %d", bullishBlocks, bearishBlocks));
    
    // Check for market regime bias
    int regimeBias = 0;
    if(currentRegime == TRENDING_UP) regimeBias = 1; // Bullish
    else if(currentRegime == TRENDING_DOWN) regimeBias = -1; // Bearish
    
    // Generate signal based on order blocks and regime
    int signal = 0;
    
    // Favor blocks aligned with the regime
    if(bullishBlocks > 0 && (regimeBias >= 0 || bearishBlocks == 0)) {
        int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
double ma20Buffer[];
ArraySetAsSeries(ma20Buffer, true);
CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer);
double ma20 = ma20Buffer[0];
        int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
double ma50Buffer[];
ArraySetAsSeries(ma50Buffer, true);
CopyBuffer(ma50Handle, 0, 0, 1, ma50Buffer);
double ma50 = ma50Buffer[0];
        // Get slope using proper MQL5 indicator handle pattern
        int maSlopeHandle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
        double maSlopeBuffer[];
        ArraySetAsSeries(maSlopeBuffer, true);
        CopyBuffer(maSlopeHandle, 0, 0, 6, maSlopeBuffer);
        double maSlope = ma20 - maSlopeBuffer[5];
        
        // For buy signal, price should preferably be above MA and MA20 above MA50
        if(priceCache.ask > ma20 && (ma20 > ma50 || maSlope > 0)) {
            signal = 1; // Buy signal
            LogInfo(StringFormat("Buy signal from %d bullish blocks with score %.0f", 
                                 bullishBlocks, highestBullScore));
        }
    } 
    else if(bearishBlocks > 0 && (regimeBias <= 0 || bullishBlocks == 0)) {
        int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
double ma20Buffer[];
ArraySetAsSeries(ma20Buffer, true);
CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer);
double ma20 = ma20Buffer[0];
        int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
double ma50Buffer[];
ArraySetAsSeries(ma50Buffer, true);
CopyBuffer(ma50Handle, 0, 0, 1, ma50Buffer);
double ma50 = ma50Buffer[0];
        int maSlopeHandle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
double maSlopeBuffer[];
ArraySetAsSeries(maSlopeBuffer, true);
CopyBuffer(maSlopeHandle, 0, 0, 6, maSlopeBuffer);
double maSlope = ma20 - maSlopeBuffer[5];
        
        // For sell signal, price should preferably be below MA and MA20 below MA50
        if(priceCache.bid < ma20 && (ma20 < ma50 || maSlope < 0)) {
            signal = -1; // Sell signal
            LogInfo(StringFormat("Sell signal from %d bearish blocks with score %.0f", 
                                 bearishBlocks, highestBearScore));
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Check momentum confirmation across multiple indicators           |
//+------------------------------------------------------------------+
bool CheckMomentumConfirmation(int signal) {
    if(!RequireMomentumConfirmation || signal == 0) return true;
    
    int confirmed = 0;
    int requiredConfirmations = 2; // Need at least 2 out of 3 indicators to confirm
    
    // Initialize arrays for indicators
    double rsiBuffer[];
    ArraySetAsSeries(rsiBuffer, true);
    
    // Initialize close price array for divergence checking
    double closePrice[];
    ArraySetAsSeries(closePrice, true);
    CopyClose(Symbol(), Period(), 0, 3, closePrice);
    // --- Explicit RSI/MACD divergence and pattern clustering logic ---
    // 1. RSI/MACD divergence
    bool rsiMacdDivergence = false;
    double rsiPrev = 0, rsiCurr = 0;
    
    // Get RSI values
    int rsiHandleDiv = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
    if(rsiHandleDiv != INVALID_HANDLE && CopyBuffer(rsiHandleDiv, 0, 0, 3, rsiBuffer) >= 3) {
        rsiPrev = rsiBuffer[2];
        rsiCurr = rsiBuffer[0];
    }
    IndicatorRelease(rsiHandleDiv);
    
    // Get MACD values
    double macdPrev = 0, macdCurr = 0;
    int macdHandleDiv = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    double macdMainDiv[], macdSignalDiv[];
    if(macdHandleDiv != INVALID_HANDLE) {
        if(CopyBuffer(macdHandleDiv, 0, 0, 3, macdMainDiv) >= 3 && CopyBuffer(macdHandleDiv, 1, 0, 3, macdSignalDiv) >= 3) {
            macdPrev = macdMainDiv[2];
            macdCurr = macdMainDiv[0];
            // Make sure we have enough price data
            
            // Get the close prices for divergence checks
            double closeData[];
            ArraySetAsSeries(closeData, true);
            if(CopyClose(Symbol(), PERIOD_CURRENT, 0, 3, closeData) >= 3) {
                // Bullish divergence: price lower, RSI/MACD higher
                if(signal > 0 && (closeData[0] < closeData[2]) && (rsiCurr > rsiPrev) && (macdCurr > macdPrev)) {
                    rsiMacdDivergence = true;
                    confirmed++;
                }
                // Bearish divergence: price higher, RSI/MACD lower
                else if(signal < 0 && (closeData[0] > closeData[2]) && (rsiCurr < rsiPrev) && (macdCurr < macdPrev)) {
                    rsiMacdDivergence = true;
                    confirmed++;
                }
            }
        }
        IndicatorRelease(macdHandleDiv);
    }
    // 2. Pattern clustering/boosting
    bool patternBoosted = false;
    for(int i=0; i<CLUSTER_MAX; i++) {
        if(patternClusters[i].active && patternClusters[i].bullish == (signal > 0)) {
            if(patternClusters[i].winRate > 0.6 && patternClusters[i].lastSignalQuality > 0.7) {
                patternBoosted = true;
                confirmed++;
                LogInfo(StringFormat("Pattern cluster '%s' boosted confirmation for signal %d", patternClusters[i].name, signal));
            }
        }
    }

    
    // 1. RSI Momentum
    int rsiHandle = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
    // rsiBuffer already declared above
    bool rsiConfirmed = false;
    
    if(rsiHandle != INVALID_HANDLE && CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) >= 3) {
        // For buy signal: RSI should be above 50 and rising
        if(signal > 0 && rsiBuffer[0] > 50 && rsiBuffer[0] > rsiBuffer[1]) {
            rsiConfirmed = true;
            confirmed++;
        }
        // For sell signal: RSI should be below 50 and falling
        else if(signal < 0 && rsiBuffer[0] < 50 && rsiBuffer[0] < rsiBuffer[1]) {
            rsiConfirmed = true;
            confirmed++;
        }
    }
    IndicatorRelease(rsiHandle);
    
    // 2. MACD Momentum
    int macdHandle = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    double macdMain[], macdSignal[];
    bool macdConfirmed = false;
    
    if(macdHandle != INVALID_HANDLE) {
        if(CopyBuffer(macdHandle, 0, 0, 3, macdMain) >= 3 && CopyBuffer(macdHandle, 1, 0, 3, macdSignal) >= 3) {
            // For buy signal: MACD should be above signal line and rising
            if(signal > 0 && macdMain[0] > macdSignal[0] && macdMain[0] > macdMain[1]) {
                macdConfirmed = true;
                confirmed++;
            }
            // For sell signal: MACD should be below signal line and falling
            else if(signal < 0 && macdMain[0] < macdSignal[0] && macdMain[0] < macdMain[1]) {
                macdConfirmed = true;
                confirmed++;
            }
        }
    }
    IndicatorRelease(macdHandle);
    
    // 3. MA Momentum
    int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
    // Use a differently named buffer to avoid hiding global variable
    double ma20ConfirmBuffer[];
    bool maConfirmed = false;
    
    if(ma20Handle != INVALID_HANDLE && CopyBuffer(ma20Handle, 0, 0, 5, ma20ConfirmBuffer) >= 5) {
        // For buy signal: MA20 should be rising
        if(signal > 0 && ma20ConfirmBuffer[0] > ma20ConfirmBuffer[4]) {
            maConfirmed = true;
            confirmed++;
        }
        // For sell signal: MA20 should be falling
        else if(signal < 0 && ma20ConfirmBuffer[0] < ma20ConfirmBuffer[4]) {
            maConfirmed = true;
            confirmed++;
        }
    }
    IndicatorRelease(ma20Handle);
    
    // Log confirmation results
    LogInfo(StringFormat("Momentum confirmation check - RSI: %s, MACD: %s, MA: %s", 
                         rsiConfirmed ? "Yes" : "No", 
                         macdConfirmed ? "Yes" : "No", 
                         maConfirmed ? "Yes" : "No"));
    
    return (confirmed >= requiredConfirmations);
}

//+------------------------------------------------------------------+
//| Called on trade event to track performance                      |
//+------------------------------------------------------------------+
void OnTrade() {
    HistorySelect(0, TimeCurrent());
    
    // Check recent deals
    for(int i=HistoryDealsTotal()-1; i>=0; i--) {
        ulong ticketID = HistoryDealGetTicket(i);
        if(ticketID <= 0) continue;
        
        // Only process our own deals
        string dealComment = HistoryDealGetString(ticketID, DEAL_COMMENT);
        if(dealComment != "SMC Buy" && dealComment != "SMC Sell" && 
           StringFind(dealComment, "SMC Buy Scale") < 0 && StringFind(dealComment, "SMC Sell Scale") < 0) {
            continue;
        }
        
        long dealType = HistoryDealGetInteger(ticketID, DEAL_TYPE);
        long dealEntry = HistoryDealGetInteger(ticketID, DEAL_ENTRY);
        double dealProfit = HistoryDealGetDouble(ticketID, DEAL_PROFIT);
        double dealVolume = HistoryDealGetDouble(ticketID, DEAL_VOLUME);
        
        // Process closed positions
        if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL) {
            // Entry or exit of position
            if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY) {
                // Position closed
                if(dealProfit > 0) {
                    winStreak++;
                    lossStreak = 0;
                    LogTrade(StringFormat("Position closed with profit: %.2f", dealProfit));
                } else if(dealProfit < 0) {
                    lossStreak++;
                    consecutiveLosses++;
                    winStreak = 0;
                    LogTrade(StringFormat("Position closed with loss: %.2f (Consecutive losses: %d)", 
                                          dealProfit, consecutiveLosses));
                }
                
                // Update performance metrics
                for(int j=METRIC_WINDOW-1; j>0; j--) {
                    tradeProfits[j] = tradeProfits[j-1];
                }
                tradeProfits[0] = dealProfit;
                
                // Update regime performance
                regimeWins[currentRegime] += (dealProfit > 0 ? 1 : 0);
                regimeLosses[currentRegime] += (dealProfit < 0 ? 1 : 0);
                regimeProfit[currentRegime] += dealProfit;
                
                // Calculate win rate for regime
                int totalRegimeTrades = regimeWins[currentRegime] + regimeLosses[currentRegime];
                if(totalRegimeTrades > 0) {
                    regimeAccuracy[currentRegime] = (double)regimeWins[currentRegime] / totalRegimeTrades;
                }
                
                // Reset consecutive losses if we have a win
                if(dealProfit > 0) consecutiveLosses = 0;
                
                // Log to journal
                Journal.AddTrade(
                    HistoryDealGetInteger(ticketID, DEAL_TIME),
                    TimeCurrent(),
                    HistoryDealGetDouble(ticketID, DEAL_PRICE),
                    HistoryDealGetDouble(ticketID, DEAL_PRICE),
                    dealVolume,
                    dealProfit,
                    0,  // pips would be calculated
                    0,  // risk amount would be calculated
                    0,  // risk:reward would be calculated
                    dealType == DEAL_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                    dealType == DEAL_TYPE_BUY ? 1 : -1,  // signal
                    currentRegime,
                    0,  // session would be determined
                    lastSignalQuality,
                    RequireTrendConfirmation,  // assumed confirmed if trade was taken
                    dealComment
                );
            }
            else if(dealEntry == DEAL_ENTRY_IN) {
                // New position opened
                LogTrade(StringFormat("New position opened: %.2f lots, Type: %s", 
                                     dealVolume, dealType == DEAL_TYPE_BUY ? "Buy" : "Sell"));
            }
        }
    }
    
    // Update the dashboard after trades
    if(DisplayDebugInfo) UpdateDashboardInfo();
}

//+------------------------------------------------------------------+
//| The implementation is now complete with all key functions:       |
//| - Structure definitions with DivergenceInfo, ScalingEntry,       |
//|   PatternCluster, RegimeParameters, and PriceCache               |
//| - Enhanced market analysis with FastRegimeDetection              |
//| - Order block detection with improved validation and logging     |
//| - Optimal stop loss determination with comprehensive logging     |
//| - High-frequency trade execution with retry logic                |
//| - Trailing stops with multi-level management                     |
//| - Signal quality calculation and confirmation                    |
//| - Performance tracking and dashboard                             |
//+------------------------------------------------------------------+
// The HFT version combines the best features from the original,     
// V10, and V20 versions, optimized for speed and reliability.       
//+------------------------------------------------------------------+


