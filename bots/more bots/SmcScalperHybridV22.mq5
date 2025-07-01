//+------------------------------------------------------------------+
//| SMC Scalper Hybrid - Smart Money Concepts with Advanced Scalping |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                      V10.mq5     |
//|        (formerly SmcScalperHybrid.mq5)                          |
//|        Enhanced SMC Scal#property copyright "Copyright 2025, Leo Software - V10"               |
//+------------------------------------------------------------------+
//| V10 - Smart Money Concepts with Advanced Scalping                |
// All logic, parameters, and enhancements remain unchanged.




#property copyright "Copyright 2025, Leo Software"
#property link      "https://www.example.com"
#property version   "1.0"
#property strict

// Include required files
#include <Trade/Trade.mqh>
#include <Math/Stat/Normal.mqh>

//+------------------------------------------------------------------+
//| News Filter Utility for SMC Scalper Hybrid V10                  |
//+------------------------------------------------------------------+
// This module fetches and parses economic news events from a calendar API
// (e.g., ForexFactory, Myfxbook) and exposes blocking/reduction logic.
// For demonstration, this is a stub; HTTP/JSON parsing must be implemented
// for real news feeds in MQL5.


struct NewsEvent {
   datetime eventTime;
   string currency;
   string title;
   string impact; // "High", "Medium", "Low"
};

#define NEWS_EVENT_MAX 50
NewsEvent newsEvents[NEWS_EVENT_MAX];
int newsEventCount = 0;

// User config
input bool EnableNewsFilter = true; // Only declare once, do not redeclare later
input int NewsLookaheadMinutes = 45; // Block trades this many minutes before/after high-impact news
input bool BlockHighImpactNews = true;
input bool ReduceSizeOnMediumNews = true;
input double MediumNewsSizeReduction = 0.5;

// --- ATR Filter & Dynamic Control ---
input double MinATRThreshold = 0.00001; // Minimum ATR threshold for trading (relaxed for aggressive mode)
input bool EnableDynamicATR = true;    // If true, adapt ATR threshold online
input double ATRDynamicMultiplier = 0.5; // Multiplier for dynamic ATR threshold (e.g., 0.5 = 50% of avg ATR)
input double MinATRFloor = 0.0003;     // Absolute minimum for dynamically set ATR threshold

// Working copy of MinATRThreshold that can be modified
double workingATRThreshold = 0;


// Dummy loader (replace with real HTTP/JSON parsing)
void LoadNewsEvents() {
    // Example: populate with dummy upcoming events
    newsEventCount = 2;
    newsEvents[0].eventTime = TimeCurrent() + 1800; // 30 min from now
    newsEvents[0].currency = "USD";
    newsEvents[0].title = "FOMC Statement";
    newsEvents[0].impact = "High";
    newsEvents[1].eventTime = TimeCurrent() + 3600; // 60 min from now
    newsEvents[1].currency = "EUR";
    newsEvents[1].title = "ECB Rate Decision";
    newsEvents[1].impact = "Medium";
}

// Returns true if a high-impact event is within lookahead window for this symbol
bool IsHighImpactNewsWindow() {
    string symbol = Symbol();
    string base = StringSubstr(symbol, 0, 3);
    string quote = StringSubstr(symbol, 3, 3);
    datetime now = TimeCurrent();
    for(int i=0; i<newsEventCount; i++) {
        if(newsEvents[i].impact == "High" &&
           (newsEvents[i].currency == base || newsEvents[i].currency == quote)) {
            if(MathAbs(newsEvents[i].eventTime - now) <= NewsLookaheadMinutes*60)
                return true;
        }
    }
    return false;
}

// Returns reduction factor for medium news
// 1.0 = no reduction, <1.0 = reduce size
// Call before trade entry
// (Extend for more granular control)
double GetNewsSizeReduction() {
    string symbol = Symbol();
    string base = StringSubstr(symbol, 0, 3);
    string quote = StringSubstr(symbol, 3, 3);
    datetime now = TimeCurrent();
    for(int i=0; i<newsEventCount; i++) {
        if(newsEvents[i].impact == "Medium" &&
           (newsEvents[i].currency == base || newsEvents[i].currency == quote)) {
            if(MathAbs(newsEvents[i].eventTime - now) <= NewsLookaheadMinutes*60)
                return MediumNewsSizeReduction;
        }
    }
    return 1.0;
}


// Core Constants and Definitions
#define MAX_BLOCKS 20
#define MAX_GRABS 10
#define MAX_FVGS 10
#define MAX_FEATURES 30
#define METRIC_WINDOW 100
#define ACCURACY_WINDOW 100
#define REGIME_COUNT 9

// Market Regime Constants
#define TRENDING_UP 0
#define TRENDING_DOWN 1
#define HIGH_VOLATILITY 2
#define LOW_VOLATILITY 3
#define RANGING_NARROW 4
#define RANGING_WIDE 5
#define BREAKOUT 6
#define REVERSAL 7
#define CHOPPY 8

// Market Phase Constants
enum MARKET_PHASE { PHASE_TRENDING_UP, PHASE_TRENDING_DOWN, PHASE_RANGING, PHASE_HIGH_VOLATILITY };

// --- INPUTS AND PARAMETERS ---
// Regime Learning/Adaptation Inputs
input int RegimePerfWindow = 30; // Window for regime stats
input double RegimeMinWinRate = 0.45;
input double RegimeMinProfitFactor = 1.2;
input double RegimeMaxDrawdownPct = 8.0;
input int RegimeUnderperfN = 10; // N trades to trigger block/reduce
input double RegimeRiskReduction = 0.5; // Reduce risk by this factor if underperforming
input bool BlockUnderperfRegime = true;

// Adaptive risk parameter
input double AdaptiveRiskMultiplier = 1.0; // Multiplier for adaptive risk calculation
// News filter is in news_filter.mqh
// Trading Timeframes
input ENUM_TIMEFRAMES AnalysisTimeframe = PERIOD_H1;  // Main analysis timeframe
input ENUM_TIMEFRAMES ScanningTimeframe = PERIOD_M15; // Scanning timeframe
input ENUM_TIMEFRAMES ExecutionTimeframe = PERIOD_M5; // Execution timeframe

// Risk Management
input int TradingStartHour = 0;
input int TradingEndHour = 23;
input int MaxTrades = 2;               // Maximum concurrent trades
double RiskPercent = 0.1;        // Risk per trade as % of balance
input double MaxPortfolioRiskPercent = 5.0; // Max portfolio risk as % of balance (portfolio cap)
input bool UseKellySizing = true;           // Use Kelly/Optimal F for dynamic sizing
input double MaxKellyFraction = 0.03;       // Max Kelly/Optimal F fraction (cap)
double SL_ATR_Mult = 1.0;         // Stop loss multiplier of ATR
double TP_ATR_Mult = 2.0;         // Take profit multiplier of ATR
input double SL_Pips = 10.0;           // Fixed stop loss in pips (as backup)
input double TP_Pips = 30.0;           // Fixed take profit in pips (as backup)
input int SignalCooldownSeconds = 0;  // Seconds between trade signals (ultra low for rapid testing)
int ActualSignalCooldownSeconds = 0;   // Runtime-adjustable cooldown
input int MinBlockStrength = 0;        // Minimum order block strength for valid signal (set to 0 for aggressive scalping/testing)
input bool RequireTrendConfirmation = false; // Require trend confirmation for trades
input int MaxConsecutiveLosses = 99;    // Stop trading after this many consecutive losses

// Volatility Filter

// Advanced Scalping Parameters
input bool EnableFastExecution = true;  // Enable fast execution mode
input bool EnableAdaptiveRisk = true;   // Enable adaptive position sizing
input bool EnableAggressiveTrailing = true; // Use aggressive trailing stops
double TrailingActivationPct = 0.3; // When to activate trailing (% of TP reached, now earlier)
double TrailingStopMultiplier = 0.3; // Trailing stop multiplier of ATR (tighter for high-frequency)

// Adaptive Position Sizing Parameters
input double VolatilityMultiplier = 1.0; // Base multiplier for volatility-based position sizing
input double LowVolatilityBonus = 1.2; // Increase size in low volatility (multiply by this)
input double HighVolatilityReduction = 0.8; // Decrease size in high volatility (multiply by this)

// Signal Quality Parameters
input bool EnableDivergenceFilter = false;   // Enable divergence-based signal filtering
input bool UseDivergenceBooster = false;     // Increase position size on divergence confirmation
input double DivergenceBoostMultiplier = 1.3; // Increase position size by this factor when divergence is detected
input int RSI_Period = 14;                  // RSI period for divergence detection
input int MACD_FastEMA = 12;                // MACD fast EMA period
input int MACD_SlowEMA = 26;                // MACD slow EMA period
input int MACD_SignalPeriod = 9;            // MACD signal period
input double EnhancedRR = 2.0; // Enhanced risk:reward ratio after trailing activation
input bool EnableMarketRegimeFiltering = false; // Filter trades based on market regime
// News filter already defined above, don't redefine

// Fast Execution Parameters
input int FastExecution_MaxRetries = 3;   // Maximum retries for failed orders
input int SlippagePoints = 20;            // Maximum allowed slippage in points
input int MaxAllowedSlippagePoints = 50;  // Cap for adaptive slippage
input double HighLatencyThreshold = 0.7;  // Seconds (if exceeded, increase slippage)
input double HighSlippageThreshold = 10.0; // Points (if exceeded, increase slippage)
int AdaptiveSlippagePoints = SlippagePoints;

// MQL5 Error Code Definitions
#define ERR_NOT_ENOUGH_MONEY 10019

// Partial Take-Profit Parameters
input bool UsePartialExits = true;        // Enable partial take-profits
input double PartialTP1_Percent = 0.33;   // % of position to exit at first TP
input double PartialTP2_Percent = 0.33;   // % of position to exit at second TP
input double PartialTP3_Percent = 0.34;   // % of position to exit at third TP
input double PartialTP1_Distance = 0.7;   // First TP at x times the stop distance (ATR-adaptive)
input double PartialTP2_Distance = 1.5;   // Second TP at x times the stop distance
input double PartialTP3_Distance = 2.5;   // Third TP at x times the stop distance
// Partial Profit Parameters
input bool EnablePartialTakeProfit = true; // Enable partial profit taking
input double PartialTP1_Pct = 0.5; // Portion to close at TP1 (e.g., 0.5 = half)

// Spread Filter
input double MaxAllowedSpread = 15; // Maximum allowed spread in points for trade execution

// Performance Tracking
input bool DisplayDebugInfo = true;    // Display debug info in comments
input bool LogPerformanceStats = true; // Log detailed performance statistics

// Smart Session-Based Trading
bool EnableSessionFiltering = false;   // Enable session-based trading rules
bool TradeAsianSession = true;       // Trade during Asian session (low volatility)
bool TradeEuropeanSession = true;    // Trade during European session (medium volatility)
bool TradeAmericanSession = true;    // Trade during American session (high volatility)
bool TradeSessionOverlaps = true;    // Emphasize trading during session overlaps

// Advanced Signal Quality Evaluation
input bool EnableSignalQualityML = false;    // Use ML-like signal quality evaluation
input double MinSignalQualityToTrade = 0.6; // Minimum signal quality score (0.0-1.0) to trade

// Smart Position Recovery
input bool EnableSmartAveraging = false;    // Enable smart grid averaging for drawdown recovery
input int MaxAveragingPositions = 2;        // Maximum additional positions for averaging
input double AveragingDistanceMultiplier = 2.0; // Distance multiplier for averaging positions

// Execution Logging
string lastMissedTradeReason = "";
double lastTradeSlippage = 0.0;
double lastTradeExecTime = 0.0;
int lastTradeRetryCount = 0;
string lastTradeError = "";
double avgExecutionTime = 0.0;
int executionCount = 0;

// Dynamic Controls
input int SwingLookbackBars = 1; // Reduce from 2 bars
input double SwingTolerancePct = 0.15; // 15% tolerance

// --- GLOBAL VARIABLES ---
// Trading Status
bool emergencyMode = false;
bool marketClosed = false;
bool isWeekend = false;
datetime lastTradeTime = 0;
datetime lastSignalTime = 0;
string lastErrorMessage = "";
bool trailingActive = false;
double trailingLevel = 0;
double trailingTP = 0;
int consecutiveLosses = 0;
int currentRegime = -1;
int regimeBarCount = 0;
int lastRegime = -1;

// Market Session State
enum ENUM_MARKET_SESSION {
    SESSION_NONE = 0,
    SESSION_ASIA = 1,
    SESSION_EUROPE = 2,
    SESSION_AMERICA = 3,
    SESSION_ASIA_EUROPE_OVERLAP = 4,
    SESSION_EUROPE_AMERICA_OVERLAP = 5
};

ENUM_MARKET_SESSION currentSession = SESSION_NONE;
double currentSignalQuality = 0.0;

// Averaging System Variables
int averagingPositions = 0;
datetime lastAveragingTime = 0;

// Trade object and indicators
CTrade trade;
double atrBuffer[];
double maBuffer[];
double volBuffer[];
int winStreak = 0;
int lossStreak = 0;

// Performance arrays
double tradeProfits[];
double tradeReturns[];
int regimeWins[REGIME_COUNT];
int regimeLosses[REGIME_COUNT];
double regimeProfit[REGIME_COUNT];
double regimeDrawdown[REGIME_COUNT];
double regimeMaxDrawdown[REGIME_COUNT];
double regimeProfitFactor[REGIME_COUNT];
int regimeTradeCount[REGIME_COUNT];
bool regimeBlocked[REGIME_COUNT];
double regimeRiskFactor[REGIME_COUNT];
double predictionResults[];
int predictionCount = 0;

// SMC Structures
struct LiquidityGrab { datetime time; double high; double low; bool bullish; bool active; };
struct FairValueGap { datetime startTime; datetime endTime; double high; double low; bool bullish; bool active; };
struct OrderBlock { datetime blockTime; double priceLevel; double highPrice; double lowPrice; bool bullish; bool valid; int strength; bool hasLiquidityGrab; bool hasSDConfirm; bool hasImbalance; bool hasFVG; };
struct SwingPoint {
    int barIndex;
    double price;
    int score;
    datetime time;
};

LiquidityGrab recentGrabs[MAX_GRABS];
FairValueGap recentFVGs[MAX_FVGS];
OrderBlock recentBlocks[MAX_BLOCKS];

int grabIndex = 0, fvgIndex = 0, blockIndex = 0;
double FVGMinSize = 0.5;
int LookbackBars = 200; // Force 200-bar lookback
bool UseLiquidityGrab = true, UseImbalanceFVG = true;

// Market Structure Detection
struct MarketStructure {
    bool bosBullish;
    bool bosBearish;
    bool choch;
    datetime lastSwingHighTime;
    datetime lastSwingLowTime;
    double swingHigh;
    double swingLow;
};
MarketStructure marketStructure;

void DetectMarketStructure() {
    SwingPoint swings[];
    int swingCount;
    FindQualitySwingPoints(true, 50, swings, swingCount);
    
    if(swingCount >= 3) {
        marketStructure.bosBullish = (swings[0].price > swings[2].price && swings[1].price > swings[2].price);
        marketStructure.bosBearish = (swings[0].price < swings[2].price && swings[1].price < swings[2].price);
        marketStructure.choch = (swings[0].price > swings[2].price && swings[1].price < swings[2].price) ||
                                (swings[0].price < swings[2].price && swings[1].price > swings[2].price);
    }
}

// Fibonacci Levels
void CalculateFibonacciLevels(double &levels[]) {
    ArrayResize(levels, 5);
    levels[0] = 0.236;
    levels[1] = 0.382;
    levels[2] = 0.5;
    levels[3] = 0.618;
    levels[4] = 0.786;
}

//+------------------------------------------------------------------+
//| Price Data Cache - Reduces redundant indicator calls             |
//+------------------------------------------------------------------+
struct PriceCache {
    // Price data arrays
    double close[];
    double open[];
    double high[];
    double low[];
    double ma20[];
    double ma50[];
    double atr[];
    double rsi[];
    
    // Handles for indicators
    int ma20Handle;
    int ma50Handle;
    int atrHandle;
    int rsiHandle;
    
    // Last update time to prevent redundant updates
    datetime lastUpdateTime;
    
    // Initialize cache
    void Init() {
        ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
        ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
        atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
        rsiHandle = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
        lastUpdateTime = 0;
    }
    
    // Update cache with fresh data
    bool Update(int requestedBars = 100) {
        // Only update once per tick/bar
        datetime currentTime = TimeCurrent();
        if(currentTime == lastUpdateTime) return true;
        
        // Make sure arrays can hold the data
        ArrayResize(close, requestedBars, 0);
        ArrayResize(open, requestedBars, 0);
        ArrayResize(high, requestedBars, 0);
        ArrayResize(low, requestedBars, 0);
        ArrayResize(ma20, requestedBars, 0);
        ArrayResize(ma50, requestedBars, 0);
        ArrayResize(atr, requestedBars, 0);
        ArrayResize(rsi, requestedBars, 0);
        
        // Update price data
        ArraySetAsSeries(close, true);
        ArraySetAsSeries(open, true);
        ArraySetAsSeries(high, true);
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(ma20, true);
        ArraySetAsSeries(ma50, true);
        ArraySetAsSeries(atr, true);
        ArraySetAsSeries(rsi, true);
        
        // Copy price data - accept any non-zero amount of data
        int copiedClose = CopyClose(Symbol(), PERIOD_CURRENT, 0, requestedBars, close);
        int copiedOpen = CopyOpen(Symbol(), PERIOD_CURRENT, 0, requestedBars, open);
        int copiedHigh = CopyHigh(Symbol(), PERIOD_CURRENT, 0, requestedBars, high);
        int copiedLow = CopyLow(Symbol(), PERIOD_CURRENT, 0, requestedBars, low);
        
        // Copy indicator data - accept any non-zero amount of data
        int copiedMA20 = CopyBuffer(ma20Handle, 0, 0, requestedBars, ma20);
        int copiedMA50 = CopyBuffer(ma50Handle, 0, 0, requestedBars, ma50);
        int copiedATR = CopyBuffer(atrHandle, 0, 0, requestedBars, atr);
        int copiedRSI = CopyBuffer(rsiHandle, 0, 0, requestedBars, rsi);
        
        // Log all copy operations for debugging
        Print("[DEBUG] Price cache update results: close=",copiedClose,
              " open=",copiedOpen," high=",copiedHigh," low=",copiedLow,
              " ma20=",copiedMA20," ma50=",copiedMA50,
              " atr=",copiedATR," rsi=",copiedRSI);
        
        // Verify we got the required price data (this is essential)
        if(copiedClose <= 0 || copiedOpen <= 0 || copiedHigh <= 0 || copiedLow <= 0) {
            Print("[ERROR] Failed to get essential price data, update failed");
            return false;
        }
        
        // For indicators, we'll be more lenient and use what we can get
        // Just set zeros for any indicators that didn't load properly
        if(copiedMA20 <= 0) {
            Print("[WARN] MA20 data not available, using zeros");
            ArrayInitialize(ma20, 0);
        }
        
        if(copiedMA50 <= 0) {
            Print("[WARN] MA50 data not available, using zeros");
            ArrayInitialize(ma50, 0);
        }
        
        if(copiedATR <= 0) {
            Print("[WARN] ATR data not available, using zeros");
            ArrayInitialize(atr, 0);
        }
        
        if(copiedRSI <= 0) {
            Print("[WARN] RSI data not available, using zeros");
            ArrayInitialize(rsi, 0);
        }
        
        lastUpdateTime = currentTime;
        return true;
    }
    
    // Clean up resources
    void Cleanup() {
        IndicatorRelease(ma20Handle);
        IndicatorRelease(ma50Handle);
        IndicatorRelease(atrHandle);
        IndicatorRelease(rsiHandle);
    }
};

// Global price cache instance
PriceCache priceCache;

//+------------------------------------------------------------------+
//| Parameter Group Structure - Consolidates related parameters      |
//+------------------------------------------------------------------+
struct ParameterGroup {
    // Risk parameters
    struct Risk {
        double percent;
        double maxPortfolioPercent;
        double maxKellyFraction;
        double adaptiveMultiplier;
        
        // Initialize with default values
        void Init(double riskPct, double maxPortfolioPct, double maxKelly, double adaptiveMult) {
            percent = riskPct;
            maxPortfolioPercent = maxPortfolioPct;
            maxKellyFraction = maxKelly;
            adaptiveMultiplier = adaptiveMult;
        }
        
        // Apply market phase adjustments
        void AdjustForMarketPhase(MARKET_PHASE phase) {
            switch(phase) {
                case PHASE_TRENDING_UP:
                    percent = RiskPercent * 1.0; // No change
                    break;
                case PHASE_TRENDING_DOWN:
                    percent = RiskPercent * 1.0; // No change
                    break;
                case PHASE_RANGING:
                    percent = RiskPercent * 0.5; // Reduce risk in ranging markets
                    break;
                case PHASE_HIGH_VOLATILITY:
                    percent = RiskPercent * 0.25; // Significantly reduce risk in high volatility
                    break;
            }
        }
    } risk;
    
    // Volatility parameters
    struct Volatility {
        double minATRThreshold;
        double atrMultiplier;
        double atrDynamicMultiplier;
        double minATRFloor;
        
        void Init(double minThreshold, double multiplier, double dynamicMult, double floor) {
            minATRThreshold = minThreshold;
            atrMultiplier = multiplier;
            atrDynamicMultiplier = dynamicMult;
            minATRFloor = floor;
        }
    } volatility;
    
    // Initialize all parameter groups
    void Init() {
        // Initialize risk parameters
        risk.Init(RiskPercent, MaxPortfolioRiskPercent, MaxKellyFraction, AdaptiveRiskMultiplier);
        
        // Initialize volatility parameters
        volatility.Init(MinATRThreshold, SL_ATR_Mult, ATRDynamicMultiplier, MinATRFloor);
    }
};

// Global parameter group instance
ParameterGroup params;

//+------------------------------------------------------------------+
//| Calculate average ATR over specified periods                     |
//+------------------------------------------------------------------+
double CalculateAverageATR(int periods) {
    // Use cached ATR data instead of recalculating
    if(!priceCache.Update(periods)) {
        Print("Failed to update price cache");
        return 0;
    }
    
    double avgAtr = 0;
    for(int i=0; i<periods; i++) {
        avgAtr += priceCache.atr[i];
    }
    
    return avgAtr / periods;
}

//+------------------------------------------------------------------+
//| ML-like signal quality evaluation                                |
//+------------------------------------------------------------------+
double CalculateSignalQuality(int signal) {
    if(!EnableSignalQualityML || signal == 0) return 0.0;
    
    // Initialize quality score
    double quality = 0.0;
    double totalWeight = 0.0;
    
    // 1. Market regime alignment (weight: 25%)
    double regimeAlignment = 0.0;
    double regimeWeight = 0.25;
    totalWeight += regimeWeight;
    
    if(currentRegime >= 0) {
        if((signal > 0 && currentRegime == TRENDING_UP) || 
           (signal < 0 && currentRegime == TRENDING_DOWN)) {
            regimeAlignment = 1.0; // Perfect alignment with trend
        }
        else if(currentRegime == CHOPPY) {
            regimeAlignment = 0.2; // Poor conditions in choppy markets
        }
        else if(currentRegime == RANGING_NARROW) {
            regimeAlignment = 0.6; // Decent for range trading if at extremes
        }
        else if(currentRegime == RANGING_WIDE) {
            regimeAlignment = 0.7; // Better for range trading if at extremes
        }
        else if(currentRegime == BREAKOUT) {
            regimeAlignment = 0.8; // Good for breakout following
        }
    }
    quality += regimeAlignment * regimeWeight;
    
    // 2. Divergence confirmation (weight: 35%)
    double divergenceScore = 0.0;
    double divergenceWeight = 0.35;
    totalWeight += divergenceWeight;
    
    if(lastDivergence.found && 
       ((signal > 0 && (lastDivergence.type == DIVERGENCE_REGULAR_BULL || lastDivergence.type == DIVERGENCE_HIDDEN_BULL)) ||
        (signal < 0 && (lastDivergence.type == DIVERGENCE_REGULAR_BEAR || lastDivergence.type == DIVERGENCE_HIDDEN_BEAR)))) {
        divergenceScore = lastDivergence.strength;
    }
    quality += divergenceScore * divergenceWeight;
    
    // 3. Volatility conditions (weight: 15%)
    double volatilityScore = 0.0;
    double volatilityWeight = 0.15;
    totalWeight += volatilityWeight;
    
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    double avgAtr = CalculateAverageATR(20);
    
    if(avgAtr > 0) {
        double volatilityRatio = atr / avgAtr;
        
        // Ideal volatility is between 0.8-1.5x average
        if(volatilityRatio >= 0.8 && volatilityRatio <= 1.5) {
            volatilityScore = 1.0 - (MathAbs(1.0 - volatilityRatio) / 0.7); // Closer to 1.0 is better
        }
        else if(volatilityRatio > 1.5 && volatilityRatio <= 2.0) {
            volatilityScore = 0.5; // High volatility - riskier
        }
        else if(volatilityRatio > 0.5 && volatilityRatio < 0.8) {
            volatilityScore = 0.7; // Slightly low volatility - still tradable
        }
        else {
            volatilityScore = 0.3; // Either too low or too high
        }
    }
    quality += volatilityScore * volatilityWeight;
    
    // 4. Order block quality (weight: 15%)
    double blockWeight = 0.15;
    double blockScore = 0.0;
    totalWeight += blockWeight;
    
    // Find the best block that aligns with our signal
    int bestBlock = -1;
    int bestScore = 0;
    
    for(int i = 0; i < MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid && 
           ((signal > 0 && recentBlocks[i].bullish) || (signal < 0 && !recentBlocks[i].bullish))) {
            if(recentBlocks[i].strength > bestScore) {
                bestScore = recentBlocks[i].strength;
                bestBlock = i;
            }
        }
    }
    
    if(bestBlock != -1) {
        // Calculate normalized score (assuming max strength could be around 5)
        blockScore = MathMin(1.0, bestScore / 5.0);
    }
    quality += blockScore * blockWeight;
    
    // 5. Historical win rate in similar conditions (weight: 10%)
    double historyWeight = 0.10;
    double historyScore = 0.0;
    totalWeight += historyWeight;
    
    if(currentRegime >= 0) {
        int totalTrades = regimeWins[currentRegime] + regimeLosses[currentRegime];
        if(totalTrades > 5) {
            historyScore = (double)regimeWins[currentRegime]/totalTrades;
        }
        else {
            historyScore = 0.5; // Default if insufficient data
        }
    }
    quality += historyScore * historyWeight;
    
    // Normalize by total weight (in case some factors were skipped)
    quality = totalWeight > 0 ? quality / totalWeight : 0;
    
    // Log the quality score components if debug is enabled
    if(DisplayDebugInfo) {
        Print("[SMC] Signal Quality Analysis:");
        Print("  - Regime Alignment: ", DoubleToString(regimeAlignment, 2), " (weight: ", DoubleToString(regimeWeight, 2), ")");
        Print("  - Divergence: ", DoubleToString(divergenceScore, 2), " (weight: ", DoubleToString(divergenceWeight, 2), ")");
        Print("  - Volatility: ", DoubleToString(volatilityScore, 2), " (weight: ", DoubleToString(volatilityWeight, 2), ")");
        Print("  - Block Quality: ", DoubleToString(blockScore, 2), " (weight: ", DoubleToString(blockWeight, 2), ")");
        Print("  - Historical Performance: ", DoubleToString(historyScore, 2), " (weight: ", DoubleToString(historyWeight, 2), ")");
        Print("  - FINAL SCORE: ", DoubleToString(quality, 2), " of 1.0");
    }
    
    // Store the quality for use elsewhere
    currentSignalQuality = quality;
    return quality;
}

//+------------------------------------------------------------------+
//| Create dashboard objects on the chart                            |
//+------------------------------------------------------------------+
void CreateDashboard() {
    // Clean up any existing objects first
    ObjectsDeleteAll(0, "SMC_Dashboard_");
    
    // Set up background panel
    ObjectCreate(0, "SMC_Dashboard_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_XDISTANCE, 20);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_YDISTANCE, 200);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_XSIZE, 240);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_YSIZE, 170);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_BGCOLOR, clrDarkSlateGray);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_BACK, false);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_SELECTED, false);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, "SMC_Dashboard_BG", OBJPROP_ZORDER, 0);
    
    // Title label
    ObjectCreate(0, "SMC_Dashboard_Title", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "SMC_Dashboard_Title", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, "SMC_Dashboard_Title", OBJPROP_XDISTANCE, 30);
    ObjectSetInteger(0, "SMC_Dashboard_Title", OBJPROP_YDISTANCE, 215);
    ObjectSetInteger(0, "SMC_Dashboard_Title", OBJPROP_COLOR, clrWhite);
    ObjectSetString(0, "SMC_Dashboard_Title", OBJPROP_TEXT, "SMC SCALPER V10 DASHBOARD");
    ObjectSetString(0, "SMC_Dashboard_Title", OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, "SMC_Dashboard_Title", OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, "SMC_Dashboard_Title", OBJPROP_SELECTABLE, false);
    
    // Performance metrics labels
    string labels[] = {
        "Session", "Regime", "Signal Quality", "Profit Today", 
        "Win Rate", "Avg. Execution", "Status"
    };
    
    for(int i=0; i<ArraySize(labels); i++) {
        // Label
        ObjectCreate(0, "SMC_Dashboard_Label_" + IntegerToString(i), OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "SMC_Dashboard_Label_" + IntegerToString(i), OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, "SMC_Dashboard_Label_" + IntegerToString(i), OBJPROP_XDISTANCE, 30);
        ObjectSetInteger(0, "SMC_Dashboard_Label_" + IntegerToString(i), OBJPROP_YDISTANCE, 240 + i * 20);
        ObjectSetInteger(0, "SMC_Dashboard_Label_" + IntegerToString(i), OBJPROP_COLOR, clrLightGray);
        ObjectSetString(0, "SMC_Dashboard_Label_" + IntegerToString(i), OBJPROP_TEXT, labels[i] + ":");
        ObjectSetString(0, "SMC_Dashboard_Label_" + IntegerToString(i), OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, "SMC_Dashboard_Label_" + IntegerToString(i), OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, "SMC_Dashboard_Label_" + IntegerToString(i), OBJPROP_SELECTABLE, false);
        
        // Value
        ObjectCreate(0, "SMC_Dashboard_Value_" + IntegerToString(i), OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "SMC_Dashboard_Value_" + IntegerToString(i), OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, "SMC_Dashboard_Value_" + IntegerToString(i), OBJPROP_XDISTANCE, 140);
        ObjectSetInteger(0, "SMC_Dashboard_Value_" + IntegerToString(i), OBJPROP_YDISTANCE, 240 + i * 20);
        ObjectSetInteger(0, "SMC_Dashboard_Value_" + IntegerToString(i), OBJPROP_COLOR, clrWhite);
        ObjectSetString(0, "SMC_Dashboard_Value_" + IntegerToString(i), OBJPROP_TEXT, "N/A");
        ObjectSetString(0, "SMC_Dashboard_Value_" + IntegerToString(i), OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, "SMC_Dashboard_Value_" + IntegerToString(i), OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, "SMC_Dashboard_Value_" + IntegerToString(i), OBJPROP_SELECTABLE, false);
    }
}

//+------------------------------------------------------------------+
//| Update dashboard with current performance metrics                 |
//+------------------------------------------------------------------+
void UpdateDashboard() {
    // 1. Current session
    string sessionName = "UNKNOWN";
    color sessionColor = clrWhite;
    
    switch(currentSession) {
        case SESSION_ASIA: 
            sessionName = "ASIAN"; 
            sessionColor = clrLightSkyBlue;
            break;
        case SESSION_EUROPE: 
            sessionName = "EUROPEAN"; 
            sessionColor = clrLightGreen;
            break;
        case SESSION_AMERICA: 
            sessionName = "AMERICAN"; 
            sessionColor = clrLightSalmon;
            break;
        case SESSION_ASIA_EUROPE_OVERLAP: 
            sessionName = "ASIA-EUROPE"; 
            sessionColor = clrMediumAquamarine;
            break;
        case SESSION_EUROPE_AMERICA_OVERLAP: 
            sessionName = "EUR-US"; 
            sessionColor = clrLightGoldenrod;
            break;
        default: 
            sessionName = "OFF-HOURS";
            sessionColor = clrLightGray;
    }
    ObjectSetString(0, "SMC_Dashboard_Value_0", OBJPROP_TEXT, sessionName);
    ObjectSetInteger(0, "SMC_Dashboard_Value_0", OBJPROP_COLOR, sessionColor);
    
    // 2. Current regime
    string regimeName = "UNKNOWN";
    color regimeColor = clrWhite;
    
    switch(currentRegime) {
        case TRENDING_UP: 
            regimeName = "TRENDING UP"; 
            regimeColor = clrLime;
            break;
        case TRENDING_DOWN: 
            regimeName = "TRENDING DOWN"; 
            regimeColor = clrRed;
            break;
        case HIGH_VOLATILITY: 
            regimeName = "HIGH VOLATILITY"; 
            regimeColor = clrOrange;
            break;
        case LOW_VOLATILITY: 
            regimeName = "LOW VOLATILITY"; 
            regimeColor = clrDeepSkyBlue;
            break;
        case RANGING_NARROW: 
            regimeName = "NARROW RANGE"; 
            regimeColor = clrAqua;
            break;
        case RANGING_WIDE: 
            regimeName = "WIDE RANGE"; 
            regimeColor = clrMediumSpringGreen;
            break;
        case BREAKOUT: 
            regimeName = "BREAKOUT"; 
            regimeColor = clrYellow;
            break;
        case REVERSAL: 
            regimeName = "REVERSAL"; 
            regimeColor = clrFuchsia;
            break;
        case CHOPPY: 
            regimeName = "CHOPPY"; 
            regimeColor = clrDarkGray;
            break;
    }
    ObjectSetString(0, "SMC_Dashboard_Value_1", OBJPROP_TEXT, regimeName);
    ObjectSetInteger(0, "SMC_Dashboard_Value_1", OBJPROP_COLOR, regimeColor);
    
    // 3. Signal quality
    string qualityText = DoubleToString(currentSignalQuality, 2) + " / 1.00";
    color qualityColor = clrWhite;
    
    if(currentSignalQuality >= 0.8) qualityColor = clrLime;
    else if(currentSignalQuality >= 0.6) qualityColor = clrYellow;
    else if(currentSignalQuality >= 0.4) qualityColor = clrOrange;
    else qualityColor = clrLightGray;
    
    ObjectSetString(0, "SMC_Dashboard_Value_2", OBJPROP_TEXT, qualityText);
    ObjectSetInteger(0, "SMC_Dashboard_Value_2", OBJPROP_COLOR, qualityColor);
    
    // 4. Profit today
    double todayProfit = 0.0;
    int todayTrades = 0;
    datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    
    HistorySelect(todayStart, TimeCurrent());
    
    for(int i=0; i<HistoryDealsTotal(); i++) {
        ulong ticket = HistoryDealGetTicket(i);
        string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
        
        if(symbol == Symbol()) {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            todayProfit += profit;
            if(profit != 0) todayTrades++;
        }
    }
    
    string profitText = DoubleToString(todayProfit, 2);
    color profitColor = todayProfit >= 0 ? clrLime : clrRed;
    
    ObjectSetString(0, "SMC_Dashboard_Value_3", OBJPROP_TEXT, profitText + " (" + IntegerToString(todayTrades) + " trades)");
    ObjectSetInteger(0, "SMC_Dashboard_Value_3", OBJPROP_COLOR, profitColor);
    
    // 5. Win rate
    int totalWins = 0;
    int totalLosses = 0;
    
    for(int i=0; i<REGIME_COUNT; i++) {
        totalWins += regimeWins[i];
        totalLosses += regimeLosses[i];
    }
    
    string winRateText = totalWins + totalLosses > 0 ? 
        DoubleToString(100.0 * totalWins / (totalWins + totalLosses), 1) + "% (" + IntegerToString(totalWins + totalLosses) + " trades)" :
        "No trades yet";
    
    ObjectSetString(0, "SMC_Dashboard_Value_4", OBJPROP_TEXT, winRateText);
    
    // 6. Average execution time
    string execTimeText = executionCount > 0 ? 
        DoubleToString(avgExecutionTime * 1000, 1) + " ms" :
        "No data";
    
    ObjectSetString(0, "SMC_Dashboard_Value_5", OBJPROP_TEXT, execTimeText);
    
    // 7. Bot status
    string statusText = "ACTIVE";
    color statusColor = clrLime;
    
    if(emergencyMode) {
        statusText = "EMERGENCY MODE";
        statusColor = clrRed;
    } else if(!CanTrade()) {
        statusText = "WAITING";
        statusColor = clrOrange;
    }
    
    ObjectSetString(0, "SMC_Dashboard_Value_6", OBJPROP_TEXT, statusText);
    ObjectSetInteger(0, "SMC_Dashboard_Value_6", OBJPROP_COLOR, statusColor);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // --- INPUT VALIDATION ---
    string err = "";
    if(RiskPercent <= 0 || RiskPercent > 5) err += "RiskPercent out of bounds (0-5%)\n";
    if(MaxPortfolioRiskPercent <= 0 || MaxPortfolioRiskPercent > 20) err += "MaxPortfolioRiskPercent out of bounds (0-20%)\n";
    if(MaxKellyFraction < 0.001 || MaxKellyFraction > 0.1) err += "MaxKellyFraction out of bounds (0.001-0.1)\n";
    if(SlippagePoints < 1 || SlippagePoints > 100) err += "SlippagePoints out of bounds (1-100)\n";
    if(MinATRThreshold < 0.00001) err += "MinATRThreshold too low\n";
    if(err != "") {
        Alert("[SMC] Input validation failed:\n" + err);
        Print("[SMC] Input validation failed:\n" + err);
        return INIT_FAILED;
    }

    // Initialize trade object
    trade.SetDeviationInPoints(10);
    
    // Initialize working ATR threshold with input value
    workingATRThreshold = MinATRThreshold;
    
    // Initialize price cache system
    priceCache.Init();
    
    // Initialize parameter groups
    params.Init();
    
    // Initialize arrays
    ArrayResize(atrBuffer, 100);
    ArrayResize(maBuffer, 100);
    ArrayResize(volBuffer, 100);
    
    // Initialize regime arrays
    // Only use ArrayResize for dynamic arrays. If regimeWins, regimeLosses, regimeProfit, regimeAccuracy are static, remove ArrayResize.
    // If you want dynamic, declare: double regimeWins[]; etc. Otherwise, remove these lines.
    // Example fix for static arrays:
    // (Remove these ArrayResize lines for static arrays.)
    
    // Initialize performance arrays
    ArrayResize(tradeProfits, METRIC_WINDOW);
    ArrayResize(tradeReturns, METRIC_WINDOW);
    
    // Initialize advanced features
    AutocalibrateForSymbol();
    CreateDashboard();
    ArrayResize(predictionResults, ACCURACY_WINDOW);
    
    // Reset and initialize values
    for(int i=0; i<REGIME_COUNT; i++) {
        regimeWins[i] = 0;
        regimeLosses[i] = 0;
        regimeProfit[i] = 0.0;
        // Remove regimeAccuracy if not defined as an array
    }
    
    for(int i=0; i<METRIC_WINDOW; i++) {
        tradeProfits[i] = 0.0;
        tradeReturns[i] = 0.0;
    }
    
    for(int i=0; i<ACCURACY_WINDOW; i++) {
        predictionResults[i] = 0;
    }
    
    for(int i=0; i<100; i++) {
        atrBuffer[i] = 0.0;
        maBuffer[i] = 0.0;
        volBuffer[i] = 0.0;
    }
    
    // Clear trailing variables
    trailingActive = false;
    trailingLevel = 0;
    trailingTP = 0;
    
    // Reset counters
    consecutiveLosses = 0;
    predictionCount = 0;
    winStreak = 0;
    lossStreak = 0;

    Print("[Init] SMC Scalper Hybrid initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| On-Chart Diagnostics Panel                                       |
//+------------------------------------------------------------------+
void ShowDiagnosticsOnChart() {
    string diag = "[SMC Scalper Hybrid]";
    diag += "\nRegime: " + IntegerToString(currentRegime); // Use int to string if currentRegime is not an enum
    diag += "\nPrediction: " + DoubleToString(currentSignalQuality, 2);
    diag += "\nRisk: " + DoubleToString(RiskPercent, 2) + "%";
    double totalWins = 0, totalLosses = 0, totalProfit = 0, grossProfit = 0, grossLoss = 0, maxDD = 0;
    for(int i=0;i<REGIME_COUNT;i++) {
        totalWins += regimeWins[i];
        totalLosses += regimeLosses[i];
        totalProfit += regimeProfit[i];
        if(regimeProfit[i]>0) grossProfit += regimeProfit[i];
        else grossLoss += MathAbs(regimeProfit[i]);
        // Remove regimeMaxDrawdown if not defined
    }
    double winRate = (totalWins+totalLosses>0) ? totalWins/(totalWins+totalLosses) : 0;
    double pf = (grossLoss>0) ? grossProfit/grossLoss : 1.0;
    diag += "\nWin Rate: " + DoubleToString(winRate*100,1) + "%";
    diag += "\nPF: " + DoubleToString(pf,2);
    diag += "\nDrawdown: " + DoubleToString(maxDD,2);
    Comment(diag);
}

// OnTick function is already defined elsewhere in the file

//+------------------------------------------------------------------+
//| Improved Error Handling & Escalation                             |
//+------------------------------------------------------------------+
int consecutiveTradeErrors = 0;
input int MaxConsecutiveTradeErrors = 5;

bool HandleTradeError(int errorCode, string context) {
    Print("[SMC ERROR] ", context, " failed. Error ", errorCode, ": ", ErrorDescription(errorCode));
    consecutiveTradeErrors++;
    if(consecutiveTradeErrors >= MaxConsecutiveTradeErrors) {
        Alert("[SMC] Too many consecutive trade errors. EA auto-disabled.");
        ExpertRemove();
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Daily/Weekly Log Summary                                         |
//+------------------------------------------------------------------+
void WriteSummaryLog() {
    string fn = "SMC_PerformanceLog_"+TimeToString(TimeCurrent(),TIME_DATE)+".csv";
    int fh = FileOpen(fn, FILE_WRITE|FILE_READ|FILE_SHARE_READ|FILE_SHARE_WRITE);
    if(fh != INVALID_HANDLE) {
        FileSeek(fh, 0, SEEK_END);
        double totalWins = 0, totalLosses = 0, totalProfit = 0, grossProfit = 0, grossLoss = 0, maxDD = 0;
        for(int i=0;i<REGIME_COUNT;i++) {
            totalWins += regimeWins[i];
            totalLosses += regimeLosses[i];
            totalProfit += regimeProfit[i];
            if(regimeProfit[i]>0) grossProfit += regimeProfit[i];
            else grossLoss += MathAbs(regimeProfit[i]);
        }
        double winRate = (totalWins+totalLosses>0) ? totalWins/(totalWins+totalLosses) : 0;
        double pf = (grossLoss>0) ? grossProfit/grossLoss : 1.0;
        string logLine = TimeToString(TimeCurrent())+","+DoubleToString(totalWins,0)+","+DoubleToString(totalLosses,0)+","+DoubleToString(winRate,2)+","+DoubleToString(pf,2)+","+DoubleToString(maxDD,2)+"\r\n";
        FileWriteString(fh, logLine, StringLen(logLine));
        FileClose(fh);
    }
}

//+------------------------------------------------------------------+
//| Rolling Window Feature Stats & Online Learning                   |
//+------------------------------------------------------------------+
#define FEATURE_WINDOW 100
struct FeatureStats {
    double volatility[FEATURE_WINDOW];
    double spread[FEATURE_WINDOW];
    int hour[FEATURE_WINDOW];
    int idx;
};
FeatureStats featureStats; // Zero-initialized by default in MQL5

void UpdateFeatureStats() {
    double vol = GetATR(Symbol(), PERIOD_M5, 14, 0); // Add 'shift' parameter if required by your GetATR
    double spr = (SymbolInfoDouble(Symbol(),SYMBOL_ASK)-SymbolInfoDouble(Symbol(),SYMBOL_BID))/SymbolInfoDouble(Symbol(),SYMBOL_POINT);
    int hr;
    MqlDateTime t; TimeToStruct(TimeCurrent(), t); hr = t.hour;
    int i = featureStats.idx % FEATURE_WINDOW;
    featureStats.volatility[i] = vol;
    featureStats.spread[i] = spr;
    featureStats.hour[i] = hr;
    featureStats.idx++;
    // Example: Adapt MinATRThreshold online
    double sum=0; int cnt=0;
    for(int j=0;j<FEATURE_WINDOW;j++) { if(featureStats.volatility[j]>0) {sum+=featureStats.volatility[j];cnt++;} }
    // Only adapt if enabled; always respect a floor
    if(cnt>10 && EnableDynamicATR) {
        double dynamicATR = sum/cnt * ATRDynamicMultiplier;
        workingATRThreshold = (dynamicATR > MinATRFloor) ? dynamicATR : MinATRFloor;
    } else {
        workingATRThreshold = MinATRThreshold; // Use the input value
    }
}

//+------------------------------------------------------------------+
//| Pattern Clustering & Signal Boost                                |
//+------------------------------------------------------------------+
#define CLUSTER_MAX 10
struct PatternCluster {
    double avgWinRate;
    double avgPF;
    int count;
    double lastSignalBoost;
};
PatternCluster patternClusters[CLUSTER_MAX]; // Will initialize elements in OnInit or first use

void ClusterAndBoostPatterns() {
    int clusterIdx = GetCurrentPatternCluster();
    if(clusterIdx<0 || clusterIdx>=CLUSTER_MAX) return;
    
    // Update stats (stub: replace with real pattern extraction)
    double lastResult = predictionResults[(featureStats.idx-1+ACCURACY_WINDOW)%ACCURACY_WINDOW];
    
    // Update pattern cluster stats
    patternClusters[clusterIdx].avgWinRate = (patternClusters[clusterIdx].avgWinRate * 
                                           patternClusters[clusterIdx].count + 
                                           (lastResult>0?1:0)) / 
                                          (patternClusters[clusterIdx].count+1);
    patternClusters[clusterIdx].count++;
    
    // If cluster win rate is high, boost signal
    if(patternClusters[clusterIdx].avgWinRate > 0.65 && 
       patternClusters[clusterIdx].count > 10) {
        patternClusters[clusterIdx].lastSignalBoost = 1.2;
    } else {
        patternClusters[clusterIdx].lastSignalBoost = 1.0;
    }
}

int GetCurrentPatternCluster() {
    // Simple stub: cluster by hour of day (replace with real pattern logic)
    int hr; MqlDateTime t; TimeToStruct(TimeCurrent(), t); hr = t.hour;
    return hr % CLUSTER_MAX;
}

// OnDeinit function is already defined elsewhere

//+------------------------------------------------------------------+
//| Detect current market session based on server time               |
//+------------------------------------------------------------------+
ENUM_MARKET_SESSION DetectMarketSession() {
    if(!EnableSessionFiltering) return SESSION_NONE;
    
    // Get current server time
    MqlDateTime serverTime;
    TimeCurrent(serverTime);
    int hour = serverTime.hour;
    
    // Define session hours in GMT (adjust if your server uses a different timezone)
    int asiaStart = 22;        // 22:00 GMT (Tokyo open)
    int asiaEnd = 8;           // 08:00 GMT (Tokyo/Sydney close)
    int europeStart = 7;       // 07:00 GMT (London pre-market)
    int europeEnd = 16;        // 16:00 GMT (London close)
    int americaStart = 13;     // 13:00 GMT (New York open)
    int americaEnd = 21;       // 21:00 GMT (New York close)
    
    // Detect session overlaps
    if(hour >= europeStart && hour < europeEnd && hour >= americaStart && hour < americaEnd) {
        return SESSION_EUROPE_AMERICA_OVERLAP;
    }
    if((hour >= asiaStart || hour < asiaEnd) && (hour >= europeStart && hour < europeEnd)) {
        return SESSION_ASIA_EUROPE_OVERLAP;
    }
    
    // Detect single sessions
    if(hour >= asiaStart || hour < asiaEnd) {
        return SESSION_ASIA;
    }
    if(hour >= europeStart && hour < europeEnd) {
        return SESSION_EUROPE;
    }
    if(hour >= americaStart && hour < americaEnd) {
        return SESSION_AMERICA;
    }
    
    return SESSION_NONE;
}

//+------------------------------------------------------------------+
//| Adjust parameters based on current session                        |
//+------------------------------------------------------------------+
void AdjustSessionParameters() {
    if(!EnableSessionFiltering) return;
    
    // Store original values for reference (if needed)
    static double originalSL_ATR_Mult = SL_ATR_Mult;
    static double originalTP_ATR_Mult = TP_ATR_Mult;
    static double originalTrailingActivationPct = TrailingActivationPct;
    
    // Update current session
    currentSession = DetectMarketSession();
    
    // Skip if session tracking disabled or no clear session detected
    if(currentSession == SESSION_NONE) return;
    
    if(DisplayDebugInfo) {
        string sessionName = "UNKNOWN";
        switch(currentSession) {
            case SESSION_ASIA: sessionName = "ASIAN"; break;
            case SESSION_EUROPE: sessionName = "EUROPEAN"; break;
            case SESSION_AMERICA: sessionName = "AMERICAN"; break;
            case SESSION_ASIA_EUROPE_OVERLAP: sessionName = "ASIA-EUROPE OVERLAP"; break;
            case SESSION_EUROPE_AMERICA_OVERLAP: sessionName = "EUROPE-AMERICA OVERLAP"; break;
        }
        Print("[SMC] Current market session detected: ", sessionName);
    }
    
    // Adjust parameters based on current session
    switch(currentSession) {
        case SESSION_ASIA: // Lower volatility usually
            if(!TradeAsianSession) {
                if(DisplayDebugInfo) Print("[SMC] Asian session trading disabled in settings");
                return;
            }
            // Tighter stops, smaller targets in slower Asian session
            SL_ATR_Mult = originalSL_ATR_Mult * 0.8;
            TP_ATR_Mult = originalTP_ATR_Mult * 0.7;
            TrailingActivationPct = 0.25; // Earlier trailing in lower volatility
            TrailingStopMultiplier = 0.2;  // Tighter trailing
            break;
            
        case SESSION_EUROPE: // Medium volatility
            if(!TradeEuropeanSession) {
                if(DisplayDebugInfo) Print("[SMC] European session trading disabled in settings");
                return;
            }
            // Standard parameters for European session
            SL_ATR_Mult = originalSL_ATR_Mult * 1.0;
            TP_ATR_Mult = originalTP_ATR_Mult * 1.0;
            TrailingActivationPct = 0.3;
            TrailingStopMultiplier = 0.3;
            break;
            
        case SESSION_AMERICA: // Higher volatility
            if(!TradeAmericanSession) {
                if(DisplayDebugInfo) Print("[SMC] American session trading disabled in settings");
                return;
            }
            // Wider stops, larger targets in volatile NY session
            SL_ATR_Mult = originalSL_ATR_Mult * 1.2;
            TP_ATR_Mult = originalTP_ATR_Mult * 1.3;
            TrailingActivationPct = 0.35; // Later trailing in higher volatility
            TrailingStopMultiplier = 0.4;  // Wider trailing
            break;
            
        case SESSION_ASIA_EUROPE_OVERLAP:
        case SESSION_EUROPE_AMERICA_OVERLAP:
            if(!TradeSessionOverlaps) {
                if(DisplayDebugInfo) Print("[SMC] Session overlap trading disabled in settings");
                return;
            }
            // Increased volatility during session overlaps
            SL_ATR_Mult = originalSL_ATR_Mult * 1.1;
            TP_ATR_Mult = originalTP_ATR_Mult * 1.2;
            TrailingActivationPct = 0.4;
            TrailingStopMultiplier = 0.35;
            break;
    }
    
    if(DisplayDebugInfo) {
        Print("[SMC] Session-adjusted parameters: SL_ATR_Mult=", DoubleToString(SL_ATR_Mult, 2), 
              ", TP_ATR_Mult=", DoubleToString(TP_ATR_Mult, 2),
              ", TrailingActivationPct=", DoubleToString(TrailingActivationPct, 2));
    }
}

//+------------------------------------------------------------------+
//| Dynamically calibrate parameters based on currency pair          |
//+------------------------------------------------------------------+
void AutocalibrateForSymbol() {
    ActualSignalCooldownSeconds = SignalCooldownSeconds;
    string symbolName = Symbol();
    double originalATRThreshold = MinATRThreshold; // Store the input value
    double originalTrailingStopMultiplier = TrailingStopMultiplier;
    
    // Setup for JPY pairs (higher pip values, need different scaling)
    if(StringFind(symbolName, "JPY") >= 0) {
        workingATRThreshold = 0.008;
        TrailingStopMultiplier = 0.4;
        if(DisplayDebugInfo) Print("[SMC] Calibrated for JPY pair: higher ATR threshold and trailing");
    }
    // Setup for GBP pairs (higher volatility)
    else if(StringFind(symbolName, "GBP") >= 0) {
        workingATRThreshold = 0.0012;
        TrailingStopMultiplier = 0.35;
        if(DisplayDebugInfo) Print("[SMC] Calibrated for GBP pair: adjusted for higher volatility");
    }
    // Setup for CHF pairs
    else if(StringFind(symbolName, "CHF") >= 0) {
        workingATRThreshold = 0.0008;
        TrailingStopMultiplier = 0.3;
        if(DisplayDebugInfo) Print("[SMC] Calibrated for CHF pair");
    }
    // Setup for commodity pairs (AUDUSD, NZDUSD, etc)
    else if(StringFind(symbolName, "AUD") >= 0 || StringFind(symbolName, "NZD") >= 0) {
        workingATRThreshold = 0.0007;
        TrailingStopMultiplier = 0.25;
        if(DisplayDebugInfo) Print("[SMC] Calibrated for commodity currency pair");
    }
    // Setup for major pairs (EURUSD, etc)
    else if(StringFind(symbolName, "EUR") >= 0 && StringFind(symbolName, "USD") >= 0) {
        workingATRThreshold = 0.0005;
        TrailingStopMultiplier = 0.3;
        if(DisplayDebugInfo) Print("[SMC] Calibrated for major pair: standard settings");
    }
    // Default calibration for other pairs
    else {
        workingATRThreshold = originalATRThreshold;
        TrailingStopMultiplier = originalTrailingStopMultiplier;
    }
    
    // Also check for high spread pairs
    double spread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    if(spread > 20) { // High spread pair
        // For high spread pairs, reduce trade frequency and increase targets
        ActualSignalCooldownSeconds = (int)MathRound((double)SignalCooldownSeconds * 1.5);
        TP_ATR_Mult *= 1.3;
        if(DisplayDebugInfo) Print("[SMC] High spread pair detected (", spread, " points). Adjusted parameters.");
    }
    
    if(symbolName == "XAUUSD") {
        workingATRThreshold = 0.0003; // Adjusted for current volatility
        TrailingStopMultiplier = 0.25; // Tighter trailing stops
    }
}

//+------------------------------------------------------------------+
//| Utility: CanTrade                                               |
//+------------------------------------------------------------------+
bool CanTrade() {
    // Check if autotrading is enabled
    bool autoTradingEnabled = TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
    
    // Detailed conditions check with debug info if enabled
    if(DisplayDebugInfo) {
        Print("[TRADE STATUS] AutoTrading Enabled: ", autoTradingEnabled,
              ", emergencyMode: ", emergencyMode,
              ", marketClosed: ", marketClosed,
              ", isWeekend: ", isWeekend);
    }
    
    // For maximum permissiveness during testing, you could force return true here
    // return true;
    
    // Normal operation: more detailed check with autotrading permission
    return (autoTradingEnabled && !emergencyMode && !marketClosed && !isWeekend);
}

//+------------------------------------------------------------------+
//| Utility: ManageOpenTrade                                        |
//+------------------------------------------------------------------+
void ManageOpenTrade() {
    // Stub for managing open trades (implement your trailing, partial TP, etc.)
}

//+------------------------------------------------------------------+
//| Utility: CalculatePositionSize                                  |
//+------------------------------------------------------------------+
double CalculatePositionSize() {
    // Stub for position sizing (replace with your adaptive logic)
    return 0.01;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up resources
    ObjectsDeleteAll(0, "SMC_GUI_");
    
    // Clean up price cache resources
    priceCache.Cleanup();
    
    // Log statistics if enabled
    if(LogPerformanceStats) {
        // Calculate performance metrics
        double totalWins = 0, totalLosses = 0, totalProfit = 0;
        for(int i=0; i<REGIME_COUNT; i++) {
            totalWins += regimeWins[i];
            totalLosses += regimeLosses[i];
            totalProfit += regimeProfit[i];
        }
        
        // Calculate overall win rate
        double winRate = (totalWins + totalLosses > 0) ? (double)totalWins/(totalWins + totalLosses) : 0;
        
        // Log statistics
        Print("[Deinit] SMC Scalper Hybrid terminated. Reason: ", reason);
        Print("[Deinit] Total profit: ", totalProfit);
        Print("[Deinit] Win rate: ", winRate);
        Print("[Deinit] Total trades: ", totalWins + totalLosses);
        
        // Write summary log
        WriteSummaryLog();
    }
}

//+------------------------------------------------------------------+
//| Expert tick function - Optimized for performance                 |
//+------------------------------------------------------------------+
void OnTick()
{
    // Performance tracking
    ulong tickStartTime = GetTickCount64();
    
    // Update price cache once per tick - this reduces redundant indicator calls
    if(!priceCache.Update(100)) {
        Print("[ERROR] Failed to update price cache, skipping tick");
        return;
    }
    
    // Early exit checks - do these first to avoid unnecessary processing
    if(!CanTrade()) {
        if(DisplayDebugInfo) {
            Print("[INFO] Trading not allowed, skipping heavy logic.");
            UpdateDashboard(); // Still update dashboard even when not trading
        }
        return;
    }
    
    // Check for open positions first (most common case)
    if(PositionSelect(Symbol())) {
        ManageOpenTrade();
        ManageTrailingStops(); // Always manage trailing stops for open positions
        UpdateDashboard();
        return; // Don't open new positions if we already have one
    }
    
    // Only run these expensive operations if we might actually trade
    MARKET_PHASE currentPhase = DetectMarketPhase();
    AdjustTradeFrequency(currentPhase);
    AdjustRiskParameters(currentPhase);
    
    // Always reset runtime cooldown from input at the start of each tick
    ActualSignalCooldownSeconds = SignalCooldownSeconds;
    if(ActualSignalCooldownSeconds < 1) ActualSignalCooldownSeconds = 1; // Safety check
    
    // Dynamic session & symbol calibration - only when needed
    AdjustSessionParameters();
    
    if(EnableMarketRegimeFiltering) {
        currentRegime = FastRegimeDetection(Symbol());
    }
    
    // Step 3: Get trading signal
    int signal = GetTradingSignal();
    // Uncomment the next line to force a trade for testing:
    // signal = 1;
    
    // Step 4: Check if we should execute a trade (simple cooldown and safety checks)
    bool cooldownPassed = (TimeCurrent() - lastTradeTime) >= ActualSignalCooldownSeconds;
    if(DisplayDebugInfo) {
        Print("[DEBUG] signal=", signal, ", cooldownPassed=", cooldownPassed, ", emergencyMode=", emergencyMode, ", CanTrade=", CanTrade(), ", cooldownUsed=", ActualSignalCooldownSeconds, ", lastTradeTime=", lastTradeTime, ", now=", TimeCurrent());
        if(!cooldownPassed) {
            Print("[DEBUG] Cooldown active. Seconds since last signal: ", (TimeCurrent() - lastTradeTime), " / ", ActualSignalCooldownSeconds);
        }
        if(signal == 0) {
            Print("[DEBUG] No valid signal present.");
        }
        if(emergencyMode) {
            Print("[DEBUG] Emergency mode active. Trading disabled.");
        }
        if(!CanTrade()) {
            Print("[DEBUG] CanTrade() returned false. Trading disabled.");
        }
    }
    if(signal != 0 && cooldownPassed && !emergencyMode && CanTrade()) {
        bool tradePlaced = false;
        if(EnableFastExecution) {
            tradePlaced = ExecuteTradeWithRetry(signal, FastExecution_MaxRetries);
        } else {
            tradePlaced = ExecuteTrade(signal);
        }
        if(tradePlaced) {
            lastSignalTime = TimeCurrent();
            if(DisplayDebugInfo) Print("[DEBUG] Trade placed. Cooldown reset. lastSignalTime=", lastSignalTime);
        } else {
            if(DisplayDebugInfo) Print("[DEBUG] Trade attempt failed. Cooldown NOT reset.");
        }
    }
    
    // Step 5: Manage open positions
    if(EnableAggressiveTrailing) {
        ManageTrailingStops();
    }
    
    // Step 6: Display debug information if enabled
    if(DisplayDebugInfo) {
        ShowDebugInfo();
    }
}

//+------------------------------------------------------------------+
//| Called on each trade event to track performance                  |
//+------------------------------------------------------------------+
void OnTrade() {
    HistorySelect(0, TimeCurrent());
    for(int i=HistoryDealsTotal()-1; i>=0; i--) {
        ulong ticketID = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticketID, DEAL_COMMENT) == "SMC Buy" || 
           HistoryDealGetString(ticketID, DEAL_COMMENT) == "SMC Sell") {
            double profit = HistoryDealGetDouble(ticketID, DEAL_PROFIT);
            
            // Update performance metrics
            if(profit < 0) {
                consecutiveLosses++;
                lossStreak++;
                winStreak = 0;
            } else {
                consecutiveLosses = 0;
                lossStreak = 0;
                winStreak++;
            }
            
            // Store profit in the metrics array
            int idx = predictionCount % METRIC_WINDOW;
            tradeProfits[idx] = profit;
            
            // Update regime statistics if we have a valid regime
            if(currentRegime >= 0 && currentRegime < REGIME_COUNT) {
                if(profit > 0) regimeWins[currentRegime]++;
                else regimeLosses[currentRegime]++;
                regimeProfit[currentRegime] += profit;
                
                // Update accuracy - remove regimeAccuracy if not defined
                int totalTrades = regimeWins[currentRegime] + regimeLosses[currentRegime];
                // Removed reference to regimeAccuracy array
            }
            
            predictionCount++;
            break;
        }
    }
    
    // Emergency shutoff after too many consecutive losses
    if(consecutiveLosses >= MaxConsecutiveLosses) {
        emergencyMode = true;
        Print("[SMC] EMERGENCY MODE ACTIVATED: Too many consecutive losses (", consecutiveLosses, ")");
    }
}

//+------------------------------------------------------------------+
//| Market Regime Detection (from ScalperV3)                         |
//+------------------------------------------------------------------+
int FastRegimeDetection(string symbol) {
    // Get price data for multiple timeframes
    double close0 = iClose(symbol, PERIOD_M5, 0);
    double close1 = iClose(symbol, PERIOD_M5, 1);
    double close3 = iClose(symbol, PERIOD_M5, 3);
    double close5 = iClose(symbol, PERIOD_M5, 5);
    double close10 = iClose(symbol, PERIOD_M5, 10);
    
    // Get high/low data
    double high0 = iHigh(symbol, PERIOD_M5, 0);
    double high1 = iHigh(symbol, PERIOD_M5, 1);
    double high3 = iHigh(symbol, PERIOD_M5, 3);
    double low0 = iLow(symbol, PERIOD_M5, 0);
    double low1 = iLow(symbol, PERIOD_M5, 1);
    double low3 = iLow(symbol, PERIOD_M5, 3);
    
    // Calculate multiple moving averages for trend detection
    double ma3 = 0, ma5 = 0, ma10 = 0, ma20 = 0;
    for(int i=0; i<3; i++) ma3 += iClose(symbol, PERIOD_M5, i);
    for(int i=0; i<5; i++) ma5 += iClose(symbol, PERIOD_M5, i);
    for(int i=0; i<10; i++) ma10 += iClose(symbol, PERIOD_M5, i);
    for(int i=0; i<20; i++) ma20 += iClose(symbol, PERIOD_M5, i);
    ma3 /= 3;
    ma5 /= 5;
    ma10 /= 10;
    ma20 /= 20;
    
    // Calculate volatility metrics
    double quickAtr = 0.0;
    // Direct implementation instead of calling GetATR
    int atrHandle = iATR(symbol, PERIOD_M5, 14);
    if(atrHandle != INVALID_HANDLE) {
        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);
        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
            quickAtr = atrBuffer[0];
        }
        IndicatorRelease(atrHandle);
    }
    
    double avgRange = 0;
    for(int i=0; i<5; i++) {
        avgRange += MathAbs(iHigh(symbol, PERIOD_M5, i) - iLow(symbol, PERIOD_M5, i));
    }
    avgRange /= 5;
    
    // Calculate price range over different periods
    double range3 = MathMax(high0, high1) - MathMin(low0, low1);
    double range10 = 0;
    double highestHigh = iHigh(symbol, PERIOD_M5, iHighest(symbol, PERIOD_M5, MODE_HIGH, 10, 0));
    double lowestLow = iLow(symbol, PERIOD_M5, iLowest(symbol, PERIOD_M5, MODE_LOW, 10, 0));
    range10 = highestHigh - lowestLow;
    
    // Calculate momentum and direction changes
    double momentum3 = close0 - close3;
    double momentum5 = close0 - close5;
    double momentum10 = close0 - close10;
    
    // Count direction changes (choppiness)
    int directionChanges = 0;
    for(int i=1; i<5; i++) {
        if((iClose(symbol, PERIOD_M5, i) > iClose(symbol, PERIOD_M5, i+1) && 
            iClose(symbol, PERIOD_M5, i-1) < iClose(symbol, PERIOD_M5, i)) ||
           (iClose(symbol, PERIOD_M5, i) < iClose(symbol, PERIOD_M5, i+1) && 
            iClose(symbol, PERIOD_M5, i-1) > iClose(symbol, PERIOD_M5, i))) {
            directionChanges++;
        }
    }
    
    // Calculate Bollinger Band width (for range detection)
    double bbUpper = 0, bbLower = 0;
    int bbHandle = iBands(symbol, PERIOD_M5, 20, 2.0, 0, PRICE_CLOSE);
    if(bbHandle != INVALID_HANDLE) {
        double upperBuffer[], lowerBuffer[];
        ArraySetAsSeries(upperBuffer, true);
        ArraySetAsSeries(lowerBuffer, true);
        
        // Copy upper band (band 1)
        if(CopyBuffer(bbHandle, 1, 0, 1, upperBuffer) > 0) {
            bbUpper = upperBuffer[0];
        }
        
        // Copy lower band (band 2)
        if(CopyBuffer(bbHandle, 2, 0, 1, lowerBuffer) > 0) {
            bbLower = lowerBuffer[0];
        }
        
        IndicatorRelease(bbHandle);
    }
    
    double bbWidth = (bbUpper - bbLower) / ma20;
    
    // Check for breakouts
    bool breakoutUp = close0 > bbUpper && close1 <= bbUpper;
    bool breakoutDown = close0 < bbLower && close1 >= bbLower;
    bool insideBands = close0 > bbLower && close0 < bbUpper;
    
    // Check for reversals
    bool potentialReversal = (momentum3 * momentum10 < 0) && MathAbs(momentum3) > quickAtr * 0.3;
    
    // Detect market conditions
    bool isVolatile = quickAtr > avgRange * 1.2;
    bool isVeryVolatile = quickAtr > avgRange * 1.8;
    bool isTrendingUp = ma3 > ma5 && ma5 > ma10 && momentum5 > 0;
    bool isTrendingDown = ma3 < ma5 && ma5 < ma10 && momentum5 < 0;
    bool isChoppy = directionChanges >= 3;
    bool isRangingNarrow = bbWidth < 0.01 && !isVolatile && insideBands;
    bool isRangingWide = bbWidth >= 0.01 && bbWidth < 0.03 && insideBands;
    
    // Determine market regime based on all factors
    int regime = LOW_VOLATILITY; // Default regime
    
    if(breakoutUp || breakoutDown) {
        regime = BREAKOUT;
    }
    else if(potentialReversal) {
        regime = REVERSAL;
    }
    else if(isChoppy) {
        regime = CHOPPY;
    }
    else if(isRangingNarrow) {
        regime = RANGING_NARROW;
    }
    else if(isRangingWide) {
        regime = RANGING_WIDE;
    }
    else if(isTrendingUp && !isVeryVolatile) {
        regime = TRENDING_UP;
    }
    else if(isTrendingDown && !isVeryVolatile) {
        regime = TRENDING_DOWN;
    }
    else if(isVolatile) {
        regime = HIGH_VOLATILITY;
    }
    
    // Update regime stats if regime changed
    if(regime != lastRegime) {
        regimeBarCount = 0;
        lastRegime = regime;
    } else {
        regimeBarCount++;
    }
    
    return regime;
}

//+------------------------------------------------------------------+
//| ATR Helper Function                                              |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Detect liquidity grabs (from original SMC EA)                    |
//+------------------------------------------------------------------+
void DetectLiquidityGrabs() {
   int lookback = MathMin(LookbackBars, Bars(Symbol(), PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   long volume[];
   CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback+2, high);
   CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback+2, low);
   CopyOpen(Symbol(), PERIOD_CURRENT, 0, lookback+2, open);
   CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback+2, close);
   CopyTime(Symbol(), PERIOD_CURRENT, 0, lookback+2, time);
   CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, lookback+2, volume);
   for(int i = 1; i < lookback; i++) {
      double prevHigh = high[i+1];
      double prevLow = low[i+1];
      double currHigh = high[i];
      double currLow = low[i];
      double wickTop = currHigh - MathMax(open[i], close[i]);
      double wickBottom = MathMin(open[i], close[i]) - currLow;
      if(currLow < prevLow && wickBottom > (0.5 * (currHigh - currLow))) {
         recentGrabs[grabIndex].time = time[i];
         recentGrabs[grabIndex].high = currHigh;
         recentGrabs[grabIndex].low = currLow;
         recentGrabs[grabIndex].bullish = true;
         recentGrabs[grabIndex].active = true;
         grabIndex = (grabIndex + 1) % MAX_GRABS;
      }
      if(currHigh > prevHigh && wickTop > (0.5 * (currHigh - currLow))) {
         recentGrabs[grabIndex].time = time[i];
         recentGrabs[grabIndex].high = currHigh;
         recentGrabs[grabIndex].low = currLow;
         recentGrabs[grabIndex].bullish = false;
         recentGrabs[grabIndex].active = true;
         grabIndex = (grabIndex + 1) % MAX_GRABS;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect fair value gaps (from original SMC EA)                    |
//+------------------------------------------------------------------+
void DetectFairValueGaps() {
   int lookback = MathMin(500, Bars(Symbol(), PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback+3, high);
   CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback+3, low);
   CopyOpen(Symbol(), PERIOD_CURRENT, 0, lookback+3, open);
   CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback+3, close);
   CopyTime(Symbol(), PERIOD_CURRENT, 0, lookback+3, time);
   for(int i = 2; i < lookback; i++) {
      double prevHigh = high[i];
      double prevLow = low[i];
      double nextLow = low[i-2];
      double nextHigh = high[i-2];
      if(nextLow - prevHigh > FVGMinSize * _Point) {
         recentFVGs[fvgIndex].startTime = time[i];
         recentFVGs[fvgIndex].endTime = time[i-2];
         recentFVGs[fvgIndex].high = nextLow;
         recentFVGs[fvgIndex].low = prevHigh;
         recentFVGs[fvgIndex].bullish = true;
         recentFVGs[fvgIndex].active = true;
         fvgIndex = (fvgIndex + 1) % MAX_FVGS;
      }
      if(prevLow - nextHigh > FVGMinSize * _Point) {
         recentFVGs[fvgIndex].startTime = time[i];
         recentFVGs[fvgIndex].endTime = time[i-2];
         recentFVGs[fvgIndex].high = prevLow;
         recentFVGs[fvgIndex].low = nextHigh;
         recentFVGs[fvgIndex].bullish = false;
         recentFVGs[fvgIndex].active = true;
         fvgIndex = (fvgIndex + 1) % MAX_FVGS;
      }
   }
}

//+------------------------------------------------------------------+
//| Simple MA calculation for arrays                                 |
//+------------------------------------------------------------------+
void SimpleMAOnArray(const long &src[], int total, int period, double &dst[]) {
   for(int i=0; i<total; i++) {
      double sum = 0;
      int count = 0;
      for(int j=0; j<period && (i+j)<total; j++) {
         sum += (double)src[i+j]; // Explicit cast from long to double
         count++;
      }
      dst[i] = (count>0) ? sum/count : 0;
   }
}

//+------------------------------------------------------------------+
//| Detect order blocks (from original SMC EA with enhancements)     |
//+------------------------------------------------------------------+
void DetectOrderBlocks() {
    int detectedBlocks = 0;
   int lookback = MathMin(500, Bars(Symbol(), PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   long volume[];
   CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback+3, high);
   CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback+3, low);
   CopyOpen(Symbol(), PERIOD_CURRENT, 0, lookback+3, open);
   CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback+3, close);
   CopyTime(Symbol(), PERIOD_CURRENT, 0, lookback+3, time);
   CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, lookback+3, volume);
   int ma_period = 20;
   double volMA[];
   ArrayResize(volMA, lookback+3);
   SimpleMAOnArray(volume, lookback+3, ma_period, volMA);
   for(int i = 2; i < lookback-2; i++) {
      bool swingHigh = high[i] > high[i-1] && high[i] > high[i+1];
      bool swingLow = low[i] < low[i-1] && low[i] < low[i+1];
      if(swingHigh || swingLow) {
         // Enhanced: Require minimum body size and volume
         double minBody = (high[i] - low[i]) * 0.15;
         // Aggressive: relax body size and volume filters for testing
         // if(MathAbs(open[i] - close[i]) < minBody) continue;
         // if(volume[i] < volMA[i]) continue;
         if(DisplayDebugInfo) Print("[DEBUG][Aggressive] Block candidate: i=",i," body=",MathAbs(open[i]-close[i])," minBody=",minBody, " vol=",volume[i], " volMA=",volMA[i]);
         recentBlocks[blockIndex].blockTime = time[i];
         recentBlocks[blockIndex].priceLevel = swingHigh ? high[i] : low[i];
         recentBlocks[blockIndex].highPrice = high[i];
         recentBlocks[blockIndex].lowPrice = low[i];
         recentBlocks[blockIndex].bullish = swingLow;
         recentBlocks[blockIndex].valid = true;
         detectedBlocks++;
         long vol = volume[i];
         double body = MathAbs(open[i] - close[i]);
         int score = 0;
         if(vol > volMA[i]) score++;
         if(body < (high[i] - low[i]) * 0.5) score++;
         if(UseLiquidityGrab && swingLow && recentGrabs[(grabIndex-1+MAX_GRABS)%MAX_GRABS].active) score++;
         if(UseImbalanceFVG && recentFVGs[(fvgIndex-1+MAX_FVGS)%MAX_FVGS].active) score++;
         
         // Advanced scoring based on market regime
         if(EnableMarketRegimeFiltering && currentRegime >= 0) {
            // In trending markets, give higher score to blocks aligned with trend
            if(currentRegime == TRENDING_UP && swingLow) score++;
            if(currentRegime == TRENDING_DOWN && swingHigh) score++;
            
            // In ranging markets, give higher score to blocks at range boundaries
            if((currentRegime == RANGING_NARROW || currentRegime == RANGING_WIDE) && 
               (recentBlocks[blockIndex].priceLevel == MathMin(high[i], high[i-1]) || 
                recentBlocks[blockIndex].priceLevel == MathMax(low[i], low[i-1]))) {
               score++;
            }
            
            // In high volatility, require stronger confirmation
            if(currentRegime == HIGH_VOLATILITY && vol > volMA[i] * 1.5) score++;
            
            // In breakouts, give higher scores to blocks after the breakout
            if(currentRegime == BREAKOUT && i >= 3) {
               bool breakoutUp = close[i-1] > close[i-2] && close[i-2] > close[i-3] && close[i-1] - close[i-3] > GetATR(Symbol(), PERIOD_CURRENT, 14, i-1);
               bool breakoutDown = close[i-1] < close[i-2] && close[i-2] < close[i-3] && close[i-3] - close[i-1] > GetATR(Symbol(), PERIOD_CURRENT, 14, i-1);
               
               if(swingLow && breakoutUp) score++;
               if(swingHigh && breakoutDown) score++;
            }
         }
         
         recentBlocks[blockIndex].strength = score;
         if(DisplayDebugInfo) {
            Print("[SMC] OrderBlock detected: ", (swingLow ? "Bullish" : "Bearish"),
                  " | Price=", DoubleToString(recentBlocks[blockIndex].priceLevel, _Digits),
                  " | Score=", score);
         }
         blockIndex = (blockIndex + 1) % MAX_BLOCKS;
      }
   }
   if(DisplayDebugInfo) {
       Print("[DEBUG] Order Block Scan - Analyzing ", lookback, " bars with strength threshold ", MinBlockStrength);
   }
}

//+------------------------------------------------------------------+
//| Validate supply and demand zones                                |
//+------------------------------------------------------------------+
void ValidateSupplyDemandZones() {
   int confirmedZones = 0;
   double low[], high[];
   CopyLow(Symbol(), PERIOD_CURRENT, 0, 1, low);
   CopyHigh(Symbol(), PERIOD_CURRENT, 0, 1, high);
   for(int i = 0; i < MAX_BLOCKS; i++) {
      if(!recentBlocks[i].valid) continue;
      // Enhanced: Require close beyond for confirmation
      if(recentBlocks[i].bullish) {
         if(low[0] > recentBlocks[i].lowPrice && iClose(Symbol(), PERIOD_CURRENT, 0) > recentBlocks[i].lowPrice) {
            if(!recentBlocks[i].hasSDConfirm) {
                recentBlocks[i].hasSDConfirm = true;
                confirmedZones++;
                if(DisplayDebugInfo) Print("[SMC] Bullish SD zone confirmed at ", DoubleToString(recentBlocks[i].lowPrice, _Digits));
            }
         }
      } else {
         if(high[0] < recentBlocks[i].highPrice && iClose(Symbol(), PERIOD_CURRENT, 0) < recentBlocks[i].highPrice) {
            if(!recentBlocks[i].hasSDConfirm) {
                recentBlocks[i].hasSDConfirm = true;
                confirmedZones++;
                if(DisplayDebugInfo) Print("[SMC] Bearish SD zone confirmed at ", DoubleToString(recentBlocks[i].highPrice, _Digits));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get trading signal with regime-based filtering                   |
//+------------------------------------------------------------------+
int GetTradingSignal() {
    // --- M5 Trend Logic (for multi-timeframe alignment) ---
    double ma3_M5 = 0, ma5_M5 = 0, ma10_M5 = 0;
    for(int i=0; i<3; i++) ma3_M5 += iClose(Symbol(), PERIOD_M5, i);
    for(int i=0; i<5; i++) ma5_M5 += iClose(Symbol(), PERIOD_M5, i);
    for(int i=0; i<10; i++) ma10_M5 += iClose(Symbol(), PERIOD_M5, i);
    ma3_M5 /= 3;
    ma5_M5 /= 5;
    ma10_M5 /= 10;
    bool isTrendingUp = (ma3_M5 > ma5_M5 && ma5_M5 > ma10_M5);
    bool isTrendingDown = (ma3_M5 < ma5_M5 && ma5_M5 < ma10_M5);
    // --- Multi-Timeframe Confirmation ---
    // Detect trend on H1 timeframe
    double ma3_H1 = 0, ma5_H1 = 0, ma10_H1 = 0;
    for(int i=0; i<3; i++) ma3_H1 += iClose(Symbol(), PERIOD_H1, i);
    for(int i=0; i<5; i++) ma5_H1 += iClose(Symbol(), PERIOD_H1, i);
    for(int i=0; i<10; i++) ma10_H1 += iClose(Symbol(), PERIOD_H1, i);
    ma3_H1 /= 3;
    ma5_H1 /= 5;
    ma10_H1 /= 10;
    
    bool H1Bullish = (ma3_H1 > ma5_H1 && ma5_H1 > ma10_H1);
    bool H1Bearish = (ma3_H1 < ma5_H1 && ma5_H1 < ma10_H1);
    // --- End Multi-Timeframe Confirmation ---

    int potentialSignal = 0; // Declare at start
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double fibLevels[5];
    CalculateFibonacciLevels(fibLevels);

    if(currentPrice >= fibLevels[3] && currentPrice <= fibLevels[4]) {
        if(potentialSignal != 0) potentialSignal = (int)(potentialSignal * 1.3); // Only boost if nonzero
    }

    // 1. Volatility filter: ATR must be above threshold
    double atr = GetATR(Symbol(), ExecutionTimeframe, 14, 0);
    if(atr < workingATRThreshold) {
        if(DisplayDebugInfo) Print("[SMC] GetTradingSignal: ATR (", atr, ") below threshold (", workingATRThreshold, "). No signal.");
        return 0;
    }
    
    // 2. Emergency mode or consecutive losses
    if(emergencyMode || consecutiveLosses >= MaxConsecutiveLosses) {
        Print("[SMC] GetTradingSignal: Too many consecutive losses (", consecutiveLosses, ") or emergency mode. No signal.");
        return 0;
    }
    
    // 2.5. Cooldown check: Show seconds remaining
    if(TimeCurrent() - lastTradeTime < SignalCooldownSeconds) {
        int secondsRemaining = SignalCooldownSeconds - (int)(TimeCurrent() - lastTradeTime);
        if(DisplayDebugInfo) Print("[SMC] GetTradingSignal: Cooldown period active. Seconds remaining: ", secondsRemaining);
        return 0;
    }
    // 3. Check if session allows trading
    if(EnableSessionFiltering) {
        bool sessionAllowed = false;
        
        switch(currentSession) {
            case SESSION_ASIA:
                sessionAllowed = TradeAsianSession;
                break;
            case SESSION_EUROPE:
                sessionAllowed = TradeEuropeanSession;
                break;
            case SESSION_AMERICA:
                sessionAllowed = TradeAmericanSession;
                break;
            case SESSION_ASIA_EUROPE_OVERLAP:
            case SESSION_EUROPE_AMERICA_OVERLAP:
                sessionAllowed = TradeSessionOverlaps;
                break;
            default:
                sessionAllowed = true; // Allow trading in unrecognized sessions
        }
        
        if(!sessionAllowed) {
            if(DisplayDebugInfo) Print("[SMC] GetTradingSignal: Trading not allowed in current session");
            return 0;
        }
    }
    
    // Multi-Timeframe Filtering (M5 trend logic must already exist above)
    // Only allow buys if both M5 and H1 are bullish, sells if both are bearish
    // isTrendingUp/isTrendingDown should already be defined above
    if((isTrendingUp && !H1Bullish) || (isTrendingDown && !H1Bearish)) {
        if(DisplayDebugInfo) Print("[SMC] Multi-timeframe filter: M5 and H1 not aligned. No signal.");
        return 0;
    }

    int bestBlock = -1;
    int bestScore = 0;
    if(DisplayDebugInfo) {
        for(int i = 0; i < MAX_BLOCKS; i++) {
            if(recentBlocks[i].valid) {
                Print("[DEBUG] Block ", i, ": strength=", recentBlocks[i].strength, ", bullish=", recentBlocks[i].bullish);
            }
        }
    }
    
    for(int i = 0; i < MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid && recentBlocks[i].strength >= MinBlockStrength) {
            if(recentBlocks[i].strength > bestScore || bestBlock == -1) {
                bestScore = recentBlocks[i].strength;
                bestBlock = i;
            }
        }
    }
    
    if(bestBlock == -1) {
        if(DisplayDebugInfo) Print("[SMC] No valid order block found. No signal.");
        return 0;
    }
    
    // 4. Determine potential signal based on best order block
    potentialSignal = recentBlocks[bestBlock].bullish ? 1 : -1; // Use existing variable
    
    // 5. Check for divergence confirmation
    if(EnableDivergenceFilter) {
        // Check if there's a divergence that matches our signal direction
        if(DisplayDebugInfo) {
            Print("[SMC] Checking for divergence to confirm signal direction: ", potentialSignal);
        }
        
        DivergenceInfo divInfo;
        bool hasDivergence = CheckForDivergence(potentialSignal, divInfo);
        
        // 5.1 For enhanced signal quality, we can either:
        // a) Require divergence for trade entry (strict)
        // b) Use divergence as a signal booster only (flexible)
        
        if(hasDivergence) {
            // Store the divergence information for position sizing in ExecuteTrade
            lastDivergence = divInfo;
            
            if(DisplayDebugInfo) {
                string divType = "";
                switch(divInfo.type) {
                    case DIVERGENCE_REGULAR_BULL: divType = "Regular Bullish"; break;
                    case DIVERGENCE_REGULAR_BEAR: divType = "Regular Bearish"; break;
                    case DIVERGENCE_HIDDEN_BULL: divType = "Hidden Bullish"; break;
                    case DIVERGENCE_HIDDEN_BEAR: divType = "Hidden Bearish"; break;
                }
                
                Print("[SMC] Divergence confirmed! Type: ", divType, ", Strength: ", 
                    DoubleToString(divInfo.strength, 2), ". Signal quality enhanced.");
            }
            
            // Strong divergence with good block - excellent entry
            if(divInfo.strength > 0.8 && bestScore >= MinBlockStrength + 1) {
                if(DisplayDebugInfo) Print("[SMC] High-quality signal with strong divergence!");
            }
        } else {
            // No divergence found - could still trade, but note the lack of confirmation
            if(DisplayDebugInfo) {
                Print("[SMC] No divergence found to confirm signal. Proceeding with standard signal quality.");
            }
        }
    }
    
    // Apply ML-like signal quality evaluation if enabled
    if(EnableSignalQualityML && potentialSignal != 0) {
        double signalQuality = CalculateSignalQuality(potentialSignal);
        
        // Only trade if signal quality meets minimum threshold
        if(signalQuality < MinSignalQualityToTrade) {
            if(DisplayDebugInfo) Print("[SMC] Signal filtered out due to low quality score: ", 
                                       DoubleToString(signalQuality, 2), " (minimum: ", 
                                       DoubleToString(MinSignalQualityToTrade, 2), ")");
            return 0;
        } else {
            if(DisplayDebugInfo) Print("[SMC] High quality signal detected: ", 
                                       DoubleToString(signalQuality, 2), " (direction: ", 
                                       (potentialSignal > 0 ? "BUY" : "SELL"), ")");
        }
    }
    
    // Return final signal
    if(recentBlocks[bestBlock].bullish) {
        if(DisplayDebugInfo) {
            Print("[SMC] Buy signal generated. BlockScore=", bestScore, 
                  (lastDivergence.found ? ", Divergence Confirmed" : ""));
        }
        return 1;
    } else {
        if(DisplayDebugInfo) {
            Print("[SMC] Sell signal generated. BlockScore=", bestScore, 
                  (lastDivergence.found ? ", Divergence Confirmed" : ""));
        }
        return -1;
    }
    
    // Return the final signal
    return potentialSignal;
}

//+------------------------------------------------------------------+
//| Modify stops when Change of Character (CHOCH) is detected        |
//+------------------------------------------------------------------+
void ModifyStopsOnCHOCH() {
    for(int i=0; i<PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            double newSL = PositionGetDouble(POSITION_SL) * 0.8;
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
    }
}

//+------------------------------------------------------------------+
//| Dummy news filter function                                       |
//+------------------------------------------------------------------+
bool IsHighImpactNewsTime() { 
   return false; // Placeholder - implement news filter if needed
}

//+------------------------------------------------------------------+
//| Bollinger Bands helper function                                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Advanced Trade Execution with Fixed Pips for SL/TP               |
//+------------------------------------------------------------------+
bool ExecuteTrade(int signal) {
    if(!CanTrade()) { 
        if(DisplayDebugInfo) Print("[SMC] ExecuteTrade: CanTrade returned false"); 
        return false; 
    }
    
    // Calculate position size
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double riskAmount = balance * RiskPercent / 100.0;
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double priceDiff = SL_Pips * point;
    double ticksPerPoint = 1.0 / point;
    double pointValue = tickValue * ticksPerPoint;
    double positionSizeInLots = riskAmount / (priceDiff * pointValue);
    
    // Round lot size to valid value
    positionSizeInLots = MathMax(minLot, MathMin(maxLot, MathFloor(positionSizeInLots/lotStep)*lotStep));
    double lot2 = 0.0; // Declare lot2 variable
    
    // Get current price for buy/sell
    double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double currentPrice = (signal > 0) ? currentAsk : currentBid;
    
    // Calculate SL/TP levels based on fixed pips
    double slPrice = (signal > 0) ? currentPrice - SL_Pips * point : currentPrice + SL_Pips * point;
    double tpPrice = (signal > 0) ? currentPrice + TP_Pips * point : currentPrice - TP_Pips * point;
    
    if(slPrice <= 0 || tpPrice <= 0) { 
        Print("[SMC] ExecuteTrade: Invalid SL/TP"); 
        lastErrorMessage = "Invalid SL/TP"; 
        return false; 
    }
    
    if(DisplayDebugInfo) {
        Print("[SMC] ExecuteTrade: Attempting ", (signal > 0 ? "BUY" : "SELL"), 
              " Size: ", DoubleToString(positionSizeInLots, 2), 
              " Entry: ", DoubleToString(currentPrice, _Digits), 
              " SL: ", DoubleToString(slPrice, _Digits), 
              " TP: ", DoubleToString(tpPrice, _Digits));
    }
    
    // Execute trade with retry logic
    bool result = false;
    int retryCount = 0;
    double entryPrice = 0.0; // Declare entryPrice
    trade.SetDeviationInPoints(AdaptiveSlippagePoints);
    double execStart = (double)GetMicrosecondCount();

    // --- Regime Learning & News Filter: Block or reduce trade as needed ---
    int regime = currentRegime;
    if(regime >= 0) {
        // Block if regime is underperforming
        if(regimeBlocked[regime]) {
            if(DisplayDebugInfo) Print("[SMC] Trade blocked: regime underperforming (", regime, ")");
            lastMissedTradeReason = "Regime underperforming";
            return false;
        }
    }
    // News filter: Block or reduce size
    LoadNewsEvents();
    if(EnableNewsFilter && IsHighImpactNewsWindow()) {
        if(BlockHighImpactNews) {
            if(DisplayDebugInfo) Print("[SMC] Trade blocked: high-impact news event");
            lastMissedTradeReason = "High-impact news";
            return false;
        }
    }
    double newsSizeRed = EnableNewsFilter ? GetNewsSizeReduction() : 1.0;
    double regimeRiskRed = (regime >= 0) ? regimeRiskFactor[regime] : 1.0;
    positionSizeInLots *= newsSizeRed * regimeRiskRed;
    
    while(retryCount < FastExecution_MaxRetries) {
        // --- Broker Compliance: Validate SL/TP and lot size before sending order ---
        double minStopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
        double validSL = slPrice;
        double validTP = tpPrice;
        // Ensure SL/TP distance is valid
        if(signal > 0) {
            if(currentPrice - slPrice < minStopLevel) validSL = currentPrice - minStopLevel;
            if(tpPrice - currentPrice < minStopLevel) validTP = currentPrice + minStopLevel;
        } else {
            if(slPrice - currentPrice < minStopLevel) validSL = currentPrice + minStopLevel;
            if(currentPrice - tpPrice < minStopLevel) validTP = currentPrice - minStopLevel;
        }
        // Ensure lot size is valid
        double validLot = MathMax(minLot, MathMin(maxLot, MathFloor(positionSizeInLots/lotStep)*lotStep));
        if(signal > 0) {
            result = trade.Buy(validLot, Symbol(), 0, validSL, validTP, "SMC Buy");
            entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        } else {
            result = trade.Sell(validLot, Symbol(), 0, validSL, validTP, "SMC Sell");
            entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        }
        
        if(result) {
            // Trade successful, exit the loop
            break;
        }
        
        // If trade failed, get error and decide whether to retry
        int errorCode = GetLastError();
        
        // Critical errors - stop retrying
        if(errorCode == ERR_NOT_ENOUGH_MONEY || errorCode == ERR_TRADE_DISABLED) {
            Print("[SMC] ExecuteTrade: Critical error ", errorCode, ": ", ErrorDescription(errorCode), ". Stopping retries.");
            break;
        }
        
        // Non-critical errors - retry after a brief delay
        if(retryCount < FastExecution_MaxRetries - 1) { // Only sleep if not the last attempt
            Print("[SMC] ExecuteTrade: Retry ", retryCount + 1, "/", FastExecution_MaxRetries, 
                  " after error: ", errorCode, " - ", ErrorDescription(errorCode));
            Sleep(100); // Wait 100ms before retry
        }
        
        retryCount++;
    }
    
    double execEnd = (double)GetMicrosecondCount();
    double execTime = (execEnd - execStart) / 1000000.0; // seconds

    // --- LOGGING: Log slippage and execution time ---
    double actualPrice = 0.0;
    double thisTradeSlippage = 0.0;
    if(PositionSelect(Symbol())) {
        actualPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        thisTradeSlippage = MathAbs(actualPrice - entryPrice) / point;
        lastTradeSlippage = thisTradeSlippage;
        if(DisplayDebugInfo) Print("[SMC] ExecuteTrade: Order executed with slippage: ", DoubleToString(thisTradeSlippage, 1), " points, ExecTime: ", DoubleToString(execTime, 3), "s");
        // Log to file
        int fh = FileOpen("SMC_TradeLatencyLog.csv", FILE_WRITE|FILE_READ|FILE_SHARE_READ|FILE_SHARE_WRITE);
        if(fh != INVALID_HANDLE) {
            FileSeek(fh, 0, SEEK_END);
            string logLine = TimeToString(TimeCurrent())+","+DoubleToString(thisTradeSlippage, 2)+","+DoubleToString(execTime, 3)+"\r\n";
            FileWriteString(fh, logLine, StringLen(logLine));
            FileClose(fh);
        }
    }
    // --- Adaptive Slippage: If high latency or slippage, increase allowed slippage ---
    if(execTime > HighLatencyThreshold || lastTradeSlippage > HighSlippageThreshold) {
        AdaptiveSlippagePoints = MathMin(MaxAllowedSlippagePoints, AdaptiveSlippagePoints + 5);
        if(DisplayDebugInfo) Print("[SMC] High latency/slippage detected. Adaptive slippage increased to ", AdaptiveSlippagePoints, " points.");
    } else if(AdaptiveSlippagePoints > SlippagePoints && execTime < HighLatencyThreshold*0.7 && lastTradeSlippage < HighSlippageThreshold*0.7) {
        AdaptiveSlippagePoints = MathMax(SlippagePoints, AdaptiveSlippagePoints - 2); // Gradually reduce if stable
    }
    
    if(result) {    
        if(DisplayDebugInfo) Print("[SMC] ExecuteTrade: Order placed successfully");
        lastTradeTime = TimeCurrent();
    } else {
        int errorCode = GetLastError();
        Print("[SMC] ExecuteTrade: Order failed! Error: ", errorCode, " - ", ErrorDescription(errorCode));
    }
    
    return result;  // Make sure we return the result in all paths
}

//+------------------------------------------------------------------+
//| Detect multiple swing points and return quality scores           |
//+------------------------------------------------------------------+
void FindQualitySwingPoints(bool isBuy, int lookbackBars, SwingPoint &swingPoints[], int &count) {
    count = 0;
    double high[], low[], close[], open[], volume[];
    long vol[];
    datetime time[];
    
    int bars = MathMin(lookbackBars, Bars(Symbol(), PERIOD_CURRENT));
    
    if(bars < 10) return; // Not enough bars for proper analysis
    
    ArrayResize(swingPoints, bars); // Pre-allocate max possible size
    
    // Copy necessary price data
    CopyHigh(Symbol(), PERIOD_CURRENT, 0, bars, high);
    CopyLow(Symbol(), PERIOD_CURRENT, 0, bars, low);
    CopyClose(Symbol(), PERIOD_CURRENT, 0, bars, close);
    CopyOpen(Symbol(), PERIOD_CURRENT, 0, bars, open);
    CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, bars, vol);
    CopyTime(Symbol(), PERIOD_CURRENT, 0, bars, time);
    
    // Calculate some indicators for quality scoring
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    double volMA[];
    ArrayResize(volMA, bars);
    SimpleMAOnArray(vol, bars, 20, volMA);
    
    // First pass - find all potential swing points
    for(int i = 3; i < bars - 3; i++) {
        bool isSwingPoint = false;
        double price = 0;
        
        if(isBuy) { // Looking for swing lows for buy stop placement
            // Check if this candle's low is lower than surrounding candles
            if(low[i] < low[i-1] && low[i] < low[i+1] &&
               low[i] < low[i-2] && low[i] < low[i+2]) {
                isSwingPoint = true;
                price = low[i];
            }
        } else { // Looking for swing highs for sell stop placement
            // Check if this candle's high is higher than surrounding candles
            if(high[i] > high[i-1] && high[i] > high[i+1] &&
               high[i] > high[i-2] && high[i] > high[i+2]) {
                isSwingPoint = true;
                price = high[i];
            }
        }
        
        if(isSwingPoint) {
            // Calculate quality score for this swing point
            int score = 0;
            double bodySize = MathAbs(open[i] - close[i]);
            double candleRange = high[i] - low[i];
            
            // Factor 1: Volume spike at the swing point (high volume validates the swing)
            if(vol[i] > volMA[i] * 1.5) score += 3;
            else if(vol[i] > volMA[i] * 1.2) score += 2;
            else if(vol[i] > volMA[i]) score += 1;
            
            // Factor 2: Strong reversal candle at the swing point
            if(bodySize > candleRange * 0.7) score += 2; // Strong body
            
            // Factor 3: Distance from current price (too close is risky, too far may be inefficient)
            double currentPrice = iClose(Symbol(), PERIOD_CURRENT, 0);
            double distanceInATR = MathAbs(currentPrice - price) / atr;
            if(distanceInATR >= 0.5 && distanceInATR <= 1.5) score += 2; // Optimal distance
            else if(distanceInATR > 1.5 && distanceInATR <= 2.5) score += 1; // Still acceptable
            
            // Factor 4: Clear break after the swing (validates the swing's significance)
            bool clearBreak = false;
            if(isBuy) {
                if(close[i-2] > close[i-1] && close[i-1] > close[i] && 
                   close[i+1] > close[i] && close[i+2] > close[i+1]) {
                    clearBreak = true;
                }
            } else {
                if(close[i-2] < close[i-1] && close[i-1] < close[i] && 
                   close[i+1] < close[i] && close[i+2] < close[i+1]) {
                    clearBreak = true;
                }
            }
            if(clearBreak) score += 2;
            
            // Factor 5: Price interaction with this level after swing formation
            bool retested = false;
            for(int j = i-1; j >= 0; j--) {
                if(isBuy && low[j] <= price + (10 * _Point) && low[j] >= price - (10 * _Point)) {
                    retested = true;
                    break;
                } else if(!isBuy && high[j] >= price - (10 * _Point) && high[j] <= price + (10 * _Point)) {
                    retested = true;
                    break;
                }
            }
            if(retested) score += 3; // Tested and respected
            
            // Store the swing point with its score
            swingPoints[count].barIndex = i;
            swingPoints[count].price = price;
            swingPoints[count].score = score;
            swingPoints[count].time = time[i];
            count++;
        }
    }
    
    // Sort swing points by score (highest first)
    if(count > 1) {
        for(int i = 0; i < count-1; i++) {
            for(int j = i+1; j < count; j++) {
                if(swingPoints[j].score > swingPoints[i].score) {
                    // Swap
                    SwingPoint temp = swingPoints[i];
                    swingPoints[i] = swingPoints[j];
                    swingPoints[j] = temp;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Determine optimal stop loss for given conditions                 |
//+------------------------------------------------------------------+
double DetermineOptimalStopLoss(int signal, double entryPrice) {
    // Array to store potential swing points
    SwingPoint swingPoints[];
    int swingCount = 0;
    
    // Get ATR for volatility context
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    
    // Scan for swing points
    FindQualitySwingPoints(signal > 0, 50, swingPoints, swingCount);
    
    // No valid swing points found - use adaptive ATR-based stop
    if(swingCount == 0) {
        double atrMultiplier = 1.0;
        
        // Adjust ATR multiplier based on market regime
        if(EnableMarketRegimeFiltering && currentRegime >= 0) {
            switch(currentRegime) {
                case TRENDING_UP:
                case TRENDING_DOWN:
                    atrMultiplier = 1.2; // Wider stops in trends
                    break;
                    
                case HIGH_VOLATILITY:
                    atrMultiplier = 1.5; // Much wider stops in volatility
                    break;
                    
                case CHOPPY:
                    atrMultiplier = 1.3; // Wider stops in choppy markets
                    break;
                    
                case RANGING_NARROW:
                    atrMultiplier = 0.8; // Tighter stops in narrow ranges
                    break;
                    
                default:
                    atrMultiplier = 1.0;
                    break;
            }
        }
        
        // Calculate ATR-based stop loss
        double stopLoss = signal > 0 ? 
            entryPrice - (atr * atrMultiplier) : 
            entryPrice + (atr * atrMultiplier);
            
        if(DisplayDebugInfo) {
            Print("[SMC] Using ATR-based stop loss: ", stopLoss, " (ATR: ", atr, 
                  ", Mult: ", atrMultiplier, ", Regime: ", currentRegime, ")");
        }
        
        return stopLoss;
    }
    
    // First check for high-quality swing points (score >= 7)
    for(int i = 0; i < swingCount; i++) {
        if(swingPoints[i].score >= 7) {
            double buffer = signal > 0 ? -(5 * _Point) : (5 * _Point);
            double stopLoss = swingPoints[i].price + buffer;
            
            // Check if the distance is reasonable (0.5-2.5 ATR)
            double stopDistance = MathAbs(entryPrice - stopLoss);
            if(stopDistance >= atr * 0.5 && stopDistance <= atr * 2.5) {
                if(DisplayDebugInfo) {
                    Print("[SMC] Using high-quality swing point stop: ", stopLoss, 
                          " (Score: ", swingPoints[i].score, ", Bar: ", swingPoints[i].barIndex, ")");
                }
                return stopLoss;
            }
        }
    }
    
    // If no high-quality point with reasonable distance, consider medium quality (score >= 4)
    double bestStopLoss = 0;
    double optimalDistance = atr * 1.0; // Target 1 ATR distance
    double bestDistanceDiff = 999999;
    
    for(int i = 0; i < swingCount; i++) {
        if(swingPoints[i].score >= 4) {
            double buffer = signal > 0 ? -(5 * _Point) : (5 * _Point);
            double stopLoss = swingPoints[i].price + buffer;
            double stopDistance = MathAbs(entryPrice - stopLoss);
            double distanceDiff = MathAbs(stopDistance - optimalDistance);
            
            // Find the stop that's closest to our optimal distance
            if(distanceDiff < bestDistanceDiff) {
                bestDistanceDiff = distanceDiff;
                bestStopLoss = stopLoss;
            }
        }
    }
    
    // If we found a decent stop loss
    if(bestStopLoss != 0) {
        if(DisplayDebugInfo) {
            Print("[SMC] Using medium-quality swing stop: ", bestStopLoss);
        }
        return bestStopLoss;
    }
    
    // Fallback: use any swing point with reasonable distance
    double nearestSwingStop = 0;
    bestDistanceDiff = 999999;
    
    for(int i = 0; i < swingCount; i++) {
        double buffer = signal > 0 ? -(5 * _Point) : (5 * _Point);
        double stopLoss = swingPoints[i].price + buffer;
        double stopDistance = MathAbs(entryPrice - stopLoss);
        
        if(stopDistance >= atr * 0.5 && stopDistance <= atr * 2.5) {
            double distanceDiff = MathAbs(stopDistance - optimalDistance);
            if(distanceDiff < bestDistanceDiff) {
                bestDistanceDiff = distanceDiff;
                nearestSwingStop = stopLoss;
            }
        }
    }
    
    if(nearestSwingStop != 0) {
        if(DisplayDebugInfo) {
            Print("[SMC] Using nearest swing stop: ", nearestSwingStop);
        }
        return nearestSwingStop;
    }
    
    // Last resort: fixed ATR stop
    double defaultStop = signal > 0 ? 
        entryPrice - (atr * 1.0) : 
        entryPrice + (atr * 1.0);
        
    if(DisplayDebugInfo) {
        Print("[SMC] Using default ATR stop: ", defaultStop);
    }
    
    return defaultStop;
}

//+------------------------------------------------------------------+
//| Calculate Kelly/Optimal F fraction using rolling stats          |
//+------------------------------------------------------------------+
double CalculateKellyFraction() {
    int wins = 0, losses = 0;
    double avgWin = 0, avgLoss = 0;
    double winRate = 0.5;
    for(int i=0; i<METRIC_WINDOW; i++) {
        double p = tradeProfits[i];
        if(p > 0) { avgWin += p; wins++; }
        if(p < 0) { avgLoss += p; losses++; }
    }
    avgWin = (wins > 0) ? avgWin/wins : 0.0;
    avgLoss = (losses > 0) ? avgLoss/losses : 0.0;
    winRate = (wins+losses > 0) ? (double)wins/(wins+losses) : 0.5;
    double b = (avgLoss != 0) ? MathAbs(avgWin/avgLoss) : 1.0;
    double q = 1.0 - winRate;
    double kelly = (b*winRate - q) / b;
    if(kelly < 0) kelly = 0.01;
    kelly = MathMin(MaxKellyFraction, kelly);
    return kelly;
}

//+------------------------------------------------------------------+
//| Calculate Optimal F using rolling stats                         |
//+------------------------------------------------------------------+
double CalculateOptimalF() {
    double maxWin = 0, maxLoss = 0;
    for(int i=0; i<METRIC_WINDOW; i++) {
        if(tradeProfits[i]>maxWin) maxWin = tradeProfits[i];
        if(tradeProfits[i]<maxLoss) maxLoss = tradeProfits[i];
    }
    double f = (maxWin > 0 && maxLoss < 0) ? 0.5 * (maxWin/(-maxLoss)) : 0.01;
    f = MathMin(MaxKellyFraction, f);
    if(f < 0.01) f = 0.01;
    return f;
}

//+------------------------------------------------------------------+
//| Portfolio Risk Cap: Block trades if total open risk too high     |
//+------------------------------------------------------------------+
bool IsPortfolioRiskWithinCap() {
    double totalRisk = 0.0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    for(int i=0; i<PositionsTotal(); i++) {
        if(PositionGetSymbol(i)==Symbol()) {
            double posVolume = PositionGetDouble(POSITION_VOLUME);
            double posSL = PositionGetDouble(POSITION_SL);
            double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double riskPerLot = MathAbs(posPrice-posSL);
            double tickValue = SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_VALUE);
            double point = SymbolInfoDouble(Symbol(),SYMBOL_POINT);
            double risk = (riskPerLot/point)*tickValue*posVolume;
            totalRisk += risk;
        }
    }
    double riskPct = (totalRisk/balance)*100.0;
    if(riskPct > MaxPortfolioRiskPercent) {
        if(DisplayDebugInfo) Print("[SMC] Portfolio risk cap exceeded: ", DoubleToString(riskPct,2), "% > ", MaxPortfolioRiskPercent, "%");
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Calculate adaptive position size based on volatility            |
//+------------------------------------------------------------------+
double CalculateAdaptivePositionSize(double baseSize, double atr) {
    // If adaptive risk is not enabled, return the base size
    if(!EnableAdaptiveRisk) return baseSize;
    
    // Calculate average ATR over last 20 periods to determine relative volatility
    double avgAtr = 0;
    int validAtrCount = 0;
    
    for(int i=0; i<20; i++) {
        double periodAtr = GetATR(Symbol(), ExecutionTimeframe, 14, i);
        if(periodAtr > 0) {
            avgAtr += periodAtr;
            validAtrCount++;
        }
    }
    
    // Avoid division by zero
    if(validAtrCount == 0) return baseSize;
    
    avgAtr /= validAtrCount;
    double volatilityRatio = atr / avgAtr;
    double adaptiveSize = baseSize * VolatilityMultiplier;
    
    // Increase position size in low volatility conditions
    if(volatilityRatio < 0.8) {
        adaptiveSize *= LowVolatilityBonus;
        if(DisplayDebugInfo) Print("[SMC] Low volatility detected, increasing position size by ", 
                                  DoubleToString(LowVolatilityBonus, 2), "x");
    }
    // Decrease position size in high volatility conditions
    else if(volatilityRatio > 1.2) {
        adaptiveSize *= HighVolatilityReduction;
        if(DisplayDebugInfo) Print("[SMC] High volatility detected, reducing position size by ", 
                                  DoubleToString(HighVolatilityReduction, 2), "x");
    }
    
    // Adjust based on market regime if available
    if(EnableMarketRegimeFiltering && currentRegime >= 0) {
        // Calculate regime-specific adjustment
        double regimeMultiplier = 1.0;
        
        switch(currentRegime) {
            case TRENDING_UP:
            case TRENDING_DOWN:
                // In trending markets, we can be more aggressive
                regimeMultiplier = 1.1;
                break;
                    
            case CHOPPY:
                // In choppy markets, be more conservative
                regimeMultiplier = 0.9;
                break;
            case HIGH_VOLATILITY:
                // In high volatility, reduce position size further
                regimeMultiplier = 0.8;
                break;
            case RANGING_NARROW:
                // In narrow ranges, we can be more aggressive
                regimeMultiplier = 1.2;
                break;
        }
        
        adaptiveSize *= regimeMultiplier;
        if(DisplayDebugInfo && regimeMultiplier != 1.0) {
            Print("[SMC] Regime-based position adjustment: ", DoubleToString(regimeMultiplier, 2), "x");
        }
    }
    
    // Apply win/loss streak adjustments
    if(winStreak >= 3) {
        // After 3+ consecutive wins, slightly increase position size
        double streakMultiplier = 1.0 + (MathMin(winStreak, 5) * 0.05);
        adaptiveSize *= streakMultiplier;
        if(DisplayDebugInfo) Print("[SMC] Win streak of ", winStreak, ", increasing position by ", 
                                  DoubleToString(streakMultiplier, 2), "x");
    } else if(lossStreak >= 2) {
        // After 2+ consecutive losses, reduce position size
        double streakMultiplier = 1.0 - (MathMin(lossStreak, 3) * 0.1);
        adaptiveSize *= streakMultiplier;
        if(DisplayDebugInfo) Print("[SMC] Loss streak of ", lossStreak, ", reducing position by ", 
                                  DoubleToString(streakMultiplier, 2), "x");
    }
    
    // Apply divergence-based position sizing boost
    if(UseDivergenceBooster && lastDivergence.found) {
        // Only boost position size if the divergence is recent (within last 3 bars)
        if(TimeCurrent() - lastDivergence.timeDetected < PeriodSeconds(PERIOD_CURRENT) * 3) {
            // Scale the boost multiplier based on divergence strength
            double divBoostFactor = DivergenceBoostMultiplier * lastDivergence.strength;
            
            // Apply the boost
            adaptiveSize *= divBoostFactor;
            
            if(DisplayDebugInfo) {
                string divType = "";
                switch(lastDivergence.type) {
                    case DIVERGENCE_REGULAR_BULL: divType = "Regular Bullish"; break;
                    case DIVERGENCE_REGULAR_BEAR: divType = "Regular Bearish"; break;
                    case DIVERGENCE_HIDDEN_BULL: divType = "Hidden Bullish"; break;
                    case DIVERGENCE_HIDDEN_BEAR: divType = "Hidden Bearish"; break;
                }
                
                Print("[SMC] Divergence-based position boost: ", DoubleToString(divBoostFactor, 2), 
                      "x (Type: ", divType, ", Strength: ", DoubleToString(lastDivergence.strength, 2), ")");
            }
        }
    }
    
    return adaptiveSize;
}

//+------------------------------------------------------------------+
//| Execute trade with retry logic and partial take-profits         |
//+------------------------------------------------------------------+
bool ExecuteTradeWithRetry(int signal, int maxRetries) {
    if(!CanTrade()) { 
        if(DisplayDebugInfo) Print("[SMC] ExecuteTradeWithRetry: CanTrade returned false"); 
        return false; 
    }
    
    // Reset retry counter for logging
    lastTradeRetryCount = 0;
    
    // --- Portfolio Risk Cap ---
    if(!IsPortfolioRiskWithinCap()) {
        if(DisplayDebugInfo) Print("[SMC] Trade blocked: portfolio risk cap exceeded");
        return false;
    }
    // Calculate position size
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double riskFrac = RiskPercent/100.0;
    if(UseKellySizing) {
        double kelly = CalculateKellyFraction();
        double optF = CalculateOptimalF();
        riskFrac = MathMax(0.001, MathMin(MaxKellyFraction, MathMax(kelly,optF)));
        if(DisplayDebugInfo) Print("[SMC] Kelly/OptimalF risk fraction used: ", DoubleToString(riskFrac*100,2), "%");
    }
    double riskAmount = balance * riskFrac;
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    
    // Get ATR for dynamic SL/TP calculation
    double atr = GetATR(Symbol(), ExecutionTimeframe, 14, 0);
    double slDistance = SL_ATR_Mult * atr;
    double tpDistance = TP_ATR_Mult * atr;
    
    // Ensure minimum distance
    slDistance = MathMax(slDistance, 10 * point);
    
    // Calculate position size based on risk and SL distance
    double ticksPerPoint = 1.0 / point;
    double pointValue = tickValue * ticksPerPoint;
    double basePositionSize = riskAmount / (slDistance * pointValue);
    
    // Apply adaptive position sizing based on market conditions
    double positionSizeInLots = EnableAdaptiveRisk ? 
        CalculateAdaptivePositionSize(basePositionSize, atr) : basePositionSize;
    
    // Round lot size to valid value
    positionSizeInLots = MathMax(minLot, MathMin(maxLot, MathFloor(positionSizeInLots/lotStep)*lotStep));
    
    // Prepare for execution with retries
    bool result = false;
    double execStart = (double)GetMicrosecondCount();
    trade.SetDeviationInPoints(SlippagePoints); // Increased slippage tolerance for fast execution
    
    // Execute with retry logic
    for(int attempt = 1; attempt <= maxRetries; attempt++) {
        lastTradeRetryCount = attempt;
        
        // Get fresh prices on each attempt
        double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        double currentPrice = (signal > 0) ? currentAsk : currentBid;
        
        // Calculate SL/TP
        double slPrice = (signal > 0) ? currentPrice - slDistance : currentPrice + slDistance;
        double tpPrice = (signal > 0) ? currentPrice + tpDistance : currentPrice - tpDistance;
        
        // Check if SL/TP are valid
        if(slPrice <= 0 || tpPrice <= 0) { 
            Print("[SMC] ExecuteTradeWithRetry: Invalid SL/TP"); 
            lastErrorMessage = "Invalid SL/TP"; 
            continue; // Try again
        }
        
        // For partial take profits
        if(UsePartialExits) {
            // Simplify: Use a single TP instead of partials to fix compilation errors
            double tpDistance = signal > 0 ? 
                (currentPrice - slPrice) * 2.0 : // 2:1 reward:risk ratio
                (slPrice - currentPrice) * 2.0;
                
            double tpPrice = signal > 0 ?
                currentPrice + tpDistance :
                currentPrice - tpDistance;

            if(DisplayDebugInfo) {
                Print("[SMC] ExecuteTradeWithRetry: ", (signal > 0 ? "BUY" : "SELL"), 
                      " Size: ", DoubleToString(positionSizeInLots, 2), 
                      " Entry: ", DoubleToString(currentPrice, _Digits), " SL: ", DoubleToString(slPrice, _Digits), " TP: ", DoubleToString(tpPrice, _Digits));
            }
            
            // Execute trade with validated lot size
            if(positionSizeInLots >= minLot) {
                if(signal > 0)
                    result = trade.Buy(positionSizeInLots, Symbol(), 0, slPrice, tpPrice, "SMC Buy");
                else
                    result = trade.Sell(positionSizeInLots, Symbol(), 0, slPrice, tpPrice, "SMC Sell");
            }
            
            // If you want to implement partial take-profits, add the code here
            // For now, we'll use a single position with one TP
        } else {
            // Standard execution with single TP
            if(DisplayDebugInfo) {
                Print("[SMC] ExecuteTradeWithRetry (Attempt ", attempt, "): Attempting ", (signal > 0 ? "BUY" : "SELL"), 
                      " Size: ", DoubleToString(positionSizeInLots, 2), 
                      " Entry: ", DoubleToString(currentPrice, _Digits), 
                      " SL: ", DoubleToString(slPrice, _Digits), 
                      " TP: ", DoubleToString(tpPrice, _Digits));
            }
            
            if(signal > 0) {
                result = trade.Buy(positionSizeInLots, Symbol(), 0, slPrice, tpPrice, "SMC Buy");
            } else {
                result = trade.Sell(positionSizeInLots, Symbol(), 0, slPrice, tpPrice, "SMC Sell");
            }
        }
        
        // Check result
        if(result) {
            // Successfully placed order
            break;
        } else {
            // Order failed
            int errorCode = GetLastError();
            lastTradeError = ErrorDescription(errorCode);
            
            // Critical errors - stop retrying
            if(errorCode == ERR_NOT_ENOUGH_MONEY || errorCode == ERR_TRADE_DISABLED) {
                Print("[SMC] ExecuteTradeWithRetry: Critical error ", errorCode, ": ", lastTradeError, ". Stopping retries.");
                break;
            }
            
            // Temporary errors - retry after brief delay
            Print("[SMC] ExecuteTradeWithRetry: Order failed on attempt ", attempt, "/", maxRetries, ". Error: ", errorCode, ": ", lastTradeError);
            
            // Only sleep if we're going to retry
            if(attempt < maxRetries) {
                Sleep(100); // Wait 100ms before retry
            }
        }
    }
    
    double execEnd = (double)GetMicrosecondCount();
    lastTradeExecTime = (execEnd - execStart) / 1000000.0; // Convert to seconds
    
    if(result) {
        // Track execution time statistics
        avgExecutionTime = (avgExecutionTime * executionCount + lastTradeExecTime) / (executionCount + 1);
        executionCount++;
        
        if(DisplayDebugInfo) {
            Print("[SMC] ExecuteTradeWithRetry: Order placed successfully");
            Print("[SMC] Execution time: ", DoubleToString(lastTradeExecTime, 6), "s");
        }
        lastTradeTime = TimeCurrent();
    } else {
        Print("[SMC] ExecuteTradeWithRetry: All attempts failed");
    }
    
    return result;
}


//+------------------------------------------------------------------+
//| Calculate dynamic take profit based on market regime             |
//+------------------------------------------------------------------+
double CalculateDynamicTakeProfit(int signal, double entryPrice, double stopLossPrice) {
    // Calculate base risk in price
    double baseRisk = MathAbs(entryPrice - stopLossPrice);
    
    // Get ATR for volatility measurement
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    
    // Base multiplier - modified by market regime
    double rrMultiplier = 2.0; // Default risk:reward ratio
    
    // Adjust based on market regime
    if(EnableMarketRegimeFiltering && currentRegime >= 0) {
        switch(currentRegime) {
            case TRENDING_UP:
            case TRENDING_DOWN:
                rrMultiplier = 3.0; // Higher targets in trending markets
                break;
                
            case BREAKOUT:
                rrMultiplier = 2.5; // Decent targets in breakouts
                break;
                
            case RANGING_NARROW:
                rrMultiplier = 1.5; // Lower targets in tight ranges
                break;
                
            case RANGING_WIDE:
                rrMultiplier = 2.0; // Standard targets in ranges
                break;
                
            case HIGH_VOLATILITY:
                rrMultiplier = 2.25; // Adjust for volatility
                break;
                
            case CHOPPY:
                rrMultiplier = 1.5; // Conservative in choppy markets
                break;
        }
    }
    
    // Calculate regime accuracy adjustment - increase targets in regimes with high win rates
    if(EnableMarketRegimeFiltering && currentRegime >= 0) {
        int totalRegimeTrades = regimeWins[currentRegime] + regimeLosses[currentRegime];
        if(totalRegimeTrades > 5) {
            // Adjust RR multiplier based on win rate in this regime
            double accuracy = regimeWins[currentRegime] / (double)totalRegimeTrades;
            if(accuracy > 0.6) {
                rrMultiplier *= 1.2; // Increase targets in high-win regimes
            } else if(accuracy < 0.4) {
                rrMultiplier *= 0.8; // Decrease targets in low-win regimes
            }
        }
    }
    
    // Calculate take profit
    double takeProfit = entryPrice;
    if(signal > 0) { // Buy
        takeProfit = entryPrice + (baseRisk * rrMultiplier);
    } else { // Sell
        takeProfit = entryPrice - (baseRisk * rrMultiplier);
    }
    
    // Ensure minimum take profit distance
    double minTakeProfit = signal > 0 ? 
        entryPrice + (15 * _Point) : 
        entryPrice - (15 * _Point);
        
    return signal > 0 ? 
        MathMax(takeProfit, minTakeProfit) : 
        MathMin(takeProfit, minTakeProfit);
}

//+------------------------------------------------------------------+
//| Find recent swing points - Optimized version                     |
//+------------------------------------------------------------------+
int FindRecentSwingPoint(bool isBuy, int startBar = 1, int lookbackBars = 20) {
    // Early exit if parameters are invalid
    if(startBar < 0 || lookbackBars <= 0) return -1;
    
    // Cache values to avoid repeated function calls
    int bars = Bars(Symbol(), PERIOD_CURRENT);
    int maxBar = MathMin(lookbackBars + startBar, bars - 1);
    int swingPointBar = -1;
    double swingValue = isBuy ? 999999 : -999999;
    
    // Pre-calculate tolerance factor once
    double toleranceFactor = SwingTolerancePct / 100.0;
    
    // Pre-fetch price data to avoid repeated API calls
    double lowPrices[], highPrices[];
    CopyLow(Symbol(), PERIOD_CURRENT, 0, maxBar + SwingLookbackBars, lowPrices);
    CopyHigh(Symbol(), PERIOD_CURRENT, 0, maxBar + SwingLookbackBars, highPrices);
    
    // Main loop - optimized to use cached values
    for(int i = startBar; i < maxBar; i++) {
        if(isBuy) { // For buy orders, find swing low
            double low = lowPrices[i];
            bool isSwingLow = true;
            double tolerance = low * toleranceFactor;
            
            // Check if this is a swing low (lower than neighbors, within tolerance)
            for(int j = 1; j <= SwingLookbackBars && isSwingLow; j++) {
                if(i+j < bars && lowPrices[i+j] <= (low + tolerance)) {
                    isSwingLow = false;
                }
                if(i-j >= 0 && lowPrices[i-j] <= (low + tolerance)) {
                    isSwingLow = false;
                }
            }
            
            if(isSwingLow && low < swingValue) {
                swingValue = low;
                swingPointBar = i;
            }
        } else { // For sell orders, find swing high
            double high = iHigh(Symbol(), PERIOD_CURRENT, i);
            bool isSwingHigh = true;
            
            // Check if this is a swing high (higher than neighbors, within tolerance)
            for(int j = 1; j <= SwingLookbackBars; j++) {
                double tolerance = high * (SwingTolerancePct / 100.0);
                if(i+j < Bars(Symbol(), PERIOD_CURRENT) && iHigh(Symbol(), PERIOD_CURRENT, i+j) >= (high - tolerance)) {
                    isSwingHigh = false;
                    break;
                }
                if(i-j >= 0 && iHigh(Symbol(), PERIOD_CURRENT, i-j) >= (high - tolerance)) {
                    isSwingHigh = false;
                    break;
                }
            }
            
            if(isSwingHigh && high > swingValue) {
                swingValue = high;
                swingPointBar = i;
            }
        }
    }
    
    return swingPointBar;
}

//+------------------------------------------------------------------+
//| Check for divergence between price and oscillators               |
//+------------------------------------------------------------------+
enum ENUM_DIVERGENCE_TYPE {
    DIVERGENCE_NONE = 0,    // No divergence
    DIVERGENCE_REGULAR_BULL, // Regular bullish (price lower low, oscillator higher low)
    DIVERGENCE_REGULAR_BEAR, // Regular bearish (price higher high, oscillator lower high)
    DIVERGENCE_HIDDEN_BULL,  // Hidden bullish (price higher low, oscillator lower low)
    DIVERGENCE_HIDDEN_BEAR   // Hidden bearish (price lower high, oscillator higher high)
};

// Structure to store divergence detection results
struct DivergenceInfo {
    bool found;
    ENUM_DIVERGENCE_TYPE type;
    double strength;    // 0.0 to 1.0, indicating strength of divergence
    int firstBar;       // Bar index of the first point
    int secondBar;      // Bar index of the second point
    datetime timeDetected;
};

DivergenceInfo lastDivergence;

//+------------------------------------------------------------------+
//| Check if a divergence exists with RSI (Relative Strength Index)  |
//+------------------------------------------------------------------+
bool CheckRSIDivergence(int signal, DivergenceInfo &divInfo) {
    if(!EnableDivergenceFilter) return false;
    
    // Initialize divergence info
    divInfo.found = false;
    divInfo.strength = 0.0;
    divInfo.firstBar = -1;
    divInfo.secondBar = -1;
    divInfo.type = DIVERGENCE_NONE;
    
    // Initialize RSI indicator
    int rsiHandle = iRSI(Symbol(), PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    if(rsiHandle == INVALID_HANDLE) {
        Print("[SMC] Failed to create RSI indicator handle");
        return false;
    }
    
    // Prepare data arrays
    double rsiValues[], lowPrices[], highPrices[];
    datetime times[];
    int lookbackBars = 30; // Look back 30 bars for divergence
    
    ArraySetAsSeries(rsiValues, true);
    ArraySetAsSeries(lowPrices, true);
    ArraySetAsSeries(highPrices, true);
    ArraySetAsSeries(times, true);
    
    // Copy price and RSI data
    if(CopyBuffer(rsiHandle, 0, 0, lookbackBars, rsiValues) < lookbackBars) {
        Print("[SMC] Failed to copy RSI values");
        IndicatorRelease(rsiHandle);
        return false;
    }
    
    if(CopyLow(Symbol(), PERIOD_CURRENT, 0, lookbackBars, lowPrices) < lookbackBars ||
       CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookbackBars, highPrices) < lookbackBars ||
       CopyTime(Symbol(), PERIOD_CURRENT, 0, lookbackBars, times) < lookbackBars) {
        Print("[SMC] Failed to copy price data");
        IndicatorRelease(rsiHandle);
        return false;
    }
    
    // Release the indicator handle
    IndicatorRelease(rsiHandle);
    
    // Look for divergence based on signal direction
    if(signal > 0) { // Buy signal - look for bullish divergence
        // Find two recent lows in price for regular divergence
        int low1 = -1, low2 = -1;
        for(int i=1; i<lookbackBars-5; i++) {
            // Price has a lower low than previous bar
            if(lowPrices[i] < lowPrices[i-1] && lowPrices[i] < lowPrices[i+1]) {
                if(low1 == -1) {
                    low1 = i;
                } else {
                    low2 = i;
                    break;
                }
            }
        }
        
        if(low1 > 0 && low2 > 0) {
            // Check if price made lower low but RSI made higher low (regular bullish divergence)
            if(lowPrices[low1] < lowPrices[low2] && rsiValues[low1] > rsiValues[low2]) {
                divInfo.found = true;
                divInfo.type = DIVERGENCE_REGULAR_BULL;
                divInfo.firstBar = low2;
                divInfo.secondBar = low1;
                divInfo.strength = 0.7 + 0.3 * (rsiValues[low1] - rsiValues[low2]) / rsiValues[low2];
                divInfo.timeDetected = times[0];
                
                if(DisplayDebugInfo) {
                    Print("[SMC] Regular Bullish Divergence detected: Price made lower low but RSI made higher low");
                    Print("[SMC] Divergence Strength: ", DoubleToString(divInfo.strength, 2));
                }
                return true;
            }
            // Also check for hidden bullish divergence (price higher low, oscillator lower low)
            else if(lowPrices[low1] > lowPrices[low2] && rsiValues[low1] < rsiValues[low2]) {
                divInfo.found = true;
                divInfo.type = DIVERGENCE_HIDDEN_BULL;
                divInfo.firstBar = low2;
                divInfo.secondBar = low1;
                divInfo.strength = 0.5 + 0.3 * (lowPrices[low1] - lowPrices[low2]) / lowPrices[low2];
                divInfo.timeDetected = times[0];
                
                if(DisplayDebugInfo) {
                    Print("[SMC] Hidden Bullish Divergence detected: Price made higher low but RSI made lower low");
                    Print("[SMC] Divergence Strength: ", DoubleToString(divInfo.strength, 2));
                }
                return true;
            }
        }
    } 
    else { // Sell signal - look for bearish divergence
        // Find two recent highs in price for regular divergence
        int high1 = -1, high2 = -1;
        for(int i=1; i<lookbackBars-5; i++) {
            // Price has a higher high than previous bar
            if(highPrices[i] > highPrices[i-1] && highPrices[i] > highPrices[i+1]) {
                if(high1 == -1) {
                    high1 = i;
                } else {
                    high2 = i;
                    break;
                }
            }
        }
        
        if(high1 > 0 && high2 > 0) {
            // Check if price made higher high but RSI made lower high (regular bearish divergence)
            if(highPrices[high1] > highPrices[high2] && rsiValues[high1] < rsiValues[high2]) {
                divInfo.found = true;
                divInfo.type = DIVERGENCE_REGULAR_BEAR;
                divInfo.firstBar = high2;
                divInfo.secondBar = high1;
                divInfo.strength = 0.7 + 0.3 * (rsiValues[high2] - rsiValues[high1]) / rsiValues[high2];
                divInfo.timeDetected = times[0];
                
                if(DisplayDebugInfo) {
                    Print("[SMC] Regular Bearish Divergence detected: Price made higher high but RSI made lower high");
                    Print("[SMC] Divergence Strength: ", DoubleToString(divInfo.strength, 2));
                }
                return true;
            }
            // Also check for hidden bearish divergence (price lower high, oscillator higher high)
            else if(highPrices[high1] < highPrices[high2] && rsiValues[high1] > rsiValues[high2]) {
                divInfo.found = true;
                divInfo.type = DIVERGENCE_HIDDEN_BEAR;
                divInfo.firstBar = high2;
                divInfo.secondBar = high1;
                divInfo.strength = 0.5 + 0.3 * (highPrices[high2] - highPrices[high1]) / highPrices[high2];
                divInfo.timeDetected = times[0];
                
                if(DisplayDebugInfo) {
                    Print("[SMC] Hidden Bearish Divergence detected: Price made lower high but RSI made higher high");
                    Print("[SMC] Divergence Strength: ", DoubleToString(divInfo.strength, 2));
                }
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for MACD divergence - provides additional confirmation     |
//+------------------------------------------------------------------+
bool CheckMACDDivergence(int signal, DivergenceInfo &divInfo) {
    if(!EnableDivergenceFilter) return false;
    
    // Initialize MACD indicator
    int macdHandle = iMACD(Symbol(), PERIOD_CURRENT, MACD_FastEMA, MACD_SlowEMA, MACD_SignalPeriod, PRICE_CLOSE);
    if(macdHandle == INVALID_HANDLE) {
        Print("[SMC] Failed to create MACD indicator handle");
        return false;
    }
    
    // Prepare data arrays
    double macdValues[], macdSignal[], lowPrices[], highPrices[];
    datetime times[];
    int lookbackBars = 30; // Look back 30 bars for divergence
    
    ArraySetAsSeries(macdValues, true);
    ArraySetAsSeries(macdSignal, true);
    ArraySetAsSeries(lowPrices, true);
    ArraySetAsSeries(highPrices, true);
    ArraySetAsSeries(times, true);
    
    // Copy price and MACD data
    if(CopyBuffer(macdHandle, 0, 0, lookbackBars, macdValues) < lookbackBars ||
       CopyBuffer(macdHandle, 1, 0, lookbackBars, macdSignal) < lookbackBars) {
        Print("[SMC] Failed to copy MACD values");
        IndicatorRelease(macdHandle);
        return false;
    }
    
    if(CopyLow(Symbol(), PERIOD_CURRENT, 0, lookbackBars, lowPrices) < lookbackBars ||
       CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookbackBars, highPrices) < lookbackBars ||
       CopyTime(Symbol(), PERIOD_CURRENT, 0, lookbackBars, times) < lookbackBars) {
        Print("[SMC] Failed to copy price data");
        IndicatorRelease(macdHandle);
        return false;
    }
    
    // Release the indicator handle
    IndicatorRelease(macdHandle);
    
    // Similar divergence detection logic as RSI but using MACD
    // Since MACD logic is similar to RSI, we'll only check for regular divergences
    
    if(signal > 0) { // Buy signal - look for bullish divergence
        // Find two recent lows in price
        int low1 = -1, low2 = -1;
        for(int i=1; i<lookbackBars-5; i++) {
            if(lowPrices[i] < lowPrices[i-1] && lowPrices[i] < lowPrices[i+1] && macdValues[i] < 0) {
                if(low1 == -1) {
                    low1 = i;
                } else {
                    low2 = i;
                    break;
                }
            }
        }
        
        if(low1 > 0 && low2 > 0) {
            // Check if price made lower low but MACD made higher low
            if(lowPrices[low1] < lowPrices[low2] && macdValues[low1] > macdValues[low2]) {
                divInfo.found = true;
                divInfo.type = DIVERGENCE_REGULAR_BULL;
                divInfo.firstBar = low2;
                divInfo.secondBar = low1;
                divInfo.strength = 0.7 + 0.3 * (macdValues[low1] - macdValues[low2]) / MathAbs(macdValues[low2]);
                divInfo.timeDetected = times[0];
                
                if(DisplayDebugInfo) {
                    Print("[SMC] MACD Bullish Divergence detected");
                    Print("[SMC] MACD Divergence Strength: ", DoubleToString(divInfo.strength, 2));
                }
                return true;
            }
        }
    } 
    else { // Sell signal - look for bearish divergence
        // Find two recent highs
        int high1 = -1, high2 = -1;
        for(int i=1; i<lookbackBars-5; i++) {
            if(highPrices[i] > highPrices[i-1] && highPrices[i] > highPrices[i+1] && macdValues[i] > 0) {
                if(high1 == -1) {
                    high1 = i;
                } else {
                    high2 = i;
                    break;
                }
            }
        }
        
        if(high1 > 0 && high2 > 0) {
            // Check if price made higher high but MACD made lower high
            if(highPrices[high1] > highPrices[high2] && macdValues[high1] < macdValues[high2]) {
                divInfo.found = true;
                divInfo.type = DIVERGENCE_REGULAR_BEAR;
                divInfo.firstBar = high2;
                divInfo.secondBar = high1;
                divInfo.strength = 0.7 + 0.3 * (macdValues[high2] - macdValues[high1]) / macdValues[high2];
                divInfo.timeDetected = times[0];
                
                if(DisplayDebugInfo) {
                    Print("[SMC] MACD Bearish Divergence detected");
                    Print("[SMC] MACD Divergence Strength: ", DoubleToString(divInfo.strength, 2));
                }
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Combined divergence check using multiple indicators              |
//+------------------------------------------------------------------+
bool CheckForDivergence(int signal, DivergenceInfo &divInfo) {
    if(!EnableDivergenceFilter) return false;
    
    divInfo.found = false;
    divInfo.strength = 0.0;
    
    // Try RSI divergence first
    bool rsiDivergence = CheckRSIDivergence(signal, divInfo);
    if(rsiDivergence) {
        return true; // RSI divergence found
    }
    
    // If no RSI divergence, try MACD
    bool macdDivergence = CheckMACDDivergence(signal, divInfo);
    if(macdDivergence) {
        return true; // MACD divergence found
    }
    
    return false; // No divergence found
}

//+------------------------------------------------------------------+
//| Manage trailing stops with enhanced early activation           |
//+------------------------------------------------------------------+
void ManageTrailingStops() {
    if(!EnableAggressiveTrailing) return;
    int trailedPositions = 0;
    
    // Breakeven logic: Move SL to BE+ after first TP is hit
    for(int i=0; i<PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        string comment = PositionGetString(POSITION_COMMENT);
        if(StringFind(comment, "TP1") < 0) continue; // Only for first partial
        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double beBuffer = 2 * SymbolInfoDouble(Symbol(), SYMBOL_POINT); // BE+2 points
        double newSL = (posType == POSITION_TYPE_BUY) ? entryPrice + beBuffer : entryPrice - beBuffer;
        if((posType == POSITION_TYPE_BUY && currentSL < newSL && currentPrice > entryPrice) ||
           (posType == POSITION_TYPE_SELL && currentSL > newSL && currentPrice < entryPrice)) {
            if(trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
                if(DisplayDebugInfo) Print("[SMC] Breakeven SL moved for partial TP1: Ticket=", ticket, ", NewSL=", newSL);
            }
        }
    }
    for(int i=0; i<PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(!PositionSelectByTicket(ticket)) continue;
        
        string posSymbol = PositionGetString(POSITION_SYMBOL);
        if(posSymbol != Symbol()) continue;
        
        string comment = PositionGetString(POSITION_COMMENT);
        // Include all our position types, including partial TPs
        if(StringFind(comment, "SMC") < 0) continue;
        
        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double profit = PositionGetDouble(POSITION_PROFIT);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        // Get ATR for adaptive trailing
        double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
        
        // Enhanced trailing based on ATR and market regime
        double trailAmount = atr * TrailingStopMultiplier;
        
        // Apply market regime modifications to trailing
        if(EnableMarketRegimeFiltering && currentRegime >= 0) {
            switch(currentRegime) {
                case TRENDING_UP:
                case TRENDING_DOWN:
                    trailAmount *= 1.5; // More aggressive trailing in trends
                    break;
                    
                case CHOPPY:
                case HIGH_VOLATILITY:
                    trailAmount *= 0.8; // Tighter trailing in volatile/choppy conditions
                    break;
            }
        }
        
        // Minimum trailing amount
        trailAmount = MathMax(trailAmount, 10 * _Point);
        
        // Calculate how far we've moved from entry
        double priceMovement = posType == POSITION_TYPE_BUY ? 
            (currentPrice - entryPrice) : 
            (entryPrice - currentPrice);
            
        // Calculate potential profit as percentage of initial risk
        double initialRisk = MathAbs(entryPrice - currentSL);
        double profitPct = initialRisk > 0 ? priceMovement / initialRisk : 0;
        
        // Different activation thresholds based on position type
        double activationThreshold = TrailingActivationPct;
        
        // For runner positions, activate trailing even earlier
        if(StringFind(comment, "Runner") >= 0 || StringFind(comment, "TP2") >= 0) {
            activationThreshold = TrailingActivationPct * 0.7; // 30% earlier for runners
        }
        
        // Only start trailing after we've reached activation threshold
        if(profitPct >= activationThreshold) {
            double newSL = 0;
            
            if(posType == POSITION_TYPE_BUY) {
                // For buy positions, check if we should update SL (move it up)
                double potentialSL = currentPrice - trailAmount;
                
                // Find a swing low for better trailing if possible
                int swingBar = FindRecentSwingPoint(true, 1, 10); // Look at recent 10 bars
                double swingSL = 0;
                
                if(swingBar >= 0) {
                    swingSL = iLow(Symbol(), PERIOD_CURRENT, swingBar) - (3 * _Point);
                    
                    // Use swing low only if it's higher than current SL and less than price - trailAmount
                    if(swingSL > currentSL && swingSL < currentPrice - (5 * _Point)) {
                        potentialSL = MathMax(potentialSL, swingSL);
                    }
                }
                
                // More aggressive trailing based on profit % - tighten as profit increases
                if(profitPct > 1.0) { // Over 100% of initial risk
                    // Reduce trailing distance as profit grows
                    double reducedTrail = trailAmount * (1.0 - MathMin(0.5, (profitPct - 1.0) * 0.25));
                    potentialSL = MathMax(potentialSL, currentPrice - reducedTrail);
                    
                    if(DisplayDebugInfo && newSL > 0) {
                        Print("[SMC] Enhanced trailing: profit at ", DoubleToString(profitPct, 2), 
                              "x risk, tightening trail to ", DoubleToString(reducedTrail/_Point, 1), " points");
                    }
                }
                
                if(potentialSL > currentSL + (1 * _Point)) {
                    newSL = potentialSL;
                }
                
                // Once we're at 80% of TP, extend TP if in trending regime
                if(profitPct >= 0.8 && (currentRegime == TRENDING_UP) && currentTP > 0) {
                    double newTP = currentTP + (MathAbs(currentTP - entryPrice) * 0.5);
                    if(newTP > currentTP + (5 * _Point)) {
                        trade.PositionModify(ticket, newSL > 0 ? newSL : currentSL, newTP);
                        if(DisplayDebugInfo) Print("[SMC] Extended TP for ticket ", ticket, " to ", newTP);
                        continue; // Skip regular SL update as we've already modified
                    }
                }
            } else {
                // For sell positions, check if we should update SL (move it down)
                double potentialSL = currentPrice + trailAmount;
                
                // Find a swing high for better trailing if possible
                int swingBar = FindRecentSwingPoint(false, 1, 10); // Look at recent 10 bars
                double swingSL = 0;
                
                if(swingBar >= 0) {
                    swingSL = iHigh(Symbol(), PERIOD_CURRENT, swingBar) + (3 * _Point);
                    
                    // Use swing high only if it's lower than current SL and more than price + trailAmount
                    if((currentSL == 0 || swingSL < currentSL) && swingSL > currentPrice + (5 * _Point)) {
                        potentialSL = MathMin(potentialSL, swingSL);
                    }
                }
                
                if(currentSL == 0 || potentialSL < currentSL - (1 * _Point)) {
                    newSL = potentialSL;
                }
                
                // Once we're at 80% of TP, extend TP if in trending regime
                if(profitPct >= 0.8 && (currentRegime == TRENDING_DOWN) && currentTP > 0) {
                    double newTP = currentTP - (MathAbs(entryPrice - currentTP) * 0.5);
                    if(newTP < currentTP - (5 * _Point)) {
                        trade.PositionModify(ticket, newSL > 0 ? newSL : currentSL, newTP);
                        if(DisplayDebugInfo) Print("[SMC] Extended TP for ticket ", ticket, " to ", newTP);
                        continue; // Skip regular SL update as we've already modified
                    }
                }
            }
            
            // Update stop loss if needed
            // Enhanced: Only trail if profitable and SL not too close
            if(newSL != 0 && MathAbs(newSL - currentSL) > (3 * _Point) && ((posType == POSITION_TYPE_BUY && newSL < currentPrice) || (posType == POSITION_TYPE_SELL && newSL > currentPrice))) {
                if(trade.PositionModify(ticket, newSL, currentTP)) {
                    trailedPositions++;
                    if(DisplayDebugInfo) Print("[SMC] Trailing stop updated: Ticket=", ticket, ", OldSL=", currentSL, ", NewSL=", newSL);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Display debug information in the chart                           |
//+------------------------------------------------------------------+
void ShowDebugInfo() {
    if(!DisplayDebugInfo) return;
    
    string info = "=== SMC Scalper Hybrid ===\n";
    
    // Regime info
    string regimeNames[] = {"TRENDING_UP", "TRENDING_DOWN", "HIGH_VOLATILITY", "LOW_VOLATILITY", 
                            "RANGING_NARROW", "RANGING_WIDE", "BREAKOUT", "REVERSAL", "CHOPPY"};
    
    string currentRegimeName = (currentRegime >= 0 && currentRegime < REGIME_COUNT) ? 
                              regimeNames[currentRegime] : "UNKNOWN";
    
    info += "Market Regime: " + currentRegimeName + "\n";
    
    // Position stats
    int buyPos = 0, sellPos = 0;
    double buyProfit = 0, sellProfit = 0;
    
    for(int i=0; i<PositionsTotal(); i++) {
        if(PositionGetSymbol(i) != Symbol()) continue;
        
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            buyPos++;
            buyProfit += PositionGetDouble(POSITION_PROFIT);
        } else {
            sellPos++;
            sellProfit += PositionGetDouble(POSITION_PROFIT);
        }
    }
    
    info += "Positions: " + IntegerToString(buyPos + sellPos) + 
            " (Buy: " + IntegerToString(buyPos) + ", Sell: " + IntegerToString(sellPos) + ")\n";
    
    info += "Profit: " + DoubleToString(buyProfit + sellProfit, 2) + 
            " (Buy: " + DoubleToString(buyProfit, 2) + ", Sell: " + DoubleToString(sellProfit, 2) + ")\n";
    
    // Performance stats
    info += "Win Streak: " + IntegerToString(winStreak) + 
            ", Loss Streak: " + IntegerToString(lossStreak) + "\n";
    
    // Block info
    int validBlocks = 0;
    int bullishBlocks = 0;
    int bearishBlocks = 0;
    
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            validBlocks++;
            if(recentBlocks[i].bullish) bullishBlocks++;
            else bearishBlocks++;
        }
    }
    
    info += "Order Blocks: " + IntegerToString(validBlocks) + 
            " (Bullish: " + IntegerToString(bullishBlocks) + 
            ", Bearish: " + IntegerToString(bearishBlocks) + ")\n";
    
    // Status indicators
    info += "Status: " + (emergencyMode ? "EMERGENCY MODE" : "NORMAL") + "\n";
    
    Comment(info);
}

//+------------------------------------------------------------------+
//| Error description function                                       |
//+------------------------------------------------------------------+
string ErrorDescription(int error_code) {
   switch(error_code) {
      case 4106: return "Invalid volume";
      case 4107: return "Invalid price";
      case 4108: return "Invalid stops";
      case 4109: return "Trade not allowed";
      case 4110: return "Longs not allowed";
      case 4111: return "Shorts not allowed";
      case 4200: return "Order already exists";
      case 10004: return "Requote";
      case 10006: return "Order rejected";
      case 10007: return "Order cancelled by client";
      case 10013: return "Invalid stops";
      case 10014: return "Invalid trade size";
      case 10015: return "Market closed";
      case 10016: return "Market closed during pending order activation";
      case 10017: return "Trade is disabled";
      case 10018: return "Market closed";
      case 10019: return "Not enough money";
      case 10020: return "Prices changed";
      default: return "Unknown error";
   }
}

//+------------------------------------------------------------------+
//| Placeholder for order block analysis                              |
//+------------------------------------------------------------------+
void FindOrderBlocks(string symbol, ENUM_TIMEFRAMES timeframe) {
    // Placeholder - this would be an advanced order block detection function
    // It's currently integrated into DetectOrderBlocks() so we'll leave this empty
}

//+------------------------------------------------------------------+
//| Placeholder for market structure analysis                        |
//+------------------------------------------------------------------+
void AnalyzeMarketStructure(string symbol, ENUM_TIMEFRAMES timeframe) {
    // Placeholder - would implement higher timeframe market structure analysis
    // For now, this is handled by the regime detection
}

//+------------------------------------------------------------------+
//| End of Hybrid EA                                                 |
//+------------------------------------------------------------------+

MARKET_PHASE DetectMarketPhase() {
    double close0 = iClose(Symbol(), PERIOD_M5, 0);
    double close1 = iClose(Symbol(), PERIOD_M5, 1);
    double close3 = iClose(Symbol(), PERIOD_M5, 3);
    double close5 = iClose(Symbol(), PERIOD_M5, 5);
    double close10 = iClose(Symbol(), PERIOD_M5, 10);
    
    double high0 = iHigh(Symbol(), PERIOD_M5, 0);
    double high1 = iHigh(Symbol(), PERIOD_M5, 1);
    double high3 = iHigh(Symbol(), PERIOD_M5, 3);
    double low0 = iLow(Symbol(), PERIOD_M5, 0);
    double low1 = iLow(Symbol(), PERIOD_M5, 1);
    double low3 = iLow(Symbol(), PERIOD_M5, 3);
    
    double ma3 = 0, ma5 = 0, ma10 = 0, ma20 = 0;
    for(int i=0; i<3; i++) ma3 += iClose(Symbol(), PERIOD_M5, i);
    for(int i=0; i<5; i++) ma5 += iClose(Symbol(), PERIOD_M5, i);
    for(int i=0; i<10; i++) ma10 += iClose(Symbol(), PERIOD_M5, i);
    for(int i=0; i<20; i++) ma20 += iClose(Symbol(), PERIOD_M5, i);
    ma3 /= 3;
    ma5 /= 5;
    ma10 /= 10;
    ma20 /= 20;
    
    double quickAtr = GetATR(Symbol(), PERIOD_M5, 14, 0);
    double avgRange = 0;
    for(int i=0; i<5; i++) {
        avgRange += MathAbs(iHigh(Symbol(), PERIOD_M5, i) - iLow(Symbol(), PERIOD_M5, i));
    }
    avgRange /= 5;
    
    double range3 = MathMax(high0, high1) - MathMin(low0, low1);
    double range10 = 0;
    double highestHigh = iHigh(Symbol(), PERIOD_M5, iHighest(Symbol(), PERIOD_M5, MODE_HIGH, 10, 0));
    double lowestLow = iLow(Symbol(), PERIOD_M5, iLowest(Symbol(), PERIOD_M5, MODE_LOW, 10, 0));
    range10 = highestHigh - lowestLow;
    
    double momentum3 = close0 - close3;
    double momentum5 = close0 - close5;
    double momentum10 = close0 - close10;
    
    int directionChanges = 0;
    for(int i=1; i<5; i++) {
        if((iClose(Symbol(), PERIOD_M5, i) > iClose(Symbol(), PERIOD_M5, i+1) && 
            iClose(Symbol(), PERIOD_M5, i-1) < iClose(Symbol(), PERIOD_M5, i)) ||
           (iClose(Symbol(), PERIOD_M5, i) < iClose(Symbol(), PERIOD_M5, i+1) && 
            iClose(Symbol(), PERIOD_M5, i-1) > iClose(Symbol(), PERIOD_M5, i))) {
            directionChanges++;
        }
    }
    
    double bbUpper = GetBands(Symbol(), PERIOD_M5, 20, 2.0, 0, PRICE_CLOSE, 1, 0);
    double bbLower = GetBands(Symbol(), PERIOD_M5, 20, 2.0, 0, PRICE_CLOSE, 2, 0);
    double bbWidth = (bbUpper - bbLower) / ma20;
    
    bool breakoutUp = close0 > bbUpper && close1 <= bbUpper;
    bool breakoutDown = close0 < bbLower && close1 >= bbLower;
    bool insideBands = close0 > bbLower && close0 < bbUpper;
    
    bool potentialReversal = (momentum3 * momentum10 < 0) && MathAbs(momentum3) > quickAtr * 0.3;
    
    bool isVolatile = quickAtr > avgRange * 1.2;
    bool isVeryVolatile = quickAtr > avgRange * 1.8;
    bool isTrendingUp = ma3 > ma5 && ma5 > ma10 && momentum5 > 0;
    bool isTrendingDown = ma3 < ma5 && ma5 < ma10 && momentum5 < 0;
    bool isChoppy = directionChanges >= 3;
    bool isRangingNarrow = bbWidth < 0.01 && !isVolatile && insideBands;
    bool isRangingWide = bbWidth >= 0.01 && bbWidth < 0.03 && insideBands;
    
    MARKET_PHASE phase = PHASE_TRENDING_UP;
    
    if(breakoutUp || breakoutDown) {
        phase = PHASE_TRENDING_UP;
    }
    else if(potentialReversal) {
        phase = PHASE_TRENDING_DOWN;
    }
    else if(isChoppy) {
        phase = PHASE_RANGING;
    }
    else if(isRangingNarrow) {
        phase = PHASE_RANGING;
    }
    else if(isRangingWide) {
        phase = PHASE_RANGING;
    }
    else if(isTrendingUp && !isVeryVolatile) {
        phase = PHASE_TRENDING_UP;
    }
    else if(isTrendingDown && !isVeryVolatile) {
        phase = PHASE_TRENDING_DOWN;
    }
    else if(isVolatile) {
        phase = PHASE_HIGH_VOLATILITY;
    }
    
    return phase;
}

void AdjustTradeFrequency(MARKET_PHASE phase) {
    switch(phase) {
        case PHASE_TRENDING_UP:
            ActualSignalCooldownSeconds = 1;
            break;
        case PHASE_TRENDING_DOWN:
            ActualSignalCooldownSeconds = 1;
            break;
        case PHASE_RANGING:
            ActualSignalCooldownSeconds = 3;
            break;
        case PHASE_HIGH_VOLATILITY:
            ActualSignalCooldownSeconds = 5;
            break;
    }
}

void AdjustRiskParameters(MARKET_PHASE phase) {
    switch(phase) {
        case PHASE_TRENDING_UP:
            RiskPercent = 0.2;
            break;
        case PHASE_TRENDING_DOWN:
            RiskPercent = 0.2;
            break;
        case PHASE_RANGING:
            RiskPercent = 0.1;
            break;
        case PHASE_HIGH_VOLATILITY:
            RiskPercent = 0.05;
            break;
    }
}
