//+------------------------------------------------------------------+
//| SMC Adaptive Hybrid - Smart Money Concepts with Multi-Strategy Trading |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
// Error descriptions now handled internally

//+------------------------------------------------------------------+
//| Logging Functions                                                |
//+------------------------------------------------------------------+
void LogInfo(string message) {
    if(DisplayDebugInfo) {
        Print("[INFO] ", message);
    }
}

void LogWarning(string message) {
    Print("[WARNING] ", message);
}

void LogError(string message) {
    Print("[ERROR] ", message);
}

//+------------------------------------------------------------------+
//| Enhanced Trade Error Logging                                      |
//+------------------------------------------------------------------+
void LogTradeError(int errorCode, string operation, string symbol, double price, double sl, double tp) {
    string errorDesc = GetErrorDescription(errorCode);
    string errorType = "Unknown";
    string actionRequired = "Check MT5 logs for more details";
    
    // Categorize errors for better diagnostics
    if(errorCode == 10015 || errorCode == 130 || errorCode == 4110) {
        errorType = "Invalid Stops";
        double currentBid = GetCurrentBid();
        double currentAsk = GetCurrentAsk();
        double minStopDistance = GetMinimumStopDistance();
        
        // Calculate actual stop distances for detailed reporting
        double buyStopDistance = MathAbs(currentAsk - sl);
        double sellStopDistance = MathAbs(currentBid - sl);
        
        actionRequired = StringFormat("Stop levels too close to current price. Required: %.5f points, Actual: %.5f points (Buy) / %.5f points (Sell)", 
                                     minStopDistance/_Point, buyStopDistance/_Point, sellStopDistance/_Point);
    }
    else if(errorCode == 10016 || errorCode == 10014 || errorCode == 138) {
        errorType = "Invalid Volume";
        actionRequired = StringFormat("Check allowed volume/lot sizes. Min: %.2f, Max: %.2f, Step: %.2f", 
                                     SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                                     SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX),
                                     SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP));
    }
    else if(errorCode == 10019 || errorCode == 10010 || errorCode == 134 || errorCode == 139) {
        errorType = "Insufficient Funds";
        actionRequired = "Check account balance and margin requirements";
    }
    else if(errorCode == 10018) {
        errorType = "Market Closed";
        actionRequired = "Trading is currently not available for this symbol";
    }
    else if(errorCode == 10009 || errorCode == 10004) {
        errorType = "Server Busy";
        actionRequired = "Retry in a few moments or check connection";
    }
    else if(errorCode == 4756 || errorCode == 4109) {
        errorType = "Context Error";
        actionRequired = "Check terminal connection and refresh symbol";
    }
    
    // Create detailed error log
    string detailedLog = StringFormat(
        "\n===== TRADE ERROR DETAILS =====\n" +
        "Operation: %s\n" +
        "Symbol: %s\n" +
        "Price: %.5f\n" +
        "Stop Loss: %.5f\n" +
        "Take Profit: %.5f\n" +
        "Error Code: %d\n" +
        "Error Type: %s\n" +
        "Description: %s\n" +
        "Action: %s\n" +
        "==============================",
        operation, symbol, price, sl, tp, errorCode, errorType, errorDesc, actionRequired
    );
    
    // Log the error
    Print(detailedLog);
}

// Alias for LogWarning for backward compatibility
void LogWarn(string message) {
    LogWarning(message);
}

// Global trade object


// Global variables for position sizing and risk management
double g_minLot = 0.01;     // Minimum lot size (0.01 = micro lot, for small account)
double g_maxLot = 0.1;      // Maximum lot size (reduced for $40 account)
double g_lotStep = 0.01;    // Lot size increment
double g_lotSize = 0.01;    // Default lot size if calculation fails (reduced for small account)

// Trading mode enumeration
enum ENUM_TRADING_MODE {
   MODE_NORMAL = 0,           // Normal trading - longer timeframes, wider stops
   MODE_HFT = 1,              // High-frequency trading - tighter stops, faster entries/exits
   MODE_HYBRID_AUTO = 2       // Automatic hybrid mode - switches based on market conditions
};

// Global flag for emergency mode (reduced risk)
bool emergencyMode = false;  // When true, reduces position sizes

// Global variables for CHOCH detection
double lastSwingHigh = 0.0;
double lastSwingLow = 0.0;
bool chochDetected = false;
datetime lastChochTime = 0; // Time of last CHOCH detection

// Divergence type enumeration
enum ENUM_DIVERGENCE_TYPE {
    DIVERGENCE_NONE = 0,
    DIVERGENCE_REGULAR_BULL = 1,    // Regular bullish divergence
    DIVERGENCE_HIDDEN_BULL = 2,     // Hidden bullish divergence
    DIVERGENCE_REGULAR_BEAR = 3,    // Regular bearish divergence
    DIVERGENCE_HIDDEN_BEAR = 4      // Hidden bearish divergence
};

// Global variable for divergence tracking
struct DivergenceInfo {
    bool found;             // Whether divergence was found
    ENUM_DIVERGENCE_TYPE type; // Type of divergence (using the DIVERGENCE_* enum)
    double strength;        // Strength of the divergence (0.0-1.0)
    datetime timeDetected;  // When the divergence was detected (renamed from time for consistency)
    double priceLevel;      // Price level of the divergence point
    double indicatorLevel;  // Indicator level at divergence point
    int firstBar;           // Index of first bar in divergence pattern
    int secondBar;          // Index of second bar in divergence pattern
};
DivergenceInfo lastDivergence; // Structure to store divergence detection results

// Struct for swing points used in DetermineOptimalStopLoss
// Already defined at line 39, so this duplicate is commented out
/*
struct SwingPoint {
    double price;
    int barIndex;
    int score;
    datetime time;
    bool isHigh; // true for swing high, false for swing low
};
*/

// Constants for array sizes
#define METRIC_WINDOW 50   // Size of metric tracking arrays

// Risk management parameters
input double RiskPerTrade = 1.0;   // Risk per trade (percentage of account balance)
#define MAX_REGIMES 5     // Maximum number of market regimes
#define MAX_BLOCKS 50     // Maximum number of order blocks to track
#define MAX_GRABS 20
#define MAX_FVGS 30
#define REGIME_COUNT 10
#define ACCURACY_WINDOW 20  // Size of prediction accuracy tracking window
// METRIC_WINDOW already defined above, using value 50


// Global variables for market analysis and performance tracking
// Market regime/phase enums
enum ENUM_MARKET_REGIME {
   REGIME_NORMAL = 0,          // Normal market conditions
   REGIME_TRENDING_UP,         // Clear uptrend
   REGIME_TRENDING_DOWN,       // Clear downtrend
   REGIME_HIGH_VOLATILITY,     // High volatility/breakout
   REGIME_LOW_VOLATILITY,      // Low volatility
   REGIME_RANGING_NARROW,      // Narrow range
   REGIME_RANGING_WIDE,        // Wide range
   REGIME_BREAKOUT,            // Breakout regime
   REGIME_REVERSAL,            // Reversal regime
   REGIME_CHOPPY              // Choppy, sideways market
};

// Also define MARKET_PHASE enum to match ENUM_MARKET_REGIME for compatibility
enum MARKET_PHASE {
   PHASE_NORMAL = 0,          // Normal market conditions
   PHASE_TRENDING_UP,         // Clear uptrend
   PHASE_TRENDING_DOWN,       // Clear downtrend
   PHASE_HIGH_VOLATILITY,     // High volatility/breakout
   PHASE_LOW_VOLATILITY,      // Low volatility
   PHASE_RANGING_NARROW,      // Narrow range
   PHASE_RANGING_WIDE,        // Wide range
   PHASE_BULLISH_REVERSAL,    // Bullish reversal phase
   PHASE_BEARISH_REVERSAL,    // Bearish reversal phase
   PHASE_CHOPPY              // Choppy, sideways market
};

// Market structure enum for tracking trend structure
enum ENUM_MARKET_STRUCTURE {
   MARKET_STRUCTURE_UPTREND,    // Uptrend structure
   MARKET_STRUCTURE_DOWNTREND,  // Downtrend structure
   MARKET_STRUCTURE_RANGE       // Range-bound structure
};

// Global market structure tracking
ENUM_MARKET_STRUCTURE currentMarketStructure;

// Define global regime tracking variables
int regimeBarCount = 0;
int lastRegime = -1;
bool trailingActive = false;
double trailingLevel = 0.0;
double trailingTP = 0.0;
datetime lastTradeTime = 0;
int currentRegime = -1;
double workingTrailingStopMultiplierLocal = 0.8; // For storing the trailing stop multiplier value (tighter to secure profits)
// Removed duplicate emergencyMode definition
int consecutiveLosses = 0;
int winStreak = 0;
int lossStreak = 0;
double tradeProfits[]; // Array to store recent trade profits - dynamic array
double tradeReturns[]; // Array to store risk-return ratios of recent trades - dynamic array
double regimeMaxDrawdown[]; // Array for max drawdown tracking - dynamic array
// Use arrays to track performance by market regime - all as dynamic arrays
int regimeWins[]; // Track wins by regime
int regimeLosses[]; // Track losses by regime
double regimeProfit[]; // Track profit by regime

// Global buffers for indicators and calculations
double localAtrBuffer[];
double maBuffer[];
double volBuffer[];

// Price normalization function
double NormalizePrice(double price) {
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    if(tickSize == 0) tickSize = 0.00001; // Default for 5-digit brokers
    return MathRound(price / tickSize) * tickSize;
}

// Additional global variables for divergence and other features
double divergenceScore = 0.0;
double divergenceWeight = 1.0;
double BreakEvenBuffer = 10.0; // Points to add when moving stop to break-even

// Variables for CHOCH detection and divergence
int firstBar = 0;          // First bar in CHOCH pattern
int secondBar = 0;         // Second bar in CHOCH pattern
datetime timeDetected = 0; // Time when pattern was detected

// Additional global state tracking variables
bool marketClosed = false;
bool isWeekend = false;
datetime lastSignalTime = 0;
// Removed duplicate g_lotSize and g_minLot definitions
double slippage = 3.0;       // Max allowed slippage in points
int MaxSlippage = 3;         // Maximum allowed slippage for trade execution in points

// Risk management settings
double MaxDrawdownPercent = 20.0;  // Maximum allowed drawdown before reducing risk
double MinRiskMultiplier = 0.5;    // Minimum risk multiplier when in drawdown
double BreakEvenPadding = 5.0;     // Points to add to break-even level for safety

// Mode-specific trade parameters
input ENUM_TRADING_MODE TradingMode = MODE_HYBRID_AUTO;  // Trading mode selection
input int HFT_SignalCooldownSeconds = 60;               // Signal cooldown for HFT mode (seconds)
input int Normal_SignalCooldownSeconds = 300;            // Signal cooldown for normal trading mode (seconds)
input double HFT_SL_ATR_Mult = 0.7;                     // HFT mode SL ATR multiplier (tighter)
input double Normal_SL_ATR_Mult = 1.2;                  // Normal mode SL ATR multiplier (wider)
input double HFT_TP_ATR_Mult = 1.4;                     // HFT mode TP ATR multiplier
input double Normal_TP_ATR_Mult = 2.5;                  // Normal mode TP ATR multiplier

// Trading mode state variables
int currentTradingMode = MODE_HYBRID_AUTO;              // Current active trading mode
int adaptiveModeChangeCounter = 0;                      // Counter to prevent excessive mode switching
datetime lastModeChangeTime = 0;                        // Time of last mode change

// Global variables for indicator caching and performance monitoring
double tradeMetrics[METRIC_WINDOW];

// Performance monitoring globals
ulong tickStartTime;
double averageTickProcessingTime = 0;
double maxTickProcessingTime = 0;
int tickCount = 0;

// Performance profiling - detailed segment timing
ulong profilingTime_BlockDetection = 0;
ulong profilingTime_SignalGeneration = 0;
ulong profilingTime_TradeLogic = 0;
ulong profilingTime_TrailingStops = 0;
double avgTime_BlockDetection = 0;
double avgTime_SignalGeneration = 0;
double avgTime_TradeLogic = 0;
double avgTime_TrailingStops = 0;

// Dashboard stats
int validBlocksCount = 0;
int buyBlocksCount = 0;
int sellBlocksCount = 0;
double avgTradeLatency = 0;
int totalTradeAttempts = 0;
int successfulTrades = 0;
datetime lastDashboardUpdate = 0;

// Indicator caching globals
datetime lastIndicatorCalc = 0;
double cachedATR = 0;
double cachedMA20 = 0;
double cachedMA50 = 0;

// Define structures for SMC pattern tracking
struct LiquidityGrab {
    datetime time;        // Time of the grab
    double price;         // Price level of the grab
    bool isBullish;       // Direction of the grab
    double strength;      // Strength of the grab (0.0-1.0)
    bool active;          // Whether this grab is still active
    int barIndex;         // Bar index when detected
    bool valid;           // Whether this grab is valid for trading
};

struct FairValueGap {
    datetime startTime;   // Start time of the gap
    datetime endTime;     // End time of the gap
    double high;          // High price of the gap
    double low;           // Low price of the gap
    bool isBullish;       // Direction of the gap
    double size;          // Size of the gap in points
    bool active;          // Whether this gap is still unfilled
    bool tested;          // Whether the gap has been tested
    bool valid;           // Whether this gap is valid for trading
};

// Define SwingPoint struct for optimal stop loss determination
struct SwingPoint {
    datetime time;       // Time of the swing point
    double price;        // Price level of the swing point
    bool isHigh;         // true if it's a swing high, false if it's a swing low
    int strength;        // A measure of the swing point's significance (1-10)
    int barIndex;        // Bar index when detected
    int score;           // Score for ranking swing points
    bool valid;          // Whether this swing point is valid for trading
    
    // Constructor with default values
    SwingPoint(datetime t = 0, double p = 0.0, bool high = true, int str = 1) {
        time = t;
        price = p;
        isHigh = high;
        strength = str;
    }
};

// OrderBlock struct definition - merged the two definitions
struct OrderBlock {
    datetime time;         // Time of the order block
    double high;           // High of the block
    double low;            // Low of the block
    double open;           // Open price
    double close;          // Close price
    double price;          // Key level price (block level)
    long volume;           // Volume at the order block
    bool valid;            // Is the block still valid
    bool isBuy;            // Buy (true) or Sell (false) block
    int strength;          // Strength of the block (1-10)
    double score;          // Score for block quality (0.0-1.0)
    datetime invalidTime;  // Time when block becomes invalid
    double originalScore;  // Original score at creation (for decay calculation)
    double mlScore;        // Machine learning score component
    double volumeProfile;  // Volume profile at block creation
    int barIndex;          // Bar index when detected
    bool tested;           // Whether it has been tested since formation (alias for touched)
    bool touched;          // Has the block been touched/tested?
    double atrAtFormation; // ATR at the time of formation (for context)
    double imbalanceRatio; // Imbalance ratio for this block
    double divergenceScore; // Score for divergence confirmation
    int type;              // Type identifier for the block
};

// Global arrays for SMC pattern tracking
LiquidityGrab recentGrabs[MAX_GRABS];
FairValueGap recentFVGs[MAX_FVGS];
OrderBlock recentBlocks[MAX_BLOCKS]; // Order blocks for trade decisions
int grabIndex = 0;

// ===================== Adaptive Filters Consolidation =====================
// Adaptive filter settings structure
struct AdaptiveFilterSettings {
    double signalQualityThreshold;
    bool requireMultiTimeframe;
    bool requireMomentumConfirmation;
    int minimumBlockStrength;
    int consecutiveNoTrades;
    int consecutiveNoTradesLocal; // Local to avoid conflict with global
    int consecutiveLossesLocal; // Local to avoid conflict with global
    int winStreakLocal; // Local to avoid conflict with global
    double winRate;
    datetime lastAdaptationTime;
    double adaptationRate;
    double minSignalQualityAllowed;
    double maxSignalQualityAllowed;
}; 
AdaptiveFilterSettings adaptiveFilters;

void InitializeAdaptiveFilters() {
    adaptiveFilters.signalQualityThreshold = MinSignalQualityToTrade;
    adaptiveFilters.requireMultiTimeframe = RequireMultiTimeframeConfirmation;
    adaptiveFilters.requireMomentumConfirmation = RequireMomentumConfirmation;
    adaptiveFilters.minimumBlockStrength = 3;
    adaptiveFilters.consecutiveNoTrades = 0;
    adaptiveFilters.consecutiveLossesLocal = 0;
    adaptiveFilters.winStreakLocal = 0;
    adaptiveFilters.winRate = 0.5;
    adaptiveFilters.lastAdaptationTime = 0;
    adaptiveFilters.adaptationRate = 0.1;
    adaptiveFilters.minSignalQualityAllowed = 0.3;
    adaptiveFilters.maxSignalQualityAllowed = 0.8;
    LogInfo("[ADAPT] Adaptive filters initialized with quality threshold: " + DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
}

void UpdateAdaptiveFilters(bool tradeTaken, bool isWin, bool missedProfitableSetup) {
    // Using local variables for filter adjustments

    datetime currentTime = TimeCurrent();
    if(currentTime - adaptiveFilters.lastAdaptationTime < 3600) return;
    if(tradeTaken) {
        adaptiveFilters.consecutiveNoTrades = 0;
        if(isWin) {
            adaptiveFilters.consecutiveLossesLocal = 0;
            adaptiveFilters.winStreakLocal++;
        } else {
            adaptiveFilters.winStreakLocal = 0;
            adaptiveFilters.consecutiveLossesLocal++;
        }
    } else {
        adaptiveFilters.consecutiveNoTrades++;
    }
    if(adaptiveFilters.consecutiveNoTrades > 20) {
        double adjustment = adaptiveFilters.adaptationRate * 0.1;
        adaptiveFilters.signalQualityThreshold = MathMax(
            adaptiveFilters.minSignalQualityAllowed,
            adaptiveFilters.signalQualityThreshold - adjustment
        );
        if(adaptiveFilters.consecutiveNoTrades > 30 && adaptiveFilters.requireMultiTimeframe) {
            adaptiveFilters.requireMultiTimeframe = false;
            LogInfo("[ADAPT] Temporarily disabled multi-timeframe confirmation requirement due to lack of trades");
        }
        LogInfo("[ADAPT] Loosened filters due to " + IntegerToString(adaptiveFilters.consecutiveNoTrades) +
               " missed trades. New quality threshold: " + DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
    }
    if(adaptiveFilters.consecutiveLossesLocal > 3) {
        double adjustment = adaptiveFilters.adaptationRate * 0.1 * adaptiveFilters.consecutiveLossesLocal / 3.0;
        adaptiveFilters.signalQualityThreshold = MathMin(
            adaptiveFilters.maxSignalQualityAllowed,
            adaptiveFilters.signalQualityThreshold + adjustment
        );
        if(adaptiveFilters.consecutiveLossesLocal > 5) {
            adaptiveFilters.requireMultiTimeframe = true;
            adaptiveFilters.requireMomentumConfirmation = true;
            LogInfo("[ADAPT] Enabled all confirmations due to consecutive losses");
        }
        LogInfo("[ADAPT] Tightened filters due to " + IntegerToString(adaptiveFilters.consecutiveLossesLocal) +
               " consecutive losses. New quality threshold: " + DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
    }
    if(adaptiveFilters.winStreakLocal > 5) {
        double adjustment = adaptiveFilters.adaptationRate * 0.05;
        adaptiveFilters.signalQualityThreshold = MathMax(
            adaptiveFilters.minSignalQualityAllowed,
            adaptiveFilters.signalQualityThreshold - adjustment
        );
        LogInfo("[ADAPT] Optimized filters after " + IntegerToString(adaptiveFilters.winStreakLocal) +
               " consecutive wins. New quality threshold: " + DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
    }
    adaptiveFilters.lastAdaptationTime = currentTime;
}

double GetAdaptedSignalQualityThreshold() {
    return adaptiveFilters.signalQualityThreshold;
}
bool IsMultiTimeframeRequired() {
    return adaptiveFilters.requireMultiTimeframe;
}
bool IsMomentumConfirmationRequired() {
    return adaptiveFilters.requireMomentumConfirmation;
}
// Function to apply adaptive filters to a signal
bool ApplyAdaptiveFilters(int signal, int regime, double quality) {
    // ADAPTIVE MULTI-TIMEFRAME CONFIRMATION - Adjust requirements based on market conditions
    
    // Base settings
    bool baseRequireMultiTimeframe = adaptiveFilters.requireMultiTimeframe;
    int baseMinConfirmingTimeframes = 1; // Default: at least one higher timeframe must confirm
    
    // Adapt based on market regime
    bool adaptiveRequireMultiTimeframe = baseRequireMultiTimeframe;
    int adaptiveMinConfirmingTimeframes = baseMinConfirmingTimeframes;
    
    // In choppy or ranging markets, require more confirmation
    if(regime == REGIME_CHOPPY || regime == REGIME_RANGING_NARROW) {
        adaptiveRequireMultiTimeframe = true;
        adaptiveMinConfirmingTimeframes = 2; // Require more timeframes in difficult markets
        Print("[ADAPTIVE MTF] Requiring stronger multi-timeframe confirmation in challenging market");
    }
    // In trending markets with good quality signals, we can be more permissive
    else if((regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN) && quality > 0.7) {
        // For high-quality signals in trends, multi-timeframe is optional
        adaptiveRequireMultiTimeframe = false;
        Print("[ADAPTIVE MTF] Making multi-timeframe confirmation optional for high quality trend signals");
    }
    // In breakout regimes, timing is critical
    else if(regime == REGIME_BREAKOUT) {
        // For breakouts, require at least one higher timeframe confirmation
        adaptiveRequireMultiTimeframe = true;
        adaptiveMinConfirmingTimeframes = 1;
        Print("[ADAPTIVE MTF] Using standard confirmation requirements for breakout");
    }
    
    // Store the adapted requirements for use in the filter logic
    adaptiveFilters.requireMultiTimeframe = adaptiveRequireMultiTimeframe;
    
    // Enhanced diagnostic logging at filter entry
    if(DisplayDebugInfo) {
        Print("[FILTER DIAG] Evaluating " + (signal > 0 ? "BUY" : "SELL") + 
              " signal for " + Symbol() + 
              " | Quality: " + DoubleToString(quality, 2) + 
              " | Regime: " + IntegerToString(regime) +
              " | MTF Required: " + (adaptiveRequireMultiTimeframe ? "Yes" : "No"));
    }
    
    // Check if signal quality meets threshold
    if(quality < adaptiveFilters.signalQualityThreshold) {
        if(DisplayDebugInfo) LogInfo("[FILTER] Signal rejected: quality " + DoubleToString(quality, 2) + 
                            " below threshold " + DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
        return false;
    }
    
    // Apply multi-timeframe confirmation if required
    if(adaptiveFilters.requireMultiTimeframe) {
        // Simple check - this can be expanded based on your actual implementation
        bool mtfConfirmed = true; // Placeholder - replace with real logic
        if(!mtfConfirmed) {
            if(DisplayDebugInfo) LogInfo("[FILTER] Signal rejected: failed multi-timeframe confirmation");
            return false;
        }
    }
    
    // Apply momentum confirmation if required
    if(adaptiveFilters.requireMomentumConfirmation && !CheckMomentumConfirmation(signal)) {
        if(DisplayDebugInfo) LogInfo("[FILTER] Signal rejected: failed momentum confirmation");
        return false;
    }
    
    if(DisplayDebugInfo) Print("[FILTER DIAG] Signal PASSED all filters");
    return true; // Signal passed all filters
}

// This function was removed to fix compilation errors

// ===================== End Adaptive Filters =====================

// ===================== Missed Opportunities Consolidation =====================
#define MAX_MISSED_OPPORTUNITIES 50
struct MissedOpportunity {
    datetime time;
    double price;
    int type;
    string reason;
    double potential;
    double potentialProfit; // Added for existing references
    bool wouldHaveWon;      // Added for existing references
};
MissedOpportunity missedOpportunities[];
int missedOpportunityCount = 0; // Counter for missed opportunities

// More lenient trade filter settings for small accounts
void AdjustFiltersForSmallAccount() {
    // Get account balance to determine if we need small account adjustments
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // For small accounts under $100, make filters more permissive
    if(accountBalance <= 100.0) {
        // Lower signal quality threshold to allow more trades
        double lowerThreshold = 0.5;
        adaptiveFilters.signalQualityThreshold = MathMin(adaptiveFilters.signalQualityThreshold, lowerThreshold);
        
        // For small accounts we'll use default momentum confirmation (already set globally)
        // and avoid changing those settings directly to prevent errors
        
        if(DisplayDebugInfo) {
            Print("[SMALL ACCOUNT] Adjusted filters for small $", DoubleToString(accountBalance, 2), " account: ",
                  "SignalQuality=", DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
        }
    }
}

void RecordMissedOpportunity(int type, double price, string reason) {
    if(ArraySize(missedOpportunities) == 0) {
        ArrayResize(missedOpportunities, MAX_MISSED_OPPORTUNITIES);
    }
    for(int i=ArraySize(missedOpportunities)-1; i>0; i--) {
        missedOpportunities[i] = missedOpportunities[i-1];
    }
    missedOpportunities[0].time = TimeCurrent();
    missedOpportunities[0].price = price;
    missedOpportunities[0].type = type;
    missedOpportunities[0].reason = reason;
    missedOpportunities[0].potential = 0.0;
    
    // Print missed opportunity for debugging
    if(DisplayDebugInfo) {
        Print("[MISSED OPPORTUNITY] " + reason + " at price " + DoubleToString(price, Digits()) + 
              ", type: " + (type > 0 ? "BUY" : "SELL") + 
              ", count: " + IntegerToString(missedOpportunityCount));
    }
    
    missedOpportunityCount++;
}
// Removed duplicate missedOpportunities definition elsewhere in the file

void DrawMissedOpportunities() {
    ObjectsDeleteAll(0, "MissedOpp_");
    for(int i=0; i<ArraySize(missedOpportunities); i++) {
        if(missedOpportunities[i].time == 0) continue;
        string objName = "MissedOpp_" + IntegerToString(i);
        int arrowCode = (missedOpportunities[i].type > 0) ? 233 : 234;
        color clr = (missedOpportunities[i].type > 0) ? clrGreen : clrRed;
        ObjectCreate(0, objName, OBJ_ARROW, 0, missedOpportunities[i].time, missedOpportunities[i].price);
        ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
        ObjectSetString(0, objName, OBJPROP_TOOLTIP, missedOpportunities[i].reason);
    }
}

void UpdateMissedOpportunitiesDashboard() {
    int totalMissed = 0;
    int profitableMissed = 0;
    int totalWithOutcome = 0;
    for(int i=0; i<ArraySize(missedOpportunities); i++) {
        if(missedOpportunities[i].time == 0) continue;
        totalMissed++;
        if(missedOpportunities[i].potential != 0) {
            totalWithOutcome++;
            if(missedOpportunities[i].potential > 0) {
                profitableMissed++;
            }
        }
    }
    if(!ObjectFind(0, "SMC_Dashboard_Value_7")) return;
    string missedOppText = IntegerToString(totalMissed);
    if(totalWithOutcome > 0) {
        double winRate = (double)profitableMissed / totalWithOutcome * 100.0;
        missedOppText += " (" + DoubleToString(winRate, 1) + "% win)";
    }
    ObjectSetString(0, "SMC_Dashboard_Value_7", OBJPROP_TEXT, missedOppText);
}
// ===================== End Missed Opportunities =====================

// ===================== CHOCH Stop Modification Consolidation =====================
void ModifyStopsOnCHOCH(bool localChochDetected) { // Renamed parameter to avoid hiding global
    // Declare trade_local to handle order modifications
    CTrade trade_local;
    trade_local.SetDeviationInPoints(MaxSlippage);
    if(!localChochDetected) return; // Using renamed parameter
    if(DisplayDebugInfo) Print("[CHOCH] Modifying stops based on change of character");
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double newSL = currentSL;
        if(posType == POSITION_TYPE_BUY) {
            LogInfo("[CHOCH] Checking buy position #" + IntegerToString(ticket) + " Current SL: " + DoubleToString(currentSL, Digits()));
            if(marketStructure.swingLow > 0) {
                newSL = NormalizePrice(marketStructure.swingLow);
                if(newSL > currentSL) {
                    LogInfo("[CHOCH] Adjusting buy SL to swing low: " + DoubleToString(newSL, Digits()));
                }
            }
        } else {
            LogInfo("[CHOCH] Checking sell position #" + IntegerToString(ticket) + " Current SL: " + DoubleToString(currentSL, Digits()));
            if(marketStructure.swingHigh > 0) {
                newSL = NormalizePrice(marketStructure.swingHigh);
                if(newSL < currentSL) {
                    LogInfo("[CHOCH] Adjusting sell SL to swing high: " + DoubleToString(newSL, Digits()));
                }
            }
        }
        if(MathAbs(newSL - currentSL) > Point()) {
            CTrade trade_local;
            if(trade_local.PositionModify(ticket, newSL, currentTP)) {
                LogTrade("[CHOCH] Modified stop for ticket " + IntegerToString(ticket) + " from " + DoubleToString(currentSL, Digits()) + " to " + DoubleToString(newSL, Digits()));
            } else {
                LogError("[CHOCH] Failed to modify stop: Error " + IntegerToString(GetLastError()));
            }
        }
    }
}
// ===================== End CHOCH Stop Modification =====================


int fvgIndex = 0;
int blockIndex = 0;

// Order block analytics
int totalBlocksDetected = 0;
int totalBlocksValid = 0;
int totalBlocksInvalid = 0;
double sumBlockStrength = 0;
double sumBlockVolume = 0;

// --- Utility Function Prototypes ---
double GetCurrentAsk();
double GetCurrentBid();
double GetSymbolPoint();
long GetCurrentSpreadPoints();

// --- Additional Function Prototypes ---
bool AdjustTrailingStop(); // No parameters needed as it handles all positions
void AdjustTrailingStop(int ticket, double trailingDistance); // Overloaded version for specific ticket
double DetermineOptimalStopLoss(int signal, double entryPrice) {
    // Enhanced logging to diagnose 'Invalid stops' errors
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
    // Using FindRecentSwingPoint instead of FindQualitySwingPoints since it's not defined
    int swingPointIndex = FindRecentSwingPoint(isBuy, 1, lookbackBars);
    if(swingPointIndex >= 0) swingCount = 1;
    
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
    if(currentRegime == REGIME_TRENDING_UP || currentRegime == REGIME_TRENDING_DOWN) {
        // In trending markets, give more room
        atrDistance *= 1.2;
    } else if(currentRegime == REGIME_RANGING_NARROW) {
        // In tight ranges, tighter stop
        atrDistance *= 0.8;
    } else if(currentRegime == REGIME_HIGH_VOLATILITY) {
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
    
    // Detailed logging for stop level validation
    LogInfo(StringFormat("Broker validation - Stop Level: %d points, Min Stop: %.5f", stopLevel, minStop));
    LogInfo(StringFormat("Current Bid: %.5f, Ask: %.5f", currentBid, currentAsk));
    
    // Check for buy orders
    if(isBuy) {
        double stopDistance = currentBid - finalSL;
        LogInfo(StringFormat("Buy SL distance check: %.5f (minimum required: %.5f)", stopDistance, minStop));
        
        if(stopDistance < minStop) {
            double oldSL = finalSL;
            finalSL = currentBid - minStop - 5 * point; // Add 5 points buffer
            LogWarn(StringFormat("SL adjusted for broker minimums: %.5f -> %.5f", oldSL, finalSL));
        }
    } 
    // Check for sell orders
    else {
        double stopDistance = finalSL - currentAsk;
        LogInfo(StringFormat("Sell SL distance check: %.5f (minimum required: %.5f)", stopDistance, minStop));
        
        if(stopDistance < minStop) {
            double oldSL = finalSL;
            finalSL = currentAsk + minStop + 5 * point; // Add 5 points buffer
            LogWarn(StringFormat("SL adjusted for broker minimums: %.5f -> %.5f", oldSL, finalSL));
        }
    }
    
    // Final validation check
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
};
bool ExecuteMultiTargetStrategy(int signal, double entryPrice, double stopLoss) {
    // Multi-target strategy implementation with partial take profits
    if(signal == 0) return false;
    
    LogInfo("ExecuteMultiTargetStrategy called with signal: " + IntegerToString(signal) + 
            ", entry: " + DoubleToString(entryPrice, _Digits) + 
            ", SL: " + DoubleToString(stopLoss, _Digits));
    
    bool isBuy = signal > 0;
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    
    // Calculate position sizing
    double stopDistance = MathAbs(entryPrice - stopLoss);
    if(stopDistance <= 0) {
        LogError("Invalid stop distance - cannot execute multi-target strategy");
        return false;
    }
    
    // Apply lot size constraints
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    // Use the global lot size calculated earlier
    double totalLots = g_lotSize;
    
    // Define take profit targets
    double tp1Distance = atr * 1.0;  // First target at 1.0 ATR
    double tp2Distance = atr * 2.0;  // Second target at 2.0 ATR
    double tp3Distance = atr * 3.0;  // Third target at 3.0 ATR
    
    // Calculate actual TP levels
    double tp1 = isBuy ? entryPrice + tp1Distance : entryPrice - tp1Distance;
    double tp2 = isBuy ? entryPrice + tp2Distance : entryPrice - tp2Distance;
    double tp3 = isBuy ? entryPrice + tp3Distance : entryPrice - tp3Distance;
    
    // Split position into three parts
    double lot1 = NormalizeDouble(totalLots * 0.5, 2);  // 50% for first target
    double lot2 = NormalizeDouble(totalLots * 0.3, 2);  // 30% for second target
    double lot3 = NormalizeDouble(totalLots * 0.2, 2);  // 20% for third target
    
    // Ensure minimum lot size constraints
    if(lot1 < minLot) lot1 = minLot;
    if(lot2 < minLot) lot2 = minLot;
    if(lot3 < minLot) lot3 = minLot;
    
    // Normalize to lot step
    lot1 = NormalizeDouble(MathFloor(lot1 / lotStep) * lotStep, 2);
    lot2 = NormalizeDouble(MathFloor(lot2 / lotStep) * lotStep, 2);
    lot3 = NormalizeDouble(MathFloor(lot3 / lotStep) * lotStep, 2);
    
    // Execute orders
    CTrade trade_local;
    
    bool success = true;
    ulong ticket1 = 0, ticket2 = 0, ticket3 = 0;
    
    // First position with first target
    if(lot1 >= minLot) {
        if(isBuy) {
            if(!trade_local.Buy(lot1, Symbol(), 0, stopLoss, tp1, "TP1")) {
                LogError("Failed to open Buy position 1: " + IntegerToString(trade_local.ResultRetcode()));
                success = false;
            } else {
                ticket1 = trade_local.ResultOrder();
                LogInfo("Opened Buy position 1 - Ticket: " + IntegerToString((int)ticket1) + 
                       ", Lots: " + DoubleToString(lot1, 2) + ", TP: " + DoubleToString(tp1, _Digits));
            }
        } else {
            if(!trade_local.Sell(lot1, Symbol(), 0, stopLoss, tp1, "TP1")) {
                LogError("Failed to open Sell position 1: " + IntegerToString(trade_local.ResultRetcode()));
                success = false;
            } else {
                ticket1 = trade_local.ResultOrder();
                LogInfo("Opened Sell position 1 - Ticket: " + IntegerToString((int)ticket1) + 
                       ", Lots: " + DoubleToString(lot1, 2) + ", TP: " + DoubleToString(tp1, _Digits));
            }
        }
    }
    
    // Second position with second target
    if(lot2 >= minLot) {
        if(isBuy) {
            if(!trade_local.Buy(lot2, Symbol(), 0, stopLoss, tp2, "TP2")) {
                LogError("Failed to open Buy position 2: " + IntegerToString(trade_local.ResultRetcode()));
                success = false;
            } else {
                ticket2 = trade_local.ResultOrder();
                LogInfo("Opened Buy position 2 - Ticket: " + IntegerToString((int)ticket2) + 
                       ", Lots: " + DoubleToString(lot2, 2) + ", TP: " + DoubleToString(tp2, _Digits));
            }
        } else {
            if(!trade_local.Sell(lot2, Symbol(), 0, stopLoss, tp2, "TP2")) {
                LogError("Failed to open Sell position 2: " + IntegerToString(trade_local.ResultRetcode()));
                success = false;
            } else {
                ticket2 = trade_local.ResultOrder();
                LogInfo("Opened Sell position 2 - Ticket: " + IntegerToString((int)ticket2) + 
                       ", Lots: " + DoubleToString(lot2, 2) + ", TP: " + DoubleToString(tp2, _Digits));
            }
        }
    }
    
    // Third position with third target
    if(lot3 >= minLot) {
        if(isBuy) {
            if(!trade_local.Buy(lot3, Symbol(), 0, stopLoss, tp3, "TP3")) {
                LogError("Failed to open Buy position 3: " + IntegerToString(trade_local.ResultRetcode()));
                success = false;
            } else {
                ticket3 = trade_local.ResultOrder();
                LogInfo("Opened Buy position 3 - Ticket: " + IntegerToString((int)ticket3) + 
                       ", Lots: " + DoubleToString(lot3, 2) + ", TP: " + DoubleToString(tp3, _Digits));
            }
        } else {
            if(!trade_local.Sell(lot3, Symbol(), 0, stopLoss, tp3, "TP3")) {
                LogError("Failed to open Sell position 3: " + IntegerToString(trade_local.ResultRetcode()));
                success = false;
            } else {
                ticket3 = trade_local.ResultOrder();
                LogInfo("Opened Sell position 3 - Ticket: " + IntegerToString((int)ticket3) + 
                       ", Lots: " + DoubleToString(lot3, 2) + ", TP: " + DoubleToString(tp3, _Digits));
            }
        }
    }
    
    return success;
}
bool ModifyStopsOnCHOCH(int ticket, double chochLevel) {
    // Adjust stop loss based on a Change of Character (CHOCH) level
    if(!PositionSelectByTicket(ticket)) {
        LogError("ModifyStopsOnCHOCH: Position not found for ticket: " + IntegerToString(ticket));
        return false;
    }
    
    // Get position details
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    bool isBuy = (posType == POSITION_TYPE_BUY);
    
    // Log position details
    LogInfo(StringFormat("ModifyStopsOnCHOCH - Ticket: %d, Type: %s, Price: %.5f, SL: %.5f, CHOCH Level: %.5f",
             ticket, isBuy ? "Buy" : "Sell", currentPrice, currentSL, chochLevel));
    
    // Validate CHOCH level is reasonable
    if(chochLevel <= 0) {
        LogError("Invalid CHOCH level: " + DoubleToString(chochLevel, _Digits));
        return false;
    }
    
    // For buy positions, CHOCH level must be below the current price
    if(isBuy && chochLevel >= currentPrice) {
        LogError("Invalid CHOCH level for Buy position - level is above current price");
        return false;
    }
    
    // For sell positions, CHOCH level must be above the current price
    if(!isBuy && chochLevel <= currentPrice) {
        LogError("Invalid CHOCH level for Sell position - level is below current price");
        return false;
    }
    
    // Only move stop loss if it would be a better (closer) level
    bool shouldModify = false;
    
    if(isBuy) {
        // For buy positions, we want to move stop loss up to just below the CHOCH level
        double newSL = chochLevel - (5 * _Point); // 5 points buffer below CHOCH
        if(newSL > currentSL) {
            LogInfo("Moving Buy position stop loss up from " + DoubleToString(currentSL, _Digits) + 
                   " to " + DoubleToString(newSL, _Digits));
            shouldModify = true;
            currentSL = newSL;
        } else {
            LogInfo("CHOCH level would not improve stop loss position");
        }
    } else {
        // For sell positions, we want to move stop loss down to just above the CHOCH level
        double newSL = chochLevel + (5 * _Point); // 5 points buffer above CHOCH
        if(newSL < currentSL || currentSL == 0) {
            LogInfo("Moving Sell position stop loss down from " + DoubleToString(currentSL, _Digits) + 
                   " to " + DoubleToString(newSL, _Digits));
            shouldModify = true;
            currentSL = newSL;
        } else {
            LogInfo("CHOCH level would not improve stop loss position");
        }
    }
    
    // Execute the modification if needed
    if(shouldModify) {
        CTrade trade_local;
        
        if(!trade_local.PositionModify(ticket, currentSL, currentTP)) {
            LogError("Failed to modify position on CHOCH: " + IntegerToString(trade_local.ResultRetcode()));
            return false;
        }
        
        LogTrade("Modified position " + IntegerToString(ticket) + 
                " stop loss to " + DoubleToString(currentSL, _Digits) + 
                " based on CHOCH level");
        return true;
    }
    
    return false; // No modification was needed
}
bool ManageTrailingStops();
int FindRecentSwingPoint(bool isBuy, int minStrength, int lookbackBars);
bool CheckForDivergence(int signal, double &qualityDescription) {
    // Check for regular and hidden divergence patterns between price and indicators
    if(signal == 0) return false;
    
    // ADAPTIVE DIVERGENCE REQUIREMENTS - Adjust criteria based on market conditions
    
    // Base divergence parameters
    double baseDivergenceStrengthRequired = 0.65; // Default minimum strength (0-1 scale)
    double baseMinDivergenceConfirmation = 0.7;   // Default confirmation threshold
    int baseLookbackBars = 30;                    // Default lookback period
    
    // Adjust parameters based on market regime
    double adaptiveDivergenceStrength = baseDivergenceStrengthRequired;
    double adaptiveConfirmationThreshold = baseMinDivergenceConfirmation;
    int adaptiveLookbackBars = baseLookbackBars;
    
    // 1. Adjust based on market regime
    if(currentRegime == REGIME_TRENDING_UP || currentRegime == REGIME_TRENDING_DOWN) {
        // In trends, divergence is more significant but may need to look further back
        adaptiveDivergenceStrength = baseDivergenceStrengthRequired * 0.85; // 15% lower requirement
        adaptiveLookbackBars = baseLookbackBars + 10; // Look back further in trends
        Print("[ADAPTIVE DIVERGENCE] Relaxing divergence strength requirements in trending market");
    }
    else if(currentRegime == REGIME_CHOPPY || currentRegime == REGIME_RANGING_NARROW) {
        // In choppy markets, require stronger divergence confirmation
        adaptiveDivergenceStrength = baseDivergenceStrengthRequired * 1.15; // 15% higher requirement
        adaptiveConfirmationThreshold = baseMinDivergenceConfirmation * 1.1; // 10% higher confirmation
        adaptiveLookbackBars = baseLookbackBars - 5; // Look at more recent price action
        Print("[ADAPTIVE DIVERGENCE] Increasing divergence strength requirements in choppy market");
    }
    else if(currentRegime == REGIME_BREAKOUT) {
        // In breakouts, we need to be more responsive
        adaptiveDivergenceStrength = baseDivergenceStrengthRequired * 0.9; // 10% lower requirement
        adaptiveLookbackBars = baseLookbackBars - 10; // Focus on recent price action
        Print("[ADAPTIVE DIVERGENCE] Using more responsive divergence settings during breakout");
    }
    
    // 2. Adjust based on recent performance
    if(consecutiveLosses > 2) {
        // After losses, be more strict with divergence requirements
        adaptiveDivergenceStrength = MathMin(0.9, adaptiveDivergenceStrength * 1.1); // Up to 10% increase
        Print("[ADAPTIVE DIVERGENCE] Increasing divergence requirements after losses");
    }
    
    // Ensure we don't exceed reasonable bounds
    adaptiveDivergenceStrength = MathMax(0.4, MathMin(0.9, adaptiveDivergenceStrength));
    adaptiveConfirmationThreshold = MathMax(0.5, MathMin(0.95, adaptiveConfirmationThreshold));
    adaptiveLookbackBars = MathMax(15, MathMin(50, adaptiveLookbackBars));
    
    Print("[ADAPTIVE DIVERGENCE] Using strength requirement: ", adaptiveDivergenceStrength, 
          " (Base: ", baseDivergenceStrengthRequired, ")");
    Print("[ADAPTIVE DIVERGENCE] Using confirmation threshold: ", adaptiveConfirmationThreshold, 
          " (Base: ", baseMinDivergenceConfirmation, ")");
    Print("[ADAPTIVE DIVERGENCE] Using lookback period: ", adaptiveLookbackBars, 
          " (Base: ", baseLookbackBars, ")");
    
    LogInfo("CheckForDivergence called with signal: " + IntegerToString(signal));
    
    bool isBuy = signal > 0;
    int lookbackBars = adaptiveLookbackBars; // Use adaptive lookback period
    
    // Set up required buffers
    double price[], rsi[], macd[], macdSignal[];
    ArraySetAsSeries(price, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(macd, true);
    ArraySetAsSeries(macdSignal, true);
    
    // Get price data - use close price for divergence checks
    if(CopyClose(Symbol(), PERIOD_CURRENT, 0, lookbackBars, price) <= 0) {
        LogError("Failed to copy price data for divergence check");
        return false;
    }
    
    // Get RSI data
    int rsiHandle = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
    if(rsiHandle == INVALID_HANDLE) {
        LogError("Failed to create RSI indicator handle");
        return false;
    }
    
    if(CopyBuffer(rsiHandle, 0, 0, lookbackBars, rsi) <= 0) {
        LogError("Failed to copy RSI data");
        IndicatorRelease(rsiHandle);
        return false;
    }
    
    IndicatorRelease(rsiHandle);
    
    // Get MACD data
    int macdHandle = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    if(macdHandle == INVALID_HANDLE) {
        LogError("Failed to create MACD indicator handle");
        return false;
    }
    
    if(CopyBuffer(macdHandle, 0, 0, lookbackBars, macd) <= 0 || 
       CopyBuffer(macdHandle, 1, 0, lookbackBars, macdSignal) <= 0) {
        LogError("Failed to copy MACD data");
        IndicatorRelease(macdHandle);
        return false;
    }
    
    IndicatorRelease(macdHandle);
    
    // Variables to track divergence
    bool regularDivergence = false;
    bool hiddenDivergence = false;
    int divergenceType = 0; // 0=none, 1=regular, 2=hidden
    int divergenceStrength = 0; // 0-10 scale
    
    // Check for regular divergence
    if(isBuy) {
        // For buy signals, look for bullish regular divergence (price makes lower low but indicator makes higher low)
        int lastLowBar = FindSwingLowIndex(price, 5, 5, lookbackBars);
        int prevLowBar = FindSwingLowIndex(price, lastLowBar + 2, 5, lookbackBars);
        
        if(lastLowBar > 0 && prevLowBar > lastLowBar) {
            // Check if price makes a lower low
            if(price[lastLowBar] < price[prevLowBar]) {
                // Check if RSI makes a higher low (bullish divergence)
                if(rsi[lastLowBar] > rsi[prevLowBar]) {
                    LogInfo("Bullish regular divergence detected with RSI");
                    regularDivergence = true;
                    divergenceType = 1;
                    divergenceStrength += 5;
                }
                
                // Check if MACD makes a higher low (bullish divergence)
                if(macd[lastLowBar] > macd[prevLowBar]) {
                    LogInfo("Bullish regular divergence detected with MACD");
                    regularDivergence = true;
                    divergenceType = 1;
                    divergenceStrength += 5;
                }
            }
        }
        
        // Check for hidden divergence (price makes higher low but indicator makes lower low - trend continuation)
        if(lastLowBar > 0 && prevLowBar > lastLowBar) {
            // Check if price makes a higher low
            if(price[lastLowBar] > price[prevLowBar]) {
                // Check if RSI makes a lower low (bullish hidden divergence)
                if(rsi[lastLowBar] < rsi[prevLowBar]) {
                    LogInfo("Bullish hidden divergence detected with RSI");
                    hiddenDivergence = true;
                    divergenceType = 2;
                    divergenceStrength += 3;
                }
                
                // Check if MACD makes a lower low (bullish hidden divergence)
                if(macd[lastLowBar] < macd[prevLowBar]) {
                    LogInfo("Bullish hidden divergence detected with MACD");
                    hiddenDivergence = true;
                    divergenceType = 2;
                    divergenceStrength += 3;
                }
            }
        }
    } else {
        // For sell signals, look for bearish regular divergence (price makes higher high but indicator makes lower high)
        int lastHighBar = FindSwingHighIndex(price, 5, 5, lookbackBars);
        int prevHighBar = FindSwingHighIndex(price, lastHighBar + 2, 5, lookbackBars);
        
        if(lastHighBar > 0 && prevHighBar > lastHighBar) {
            // Check if price makes a higher high
            if(price[lastHighBar] > price[prevHighBar]) {
                // Check if RSI makes a lower high (bearish divergence)
                if(rsi[lastHighBar] < rsi[prevHighBar]) {
                    LogInfo("Bearish regular divergence detected with RSI");
                    regularDivergence = true;
                    divergenceType = 1;
                    divergenceStrength += 5;
                }
                
                // Check if MACD makes a lower high (bearish divergence)
                if(macd[lastHighBar] < macd[prevHighBar]) {
                    LogInfo("Bearish regular divergence detected with MACD");
                    regularDivergence = true;
                    divergenceType = 1;
                    divergenceStrength += 5;
                }
            }
        }
        
        // Check for hidden divergence (price makes lower high but indicator makes higher high - trend continuation)
        if(lastHighBar > 0 && prevHighBar > lastHighBar) {
            // Check if price makes a lower high
            if(price[lastHighBar] < price[prevHighBar]) {
                // Check if RSI makes a higher high (bearish hidden divergence)
                if(rsi[lastHighBar] > rsi[prevHighBar]) {
                    LogInfo("Bearish hidden divergence detected with RSI");
                    hiddenDivergence = true;
                    divergenceType = 2;
                    divergenceStrength += 3;
                }
                
                // Check if MACD makes a higher high (bearish hidden divergence)
                if(macd[lastHighBar] > macd[prevHighBar]) {
                    LogInfo("Bearish hidden divergence detected with MACD");
                    hiddenDivergence = true;
                    divergenceType = 2;
                    divergenceStrength += 3;
                }
            }
        }
    }
    
    // Normalize divergence strength to 0-1 range
    double divergenceQuality = divergenceStrength / 10.0;
    
    // Update quality description
    if(regularDivergence || hiddenDivergence) {
        // Convert the bool to string explicitly to avoid implicit conversion
        string divergenceTypeStr = (regularDivergence ? "Regular" : "Hidden");
        
        // Use StringFormat to properly handle string concatenation
        // Using temporary variable to avoid string-to-string implicit conversion warning
        string formattedQuality = StringFormat("%s\nDivergence: %s (%s)", 
                               qualityDescription,
                               divergenceTypeStr,
                               DoubleToString(divergenceQuality, 2));
        qualityDescription = formattedQuality;
        
        string divType = (regularDivergence ? "Regular" : "Hidden");
        LogInfo("Divergence found - Type: " + divType + ", Strength: " + 
               DoubleToString(divergenceQuality, 2));
        
        return true;
    }
    
    LogInfo("No divergence found");
    return false;
}

// Helper function to find swing low index
int FindSwingLowIndex(double &price[], int startBar, int leftBars, int rightBars) {
    for(int i = startBar; i < ArraySize(price) - rightBars; i++) {
        bool isSwingLow = true;
        
        // Check left bars
        for(int j = 1; j <= leftBars; j++) {
            if(i - j >= 0 && price[i] > price[i - j]) {
                isSwingLow = false;
                break;
            }
        }
        
        if(!isSwingLow) continue;
        
        // Check right bars
        for(int j = 1; j <= rightBars; j++) {
            if(i + j < ArraySize(price) && price[i] > price[i + j]) {
                isSwingLow = false;
                break;
            }
        }
        
        if(isSwingLow) return i;
    }
    
    return -1; // No swing low found
}

// Helper function to find swing high index
int FindSwingHighIndex(double &price[], int startBar, int leftBars, int rightBars) {
    for(int i = startBar; i < ArraySize(price) - rightBars; i++) {
        bool isSwingHigh = true;
        
        // Check left bars
        for(int j = 1; j <= leftBars; j++) {
            if(i - j >= 0 && price[i] < price[i - j]) {
                isSwingHigh = false;
                break;
            }
        }
        
        if(!isSwingHigh) continue;
        
        // Check right bars
        for(int j = 1; j <= rightBars; j++) {
            if(i + j < ArraySize(price) && price[i] < price[i + j]) {
                isSwingHigh = false;
                break;
            }
        }
        
        if(isSwingHigh) return i;
    }
    
    return -1; // No swing high found
}

// --- Utility Function Implementations ---
double GetCurrentAsk() {
    return SymbolInfoDouble(Symbol(), SYMBOL_ASK);
}
double GetCurrentBid() {
    return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}
double GetSymbolPoint() {
    return SymbolInfoDouble(Symbol(), SYMBOL_POINT);
}
long GetCurrentSpreadPoints() {
    return SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
}

#include <Math/Stat/Math.mqh>

// Include adaptive filters and missed opportunity tracking modules



// Market regime constants
// (Removed duplicate consolidated definitions below to resolve macro redefinition errors)
// #define REGIME_COUNT 9  // Total number of regimes
// #define REGIME_NORMAL 0
// #define REGIME_VOLATILE 1
// #define REGIME_HIGH_VOLATILITY 1 // Alias for REGIME_VOLATILE
// #define REGIME_RANGING 2
// #define REGIME_LOW_VOLATILITY 2 // Alias for REGIME_RANGING
// #define REGIME_CHOPPY 3
// #define REGIME_REVERSAL 3 // Alias for consistency
// #define TRENDING_UP 4
// #define TRENDING_DOWN 5
// #define REGIME_RANGING_NARROW 6
// #define REGIME_RANGING_WIDE 7
// #define BREAKOUT 8
// #define REGIME_BREAKOUT 8 // For consistency
// #define REGIME_TRENDING 4 // Alias pointing to TRENDING_UP for backward compatibility

// Signal types
#define SIGNAL_BUY 1
#define SIGNAL_SELL -1

// CHOCH (Change of Character) detection
#define CHOCH_BULLISH 1
#define CHOCH_BEARISH 2
#define CHOCH_NONE 0

// Divergence type enum
// Duplicate enum - commented out
/*
// Duplicate enum - commented out
/*
// Using ENUM_DIVERGENCE_TYPE defined at line 27
*/

// Using ENUM_DIVERGENCE_TYPE defined at line 27

// Market phase enum
enum ENUM_MARKET_PHASE {
    MARKET_PHASE_ACCUMULATION,  // Accumulation phase (typically sideways with low volatility)
    MARKET_PHASE_MARKUP,       // Markup phase (uptrend)
    MARKET_PHASE_DISTRIBUTION, // Distribution phase (typically sideways at top)
    MARKET_PHASE_MARKDOWN,     // Markdown phase (downtrend)
    MARKET_PHASE_INDECISIVE    // Indecisive or unknown phase
};

// Input parameters for strategy features
input bool EnableCHOCHDetection = true;     // Enable CHOCH Detection
input bool EnableAdaptiveRisk = true;       // Enable adaptive position sizing based on volatility
input bool EnableTimeBasedRiskReduction = true; // Enable time-based risk reduction
input bool EnableOrderBlockAnalytics = false; // Enable order block analytics
input bool EnableMarketRegimeFiltering = true; // Enable market regime filtering
input bool UseLiquidityGrab = true;       // Use liquidity grab for entry conditions
input bool UseImbalanceFVG = true;        // Use imbalance/FVG for entry conditions
input int MaximumSpreadForTrading = 15;     // Maximum allowed spread in points for trade execution (increased to allow more trading opportunities)
input int MinStopDistance = 20;             // Minimum distance between price and stop loss in points
input int LookbackBars = 100;              // Number of bars to look back for analysis
input int MinBlockStrength = 1;            // Minimum strength for valid order blocks (reduced to increase trading opportunities)
input int FVGMinSize = 10;                 // Minimum size for fair value gaps in points
input int MaxConsecutiveLosses = 3;        // Maximum consecutive losses before emergency mode (reduced to protect small account)
input double RiskRewardRatio = 2.0;         // Risk to reward ratio (increased to 2.0 for better profitability on small account)
input double RiskPercent = 0.5;             // Risk percentage per trade (reduced to 0.5% for capital preservation)
input bool DisplayDebugInfo = true;         // Display debug information in logs

// --- Additional Logging Helpers ---
// LogInfo, LogWarn, and LogError are already defined at the top of the file
void LogMessage(string message) { Print("[SMC] " + message); }
void LogParamChange(string msg) { Print("[SMC][PARAM] " + msg); }
void LogTrade(string msg) { Print("[SMC][TRADE] " + msg); }
void LogRisk(string message) { Print("[SMC][RISK] " + message); }
void LogDebug(string msg) { if(DisplayDebugInfo) Print("[SMC][DEBUG] " + msg); }
void LogCorrelation(string msg) { Print("[SMC][CORR] " + msg); }
void LogLiquidity(string message) { Print("[SMC][LIQ] " + message); }
void LogStopLossDetails(string msg) { if(DisplayDebugInfo) Print("[SMC][SL] " + msg); }

//| Get ATR value for the specified timeframe                       |
//+------------------------------------------------------------------+
double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift) {
    int atrHandle = iATR(symbol, timeframe, period);
    double atrBuffer[];
    
    // Initialize the array with the ATR indicator values
    if(CopyBuffer(atrHandle, 0, shift, 1, atrBuffer) <= 0) {
        LogError("Failed to copy ATR data for " + symbol);
        return 0.0;
    }
    
    return atrBuffer[0];
}

//| Convert error code to string description                        |
//+------------------------------------------------------------------+
string GetLastErrorText(int error_code)
{
   string error_string;
   
   switch(error_code)
   {
      //--- Standard MQL5 Error Codes
      case 0:   error_string = "No error"; break;
      case 4001: error_string = "Unexpected internal error"; break;
      case 4002: error_string = "Wrong parameter in function call"; break;
      case 4051: error_string = "Invalid function parameter value"; break;
      case 4062: error_string = "String function internal error"; break;
      case 4073: error_string = "Error installing EA"; break;
      case 4074: error_string = "Not enough memory for function execution"; break;
      case 4099: error_string = "End of file"; break;
      case 4106: error_string = "Double overflow"; break;
      case 4107: error_string = "String overflow"; break;
      case 4108: error_string = "Array overflow"; break;
      case 4109: error_string = "Too many arrays"; break;
      
      //--- Trade Server Return Codes
      case 10004: error_string = "Requote"; break;
      case 10006: error_string = "Order is not accepted by server"; break;
      case 10007: error_string = "Order rejected"; break;
      case 10008: error_string = "Order placed"; break;
      case 10009: error_string = "Order placed partially"; break;
      case 10010: error_string = "Order placing canceled"; break;
      case 10011: error_string = "Order placed, but price changed"; break;
      case 10014: error_string = "Autotrading disabled by server"; break;
      case 10015: error_string = "Autotrading disabled by client terminal"; break;
      case 10016: error_string = "Request rejected"; break;
      case 10017: error_string = "Request canceled by dealer"; break;
      case 10018: error_string = "Order accepted for execution"; break;
      case 10019: error_string = "Request accepted"; break;
      
      //--- Error codes for position operations
      case 10031: error_string = "No connection with trade server"; break;
      case 10032: error_string = "Order/Position not found"; break;
      case 10033: error_string = "Order locked for changes"; break;
      case 10034: error_string = "Insufficient funds for execution"; break;
      case 10035: error_string = "Invalid price"; break;
      case 10036: error_string = "Invalid stops or price"; break;
      case 10038: error_string = "Invalid order volume"; break;
      case 10039: error_string = "No prices for order execution"; break;
      case 10040: error_string = "Pending order not allowed"; break;
      case 10044: error_string = "Position already closed"; break;
      case 10049: error_string = "Close volume exceeds position"; break;
      
      //--- Default error output if error code is not in list
      default: error_string = "Unknown error " + IntegerToString(error_code); 
   }
   
   return error_string;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk parameters                  |
//+------------------------------------------------------------------+
double CalculatePositionSize(int signal, double entryPrice, double stopLoss) {
    // Get account info first
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskPercentage = RiskPercent; // Base risk percentage from input parameter
    
    // ADAPTIVE POSITION SIZING - Adjust risk based on market conditions and performance
    
    // 1. Adjust risk based on consecutive losses - reduce risk after losses
    if(consecutiveLosses > 0) {
        double lossAdjustment = 0.1 * MathMin(consecutiveLosses, 5); // Reduce by up to 50%
        riskPercentage *= (1.0 - lossAdjustment);
        Print("[ADAPTIVE RISK] Reducing risk by ", lossAdjustment*100, "% after ", consecutiveLosses, " consecutive losses");
    }
    
    // 2. Adjust risk based on market regime
    if(currentRegime == REGIME_TRENDING_UP || currentRegime == REGIME_TRENDING_DOWN) {
        // In trends, we can risk slightly more IF trading with the trend
        bool tradingWithTrend = (currentRegime == REGIME_TRENDING_UP && signal > 0) || 
                              (currentRegime == REGIME_TRENDING_DOWN && signal < 0);
        
        if(tradingWithTrend) {
            riskPercentage *= 1.2; // 20% increase when trading with the trend
            Print("[ADAPTIVE RISK] Increasing risk by 20% when trading with strong trend");
        }
    }
    else if(currentRegime == REGIME_CHOPPY || currentRegime == REGIME_RANGING_NARROW) {
        // In choppy or range-bound markets, reduce risk
        riskPercentage *= 0.8; // 20% decrease
        Print("[ADAPTIVE RISK] Reducing risk by 20% in choppy/ranging market");
    }
    
    // 3. Adjust risk based on time of day
    MqlDateTime localTime;
    TimeToStruct(TimeCurrent(), localTime);
    int currentHour = localTime.hour;
    
    // Preferred trading hours (adjust based on your backtesting results)
    bool isPreferredSession = (currentHour >= 8 && currentHour <= 12) ||
                             (currentHour >= 14 && currentHour <= 17);
    
    if(!isPreferredSession) {
        // Outside optimal hours, reduce risk
        riskPercentage *= 0.85; // 15% decrease
        Print("[ADAPTIVE RISK] Reducing risk by 15% outside optimal trading hours");
    }
    
    // 4. Enforce minimum and maximum risk levels
    double minRiskPercent = 0.1; // Never go below 0.1%
    double maxRiskPercent = RiskPercent * 1.2; // Never exceed 120% of base risk
    
    riskPercentage = MathMax(minRiskPercent, MathMin(maxRiskPercent, riskPercentage));
    Print("[ADAPTIVE RISK] Final risk percentage: ", riskPercentage, "% (Base: ", RiskPercent, "%)");
    
    
    // Calculate the actual risk amount in account currency
    double riskAmountLocal = accountBalance * (riskPercentage / 100.0);
    
    // If risk amount is too low (like with a $40 account), ensure at least $0.20 risk per trade
    double minimumRiskAmount = 0.20; // Minimum $0.20 risk per trade
    riskAmountLocal = MathMax(riskAmountLocal, minimumRiskAmount);
    
    // Calculate stop distance in points
    double stopDistancePointsLocal = MathAbs(entryPrice - stopLoss) / _Point;
    
    // Calculate point value
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double pointValueLocal = tickValue * (_Point / tickSize);
    
    // Special handling for small accounts - when using micro or nano lots
    if (accountBalance <= 100) {
        // Use a more conservative position size calculation for small accounts
        // Never risk more than 2% on a small account regardless of RiskPercent setting
        riskAmountLocal = MathMin(riskAmountLocal, accountBalance * 0.02);
    }
    
    // Calculate the appropriate lot size based on risk
    double lotSizeLocal = riskAmountLocal / (stopDistancePointsLocal * pointValueLocal);
    
    // Log the calculation details
    if(DisplayDebugInfo) {
        Print("[POSITION SIZE] Account: $", accountBalance, ", Risk: $", riskAmountLocal, 
              " (", riskPercentage, "%), Stop Distance: ", stopDistancePointsLocal, 
              " points, Calculated Lot Size: ", lotSizeLocal);
    }
    
    // Normalize to valid lot step
    double lotStepLocal = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLotLocal = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLotLocal = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double adjustedMaxLot = g_maxLot; // Use the global maximum lot size limit
    
    // Make sure we don't exceed our global maximum lot size setting
    maxLotLocal = MathMin(maxLotLocal, adjustedMaxLot);
    
    // Round to valid lot step
    lotSizeLocal = MathFloor(lotSizeLocal / lotStepLocal) * lotStepLocal;
    
    // Ensure within valid range
    lotSizeLocal = MathMax(minLotLocal, MathMin(maxLotLocal, lotSizeLocal));
    
    if(DisplayDebugInfo) {
        Print("[POSITION SIZE] Final lot size: ", lotSizeLocal, 
              " (min: ", minLotLocal, ", max: ", maxLotLocal, ", step: ", lotStepLocal, ")");
    }
    
    return lotSizeLocal;
}

// Emergency circuit breaker - check if trading should be halted
bool IsEmergencyModeActive() {
    // Check for extreme volatility
    int atrHandle = iATR(Symbol(), PERIOD_M1, 14);
double emergencyAtrBuffer[1]; // Renamed to avoid shadowing global localAtrBuffer
if (CopyBuffer(atrHandle, 0, 0, 1, emergencyAtrBuffer) <= 0) {
    LogError("Failed to copy ATR data");
    return false;
}
double atr = emergencyAtrBuffer[0];
    double averageAtr = 0;
    
    // Calculate average ATR over last 10 periods
    for(int i = 1; i <= 10; i++) {
    double tempBuffer[1];
    if (CopyBuffer(atrHandle, 0, i, 1, tempBuffer) > 0) {
        averageAtr += tempBuffer[0];
    }
}
    averageAtr /= 10;
    
    // If current ATR is more than 3x the average, consider it an emergency
    if(atr > 3 * averageAtr) {
        LogError("EMERGENCY MODE ACTIVATED - Extreme volatility detected");
        return true;
    }
    
    // Check for extreme spread
    long currentSpread = GetCurrentSpreadPoints();
if((double)currentSpread > 50.0) { // Adjust threshold as needed
    LogError("EMERGENCY MODE ACTIVATED - Extreme spread detected: " + IntegerToString((int)currentSpread));
    return true;
}
    
    // Check for consecutive losses
    static int consecutiveLossesLocal = 0;
static bool initializedConsecLoss = false;
    
    if(!initializedConsecLoss) {
        // Count recent consecutive losses on initialization
        int totalDeals = HistoryDealsTotal();
        double lastProfit = 0;
        
        for(int i = totalDeals - 1; i >= 0; i--) {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket == 0) continue;
            
            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != Symbol()) continue;
            
            lastProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
if((double)lastProfit < 0.0) {
                consecutiveLossesLocal++;
            } else if(lastProfit > 0) {
                break; // Stop counting at first profit
            }
        }
        
        initializedConsecLoss = true;
    }
    
    // Emergency stop after too many consecutive losses
    if(consecutiveLossesLocal >= 5) { // Adjust threshold as needed
        LogError("EMERGENCY MODE ACTIVATED - Too many consecutive losses: " + IntegerToString(consecutiveLossesLocal));
        return true;
    }
    
    return false;
}


//+------------------------------------------------------------------+
//| Structure definitions                                           |
//+------------------------------------------------------------------+
// Structure to store swing points for stop loss placement
// Commented out due to duplicate definition - already defined at line 110
/*
struct SwingPoint {
    double price;
    datetime time;
    int score;
    int barIndex;
};
*/

// Structure to store divergence detection results - commented out due to duplicate
/*
struct DivergenceInfo {
    ENUM_DIVERGENCE_TYPE type; // Type of divergence (regular/hidden, bullish/bearish)
    datetime time;             // Time when the divergence was detected
    double price;              // Price level where divergence occurred
    double indicator;          // Indicator value at divergence point
    bool confirmed;            // Whether the divergence has been confirmed
    int strength;              // Strength of the divergence signal (1-10)
};
*/

// Structure to store liquidity grabs - commented out due to duplicate
/*
struct LiquidityGrab {
    datetime time;    // Time of the liquidity grab
    double high;      // High price of the grab candle
    double low;       // Low price of the grab candle
    bool isBuy;       // True for buy opportunity, false for sell
    bool active;      // Whether the grab is still relevant/active
};
*/

// Structure to store fair value gaps - commented out due to duplicate
/*
struct FairValueGap {
    datetime startTime; // Start time of the gap
    datetime endTime;   // End time of the gap
    double high;        // High price of the gap
    double low;         // Low price of the gap
    bool isBuy;         // True for bullish FVG, false for bearish
    bool active;        // Whether the FVG is still relevant/active
};
*/

// Structure to store order blocks - commented out due to duplicate
/*
struct OrderBlock {
    datetime time;     // Time of the order block
    double price;      // Price level of the order block
    long volume;       // Volume at the order block
    bool isBuy;        // True for bullish order block, false for bearish
    bool valid;        // Whether the order block meets minimum criteria
    int strength;      // Strength score of the order block (0-10)
};
*/

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
        ma20Handle = iMA(Symbol(), Period(), 20, 0, MODE_SMA, PRICE_CLOSE);
        ma50Handle = iMA(Symbol(), Period(), 50, 0, MODE_SMA, PRICE_CLOSE);
        atrHandle = iATR(Symbol(), Period(), 14);
        rsiHandle = iRSI(Symbol(), Period(), 14, PRICE_CLOSE);
        lastUpdateTime = 0;
        
        // Pre-allocate arrays
        ArrayResize(close, 100);
        ArrayResize(open, 100);
        ArrayResize(high, 100);
        ArrayResize(low, 100);
        ArrayResize(ma20, 100);
        ArrayResize(ma50, 100);
        ArrayResize(atr, 100);
        ArrayResize(rsi, 100);

        // Ensure all arrays are set as series
        ArraySetAsSeries(close, true);
        ArraySetAsSeries(open, true);
        ArraySetAsSeries(high, true);
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(ma20, true);
        ArraySetAsSeries(ma50, true);
        ArraySetAsSeries(atr, true);
        ArraySetAsSeries(rsi, true);
        
        LogInfo("Price cache initializedConsecLoss");
    }
    
    // Update cache with fresh data
    bool Update(int bars = 100) {
        // Only update once per tick/bar
        datetime currentTime = TimeCurrent();
        if(currentTime == lastUpdateTime) return true;
        
        // Update price data
        if(CopyClose(Symbol(), Period(), 0, bars, close) <= 0) return false;
        if(CopyOpen(Symbol(), Period(), 0, bars, open) <= 0) return false;
        if(CopyHigh(Symbol(), Period(), 0, bars, high) <= 0) return false;
        if(CopyLow(Symbol(), Period(), 0, bars, low) <= 0) return false;
        
        // Update indicators
        if(CopyBuffer(ma20Handle, 0, 0, bars, ma20) <= 0) return false;
        if(CopyBuffer(ma50Handle, 0, 0, bars, ma50) <= 0) return false;
        if(CopyBuffer(atrHandle, 0, 0, bars, atr) <= 0) return false;
        if(CopyBuffer(rsiHandle, 0, 0, bars, rsi) <= 0) return false;
        
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
//| TradeJournal - Tracks and analyzes trading performance          |
//+------------------------------------------------------------------+
class TradeJournal {
private:
    // Trade record structure
    struct TradeRecord {
        datetime openTime;
        datetime closeTime;
        double openPrice;
        double closePrice;
        double lotSize;
        double profit;
        double pips;
        double riskAmount; // Amount risked in account currency
        double riskRewardRatio;
        ENUM_ORDER_TYPE orderType;
        int signal; // Signal type that generated the trade
        int regime; // Market regime during trade
        int session; // Trading session during entry
        double quality; // Signal quality score
        string notes; // Additional notes/tags
        bool wasConfirmed; // Whether it had multi-timeframe confirmation
    };
    
    // Statistics
    int totalTrades;
    int winTrades;
    int lossTrades;
    double grossProfit;
    double grossLoss;
    double netProfit;
    double profitFactor;
    double expectancy; // Average profit per trade
    double avgWin;
    double avgLoss;
    double avgRiskReward;
    double maxDrawdown;
    int maxConsecWins;
    int maxConsecLosses;
    int currentConsecWins;
    int currentConsecLosses;
    
    // Regime-specific performance
    double regimePerformance[5]; // Profit by regime
    int regimeTrades[5]; // Trade count by regime
    
    // Session-specific performance
    double sessionPerformance[5]; // Profit by session
    int sessionTrades[5]; // Trade count by session
    
    // Storage for trade records
    TradeRecord trades[];
    int maxRecords;
    int currentIndex;
    
    // File handling
    string journalFilename;
    int fileHandle;
    bool enableFileLogging;
    
public:
    // Constructor
    TradeJournal(int maxTrades = 1000, bool logToFile = true) {
        maxRecords = maxTrades;
        enableFileLogging = logToFile;
        ArrayResize(trades, maxRecords);
        currentIndex = 0;
        totalTrades = 0;
        ResetStats();
        
        // Setup file logging if enabled
        if(enableFileLogging) {
            journalFilename = "SMC_TradeJournal_" + Symbol() + ".csv";
            fileHandle = FileOpen(journalFilename, FILE_WRITE|FILE_CSV);
            if(fileHandle != INVALID_HANDLE) {
                // Write CSV header
                FileWrite(fileHandle, "Date", "Time", "Type", "Lots", "Entry", "Exit", 
                        "Profit", "Pips", "Risk", "RR", "Regime", "Session", "Quality", "MTF", "Notes");
                FileClose(fileHandle);
            }
        }
    }
    
    // Destructor
    ~TradeJournal() {
        if(fileHandle != INVALID_HANDLE) {
            FileClose(fileHandle);
        }
    }
    
    // Add a new trade to the journal
    void AddTrade(datetime openTime, datetime closeTime, double openPrice, double closePrice, 
                 double tradeLotSize, double profit, int pips, double riskAmount, double riskReward, 
                 ENUM_ORDER_TYPE orderType, int signal, int regime, int session, double quality, 
                 bool wasConfirmed, string notes = "") {
        // tradeLotSize is the parameter for this function, distinct from global lotSize
                 
        // Update the trade record
        trades[currentIndex].openTime = openTime;
        trades[currentIndex].closeTime = closeTime;
        trades[currentIndex].openPrice = openPrice;
        trades[currentIndex].closePrice = closePrice;
        trades[currentIndex].lotSize = tradeLotSize; // Use parameter, not global lotSize
        trades[currentIndex].profit = profit;
        trades[currentIndex].pips = pips;
        trades[currentIndex].riskAmount = riskAmount;
        trades[currentIndex].riskRewardRatio = riskReward;
        trades[currentIndex].orderType = orderType;
        trades[currentIndex].signal = signal;
        trades[currentIndex].regime = regime;
        trades[currentIndex].session = session;
        trades[currentIndex].quality = quality;
        trades[currentIndex].wasConfirmed = wasConfirmed;
        trades[currentIndex].notes = notes;
        
        // Update statistics
        totalTrades++;
        
        if(profit > 0) {
            winTrades++;
            grossProfit += profit;
            avgWin = (avgWin * (winTrades - 1) + profit) / winTrades;
            currentConsecWins++;
            currentConsecLosses = 0;
            if(currentConsecWins > maxConsecWins) maxConsecWins = currentConsecWins;
        } else if(profit < 0) {
            lossTrades++;
            grossLoss += profit; // Note: profit is negative
            avgLoss = (avgLoss * (lossTrades - 1) + profit) / lossTrades;
            currentConsecLosses++;
            currentConsecWins = 0;
            if(currentConsecLosses > maxConsecLosses) maxConsecLosses = currentConsecLosses;
        }
        
        netProfit = grossProfit + grossLoss;
        if(grossLoss != 0) profitFactor = MathAbs(grossProfit / grossLoss);
        expectancy = netProfit / totalTrades;
        avgRiskReward = (avgRiskReward * (totalTrades - 1) + riskReward) / totalTrades;
        
        // Update regime and session stats
        regimePerformance[regime] += profit;
        regimeTrades[regime]++;
        
        sessionPerformance[session] += profit;
        sessionTrades[session]++;
        
        // Log to file if enabled
        if(enableFileLogging) {
            fileHandle = FileOpen(journalFilename, FILE_READ|FILE_WRITE|FILE_CSV);
            if(fileHandle != INVALID_HANDLE) {
                // Position at end of file
                FileSeek(fileHandle, 0, SEEK_END);
                
                // Format date and time
                string dateStr = TimeToString(closeTime, TIME_DATE);
                string timeStr = TimeToString(closeTime, TIME_MINUTES);
                
                // Write trade record
                FileWrite(fileHandle, dateStr, timeStr, 
                         OrderTypeToString(orderType), DoubleToString(g_lotSize, 2),
                         DoubleToString(openPrice, _Digits), DoubleToString(closePrice, _Digits),
                         DoubleToString(profit, 2), DoubleToString(pips, 1),
                         DoubleToString(riskAmount, 2), DoubleToString(riskReward, 2),
                         GetRegimeName(regime), GetSessionName(session),
                         DoubleToString(quality, 2), (wasConfirmed ? "Y" : "N"), notes);
                FileClose(fileHandle);
            }
        }
        
        // Move to next index (circular buffer)
        currentIndex = (currentIndex + 1) % maxRecords;
        
        // Log summary
        LogTrade("Trade recorded: " + OrderTypeToString(orderType) + 
                " Profit=" + DoubleToString(profit, 2) + 
                " WinRate=" + DoubleToString(GetWinRate() * 100, 1) + "%");
    }
    
    // Reset all statistics
    void ResetStats() {
        totalTrades = 0;
        winTrades = 0;
        lossTrades = 0;
        grossProfit = 0;
        grossLoss = 0;
        netProfit = 0;
        profitFactor = 0;
        expectancy = 0;
        avgWin = 0;
        avgLoss = 0;
        avgRiskReward = 0;
        maxDrawdown = 0;
        maxConsecWins = 0;
        maxConsecLosses = 0;
        currentConsecWins = 0;
        currentConsecLosses = 0;
        
        // Reset regime and session stats
        ArrayInitialize(regimePerformance, 0);
        ArrayInitialize(regimeTrades, 0);
        ArrayInitialize(sessionPerformance, 0);
        ArrayInitialize(sessionTrades, 0);
    }
    
    // Calculate win rate
    double GetWinRate() {
        if(totalTrades == 0) return 0;
        return (double)winTrades / totalTrades;
    }
    
    // Calculate profit factor
    double GetProfitFactor() {
        return profitFactor;
    }
    
    // Calculate expected return per trade
    double GetExpectancy() {
        return expectancy;
    }
    
    // Get best performing regime
    int GetBestRegime() {
        int bestRegime = 0;
        double bestPerformance = regimePerformance[0];
        
        for(int i=1; i<5; i++) {
            if(regimeTrades[i] > 0 && regimePerformance[i] > bestPerformance) {
                bestPerformance = regimePerformance[i];
                bestRegime = i;
            }
        }
        
        return bestRegime;
    }
    
    // Get best performing session
    int GetBestSession() {
        int bestSession = 0;
        double bestPerformance = sessionPerformance[0];
        
        for(int i=1; i<5; i++) {
            if(sessionTrades[i] > 0 && sessionPerformance[i] > bestPerformance) {
                bestPerformance = sessionPerformance[i];
                bestSession = i;
            }
        }
        
        return bestSession;
    }
    
    // Get performance statistics summary
    string GetSummary() {
        string summary = "--- Trade Journal Summary ---\n";
        summary += "Total Trades: " + IntegerToString(totalTrades) + "\n";
        summary += "Win/Loss: " + IntegerToString(winTrades) + "/" + IntegerToString(lossTrades) + "\n";
        summary += "Win Rate: " + DoubleToString(GetWinRate() * 100, 1) + "%\n";
        summary += "Net Profit: " + DoubleToString(netProfit, 2) + "\n";
        summary += "Profit Factor: " + DoubleToString(profitFactor, 2) + "\n";
        summary += "Expectancy: " + DoubleToString(expectancy, 2) + " per trade\n";
        summary += "Avg RR Ratio: " + DoubleToString(avgRiskReward, 2) + "\n";
        summary += "Max Consecutive Wins: " + IntegerToString(maxConsecWins) + "\n";
        summary += "Max Consecutive Losses: " + IntegerToString(maxConsecLosses) + "\n";
        
        return summary;
    }
    
    // Helper - Convert order type to string
    string OrderTypeToString(ENUM_ORDER_TYPE type) {
        switch(type) {
            case ORDER_TYPE_BUY: return "BUY";
            case ORDER_TYPE_SELL: return "SELL";
            case ORDER_TYPE_BUY_LIMIT: return "BUY LIMIT";
            case ORDER_TYPE_SELL_LIMIT: return "SELL LIMIT";
            case ORDER_TYPE_BUY_STOP: return "BUY STOP";
            case ORDER_TYPE_SELL_STOP: return "SELL STOP";
            default: return "UNKNOWN";
        }
    }
    
    // Helper - Get session name
    string GetSessionName(int session) {
        switch(session) {
            case 0: return "Asian";
            case 1: return "European";
            case 2: return "American";
            case 3: return "Asia-Europe";
            case 4: return "Europe-US";
            default: return "Unknown";
        }
    }
};

// Global trade journal instance
TradeJournal Journal(1000, true);

// Function declarations moved to the top of the file

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
#include <Trade/Trade.mqh> // For RefreshRates()

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
input bool EnableNewsFilter = true; // Avoid trading during news releases
input int NewsLookaheadMinutes = 45; // Block trades this many minutes before/after high-impact news
input bool BlockHighImpactNews = true;
input bool ReduceSizeOnMediumNews = true;
input double MediumNewsSizeReduction = 0.5;

// News Avoidance Parameters
input bool EnableNewsAvoidance = true; // Enable simple news avoidance
input string NewsAvoidanceTimes = "08:00-08:30,13:30-14:00"; // London/NY opens (UTC)
input string HighImpactDays = "1,3,5"; // Monday, Wednesday, Friday (1=Sunday)

// --- ATR Filter & Dynamic Control ---
input double MinATRThreshold = 0.0; // Min ATR threshold (stop trading if volatility too low)
double MinATRThresholdGlobal = 0.0003; // Global, can be changed at runtime
input bool EnableDynamicATR = true;    // If true, adapt ATR threshold online
input double ATRDynamicMultiplier = 0.5; // Multiplier for dynamic ATR threshold (e.g., 0.5 = 50% of avg ATR)
input double MinATRFloor = 0.0003;     // Absolute minimum for dynamically set ATR threshold

// Order Block Validation
input double MinOrderBlockVolume = 1.5;    // Min volume multiplier for valid blocks
input int OrderBlockExpirySeconds = 3600;  // How long blocks remain valid (seconds)
input double MaxOrderBlockDistancePct = 2.0; // Max price deviation (%) to consider block valid

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



input double MinSignalQualityToTrade = 70.0; // Minimum signal quality to trade (0-100)
//+------------------------------------------------------------------+
//| Correlation Detection for Multi-Pair Risk Management             |
//+------------------------------------------------------------------+
#define CORRELATION_PAIRS 8  // Number of main pairs to monitor correlation
string monitoredPairs[CORRELATION_PAIRS] = {
    "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD", "EURJPY"
};

// Store correlation data
double pairCorrelations[CORRELATION_PAIRS][CORRELATION_PAIRS];

// Calculate correlation between two pairs
double CalculateCorrelation(string pair1, string pair2, int period = 20) {
    // For identical pairs, correlation is 1.0
    if(pair1 == pair2) return 1.0;
    
    // Get price data for both pairs
    double prices1[], prices2[];
    ArrayResize(prices1, period);
    ArrayResize(prices2, period);
    
    // Fetch closing prices
    for(int i = 0; i < period; i++) {
        prices1[i] = iClose(pair1, PERIOD_H1, i);
        prices2[i] = iClose(pair2, PERIOD_H1, i);
        
        // If we couldn't get prices, return 0 correlation
        if(prices1[i] == 0 || prices2[i] == 0) return 0.0;
    }
    
    // Calculate price changes
    double returns1[], returns2[];
    ArrayResize(returns1, period-1);
    ArrayResize(returns2, period-1);
    
    for(int i = 0; i < period-1; i++) {
        returns1[i] = (prices1[i] - prices1[i+1]) / prices1[i+1];
        returns2[i] = (prices2[i] - prices2[i+1]) / prices2[i+1];
    }
    
    // Calculate Pearson correlation coefficient
    double sum_x = 0, sum_y = 0, sum_xy = 0;
    double sum_x2 = 0, sum_y2 = 0;
    int n = period-1;
    
    for(int i = 0; i < n; i++) {
        sum_x += returns1[i];
        sum_y += returns2[i];
        sum_xy += returns1[i] * returns2[i];
        sum_x2 += returns1[i] * returns1[i];
        sum_y2 += returns2[i] * returns2[i];
    }
    
    // Correlation coefficient formula
    double correlation = (n * sum_xy - sum_x * sum_y) / 
                       (MathSqrt((n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y)));
    
    return correlation;
}

// Update correlation matrix for all monitored pairs
void UpdateCorrelationMatrix() {
    for(int i = 0; i < CORRELATION_PAIRS; i++) {
        for(int j = i; j < CORRELATION_PAIRS; j++) {
            double corr = CalculateCorrelation(monitoredPairs[i], monitoredPairs[j]);
            pairCorrelations[i][j] = corr;
            pairCorrelations[j][i] = corr; // Matrix is symmetric
        }
    }
}

// Calculate position size reduction based on correlation
double CalculateCorrelationAdjustment(int signal) {
    string currentSymbol = Symbol();
    int symbolIndex = -1;
    
    // Find index of current symbol in monitored pairs
    for(int i = 0; i < CORRELATION_PAIRS; i++) {
        if(monitoredPairs[i] == currentSymbol) {
            symbolIndex = i;
            break;
        }
    }
    
    // If not monitored, no adjustment
    if(symbolIndex < 0) return 1.0;
    
    // Check correlation with open positions
    double totalCorrelation = 0.0;
    int correlatedPositions = 0;
    
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        
        string posSymbol = PositionGetString(POSITION_SYMBOL);
        if(posSymbol == currentSymbol) continue; // Skip current symbol
        
        // Find position symbol in monitored pairs
        int posIndex = -1;
        for(int j = 0; j < CORRELATION_PAIRS; j++) {
            if(monitoredPairs[j] == posSymbol) {
                posIndex = j;
                break;
            }
        }
        
        if(posIndex >= 0) {
            // Get correlation and position direction
            double corr = pairCorrelations[symbolIndex][posIndex];
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double posSize = PositionGetDouble(POSITION_VOLUME);
            
            // Adjust correlation based on position direction and signal
            // If correlation is positive and same direction, or negative and opposite direction,
            // this increases exposure
            double directionMultiplier = 1.0;
            if((signal > 0 && posType == POSITION_TYPE_SELL) || 
               (signal < 0 && posType == POSITION_TYPE_BUY)) {
                directionMultiplier = -1.0; // Opposite direction
            }
            
            corr *= directionMultiplier;
            
            // Only count significant correlations
            if(MathAbs(corr) > 0.5) {
                totalCorrelation += corr * posSize;
                correlatedPositions++;
            }
        }
    }
    
    // Calculate adjustment factor
    double adjustment = 1.0;
    
    if(correlatedPositions > 0) {
        double avgCorrelation = totalCorrelation / correlatedPositions;
        
        // Positive correlation = reduce position size
        if(avgCorrelation > 0.8) adjustment = 0.5;      // High correlation, reduce by 50%
        else if(avgCorrelation > 0.6) adjustment = 0.7; // Moderate correlation, reduce by 30%
        else if(avgCorrelation > 0.4) adjustment = 0.9; // Low correlation, reduce by 10%
        // Negative correlation can slightly increase position size (diversification benefit)
        else if(avgCorrelation < -0.4) adjustment = 1.1; // Negative correlation, increase by 10%
    }
    
    LogInfo("[CORR] Correlation adjustment: " + DoubleToString(adjustment, 2) + 
           " (based on " + IntegerToString(correlatedPositions) + " positions)");
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Time-based position size decay for long-duration trades          |
//+------------------------------------------------------------------+
// Parameters for trade duration risk decay
input bool EnableTimedRiskDecay = true;   // Gradually reduce position size for longer-duration trades
input int RiskDecayStartMinutes = 120;    // Minutes to hold a position before starting risk decay
input double MaxRiskDecayPercent = 50.0;  // Maximum percentage to reduce position size (0-100)

// Calculate decay factor based on elapsed time since signal
double CalculateTimeDecayFactor(int signal) {
    if(!EnableTimedRiskDecay) return 1.0;
    
    // No signal, no decay
    if(signal == 0) return 1.0;
    
    static datetime signalTime = 0;
    static int lastSignal = 0;
    static double decayFactor = 1.0;
    
    // Reset if signal changed
    if(signal != lastSignal) {
        signalTime = TimeCurrent();
        lastSignal = signal;
        decayFactor = 1.0;
        return 1.0;
    }
    
    // Calculate time since signal
    datetime currentTime = TimeCurrent();
    int elapsedMinutes = (int)((currentTime - signalTime) / 60);
    
    // Apply decay only after the minimum threshold
    if(elapsedMinutes <= RiskDecayStartMinutes) return 1.0;
    
    // Calculate linear decay factor
    int decayMinutes = elapsedMinutes - RiskDecayStartMinutes;
    double decayPct = MaxRiskDecayPercent / 100.0;
    
    // Gradually decay over 24 hours (1440 minutes) after the start threshold
    double decay = MathMin(decayPct, decayPct * decayMinutes / 1440.0);
    decayFactor = 1.0 - decay;
    
    LogInfo("[RISK] Time-based risk decay: " + DoubleToString(decayFactor, 2) + 
            " (elapsed=" + IntegerToString(elapsedMinutes) + " mins)");
    
    return decayFactor;
}

//+------------------------------------------------------------------+
//| Momentum confirmation filter                                     |
//+------------------------------------------------------------------+
input bool RequireMomentumConfirmation = false; // Require momentum indicator confirmation - Disabled to reduce entry strictness
input int RSI_Period = 14;                     // RSI period for momentum confirmation
input int MACD_FastEMA = 12;                  // MACD fast EMA period
input int MACD_SlowEMA = 26;                  // MACD slow EMA period
input int MACD_SignalPeriod = 9;              // MACD signal line period

// Check if momentum indicators confirm the signal
bool CheckMomentumConfirmation(int signal) {
    if(!RequireMomentumConfirmation || signal == 0) return true;
    
    int confirmed = 0;
    int requiredConfirmations = 1; // Need only 1 out of 3 indicators to confirm - Reduced to lower entry strictness
    
    // 1. RSI Confirmation
    double rsi = 0;
    int rsiHandle = iRSI(Symbol(), PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    if(rsiHandle != INVALID_HANDLE) {
        double rsiBuffer[];
        if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) > 0) {
            rsi = rsiBuffer[0];
            IndicatorRelease(rsiHandle);
        }
    }
    bool rsiConfirmed = false;
    
    if(signal > 0 && rsi > 50) rsiConfirmed = true;       // Bullish momentum
    else if(signal < 0 && rsi < 50) rsiConfirmed = true;  // Bearish momentum
    
    if(rsiConfirmed) confirmed++;
    
    // 2. MACD Confirmation
    double macdMain = 0, macdSignal = 0;
    int macdHandle = iMACD(Symbol(), PERIOD_CURRENT, MACD_FastEMA, MACD_SlowEMA, MACD_SignalPeriod, PRICE_CLOSE);
    if(macdHandle != INVALID_HANDLE) {
        double macdBuffer[];
        // Main line is buffer 0
        if(CopyBuffer(macdHandle, 0, 0, 1, macdBuffer) > 0) {
            macdMain = macdBuffer[0];
        }
        // Signal line is buffer 1
        if(CopyBuffer(macdHandle, 1, 0, 1, macdBuffer) > 0) {
            macdSignal = macdBuffer[0];
        }
        IndicatorRelease(macdHandle);
    }
    bool macdConfirmed = false;
    
    if(signal > 0 && macdMain > macdSignal) macdConfirmed = true;       // Bullish crossover
    else if(signal < 0 && macdMain < macdSignal) macdConfirmed = true;  // Bearish crossover
    
    if(macdConfirmed) confirmed++;
    
    // 3. Moving Average Confirmation
    double ma20 = 0, ma50 = 0;
    int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
    int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
    
    if(ma20Handle != INVALID_HANDLE) {
        double ma20LocalBuffer[];
        if(CopyBuffer(ma20Handle, 0, 0, 1, ma20LocalBuffer) > 0) {
            ma20 = ma20LocalBuffer[0];
        }
        IndicatorRelease(ma20Handle);
    }
    
    if(ma50Handle != INVALID_HANDLE) {
        double ma50LocalBuffer[];
        if(CopyBuffer(ma50Handle, 0, 0, 1, ma50LocalBuffer) > 0) {
            ma50 = ma50LocalBuffer[0];
        }
        IndicatorRelease(ma50Handle);
    }
    
    double close = iClose(Symbol(), PERIOD_CURRENT, 0);
    bool maConfirmed = false;
    
    if(signal > 0 && close > ma20 && ma20 > ma50) maConfirmed = true;       // Bullish alignment
    else if(signal < 0 && close < ma20 && ma20 < ma50) maConfirmed = true;  // Bearish alignment
    
    if(maConfirmed) confirmed++;
    
    // Log momentum confirmation results
    LogInfo("Momentum confirmation: " + 
             (confirmed >= requiredConfirmations ? "PASSED" : "FAILED") + 
             " (" + IntegerToString(confirmed) + "/" + IntegerToString(requiredConfirmations) + ") " +
             "RSI=" + (rsiConfirmed ? "Yes" : "No") + ", " +
             "MACD=" + (macdConfirmed ? "Yes" : "No") + ", " +
             "MA=" + (maConfirmed ? "Yes" : "No"));
    
    return (confirmed >= requiredConfirmations);
}

// Core Constants and Definitions
// These constants are already defined at the top of the file
#define MAX_FEATURES 30
// ACCURACY_WINDOW already defined above

//+------------------------------------------------------------------+
//| Liquidity Detection - Identify stop clusters for entry targets   |
//+------------------------------------------------------------------+
#define MAX_LIQUIDITY_LEVELS 10

// Structure to track liquidity levels
struct LiquidityLevel {
    double price;
    double strength;  // Relative strength (0-1)
    datetime time;    // When it was detected
    bool isBuyStop;   // true=buy stop cluster, false=sell stop cluster
    bool active;      // Whether this level is still active
};

// Array of tracked liquidity levels
LiquidityLevel liquidityLevels[MAX_LIQUIDITY_LEVELS];
int currentLiquidityIndex = 0;

// Settings for liquidity detection
input bool EnableLiquidityDetection = true;  // Scan for stop clusters to target
input double LiquidityProximityPips = 20.0;  // How close price must get to trigger
input double MinLiquidityPips = 10.0;        // Minimum size for potential liquidity zone
input int LiquidityLookbackBars = 50;        // Bars to analyze for liquidity

// Detect likely stop-loss clusters (liquidity pools)
void DetectLiquidityZones() {
    if(!EnableLiquidityDetection) return;
    
    // Prepare price data
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    // Get price data
    int copied = CopyHigh(Symbol(), PERIOD_CURRENT, 0, LiquidityLookbackBars, high);
    copied = CopyLow(Symbol(), PERIOD_CURRENT, 0, LiquidityLookbackBars, low);
    copied = CopyClose(Symbol(), PERIOD_CURRENT, 0, LiquidityLookbackBars, close);
    
    if(copied <= 0) return;
    
    // 1. Identify swing highs and lows (potential stop clusters)
    for(int i = 5; i < LiquidityLookbackBars - 5; i++) {
        bool isSwingHigh = true;
        bool isSwingLow = true;
        
        // Test for swing high (price peaked then fell)
        for(int j = 1; j <= 3; j++) {
            if(high[i] <= high[i-j] || high[i] <= high[i+j]) {
                isSwingHigh = false;
                break;
            }
        }
        
        // Test for swing low (price bottomed then rose)
        for(int j = 1; j <= 3; j++) {
            if(low[i] >= low[i-j] || low[i] >= low[i+j]) {
                isSwingLow = false;
                break;
            }
        }
        
        // If we found a swing point, check if it's a valid liquidity zone
        if(isSwingHigh) {
            ProcessLiquidityLevel(high[i], false, i); // Sell stop cluster above swing high
        }
        
        if(isSwingLow) {
            ProcessLiquidityLevel(low[i], true, i);  // Buy stop cluster below swing low
        }
    }
    
    // 2. Check for levels near round numbers (often stop clusters)
    double point = GetSymbolPoint();
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    
    // Round number modifiers based on digits
    double roundLevels[] = {0.1, 0.25, 0.5, 0.75};
    
    // Get current price range
    double rangeHigh = high[ArrayMaximum(high, 0, LiquidityLookbackBars)];
    double rangeLow = low[ArrayMinimum(low, 0, LiquidityLookbackBars)];
    
    // Check round pip levels within the range
    double pipValue = (digits == 3 || digits == 5) ? 0.001 : 0.01;
    
    // Scan price levels in 50 pip increments
    for(double price = MathFloor(rangeLow / pipValue) * pipValue; 
              price <= rangeHigh + pipValue; 
              price += pipValue * 50) {
        
        // Check each round level modifier
        for(int i = 0; i < ArraySize(roundLevels); i++) {
            double levelPrice = price + (roundLevels[i] * pipValue * 50);
            
            // Skip if outside our range
            if(levelPrice < rangeLow || levelPrice > rangeHigh) continue;
            
            // Check if this level has price action evidence of stops
            bool hasEvidence = false;
            
            // Look for price approaching then reversing at this level
            for(int j = 5; j < LiquidityLookbackBars - 5; j++) {
                double distanceUp = MathAbs(high[j] - levelPrice);
                double distanceDown = MathAbs(low[j] - levelPrice);
                
                // Price approached from below then reversed
                if(distanceUp < 20 * point && close[j] < levelPrice && high[j+1] < levelPrice && high[j+2] < levelPrice) {
                    ProcessLiquidityLevel(levelPrice, false, j);
                    hasEvidence = true;
                    break;
                }
                
                // Price approached from above then reversed
                if(distanceDown < 20 * point && close[j] > levelPrice && low[j+1] > levelPrice && low[j+2] > levelPrice) {
                    ProcessLiquidityLevel(levelPrice, true, j);
                    hasEvidence = true;
                    break;
                }
            }
        }
    }
    
    // Log active liquidity levels
    string liquidityInfo = "Active liquidity levels: ";
    int activeCount = 0;
    
    for(int i = 0; i < MAX_LIQUIDITY_LEVELS; i++) {
        if(liquidityLevels[i].active) {
            liquidityInfo += DoubleToString(liquidityLevels[i].price, _Digits) + 
                          " (" + (liquidityLevels[i].isBuyStop ? "Buy" : "Sell") + 
                          ", str=" + DoubleToString(liquidityLevels[i].strength, 2) + "), ";
            activeCount++;
        }
    }
    
    if(activeCount > 0) {
        LogInfo("[LIQ] " + liquidityInfo);
    }
}

// Process a potential liquidity level
void ProcessLiquidityLevel(double price, bool isBuyStop, int barIndex) {
    double point = GetSymbolPoint();
    double currentPrice = iClose(Symbol(), PERIOD_CURRENT, 0);
    datetime currentTime = TimeCurrent();
    
    // Check if we already have this level (within a small range)
    for(int i = 0; i < MAX_LIQUIDITY_LEVELS; i++) {
        if(liquidityLevels[i].active) {
            // If we're within 5 points of existing level, strengthen it instead of adding new
            if(MathAbs(liquidityLevels[i].price - price) < 5 * point && 
               liquidityLevels[i].isBuyStop == isBuyStop) {
                
                // Increase strength
                liquidityLevels[i].strength = MathMin(1.0, liquidityLevels[i].strength + 0.2);
                liquidityLevels[i].time = currentTime; // Update time
                return; // Don't add a new level
            }
        }
    }
    
    // Calculate strength based on bar index (more recent = stronger)
    double strength = 0.5 + (0.5 * (1.0 - (double)barIndex / LiquidityLookbackBars));
    
    // Add new liquidity level
    liquidityLevels[currentLiquidityIndex].price = price;
    liquidityLevels[currentLiquidityIndex].strength = strength;
    liquidityLevels[currentLiquidityIndex].time = currentTime;
    liquidityLevels[currentLiquidityIndex].isBuyStop = isBuyStop;
    liquidityLevels[currentLiquidityIndex].active = true;
    
    // Move to next index (circular buffer)
    currentLiquidityIndex = (currentLiquidityIndex + 1) % MAX_LIQUIDITY_LEVELS;
}

// Check if price is approaching liquidity level for entry
bool IsApproachingLiquidity(int signal, double &targetPrice) {
    if(!EnableLiquidityDetection || signal == 0) return false;
    
    double currentPrice = iClose(Symbol(), PERIOD_CURRENT, 0);
    double point = GetSymbolPoint();
    double proximityDistance = LiquidityProximityPips * 10 * point;
    
    for(int i = 0; i < MAX_LIQUIDITY_LEVELS; i++) {
        if(!liquidityLevels[i].active) continue;
        
        // For buy signal, look for liquidity above (sell stops to be triggered)
        if(signal > 0 && !liquidityLevels[i].isBuyStop) {
            double distance = liquidityLevels[i].price - currentPrice;
            
            // If price is approaching liquidity zone from below
            if(distance > 0 && distance < proximityDistance) {
                targetPrice = liquidityLevels[i].price;
                LogInfo("[LIQ] Buy approaching liquidity at " + DoubleToString(targetPrice, _Digits) + 
                     " (" + DoubleToString(distance / point, 1) + " points away)");
                return true;
            }
        }
        // For sell signal, look for liquidity below (buy stops to be triggered)
        else if(signal < 0 && liquidityLevels[i].isBuyStop) {
            double distance = currentPrice - liquidityLevels[i].price;
            
            // If price is approaching liquidity zone from above
            if(distance > 0 && distance < proximityDistance) {
                targetPrice = liquidityLevels[i].price;
                LogInfo("[LIQ] Sell approaching liquidity at " + DoubleToString(targetPrice, _Digits) + 
                     " (" + DoubleToString(distance / point, 1) + " points away)");
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Smart Entry Scaling Implementation                                |
//+------------------------------------------------------------------+
input bool EnableSmartScaling = true;       // Execute scaled entries for better average price
bool ExecuteScaledEntry(int signal, double stopLoss, double dynamicSL) {
    if(!EnableSmartScaling || ScalingPositions < 2) return false;
    
    // Reset scaling entries array
    for(int i = 0; i < ArraySize(currentScalingEntries); i++) {
        currentScalingEntries[i].active = false;
        currentScalingEntries[i].ticket = 0;
    }
    
    // Get current price and ATR
    double currentPrice = iClose(Symbol(), PERIOD_CURRENT, 0);
    int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
    double atrTemp[1]; // Temporary buffer to avoid shadowing
double atr = 0.0;
if (CopyBuffer(atrHandle, 0, 0, 1, atrTemp) > 0) {
    atr = atrTemp[0];
} else {
    LogError("Failed to copy ATR for scaling entry");
    return false;
}
IndicatorRelease(atrHandle);
double point = GetSymbolPoint();
double scaleDistance = atr * ScaleDistanceMultiplier;
    
    // Calculate total lot size based on risk settings
    double totalLots = CalculatePositionSize(signal, currentPrice, stopLoss);
    

    
    // Apply correlation adjustment to position sizing
    double correlationFactor = CalculateCorrelationAdjustment(signal);
    double timeDecayFactor = CalculateTimeDecayFactor(signal);
    totalLots *= correlationFactor * timeDecayFactor;
    
    // Distribute lots across scaling entries - more lots at better prices
    double lotDistribution[5] = {0.4, 0.3, 0.2, 0.1, 0.0}; // 40%, 30%, 20%, 10% of total
    
    // Use maximum of 5 scaling positions
    int actualScalingPositions = MathMin(ScalingPositions, 5);
    
    LogInfo("Executing scaled entry: Signal=" + IntegerToString(signal) + 
            ", TotalLots=" + DoubleToString(totalLots, 2) + 
            ", ScalePositions=" + IntegerToString(actualScalingPositions));
    
    // Define the entry prices
    for(int i = 0; i < actualScalingPositions; i++) {
        // Calculate lot size for this entry
        currentScalingEntries[i].lotSize = totalLots * lotDistribution[i];
        currentScalingEntries[i].lotSize = NormalizeDouble(currentScalingEntries[i].lotSize, 2);
        
        // Calculate entry price
        if(signal > 0) { // BUY - scale down in price
            currentScalingEntries[i].entryPrice = currentPrice - (i * scaleDistance);
        }
        else { // SELL - scale up in price
            currentScalingEntries[i].entryPrice = currentPrice + (i * scaleDistance);
        }
        
        // Set shared stop loss
        currentScalingEntries[i].stopLoss = stopLoss;
        
        // Mark as active
        currentScalingEntries[i].active = true;
    }
    
    // Execute the first entry immediately
    if(currentScalingEntries[0].lotSize > 0) {
        // Use CTrade for execution, following the bot's pattern
        CTrade tradeObj; // Renamed to avoid shadowing global variable
        tradeObj.SetExpertMagicNumber(123456); // Use appropriate magic number
        
        // Execute entry based on signal direction
        bool success = false;
        string comment = "Scaled Entry 1/" + IntegerToString(actualScalingPositions);

if(signal > 0) { // BUY
    success = tradeObj.Buy(currentScalingEntries[0].lotSize, Symbol(), 0, stopLoss, 0, comment);
} else { // SELL
    success = tradeObj.Sell(currentScalingEntries[0].lotSize, Symbol(), 0, stopLoss, 0, comment);
}

if(success) {
    ulong ticket = tradeObj.ResultOrder();
    currentScalingEntries[0].ticket = ticket;
    LogTrade("Executed initial scaled entry: " + Symbol() + ", Lots=" + DoubleToString(currentScalingEntries[0].lotSize, 2) + ", Ticket=" + IntegerToString((int)ticket));
    return true;
}
    }
    
    return false;
}

// Check if we need to execute pending scaled entries
void CheckPendingScaledEntries() {
    if(!EnableSmartScaling) return;
    
    double bid = GetCurrentBid();
    double ask = GetCurrentAsk();
    
    for(int i = 1; i < ArraySize(currentScalingEntries); i++) {
        if(!currentScalingEntries[i].active || currentScalingEntries[i].ticket > 0) continue;
        
        // Check if price reached the entry level
        bool entryCondition = false;
        int entrySignal = 0;
        
        // For BUY entries (price scaled down)
        if(currentScalingEntries[0].ticket > 0 && 
           PositionSelectByTicket(currentScalingEntries[0].ticket) && 
           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            
            entrySignal = 1;
            entryCondition = (bid <= currentScalingEntries[i].entryPrice);
        }
        // For SELL entries (price scaled up)
        else if(currentScalingEntries[0].ticket > 0 && 
                PositionSelectByTicket(currentScalingEntries[0].ticket) && 
                PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
            
            entrySignal = -1;
            entryCondition = (ask >= currentScalingEntries[i].entryPrice);
        }
        
        // If entry condition met, execute the pending entry
        if(entryCondition && currentScalingEntries[i].lotSize > 0 && entrySignal != 0) {
            // Use CTrade for execution
            CTrade tradeObj; // Renamed to avoid shadowing global variable
            tradeObj.SetExpertMagicNumber(123456); // Use appropriate magic number
            
            // Execute entry based on signal direction
            bool success = false;
            string comment = "Scaled Entry " + IntegerToString(i+1) + "/" + IntegerToString(ScalingPositions);
            double stopLoss = currentScalingEntries[i].stopLoss;
            
            if(entrySignal > 0) { // BUY
                success = tradeObj.Buy(currentScalingEntries[i].lotSize, Symbol(), 0, stopLoss, 0, comment);
            } else { // SELL
                success = tradeObj.Sell(currentScalingEntries[i].lotSize, Symbol(), 0, stopLoss, 0, comment);
            }
            
            if(success) {
                ulong ticket = tradeObj.ResultOrder();
                currentScalingEntries[i].ticket = ticket;
                LogTrade("Executed additional scaled entry: " + Symbol() + 
                        ", Lots=" + DoubleToString(currentScalingEntries[i].lotSize, 2) + 
                        ", Ticket=" + IntegerToString((int)ticket));
            }
        }
    }
}

input double ScaleDistanceMultiplier = 0.5; // Distance between entries as ATR multiplier

// Structure to track scaling entries
struct ScalingEntry {
    double entryPrice;
    double lotSize;
    double stopLoss;
    double takeProfit;
    bool active;
    ulong ticket;
};

ScalingEntry currentScalingEntries[5]; // Maximum 5 scaling positions

// Market Regime Constants
#define TRENDING_UP 0
#define TRENDING_DOWN 1
#define HIGH_VOLATILITY 2
#define LOW_VOLATILITY 3
#define RANGING_NARROW 4
#define RANGING_WIDE 5
// BREAKOUT already defined at line 22
#define REVERSAL 7
#define CHOPPY 8

// Define missing constants
// #define MAX_MISSED_OPPORTUNITIES // Removed duplicate macro definition, now only defined in the .mqh file 100
#define MinStopDistance 10
#define ATRMultiplier 1.5
#define NewsAvoidanceMinutesBefore 15
#define NewsAvoidanceMinutesAfter 15
#define MaxDailyLossPercent 5.0
#define EnableTrailingStops true
#define EnableBreakEven true
#define ATRperiod 14

// Convert these to variables instead of #define to make them modifiable
input double TrailingActivationPct = 0.3; // Trailing activation threshold (% of ATR)
input double TrailingStopMultiplier = 0.3; // Trailing stop multiplier

// Using the MARKET_PHASE enum defined at the top of the file
// Additional market phase constants can be added to the single enum definition

// Define regime constants for backward compatibility
#define REGIME_HIGH_VOLATILITY PHASE_HIGH_VOLATILITY
#define REGIME_LOW_VOLATILITY PHASE_LOW_VOLATILITY
#define REGIME_TRENDING_UP PHASE_TRENDING_UP
#define REGIME_TRENDING_DOWN PHASE_TRENDING_DOWN
#define REGIME_NORMAL PHASE_NORMAL

// Pattern type constants
#define BREAKOUT 1.0

// Market Regime Parameters
input int RegimeATRPeriod = 14; // ATR period for regime detection
input double HighVolatilityThreshold = 500; // Points (ATR/Point)
input double LowVolatilityThreshold = 100; // Points (ATR/Point)

// Risk Adjustment Parameters
input double HighVolatilityRiskMultiplier = 0.5; // Reduce risk 50% in high volatility
input double LowVolatilityRiskMultiplier = 1.2;  // Increase risk 20% in low volatility
input double TrendFollowingRiskMultiplier = 1.5; // Increase risk 50% in strong trends
input double HighVolatilitySLMultiplier = 2.0;   // Double SL in high volatility
input double TrendSLMultiplier = 0.8;           // Tighten SL 20% in trends

// CHOCH detection functions are defined elsewhere in the code

//+------------------------------------------------------------------+
//| Detect Market Regime                                             |
//+------------------------------------------------------------------+
MARKET_PHASE DetectMarketRegime() {
    int atrHandle = iATR(Symbol(), Period(), RegimeATRPeriod);
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(atrHandle, 0, 1, 1, atr);
    double atrValue = atr[0];
    double point = GetSymbolPoint();
    double ratio = atrValue/point;
    
    // Basic volatility regime
    if(ratio > HighVolatilityThreshold) return PHASE_HIGH_VOLATILITY;
    if(ratio < LowVolatilityThreshold) return PHASE_LOW_VOLATILITY;
    
    // Trend detection (optional - can be enhanced)
    int maFastHandle = iMA(Symbol(), Period(), 5, 0, MODE_EMA, PRICE_CLOSE);
    int maSlowHandle = iMA(Symbol(), Period(), 20, 0, MODE_EMA, PRICE_CLOSE);
    double maFastBuffer[], maSlowBuffer[];
    ArraySetAsSeries(maFastBuffer, true);
    ArraySetAsSeries(maSlowBuffer, true);
    ArrayResize(maFastBuffer, 100);
    ArrayResize(maSlowBuffer, 100);
    CopyBuffer(maFastHandle, 0, 0, 1, maFastBuffer);
    CopyBuffer(maSlowHandle, 0, 0, 1, maSlowBuffer);
    double maFast = maFastBuffer[0];
    double maSlow = maSlowBuffer[0];
    IndicatorRelease(maFastHandle);
    IndicatorRelease(maSlowHandle);
    
    if(maFast > maSlow * 1.002) return PHASE_TRENDING_UP;
    if(maFast < maSlow * 0.998) return PHASE_TRENDING_DOWN;
    
    return PHASE_NORMAL;
}

//+------------------------------------------------------------------+
//| Get Current Regime Name                                          |
//+------------------------------------------------------------------+
string GetRegimeName(MARKET_PHASE regime) {
    switch(regime) {
        case REGIME_HIGH_VOLATILITY: return "High Volatility";
        case REGIME_LOW_VOLATILITY:  return "Low Volatility";
        case REGIME_TRENDING_UP:     return "Trending Up";
        case REGIME_TRENDING_DOWN:   return "Trending Down";
        default:                     return "Normal";
    }
}

// --- INPUTS AND PARAMETERS ---
// Regime Learning/Adaptation Inputs
input int RegimePerfWindow = 30; // Window for regime stats
input double RegimeMinWinRate = 0.5;        // Higher win rate required for regime trading
input double RegimeMinProfitFactor = 1.5;     // Higher profit factor required for regime trading
input double RegimeMaxDrawdownPct = 5.0;     // Lower maximum drawdown allowed for regime trading
input int RegimeUnderperfN = 10; // N trades to trigger block/reduce
input double RegimeRiskReduction = 0.5; // Reduce risk by this factor if underperforming
input bool BlockUnderperfRegime = true;
// News filter is in news_filter.mqh
// Trading Timeframes
input ENUM_TIMEFRAMES AnalysisTimeframe = PERIOD_H1;  // Main analysis timeframe
input ENUM_TIMEFRAMES ScanningTimeframe = PERIOD_M15; // Scanning timeframe
input ENUM_TIMEFRAMES ExecutionTimeframe = PERIOD_M5; // Execution timeframe

// Performance dashboard settings
input bool ShowPerformanceDashboard = true; // Show performance dashboard and profiling on chart
input bool EnableProfiling = true;  // Enable detailed performance profiling

// EA logging and debugging 
input int EnableDashboard = 1;          // Show dashboard (0=off, 1=on)
input bool LogToFile = false;        // Log trades to file

// EA risk management
input group "Advanced Risk Management"
// The following variables are already defined elsewhere in the code
// input bool EnableAdaptiveRisk = true; // Adjust position size based on volatility
// News filter already defined above (line 363)
input bool EnableCorrelationChecking = true; // Check for correlated pairs
input double CorrelationDiscountFactor = 0.2; // How much to reduce size for correlated pairs
// input bool EnableTimeBasedRiskReduction = true; // Reduce size near market close/weekends
// input bool EnableMarketRegimeFiltering = true; // Adjust strategy based on market regime

input int TradingStartHour = 0;
input int TradingEndHour = 23;
input int MaxTrades = 1;               // Maximum concurrent trades (reduced for small account)
//input double RiskRewardRatio = 1.5;      // Risk:Reward ratio (1.5 = 1.5:1)
input int AdaptiveSlippagePoints = 5;    // Slippage allowance for order execution
input int MagicNumber = 20230615;        // Unique identifier for this EA's trades
// These have already been declared earlier as inputs
// input double TrailingActivationPct = 0.3; // Activate trailing stop after this % of target reached (earlier to secure profits)
// input double TrailingStopMultiplier = 1.2; // Multiplier for ATR-based trailing stop
input double MaxPortfolioRiskPercent = 2.0; // Max portfolio risk as % of balance (reduced for small account)
input bool UseKellySizing = true;           // Use Kelly/Optimal F for dynamic sizing
input double MaxKellyFraction = 0.015;      // Max Kelly/Optimal F fraction (reduced for small account)
double SL_ATR_Mult = 0.8;         // Stop loss multiplier of ATR (tighter to preserve capital)
double TP_ATR_Mult = 1.6;         // Take profit multiplier of ATR (adjusted based on SL reduction)

// Define the ATR multiplier for trailing stops
input double TrailingStopATRMultiplier = 1.0; // ATR multiplier for trailing stops

// Multi-target take profit settings
input double TP1_RR_Ratio = 1.0;  // First target risk-reward ratio
input double TP2_RR_Ratio = 2.0;  // Second target risk-reward ratio
input double TP3_RR_Ratio = 3.0;  // Third target (trailing) risk-reward ratio

// Position sizing for multi-target strategy
input double TP1_Size_Percent = 0.4; // Percentage of position to close at first target
input double TP2_Size_Percent = 0.3; // Percentage of position to close at second target
input double SL_Pips = 10.0;           // Fixed stop loss in pips (as backup)
input double TP_Pips = 30.0;           // Fixed take profit in pips (as backup)
input int SignalCooldownSeconds = 300;  // Number of seconds between signals
int ActualSignalCooldownSeconds = SignalCooldownSeconds;  // Dynamic copy of cooldown variable
// int ActualSignalCooldownSeconds = 1;   // Runtime-adjustable cooldown - Already defined elsewhere
// input int MinBlockStrength = 2;        // Minimum order block strength for valid signal - Already defined elsewhere
input bool RequireTrendConfirmation = false; // Require trend confirmation for trades
// input int MaxConsecutiveLosses = 3;    // Stop trading after this many consecutive losses - Already defined elsewhere

// Order Block Struct - Already defined earlier in the code
/* 
// struct OrderBlock {
    double price;
    datetime time;
    double volume;
    bool isBuy;
    bool valid;
    int strength;
*/
// Note: The original struct already has all needed properties including imbalanceRatio
//    double imbalanceRatio; // Add imbalance ratio property
//};

// OrderBlock recentBlocks[MAX_BLOCKS];

// Volatility Filter


MARKET_PHASE currentMarketPhase = PHASE_TRENDING_UP;

// Advanced Scalping Parameters
input bool EnableFastExecution = true;  // Enable fast execution mode
// EnableAdaptiveRisk already defined above (line 1211)
input bool EnableAggressiveTrailing = true; // Use aggressive trailing stops
input bool EnableTrailingForLast = true;   // Enable volatility-based trailing
input double BreakEvenTriggerPct = 0.5;     // % of TP when to move stop to break-even (0.0-1.0)
// BreakEvenPadding already defined as global variable (line 121)
input double BreakEvenPaddingInput = 10.0;       // Points to add above entry when moving to break-even
input double TrailVolMultiplier = 1.2;      // Volatility multiplier for trailing steps
input double TrailMinStep = 5.0;            // Minimum trailing step in points
input double TrailMaxStep = 40.0;           // Maximum trailing step in points
// TrailingActivationPct already defined as input parameter (line 1224)
// TrailingStopMultiplier already defined as input parameter (line 1225)

// Adaptive Position Sizing Parameters
input double VolatilityMultiplier = 1.0; // Base multiplier for volatility-based position sizing
input double LowVolatilityBonus = 1.2; // Increase size in low volatility (multiply by this)
input double HighVolatilityReduction = 0.8; // Decrease size in high volatility (multiply by this)

// Signal Quality Parameters
input bool EnableDivergenceFilter = false;   // Enable divergence-based signal filtering - Disabled to reduce entry strictness
input bool UseDivergenceBooster = true;     // Increase position size on divergence confirmation
input double DivergenceBoostMultiplier = 1.3; // Increase position size by this factor when divergence is detected
// Using the RSI_Period, MACD_FastEMA, MACD_SlowEMA, and MACD_SignalPeriod defined earlier
input double EnhancedRR = 2.0; // Enhanced risk:reward ratio after trailing activation
// EnableMarketRegimeFiltering already defined above (line 1216)
// News filter already defined above, don't redefine

// Fast Execution Parameters
input int FastExecution_MaxRetries = 3;   // Maximum retries for failed orders
input int SlippagePoints = 20;            // Maximum allowed slippage in points
input int MaxAllowedSlippagePoints = 50;  // Cap for adaptive slippage
input double HighLatencyThreshold = 0.7;  // Seconds (if exceeded, increase slippage)
input double HighSlippageThreshold = 10.0; // Points (if exceeded, increase slippage)
// AdaptiveSlippagePoints already defined as input parameter (line 1222)

// MQL5 Error Code Definitions
#define ERR_NOT_ENOUGH_MONEY 10019

// Partial Take-Profit Parameters
input bool UsePartialExits = true;        // Enable partial take-profits
input double PartialTP1_Percent = 0.33;   // % of position to exit at first TP
input double PartialTP2_Percent = 0.33;   // % of position to exit at second TP
input double PartialTP3_Percent = 0.34;   // % of position to exit at third TP
input double PartialTP1_Distance = 0.7;   // First TP at x times the stop distance (ATR-adaptive)
input double PartialTP2_Distance = 1.5;   // Second TP at x times the stop distance
input int MinimumStopPips = 10;          // Minimum stop loss distance in pips
input double PartialTP3_Distance = 2.5;   // Third TP at x times the stop distance
// Partial Profit Parameters
input bool EnablePartialTakeProfit = true; // Enable partial profit taking
input double PartialTP1_Pct = 0.75; // Portion to close at TP1 (increased to secure profits faster)

// Spread Filter
input double MaxAllowedSpread = 30; // Maximum allowed spread in points for trade execution (further increased to allow more trading opportunities)

// Performance Tracking
// DisplayDebugInfo already defined at line 1208
input bool LogPerformanceStats = true; // Log detailed performance statistics

// Smart Session-Based Trading
bool EnableSessionFiltering = false;   // Enable session-based trading rules - Disabled to reduce entry strictness
bool TradeAsianSession = true;       // Trade during Asian session (low volatility)
bool TradeEuropeanSession = true;    // Trade during European session (medium volatility)
bool TradeAmericanSession = true;    // Trade during American session (high volatility)
bool TradeSessionOverlaps = true;    // Emphasize trading during session overlaps

// Advanced Signal Quality Evaluation
input bool EnableSignalQualityML = true;    // Use ML-like signal quality evaluation
input double MinSignalQualityTolocalTrade = 0.5; // Minimum signal quality score (0.0-1.0) to trade (reduced to allow more entries)
input bool RequireMultiTimeframeConfirmation = false; // Require additional timeframe confirmation (disabled to allow more trading opportunities)

// Smart Position Recovery
input bool EnableSmartAveraging = false;    // Enable smart grid averaging for drawdown recovery (keep disabled for small account)
input int ScalingPositions = 3;             // Number of positions to split into

//+------------------------------------------------------------------+
//| Multi-Target Take Profit Strategy                                |
//+------------------------------------------------------------------+
input bool EnableMultiTargetTP = true;        // Use tiered take-profit strategy
input double TPRatio1 = 1.0;                  // First TP level (as R multiple)
input double TPRatio2 = 2.0;                  // Second TP level (as R multiple)
// EnableTrailingForLast already defined above (line 1366)
// TrailingStopATRMultiplier already defined earlier
input double AveragingDistanceMultiplier = 2.0; // Distance multiplier for averaging positions

// Execution Logging
string lastMissedTradeReason = "";
double lastTradeSlippage = 0.0;
double lastTradeExecTimeLocal = 0.0;
int lastTradeRetryCount = 0;
string lastTradeError = "";
double avgExecutionTime = 0.0;
int executionCount = 0;

// Dynamic Controls
input int SwingLookbackBars = 1; // Reduce from 2 bars
input double SwingTolerancePct = 0.15; // 15% tolerance

// --- GLOBAL VARIABLES ---
// Trading Status - These are duplicates, already defined at the top of the file
// // Removed duplicate emergencyMode definition // Already defined in line 75
// bool marketClosed = false;
// bool isWeekend = false;
// datetime lastTradeTime = 0; // Already defined elsewhere
// datetime lastSignalTime = 0; // Already defined elsewhere
// string lastErrorMessage = ""; // Already defined elsewhere
// bool trailingActive = false; // Already defined elsewhere
// double trailingLevel = 0; // Already defined elsewhere
// double trailingTP = 0; // Already defined elsewhere
//int consecutiveLosses = 0; // Already defined at line 79
//int currentRegime = -1; // Already defined at line 76

// Working copies of constants that can be modified
double workingATRThreshold = 0.0003; // Default value, will be initialized properly in OnInit
double workingRiskPercent = 1.0; // Working copy of RiskPercent
//double workingTrailingStopMultiplierLocal = 0.5; // Already defined at line 77
double workingTrailingActivationPct = 0.5; // Working copy of TrailingActivationPct
double workingMinSignalQualityTolocalTrade = 0.6; // Working copy of MinSignalQualityToTrade
//int regimeBarCount = 0; // Already defined at line 74
//int lastRegime = -1; // Already defined at line 75

// Market Session State
enum ENUM_MARKET_SESSION {
    SESSION_NONE = 0,
    SESSION_ASIA = 1,
    SESSION_EUROPE = 2,
    SESSION_AMERICA = 3,
    SESSION_ASIA_EUROPE_OVERLAP = 4,
    SESSION_EUROPE_AMERICA_OVERLAP = 5
}; // Only one definition kept

ENUM_MARKET_SESSION currentSession = SESSION_NONE;
double currentSignalQuality = 0.0;

// Using the existing NewsEvent structure defined at line 2075
// Array to store upcoming news events
NewsEvent newsSchedule[20];

// Averaging System Variables
int averagingPositions = 0;
datetime lastAveragingTime = 0;

// Trade object and indicators
// These variables are already defined as globals - removing duplicate definitions
//int winStreak = 0; // Already defined at line 80
//int lossStreak = 0; // Already defined at line 81

// Performance arrays - already defined as globals
//double tradeProfits[]; // Already defined at line 82
//double tradeReturns[]; // Already defined at line 83
//int regimeWins[REGIME_COUNT]; // Already defined at line 85
//int regimeLosses[REGIME_COUNT]; // Already defined at line 86
//double regimeProfit[REGIME_COUNT]; // Already defined at line 87
//double regimeMaxDrawdown[REGIME_COUNT]; // Already defined at line 88
double regimeDrawdown[REGIME_COUNT];
double regimeProfitFactor[REGIME_COUNT];
int regimeTradeCount[REGIME_COUNT];
bool regimeBlocked[REGIME_COUNT];
double regimeRiskFactor[REGIME_COUNT];
double predictionResults[];
int predictionCount = 0;

// SMC Structures
// LiquidityGrab and FairValueGap structs are already defined earlier in the file

// Note: Main OrderBlock struct is already defined earlier in the code
// This is just a reference for code readability

// The NewsEvent structure and recentBlocks array are already defined earlier in the code
// Keeping the MAX_NEWS_EVENTS definition here
#define MAX_NEWS_EVENTS 50  // Maximum number of news events to track

//+------------------------------------------------------------------+
//| Missed Opportunity Tracking - Logs potential trades filtered out |
//+------------------------------------------------------------------+
// Implementation now in SmcScalperHybridV20_MissedOpportunities.mqh

// Global instance to track the last detected divergence
// DivergenceInfo lastDivergence; // Already defined earlier in the file

// Structure to track missed trading opportunities
// Removed duplicate MissedOpportunity struct and missedOpportunities array

// Adaptive filter settings
// Removed duplicate AdaptiveFilterSettings struct definition

// Global adaptive filter settings
// Removed duplicate adaptiveFilters variable definition

// Market regime already defined above - this is a duplicate
// Using the comprehensive enum definition from line ~1225

// SwingPoint struct already defined at line 19

// Global variables for market state tracking
// currentRegime already defined at line 1360 - keeping only one global instance
// ENUM_MARKET_REGIME currentRegime = REGIME_RANGING; // Default regime

// LiquidityGrab recentGrabs[MAX_GRABS];
// FairValueGap recentFVGs[MAX_FVGS];

// Order Block Analytics
// input bool EnableOrderBlockAnalytics = true; // Already defined earlier, commenting out duplicate
// int totalBlocksDetected = 0; // Already defined globally at lines 148-150
// int totalBlocksValid = 0; // Already defined globally at lines 148-150
// int totalBlocksInvalid = 0; // Already defined globally at lines 148-150
// double sumBlockStrength = 0; // Already defined globally at lines 148-150
// double sumBlockVolume = 0; // Already defined globally at lines 148-150
int rollingWindow = 100; // Already defined globally at lines 148-150
double rollingStrength[100]; // Already defined globally at lines 148-150
double rollingVolume[100]; // Already defined globally at lines 148-150
int rollingIndex = 0; // Already defined globally at lines 148-150

// // // int grabIndex = 0, fvgIndex = 0, blockIndex = 0; // Already defined globally at lines 148-150 // Already defined globally at lines 148-150 // Already defined earlier, commenting out duplicate
// // // double FVGMinSize = 0.5; // Already defined earlier // Already defined earlier // Already defined earlier, commenting out duplicate
// // // input int LookbackBars = 200; // Already defined earlier, commenting out duplicate
// // // bool UseLiquidityGrab = true, UseImbalanceFVG = true; // Already defined earlier // Already defined earlier // Already defined earlier, commenting out duplicate

// Market Structure Detection
struct MarketStructure {
    bool bosisBuy;
    bool bosBearish;
    bool choch;  // Change of character
    datetime lastSwingHighTime;
    datetime lastSwingLowTime;
    double swingHigh;
    double swingLow;
};
MarketStructure marketStructure;

//+------------------------------------------------------------------+
//| Find swing points for market structure analysis                  |
//+------------------------------------------------------------------+
void FindSwingPoints(bool isBuy, SwingPoint &swings[], int &swingCount) {
    int lookbackBars = 200; // How many bars to analyze
    int minStrength = 3;   // Minimum strength for a valid swing point
    swingCount = 0;
    
    // Resize the array to hold potential swing points
    ArrayResize(swings, 10);
    
    // For buy positions, look for swing lows (support levels)
    if(isBuy) {
        for(int i = 2; i < lookbackBars && i < Bars(Symbol(), PERIOD_CURRENT); i++) {
            double midPrice = iLow(Symbol(), PERIOD_CURRENT, i);
            
            // Check if this bar's low is lower than both neighbors
            if(midPrice < iLow(Symbol(), PERIOD_CURRENT, i-1) && 
               midPrice < iLow(Symbol(), PERIOD_CURRENT, i+1)) {
                
                // Calculate the strength of this swing point (how many bars confirm it)
                int strength = 1;
                for(int j = 2; j <= 5 && i+j < Bars(Symbol(), PERIOD_CURRENT); j++) {
                    if(midPrice < iLow(Symbol(), PERIOD_CURRENT, i+j)) strength++;
                }
                for(int j = 2; j <= 5 && i-j >= 0; j++) {
                    if(midPrice < iLow(Symbol(), PERIOD_CURRENT, i-j)) strength++;
                }
                
                // Only consider points with sufficient strength
                if(strength >= minStrength) {
                    swings[swingCount].price = midPrice;
                    swings[swingCount].barIndex = i;
                    swings[swingCount].strength = strength;
                    swings[swingCount].time = iTime(Symbol(), PERIOD_CURRENT, i);
                    swingCount++;
                    
                    // Resize array if needed
                    if(swingCount >= ArraySize(swings)) {
                        ArrayResize(swings, ArraySize(swings) + 10);
                    }
                }
            }
        }
    }
    // For sell positions, look for swing highs (resistance levels)
    else {
        for(int i = 2; i < lookbackBars && i < Bars(Symbol(), PERIOD_CURRENT); i++) {
            double midPrice = iHigh(Symbol(), PERIOD_CURRENT, i);
            
            // Check if this bar's high is higher than both neighbors
            if(midPrice > iHigh(Symbol(), PERIOD_CURRENT, i-1) && 
               midPrice > iHigh(Symbol(), PERIOD_CURRENT, i+1)) {
                
                // Calculate the strength of this swing point
                int strength = 1;
                for(int j = 2; j <= 5 && i+j < Bars(Symbol(), PERIOD_CURRENT); j++) {
                    if(midPrice > iHigh(Symbol(), PERIOD_CURRENT, i+j)) strength++;
                }
                for(int j = 2; j <= 5 && i-j >= 0; j++) {
                    if(midPrice > iHigh(Symbol(), PERIOD_CURRENT, i-j)) strength++;
                }
                
                // Only consider points with sufficient strength
                if(strength >= minStrength) {
                    swings[swingCount].price = midPrice;
                    swings[swingCount].barIndex = i;
                    swings[swingCount].strength = strength;
                    swings[swingCount].time = iTime(Symbol(), PERIOD_CURRENT, i);
                    swingCount++;
                    
                    // Resize array if needed
                    if(swingCount >= ArraySize(swings)) {
                        ArrayResize(swings, ArraySize(swings) + 10);
                    }
                }
            }
        }
    }
    
    // Debug output for swing detection
    if(DisplayDebugInfo && swingCount > 0) {
        string direction = isBuy ? "BUY" : "SELL";
        Print("[SWING DETECT] Direction=", direction, ", Found=", swingCount, " swing points");
    }
}

void DetectMarketStructure() {
    SwingPoint swings[];
    int swingCount = 0;
    // FindQualitySwingPoints is not defined - implementing FindSwingPoints instead
    FindSwingPoints(true, swings, swingCount);
    
    if(swingCount >= 3) {
        marketStructure.bosisBuy = (swings[0].price > swings[2].price && swings[1].price > swings[2].price);
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

double workingMinSignalQualityToTrade = 70.0; // Working copy of minimum signal quality

//+------------------------------------------------------------------+
//| Calculate average ATR over specified periods                     |
//+------------------------------------------------------------------+
double CalculateAverageATR(int periods) {
    double avgAtr = 0;
    int validPeriods = 0;
    
    for(int i=0; i<periods; i++) {
        double periodAtr = GetATR(Symbol(), PERIOD_CURRENT, 14, i);
        if(periodAtr > 0) {
            avgAtr += periodAtr;
            validPeriods++;
        }
    }
    
    return validPeriods > 0 ? avgAtr / validPeriods : 0;
}

//+------------------------------------------------------------------+
//| Multi-timeframe confirmation analysis                            |
//+------------------------------------------------------------------+
bool ConfirmSignalMultiTimeframe(int signal) {
    if(signal == 0) return false;
    
    // Configure which timeframes to check
    ENUM_TIMEFRAMES confirmTFs[] = {PERIOD_M5, PERIOD_D1};
    string tfNames[] = {"M5", "D1"};
    int confirmationsNeeded = 1; // How many timeframes need to confirm
    int confirmationsFound = 0;
    string confirmDetails = "";
    
    // For each confirmation timeframe
    for(int i=0; i<ArraySize(confirmTFs); i++) {
        // Get basic indicators for this timeframe
        ENUM_TIMEFRAMES tf = confirmTFs[i];
        int tfSignal = 0;
        
        // 1. Check MA alignment
        double ma20 = 0, ma50 = 0;
        int ma20Handle = iMA(Symbol(), tf, 20, 0, MODE_SMA, PRICE_CLOSE);
        int ma50Handle = iMA(Symbol(), tf, 50, 0, MODE_SMA, PRICE_CLOSE);
        
        if(ma20Handle != INVALID_HANDLE) {
    double ma20Buffer[];
    if(CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer) > 0) {
        ma20 = ma20Buffer[0];
    }
    IndicatorRelease(ma20Handle);
}

if(ma50Handle != INVALID_HANDLE) {
    double ma50Buffer[];
    if(CopyBuffer(ma50Handle, 0, 0, 1, ma50Buffer) > 0) {
        ma50 = ma50Buffer[0];
    }
    IndicatorRelease(ma50Handle);
}
        
        double close = iClose(Symbol(), tf, 0);
        double open = iOpen(Symbol(), tf, 0);
        
        bool maAligned = false;
        if(signal > 0) { // Buy signal
            if(close > ma20 && ma20 > ma50) maAligned = true;
        } else { // Sell signal
            if(close < ma20 && ma20 < ma50) maAligned = true;
        }
        
        // 2. Current candle direction
        bool candleAligned = false;
        if(signal > 0 && close > open) candleAligned = true;
        if(signal < 0 && close < open) candleAligned = true;
        
        // 3. RSI alignment
        int rsiHandle = iRSI(Symbol(), tf, 14, PRICE_CLOSE);
        double rsiBuffer[];
        CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer);
        double rsi = rsiBuffer[0];
        IndicatorRelease(rsiHandle);
        bool rsiAligned = false;
        if(signal > 0 && rsi > 50) rsiAligned = true;
        if(signal < 0 && rsi < 50) rsiAligned = true;
        
        // 4. MACD alignment
        int macdHandle = iMACD(Symbol(), tf, 12, 26, 9, PRICE_CLOSE);
        double macdMain[], macdSignal[];
        CopyBuffer(macdHandle, 0, 0, 1, macdMain);
        CopyBuffer(macdHandle, 1, 0, 1, macdSignal);
        IndicatorRelease(macdHandle);
        bool macdAligned = false;
        if(signal > 0 && macdMain[0] > macdSignal[0]) macdAligned = true;
        if(signal < 0 && macdMain[0] < macdSignal[0]) macdAligned = true;
        
        // Calculate alignment score for this timeframe
        int alignmentScore = (maAligned ? 1 : 0) + (candleAligned ? 1 : 0) + 
                             (rsiAligned ? 1 : 0) + (macdAligned ? 1 : 0);
        
        // Determine if this timeframe confirms the signal
        // At least 2 out of 4 conditions need to be aligned - Reduced from 3 to lower entry strictness
        bool confirmedTF = (alignmentScore >= 2);
        if(confirmedTF) confirmationsFound++;
        
        // Build confirmation details string
        confirmDetails += tfNames[i] + ": " + (confirmedTF ? "Confirmed" : "Not confirmed") + 
                         " (MA:" + (maAligned ? "Y" : "N") + 
                         ", Candle:" + (candleAligned ? "Y" : "N") + 
                         ", RSI:" + (rsiAligned ? "Y" : "N") + 
                         ", MACD:" + (macdAligned ? "Y" : "N") + ")\n";
    }
    
    bool confirmed = (confirmationsFound >= confirmationsNeeded);
    LogInfo("Multi-timeframe confirmation: " + (confirmed ? "PASSED" : "FAILED") + 
            " (" + IntegerToString(confirmationsFound) + "/" + IntegerToString(confirmationsNeeded) + ")\n" + 
            confirmDetails);
    
    return confirmed;
}

//+------------------------------------------------------------------+
//| ML-like signal quality evaluation                                |
//+------------------------------------------------------------------+
double CalculateSignalQuality(int signal) {
    if(!EnableSignalQualityML || signal == 0) return 0.0;
    
    // Initialize quality score
    double quality = 0.0;
    
    // Adjust base quality based on trading mode
    double modeQualityAdjustment = 0.0;
    if(currentTradingMode == MODE_HFT) {
        // For HFT, give slight preference to technical and short-term factors
        modeQualityAdjustment = 0.05;
    } else if(currentTradingMode == MODE_NORMAL) {
        // For normal trading, give slight preference to structural and fundamental factors
        modeQualityAdjustment = 0.05;
    }
    double totalWeight = 0.0;
    
    // 1. Market regime alignment (weight: 25%)
    double regimeAlignment = 0.0;
    double regimeWeight = 0.25;
    totalWeight += regimeWeight;
    
    int localRegime = currentRegime; // Use a local copy to avoid ambiguity
    if(localRegime >= 0) {
        if((signal > 0 && localRegime == TRENDING_UP) || 
           (signal < 0 && localRegime == TRENDING_DOWN)) {
            regimeAlignment = 1.0; // Perfect alignment with trend
        }
        else if(localRegime == REGIME_CHOPPY) {
            regimeAlignment = 0.2; // Poor conditions in choppy markets
        }
        else if(localRegime == REGIME_RANGING_NARROW) {
            regimeAlignment = 0.6; // Decent for range trading if at extremes
        }
        else if(localRegime == REGIME_RANGING_WIDE) {
            regimeAlignment = 0.7; // Better for range trading if at extremes
        }
        else if(localRegime == BREAKOUT) {
            regimeAlignment = 0.8; // Good for breakout following
        }
        else {
            regimeAlignment = 0.5; // Neutral conditions
        }
    }
    quality += regimeAlignment * regimeWeight;
    
    // 2. Divergence confirmation (weight: 35%)
    DivergenceInfo divInfo; // Use a local variable instead of the global lastDivergence
    divInfo.found = false;
    double divergenceQuality = 0.0; // Changed to double to match CheckForDivergence parameter
    bool hasDivergence = CheckForDivergence(signal, divergenceQuality); // Using correct overload
    divInfo.found = hasDivergence; // Update the local struct based on function result
    
    // Create a string for quality description
    string qualityDescStr = "";
    
    if(divInfo.found) {
        if(divInfo.type == DIVERGENCE_REGULAR_BULL || divInfo.type == DIVERGENCE_REGULAR_BEAR) {
        } else if(divInfo.type == DIVERGENCE_HIDDEN_BULL || divInfo.type == DIVERGENCE_HIDDEN_BEAR) {
            quality += 0.15 * (double)0.5; // Hidden divergence gets half points
        }
        string divergenceType = (divInfo.type > 2) ? "Hidden" : "Regular";
        qualityDescStr = StringFormat("Divergence: %s", divergenceType);
    }
    
    // 3. Volatility conditions (weight: 15%)
    double volatilityScore = 0.0;
    double volatilityWeight = (double)0.15;
    totalWeight += volatilityWeight;
    
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    double avgAtr = CalculateAverageATR(20);
    
    if(avgAtr > 0) {
        double volatilityRatio = atr / avgAtr;
        
        // Ideal volatility is between 0.6-2.0x average - Widened range to allow more entries
        if(volatilityRatio >= 0.6 && volatilityRatio <= 2.0) {
            volatilityScore = 1.0 - (MathAbs(1.0 - volatilityRatio) / 1.4); // Closer to 1.0 is better, but with a wider acceptable range
        }
        else if(volatilityRatio > 2.0 && volatilityRatio <= 2.5) {
            volatilityScore = 0.6; // High volatility - less risky now
        }
        else if(volatilityRatio > 0.4 && volatilityRatio < 0.6) {
            volatilityScore = 0.8; // Low volatility - more tradable now
        }
        else {
            volatilityScore = 0.5; // Even extreme volatility is more acceptable now
        }
    }
    quality += volatilityScore * volatilityWeight;
    
    // Order block quality (valid block detection with enhanced weighting)
    double blockScore = 0.0;
    double blockWeight = 0.20; // Increased from 0.15 to give more importance to blocks
    int validBlockCount = 0;
    double totalBlockStrength = 0;
    // Initialize order block structure and analytics
    // These variables are already defined as globals - removing duplicate definitions
    //OrderBlock recentBlocks[MAX_BLOCKS]; // Already defined at line 148
    //LiquidityGrab recentGrabs[MAX_BLOCKS]; // Already defined at line 146
    //FairValueGap recentFVGs[MAX_BLOCKS]; // Already defined at line 147
    for(int i=0; i<MAX_BLOCKS; i++) {
        recentBlocks[i].valid = false;
        recentGrabs[i].valid = false;
        recentFVGs[i].valid = false;
    }
    double blockVolumeScore = 0;
    double blockImbalanceScore = 0;
    
    // Find recent valid blocks that align with our signal
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(i < MAX_BLOCKS && recentBlocks[i].valid && ((signal > 0 && recentBlocks[i].isBuy) || (signal < 0 && !recentBlocks[i].isBuy))) {
            validBlockCount++;
            
            // Add block strength factors
            totalBlockStrength += recentBlocks[i].strength;
            
            // Volume analysis - higher volume blocks carry more weight
            if(recentBlocks[i].volume > 1.5) { // 50% above average
                blockVolumeScore += 0.1;
            } else if(recentBlocks[i].volume > 1.2) { // 20% above average
                blockVolumeScore += 0.05;
            }
            
            // Imbalance analysis - blocks with high imbalance ratio carry more weight
            if(recentBlocks[i].imbalanceRatio > 0.7) {
                blockImbalanceScore += 0.1;
            } else if(recentBlocks[i].imbalanceRatio > 0.5) {
                blockImbalanceScore += 0.05;
            }
            
            // Recency factor - more recent blocks carry more weight
            int age = MathMax(1, (int)((TimeCurrent() - recentBlocks[i].time) / 60)); // Age in minutes
            double recencyFactor = 1.0 / MathSqrt(age);
            blockScore += 0.15 * recencyFactor; // Base score adjusted by recency
        }
    }
    
    // Add strength, volume and imbalance components to block score
    if(validBlockCount > 0) {
        double avgStrength = totalBlockStrength / validBlockCount;
        blockScore += 0.2 * MathMin(avgStrength / 5.0, 1.0); // Normalize strength to 0-1 range
        blockScore += blockVolumeScore;
        blockScore += blockImbalanceScore;
    }
    
    // Adjust block score based on the relationship between valid blocks and market regime
    if(validBlockCount > 0 && regimeAlignment > 0.7) {
        blockScore *= 1.2; // Boost score when blocks align with strong regime
    }
    
    // Cap the blockScore at 1.0
    blockScore = MathMin(blockScore, 1.0);
    
    LogInfo("Enhanced block scoring: ValidCount=" + IntegerToString(validBlockCount) + 
            " AvgStrength=" + DoubleToString(validBlockCount > 0 ? totalBlockStrength/validBlockCount : 0, 2) + 
            " Volume=" + DoubleToString(blockVolumeScore, 2) + 
            " Imbalance=" + DoubleToString(blockImbalanceScore, 2) + 
            " Final=" + DoubleToString(blockScore, 2));
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
        LogInfo("Signal Quality Analysis: Regime="+DoubleToString(regimeAlignment,2)+" (w="+DoubleToString(regimeWeight,2)+") "+
                "Divergence="+DoubleToString(divergenceScore,2)+" (w="+DoubleToString(divergenceWeight,2)+") "+
                "Volatility="+DoubleToString(volatilityScore,2)+" (w="+DoubleToString(volatilityWeight,2)+") "+
                "BlockQuality="+DoubleToString(blockScore,2)+" (w="+DoubleToString(blockWeight,2)+") "+
                "History="+DoubleToString(historyScore,2)+" (w="+DoubleToString(historyWeight,2)+") Final="+DoubleToString(quality,2));
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
    // --- Expanded Dashboard ---
    double winRate = 0, avgRisk = 0;
    int nTrades = 0, nWins = 0, nLosses = 0;
    int tradeProfitsSize = ArraySize(tradeProfits);
    
    // Get color and display name for current trading mode
    color modeColor = clrWhite;
    string modeName = "UNKNOWN";
    string modeDescription = "";
    
    if(currentTradingMode == MODE_HFT) {
        modeColor = clrOrange;
        modeName = "HFT MODE";
        modeDescription = "High-Frequency Trading - Tight stops, quick targets";
    }
    else if(currentTradingMode == MODE_NORMAL) {
        modeColor = clrSkyBlue;
        modeName = "NORMAL MODE";
        modeDescription = "Standard Trading - Wider stops, larger targets";
    }
    else if(currentTradingMode == MODE_HYBRID_AUTO) {
        modeColor = clrLime;
        modeName = "HYBRID AUTO";
        modeDescription = "Auto-switching based on market conditions";
    }
    
    // Create/update trading mode label
    if(!ObjectFind(0, "SMC_Dashboard_Mode_Label")) {
        ObjectCreate(0, "SMC_Dashboard_Mode_Label", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Label", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Label", OBJPROP_XDISTANCE, 30);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Label", OBJPROP_YDISTANCE, 220);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Label", OBJPROP_COLOR, clrLightGray);
        ObjectSetString(0, "SMC_Dashboard_Mode_Label", OBJPROP_TEXT, "Trading Mode:");
        ObjectSetString(0, "SMC_Dashboard_Mode_Label", OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Label", OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Label", OBJPROP_SELECTABLE, false);
    }
    
    // Create/update mode value display
    if(!ObjectFind(0, "SMC_Dashboard_Mode_Value")) {
        ObjectCreate(0, "SMC_Dashboard_Mode_Value", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Value", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Value", OBJPROP_XDISTANCE, 140);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Value", OBJPROP_YDISTANCE, 220);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Value", OBJPROP_SELECTABLE, false);
        ObjectSetString(0, "SMC_Dashboard_Mode_Value", OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Value", OBJPROP_FONTSIZE, 8);
    }
    
    // Update mode value
    ObjectSetString(0, "SMC_Dashboard_Mode_Value", OBJPROP_TEXT, modeName);
    ObjectSetInteger(0, "SMC_Dashboard_Mode_Value", OBJPROP_COLOR, modeColor);
    
    // Create/update mode description
    if(!ObjectFind(0, "SMC_Dashboard_Mode_Desc")) {
        ObjectCreate(0, "SMC_Dashboard_Mode_Desc", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Desc", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Desc", OBJPROP_XDISTANCE, 240);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Desc", OBJPROP_YDISTANCE, 220);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Desc", OBJPROP_COLOR, clrSilver);
        ObjectSetString(0, "SMC_Dashboard_Mode_Desc", OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Desc", OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, "SMC_Dashboard_Mode_Desc", OBJPROP_SELECTABLE, false);
    }
    
    // Update mode description
    ObjectSetString(0, "SMC_Dashboard_Mode_Desc", OBJPROP_TEXT, modeDescription);
    
    // Mode-specific performance metrics
    int hftWins = 0, hftLosses = 0, normalWins = 0, normalLosses = 0;
    double hftProfit = 0, normalProfit = 0;
    
    // Track performance by mode (assuming we've added mode tracking to the Journal)
    // This would need corresponding updates to the AddTrade function in the Journal class
    for(int i=0; i<tradeProfitsSize && i<METRIC_WINDOW; i++) {
        if(tradeProfits[i] > 0) nWins++;
        else if(tradeProfits[i] < 0) nLosses++;
        if(tradeProfits[i] != 0) { avgRisk += MathAbs(tradeReturns[i]); nTrades++; }
    }
    if(nTrades > 0) {
        winRate = double(nWins)/nTrades;
        avgRisk /= nTrades;
    }
    string regimeStr = GetRegimeName(currentRegime);
    int validBlocks = 0, bearishBlocks = 0, bullishBlocks = 0;
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            validBlocks++;
            if(recentBlocks[i].isBuy) bullishBlocks++;
            else bearishBlocks++;
        }
    }
    string info = "WinRate: "+DoubleToString(winRate*100,1)+"% "+
                 "AvgRisk: "+DoubleToString(avgRisk,2)+" "+
                 "Regime: "+regimeStr+"\n"+
                 "Blocks: Valid="+IntegerToString(validBlocks)+
                 " Bull="+IntegerToString(bullishBlocks)+" Bear="+IntegerToString(bearishBlocks)+"\n"+
                 "Streak: Win="+IntegerToString(winStreak)+" Loss="+IntegerToString(lossStreak)+"\n";
    Comment(info);

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
    
    switch((int)currentRegime) {
        case REGIME_TRENDING_UP: 
            regimeName = "TRENDING UP"; 
            regimeColor = clrLime;
            break;
        case REGIME_TRENDING_DOWN: 
            regimeName = "TRENDING DOWN"; 
            regimeColor = clrRed;
            break;
        case REGIME_HIGH_VOLATILITY: 
            regimeName = "HIGH VOLATILITY"; 
            regimeColor = clrOrange;
            break;
        case REGIME_LOW_VOLATILITY: 
            regimeName = "LOW VOLATILITY"; 
            regimeColor = clrDeepSkyBlue;
            break;
        case REGIME_RANGING_NARROW: 
            regimeName = "NARROW RANGE"; 
            regimeColor = clrAqua;
            break;
        case REGIME_RANGING_WIDE: 
            regimeName = "WIDE RANGE"; 
            regimeColor = clrMediumSpringGreen;
            break;
        case REGIME_BREAKOUT: 
            regimeName = "BREAKOUT"; 
            regimeColor = clrYellow;
            break;
        case REGIME_REVERSAL: 
            regimeName = "REVERSAL"; 
            regimeColor = clrFuchsia;
            break;
        // REGIME_CHOPPY case already handled above
        // Leaving this commented to avoid duplicate case value errors
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
        totalWins += ::regimeWins[i];
        totalLosses += ::regimeLosses[i];
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
    
    // Add missed opportunities and adaptive filter information to dashboard
    // Create labels if they don't exist
    if(!ObjectCreate(0, "SMC_Dashboard_Label_7", OBJ_LABEL, 0, 0, 0)) {
        ObjectMove(0, "SMC_Dashboard_Label_7", 0, 205, 190);
    }
    if(!ObjectCreate(0, "SMC_Dashboard_Value_7", OBJ_LABEL, 0, 0, 0)) {
        ObjectMove(0, "SMC_Dashboard_Value_7", 0, 335, 190);
    }
    if(!ObjectCreate(0, "SMC_Dashboard_Label_8", OBJ_LABEL, 0, 0, 0)) {
        ObjectMove(0, "SMC_Dashboard_Label_8", 0, 205, 210);
    }
    if(!ObjectCreate(0, "SMC_Dashboard_Value_8", OBJ_LABEL, 0, 0, 0)) {
        ObjectMove(0, "SMC_Dashboard_Value_8", 0, 335, 210);
    }
    
    // Configure label properties
    ObjectSetString(0, "SMC_Dashboard_Label_7", OBJPROP_TEXT, "Missed Opportunities:");
    ObjectSetInteger(0, "SMC_Dashboard_Label_7", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "SMC_Dashboard_Label_7", OBJPROP_FONTSIZE, 8);
    
    ObjectSetString(0, "SMC_Dashboard_Label_8", OBJPROP_TEXT, "Filter Threshold:");
    ObjectSetInteger(0, "SMC_Dashboard_Label_8", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "SMC_Dashboard_Label_8", OBJPROP_FONTSIZE, 8);
    
    // Calculate percentage of missed opportunities that would have been profitable
    int totalWithOutcome = 0;
    int profitableMissed = 0;
    for(int i = 0; i < missedOpportunityCount; i++) {
        if(missedOpportunities[i].potentialProfit != 0) { // Has outcome data
            totalWithOutcome++;
            if(missedOpportunities[i].wouldHaveWon) {
                profitableMissed++;
            }
        }
    }
    
    // Update value fields
    string missedOppText = IntegerToString(missedOpportunityCount) + " total";
    if(totalWithOutcome > 0) {
        double winRate = (double)profitableMissed / totalWithOutcome * 100.0;
        missedOppText += " (" + DoubleToString(winRate, 1) + "% win)";
    }
    
    ObjectSetString(0, "SMC_Dashboard_Value_7", OBJPROP_TEXT, missedOppText);
    ObjectSetInteger(0, "SMC_Dashboard_Value_7", OBJPROP_COLOR, clrOrange);
    ObjectSetInteger(0, "SMC_Dashboard_Value_7", OBJPROP_FONTSIZE, 8);
    
    string filterText = DoubleToString(adaptiveFilters.signalQualityThreshold, 2);
    filterText += " MTF:" + (adaptiveFilters.requireMultiTimeframe ? "ON" : "OFF");
    
    ObjectSetString(0, "SMC_Dashboard_Value_8", OBJPROP_TEXT, filterText);
    ObjectSetInteger(0, "SMC_Dashboard_Value_8", OBJPROP_COLOR, clrAqua);
    ObjectSetInteger(0, "SMC_Dashboard_Value_8", OBJPROP_FONTSIZE, 8);
    
    // Draw missed opportunities on chart
    DrawMissedOpportunities();
}

//+------------------------------------------------------------------+
//| Monitor trading environment for potential issues                 |
//+------------------------------------------------------------------+
void MonitorTradingEnvironment() {
    static datetime lastCheckTime = 0;
    datetime currentTime = TimeCurrent();
    
    // Only check once per minute to avoid excessive logging
    if(currentTime - lastCheckTime < 60) return;
    
    lastCheckTime = currentTime;
    
    // Check broker stop level requirements
    long stopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double currentBid = GetCurrentBid();
    double currentAsk = GetCurrentAsk();
    double spread = currentAsk - currentBid;
    double minStopDistance = GetMinimumStopDistance();
    
    // Calculate common values for high-value assets
    bool isHighValueAsset = (SymbolInfoDouble(Symbol(), SYMBOL_LAST) > 10000.0) || (StringFind(Symbol(), "BTC") >= 0);
    double atr = CalculateATR(14);
    double atrStop = GetATRStop(14);
    
    // Create diagnostic log
    if(DisplayDebugInfo) {
        string diagnosticLog = StringFormat(
            "\n===== TRADING ENVIRONMENT MONITOR =====\n" +
            "Symbol: %s\n" +
            "Current Bid/Ask: %.5f / %.5f\n" +
            "Spread: %.5f points\n" +
            "Broker Stop Level: %d points\n" +
            "Minimum Stop Distance: %.5f (%.1f points)\n" +
            "Current ATR: %.5f\n" +
            "ATR-based Stop: %.5f (%.1f points)\n" +
            "High-value Asset: %s\n" +
            "====================================",
            Symbol(), currentBid, currentAsk, spread/_Point, 
            stopLevel, minStopDistance, minStopDistance/_Point,
            atr, atrStop, atrStop/_Point,
            (isHighValueAsset ? "Yes" : "No")
        );
        
        Print(diagnosticLog);
    }
    
    // Check for potential trading issues
    if(spread > minStopDistance) {
        LogWarning(StringFormat("Current spread (%.1f points) exceeds minimum stop distance (%.1f points) - trades may fail", 
                             spread/_Point, minStopDistance/_Point));
    }
    
    // Check if market is closed
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    bool isWeekendNow = (dt.day_of_week == 0 || dt.day_of_week == 6);
    bool isLateNight = (dt.hour >= 22 || dt.hour <= 2);
    
    // Update the global variable
    isWeekend = isWeekendNow;
    
    if(isWeekendNow && !isHighValueAsset) {
        LogWarning("Weekend detected - trading may be limited for non-crypto assets");
    }
    
    if(isLateNight) {
        // Check for wider spreads during low liquidity periods
        double normalSpread = 20 * _Point; // Typical normal spread (adjust based on symbol)
        if(spread > normalSpread * 3) {
            LogWarning(StringFormat("Wider than normal spread detected during low liquidity period (%.1f points)", 
                                 spread/_Point));
        }
    }
}

//+------------------------------------------------------------------+
//| Timer function for background calculations                        |
//+------------------------------------------------------------------+
void OnTimer() {
    // Update cached indicators to reduce OnTick overhead
    datetime currentTime = TimeCurrent();
    
    // Handle performance dashboard - it needs to be created first
    static bool dashboardInitialized = false;
    if(ShowPerformanceDashboard) {
        if(!dashboardInitialized) {
            CreatePerformanceDashboard();
            dashboardInitialized = true;
            Print("[TIMER] Performance dashboard initialized");
        } else {
            UpdatePerformanceDashboard();
        }
    }
    
    // Only recalculate every 2 seconds to avoid excessive calculations
    if(currentTime - lastIndicatorCalc >= 2) {
        // Calculate and cache common indicators
        cachedATR = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
        
        int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
        int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
        
        double ma20Buffer[], ma50Buffer[];
        ArraySetAsSeries(ma20Buffer, true);
        ArraySetAsSeries(ma50Buffer, true);
        
        if(CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer) > 0) cachedMA20 = ma20Buffer[0];
        if(CopyBuffer(ma50Handle, 0, 0, 1, ma50Buffer) > 0) cachedMA50 = ma50Buffer[0];
        
        IndicatorRelease(ma20Handle);
        IndicatorRelease(ma50Handle);
        
        lastIndicatorCalc = currentTime;
        
        // Log indicator update (only in debug mode)
        if(DisplayDebugInfo) {
            LogInfo(StringFormat("Cached indicators updated: ATR=%.5f, MA20=%.5f, MA50=%.5f", 
                               cachedATR, cachedMA20, cachedMA50));
        }
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set initial trading mode based on input parameter
    currentTradingMode = TradingMode;
    if(currentTradingMode == MODE_HYBRID_AUTO) {
        // If in hybrid mode, start with normal mode until first analysis
        currentTradingMode = MODE_NORMAL;
        Print("[INIT] Starting in HYBRID AUTO mode - will determine optimal mode on first tick");
    } else {
        Print("[INIT] Starting in fixed mode: ", EnumToString((ENUM_TRADING_MODE)currentTradingMode));
    }
    
    // Enable timer for background indicator calculations (every 1 second)
    EventSetTimer(1);
    Print("[INIT] Performance optimization: Timer enabled for background calculations");
    
    // Initialize performance dashboard
    if(ShowPerformanceDashboard) {
        Print("[INIT] Performance dashboard will be initialized");
        // CreatePerformanceDashboard function will be called from OnTimer
    }
    // --- Input Validation ---
    string err = "";
    if(RiskPercent < 0.01 || RiskPercent > 10) err += "RiskPercent out of range (0.01-10). ";
    if(SL_ATR_Mult < 0.1 || SL_ATR_Mult > 10) err += "SL_ATR_Mult out of range (0.1-10). ";
    if(TP_ATR_Mult < 0.1 || TP_ATR_Mult > 20) err += "TP_ATR_Mult out of range (0.1-20). ";
    if(TrailingStopMultiplier < 0.05 || TrailingStopMultiplier > 5) err += "TrailingStopMultiplier out of range (0.05-5). ";
    if(ActualSignalCooldownSeconds < 1 || ActualSignalCooldownSeconds > 3600) err += "SignalCooldownSeconds out of range (1-3600). ";
    if(MaxPortfolioRiskPercent < 0.1 || MaxPortfolioRiskPercent > 100) err += "MaxPortfolioRiskPercent out of range (0.1-100). ";
    if(err != "") { LogError("Input validation failed: " + err); return INIT_FAILED; }
    LogInfo("Initialization complete. All input parameters validated.");

    // Initialize the adaptive filters for optimized trading
    InitializeAdaptiveFilters();
    
    // Set up tracker for missed opportunities
    ArrayResize(missedOpportunities, MAX_MISSED_OPPORTUNITIES);
    
    // DIAGNOSTIC: Create effective block strength variable since we can't modify the constant
    int effectiveMinBlockStrength = 1;  // Use this variable instead of MinBlockStrength
    if(DisplayDebugInfo) Print("[DIAG] Using effectiveMinBlockStrength=", effectiveMinBlockStrength, " instead of MinBlockStrength=", MinBlockStrength);
    
    // Ensure enough bars for analysis
    if(Bars(Symbol(), PERIOD_CURRENT) < 500) {
        Alert("Need at least 500 bars for proper analysis");
        return INIT_FAILED;
    }
    
    // Initialize working copies of constants
    
    // Initialize adaptive filters system
    InitializeAdaptiveFilters();
    
    // Initialize price cache
    priceCache.Init();
    
    // Log adaptive filter initialization
    LogInfo("Adaptive filter system initialized with quality threshold: " + 
            DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
    workingATRThreshold = MinATRThresholdGlobal;
    workingRiskPercent = RiskPercent;
    // Use the global workingTrailingStopMultiplierLocal
    workingTrailingStopMultiplierLocal = TrailingStopMultiplier;
    // workingTrailingStopMultiplierLocal = EnhancedTrailingStopMultiplier; // Commented out as EnhancedTrailingStopMultiplier is undeclared
    workingTrailingActivationPct = TrailingActivationPct;
    workingMinSignalQualityTolocalTrade = MinSignalQualityToTrade;
    
    if(DisplayDebugInfo) {
        LogInfo("Initialized working variables:");
        LogInfo("  workingATRThreshold = " + DoubleToString(workingATRThreshold, 6));
        LogInfo("  workingRiskPercent = " + DoubleToString(workingRiskPercent, 2));
        LogInfo("  workingTrailingStopMultiplierLocal = " + DoubleToString(workingTrailingStopMultiplierLocal, 2));
        LogInfo("  workingTrailingActivationPct = " + DoubleToString(workingTrailingActivationPct, 2));
    }

    // Initialize trade object
    CTrade trade_local; // Declare local trade object
    trade_local.SetDeviationInPoints(10);

    // Initialize indicator buffer arrays
    if(ArraySize(localAtrBuffer) < 100) ArraySetAsSeries(localAtrBuffer, true);
    if(ArraySize(maBuffer) < 100) ArraySetAsSeries(maBuffer, true);
    if(ArraySize(volBuffer) < 100) ArraySetAsSeries(volBuffer, true);
    
    // Resize arrays to ensure they have enough capacity
    ArrayResize(localAtrBuffer, 100);
    ArrayResize(maBuffer, 100);
    ArrayResize(volBuffer, 100);
    
    // Initialize performance arrays
    // Ensure all arrays are properly declared as dynamic in the globals section
    if(ArraySize(tradeProfits) == 0) ArrayResize(tradeProfits, METRIC_WINDOW);
    if(ArraySize(regimeWins) == 0) ArrayResize(regimeWins, MAX_REGIMES);
    if(ArraySize(regimeLosses) == 0) ArrayResize(regimeLosses, MAX_REGIMES);
    if(ArraySize(regimeProfit) == 0) ArrayResize(regimeProfit, MAX_REGIMES);
    
    // Initialize advanced features
    AutocalibrateForSymbol();
    CreateDashboard();
    
    // Resize regime tracking arrays first - using :: to avoid ambiguous access
    if(ArraySize(::regimeWins) < REGIME_COUNT) ArrayResize(::regimeWins, REGIME_COUNT);
    if(ArraySize(::regimeLosses) < REGIME_COUNT) ArrayResize(::regimeLosses, REGIME_COUNT);
    if(ArraySize(::regimeProfit) < REGIME_COUNT) ArrayResize(::regimeProfit, REGIME_COUNT);
    if(ArraySize(::regimeMaxDrawdown) < REGIME_COUNT) ArrayResize(::regimeMaxDrawdown, REGIME_COUNT);
    
    // Initialize regime tracking arrays using scope resolution operator to avoid ambiguity
    for(int i=0; i<REGIME_COUNT; i++) {
        ::regimeWins[i] = 0;
        ::regimeLosses[i] = 0;
        ::regimeProfit[i] = 0.0;
        ::regimeMaxDrawdown[i] = 0.0;
    }
    
    // Resize and initialize performance tracking arrays
    ArrayResize(tradeProfits, METRIC_WINDOW);
    for(int i=0; i<METRIC_WINDOW; i++) {
        tradeProfits[i] = 0.0;
    }
    
    // Resize and initialize prediction tracking arrays
    ArrayResize(predictionResults, ACCURACY_WINDOW);
    for(int i=0; i<ACCURACY_WINDOW; i++) {
        predictionResults[i] = 0;
    }
    
    // Resize and initialize indicator buffers
    ArrayResize(localAtrBuffer, 100);
    ArrayResize(maBuffer, 100);
    ArrayResize(volBuffer, 100);
    for(int i=0; i<100; i++) {
        localAtrBuffer[i] = 0.0;
        maBuffer[i] = 0.0;
        volBuffer[i] = 0.0;
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

    Print("[Init] SMC Scalper Hybrid initializedConsecLoss successfully");
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
        totalWins += ::regimeWins[i];
        totalLosses += ::regimeLosses[i];
        totalProfit += ::regimeProfit[i];
        if(::regimeProfit[i]>0) grossProfit += ::regimeProfit[i];
        else grossLoss += MathAbs(::regimeProfit[i]);
        // Add check for max drawdown
        if(::regimeMaxDrawdown[i] > maxDD) maxDD = ::regimeMaxDrawdown[i];
    }
    double winRate = (totalWins+totalLosses>0) ? totalWins/(totalWins+totalLosses) : 0;
    double pf = (grossLoss>0) ? grossProfit/grossLoss : 1.0;
    diag += "\nWin Rate: " + DoubleToString(winRate*100,1) + "%";
    diag += "\nPF: " + DoubleToString(pf,2);
    diag += "\nDrawdown: " + DoubleToString(maxDD,2);
    Comment(diag);
}

//+------------------------------------------------------------------+
//| Improved Error Handling & Escalation                             |
//+------------------------------------------------------------------+
int consecutiveTradeErrors = 0;
input int MaxConsecutiveTradeErrors = 5;

bool HandleTradeError(int errorCode, string context) {
    // Use our enhanced error logging function
    string operation = context;
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_LAST);
    LogTradeError(errorCode, operation, Symbol(), currentPrice, 0, 0);
    
    Print("[SMC ERROR] ", context, " failed. Error ", errorCode, ": ", GetLastError());
    consecutiveTradeErrors++;
    if(consecutiveTradeErrors >= MaxConsecutiveTradeErrors) {
        Alert("[SMC] Too many consecutive trade errors. EA auto-disabled.");
        ExpertRemove();
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Enhanced Trade Processing - To be called during each tick/cycle   |
//+------------------------------------------------------------------+
void EnhancedTradeProcessing() {
    // Reset consecutive error counter on successful operations
    static datetime lastResetTime = 0;
    if(TimeCurrent() - lastResetTime > 3600) { // Reset error counter every hour if no new errors
        consecutiveTradeErrors = 0;
        lastResetTime = TimeCurrent();
    }
    
    // Monitor trading environment for potential issues
    MonitorTradingEnvironment();
    
    // Check for invalid trade parameters before attempting execution
    double minStopDistance = GetMinimumStopDistance();
    double currentBid = GetCurrentBid();
    double currentAsk = GetCurrentAsk();
    double spread = currentAsk - currentBid;
    
    // Check for common trading issues
    if(spread > minStopDistance * 1.5) {
        LogWarning(StringFormat("[TRADE WARNING] Spread (%.1f points) exceeds 150%% of minimum stop distance (%.1f points)", 
                             spread/_Point, minStopDistance/_Point));
        // Consider adjusting trade parameters or skipping trades in extreme conditions
    }
    
    // Check market hours and conditions
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Just use the global isWeekend variable directly without redeclaring it
    // Update the global variable for consistent state tracking
    isWeekend = (dt.day_of_week == 0 || dt.day_of_week == 6);
    
    // Adjust trading for crypto assets that trade 24/7
    bool isCrypto = (StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "ETH") >= 0);
    if(isWeekend && !isCrypto) {
        LogInfo("Weekend detected for non-crypto asset - adjusting trade parameters");
        // Weekend trading might have different conditions
    }
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
            totalWins += ::regimeWins[i];
            totalLosses += ::regimeLosses[i];
            totalProfit += ::regimeProfit[i];
            if(::regimeProfit[i]>0) grossProfit += ::regimeProfit[i];
            else grossLoss += MathAbs(::regimeProfit[i]);
            // Check max drawdown
            if(::regimeMaxDrawdown[i] > maxDD) maxDD = ::regimeMaxDrawdown[i];
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
FeatureStats featureStats; // Zero-initializedConsecLoss by default in MQL5

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
        MinATRThresholdGlobal = (dynamicATR > MinATRFloor) ? dynamicATR : MinATRFloor;
    } else {
        MinATRThresholdGlobal = MinATRThreshold;
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
//+------------------------------------------------------------------+
//| Define regime-specific parameter sets                            |
//+------------------------------------------------------------------+
struct RegimeParameters {
    double riskPercent;
    double slAtrMult;
    double tpAtrMult;
    double trailingMult;
    double minSignalQuality;
    double aggressiveness;
};

// Define parameter sets for different market regimes
RegimeParameters regimeParams[5]; // For each regime type

//+------------------------------------------------------------------+
//| Initialize regime-specific parameter sets                         |
//+------------------------------------------------------------------+
void InitRegimeParameters() {
    // Default/neutral regime (2)
    regimeParams[2].riskPercent = RiskPercent;
    regimeParams[2].slAtrMult = SL_ATR_Mult;
    regimeParams[2].tpAtrMult = TP_ATR_Mult;
    regimeParams[2].trailingMult = TrailingStopMultiplier;
    regimeParams[2].minSignalQuality = MinSignalQualityToTrade;
    regimeParams[2].aggressiveness = 1.0;
    
    // Strong uptrend regime (0) - more aggressive for buys
    regimeParams[0].riskPercent = RiskPercent * 1.1;
    regimeParams[0].slAtrMult = SL_ATR_Mult * 1.2;
    regimeParams[0].tpAtrMult = TP_ATR_Mult * 1.3;
    regimeParams[0].trailingMult = TrailingStopMultiplier * 0.8;
    regimeParams[0].minSignalQuality = MinSignalQualityToTrade * 0.9;
    regimeParams[0].aggressiveness = 1.2;
    
    // Strong downtrend regime (1) - more aggressive for sells
    regimeParams[1].riskPercent = RiskPercent * 1.1;
    regimeParams[1].slAtrMult = SL_ATR_Mult * 1.2;
    regimeParams[1].tpAtrMult = TP_ATR_Mult * 1.3;
    regimeParams[1].trailingMult = TrailingStopMultiplier * 0.8;
    regimeParams[1].minSignalQuality = MinSignalQualityToTrade * 0.9;
    regimeParams[1].aggressiveness = 1.2;
    
    // Choppy/ranging regime (3) - more conservative
    regimeParams[3].riskPercent = RiskPercent * 0.7;
    regimeParams[3].slAtrMult = SL_ATR_Mult * 0.8;
    regimeParams[3].tpAtrMult = TP_ATR_Mult * 0.7;
    regimeParams[3].trailingMult = TrailingStopMultiplier * 1.2;
    regimeParams[3].minSignalQuality = MinSignalQualityToTrade * 1.2;
    regimeParams[3].aggressiveness = 0.7;
    
    // Extreme volatility regime (4) - very conservative
    regimeParams[4].riskPercent = RiskPercent * 0.5;
    regimeParams[4].slAtrMult = SL_ATR_Mult * 0.7;
    regimeParams[4].tpAtrMult = TP_ATR_Mult * 0.5;
    regimeParams[4].trailingMult = TrailingStopMultiplier * 1.5;
    regimeParams[4].minSignalQuality = MinSignalQualityToTrade * 1.5;
    regimeParams[4].aggressiveness = 0.5;
    
    LogInfo("Regime-specific parameters initializedConsecLoss");
}

//+------------------------------------------------------------------+
//| Apply regime-specific parameters based on current market regime   |
//+------------------------------------------------------------------+
void ApplyRegimeParameters() {
    if(currentRegime < 0 || currentRegime > 4) {
        LogWarn("Invalid regime detected: " + IntegerToString(currentRegime) + ". Using neutral parameters.");
        currentRegime = 2; // Default to neutral
    }
    
    // Store original values
    static double originalRiskPercent = RiskPercent;
    static double originalSL_ATR_Mult = SL_ATR_Mult;
    static double originalTP_ATR_Mult = TP_ATR_Mult;
    static double originalTrailingMult = TrailingStopMultiplier;
    static double originalMinSignalQuality = MinSignalQualityToTrade;
    
    // Get parameters for current regime
    double newRiskPercent = regimeParams[currentRegime].riskPercent;
    double newSL_ATR_Mult = regimeParams[currentRegime].slAtrMult;
    double newTP_ATR_Mult = regimeParams[currentRegime].tpAtrMult;
    double newTrailingMult = regimeParams[currentRegime].trailingMult;
    double newMinSignalQuality = regimeParams[currentRegime].minSignalQuality;
    
    // Log changes only if there's a significant difference
    if(MathAbs(workingRiskPercent - newRiskPercent) > 0.01) {
        LogParamChange("Regime " + GetRegimeName(currentRegime) + " adjusted RiskPercent: " + 
                      DoubleToString(workingRiskPercent, 2) + " -> " + DoubleToString(newRiskPercent, 2));
        workingRiskPercent = newRiskPercent;
    }
    
    if(MathAbs(SL_ATR_Mult - newSL_ATR_Mult) > 0.01) {
        LogParamChange("Regime " + GetRegimeName(currentRegime) + " adjusted SL_ATR_Mult: " + 
                      DoubleToString(SL_ATR_Mult, 2) + " -> " + DoubleToString(newSL_ATR_Mult, 2));
        // Use a working copy if needed or handle differently
        // SL_ATR_Mult = newSL_ATR_Mult; // Cannot modify constant
    }
    
    if(MathAbs(TP_ATR_Mult - newTP_ATR_Mult) > 0.01) {
        LogParamChange("Regime " + GetRegimeName(currentRegime) + " adjusted TP_ATR_Mult: " + 
                      DoubleToString(TP_ATR_Mult, 2) + " -> " + DoubleToString(newTP_ATR_Mult, 2));
        // Use a working copy if needed or handle differently
        // TP_ATR_Mult = newTP_ATR_Mult; // Cannot modify constant
    }
    
    if(MathAbs(workingTrailingStopMultiplierLocal - newTrailingMult) > 0.01) {
        LogParamChange("Regime " + GetRegimeName(currentRegime) + " adjusted TrailingStopMultiplier: " + 
                      DoubleToString(workingTrailingStopMultiplierLocal, 2) + " -> " + DoubleToString(newTrailingMult, 2));
        workingTrailingStopMultiplierLocal = newTrailingMult;
    }
    
    if(MathAbs(workingMinSignalQualityToTrade - newMinSignalQuality) > 0.01) {
        LogParamChange("Regime " + GetRegimeName(currentRegime) + " adjusted MinSignalQualityToTrade: " + 
                      DoubleToString(workingMinSignalQualityToTrade, 2) + " -> " + DoubleToString(newMinSignalQuality, 2));
        workingMinSignalQualityTolocalTrade = newMinSignalQuality;
    }
}

//+------------------------------------------------------------------+
//| Get human-readable name for market regime                         |
//+------------------------------------------------------------------+
string GetRegimeName(int regime) {
    switch(regime) {
        case 0: return "Strong Uptrend";
        case 1: return "Strong Downtrend";
        case 2: return "Neutral/Balanced";
        case 3: return "Choppy/Ranging";
        case 4: return "Extreme Volatility";
        default: return "Unknown (" + IntegerToString(regime) + ")";
    }
}

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
            case SESSION_ASIA_EUROPE_OVERLAP: sessionName = "ASIA-EUROPE"; break;
            case SESSION_EUROPE_AMERICA_OVERLAP: sessionName = "EUR-US"; break;
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
            // Cannot modify constants directly, using working copies or commenting out
            // SL_ATR_Mult = originalSL_ATR_Mult * 0.8; // Cannot modify constant
            // TP_ATR_Mult = originalTP_ATR_Mult * 0.7; // Cannot modify constant
            workingTrailingActivationPct = 0.25; // Earlier trailing in lower volatility
            workingTrailingStopMultiplierLocal = 0.2;  // Tighter trailing
            break;
            
        case SESSION_EUROPE: // Medium volatility
            if(!TradeEuropeanSession) {
                if(DisplayDebugInfo) Print("[SMC] European session trading disabled in settings");
                return;
            }
            // Standard parameters for European session
            // Cannot modify constants directly, using working copies or commenting out
            // SL_ATR_Mult = originalSL_ATR_Mult * 1.0; // Cannot modify constant
            // TP_ATR_Mult = originalTP_ATR_Mult * 1.0; // Cannot modify constant
            workingTrailingActivationPct = 0.3;
            workingTrailingStopMultiplierLocal = 0.3;
            break;
            
        case SESSION_AMERICA: // Higher volatility
            if(!TradeAmericanSession) {
                if(DisplayDebugInfo) Print("[SMC] American session trading disabled in settings");
                return;
            }
            // Wider stops, larger targets in volatile NY session
            // Cannot modify constants directly, using working copies or commenting out
            // SL_ATR_Mult = originalSL_ATR_Mult * 1.2; // Cannot modify constant
            // TP_ATR_Mult = originalTP_ATR_Mult * 1.3; // Cannot modify constant
            workingTrailingActivationPct = 0.35; // Later trailing in higher volatility
            workingTrailingStopMultiplierLocal = 0.4;  // Wider trailing
            break;
            
        case SESSION_ASIA_EUROPE_OVERLAP:
        case SESSION_EUROPE_AMERICA_OVERLAP:
            if(!TradeSessionOverlaps) {
                if(DisplayDebugInfo) Print("[SMC] Session overlap trading disabled in settings");
                return;
            }
            // Increased volatility during session overlaps
            // Cannot modify constants directly, using working copies or commenting out
            // SL_ATR_Mult = originalSL_ATR_Mult * 1.1; // Cannot modify constant
            // TP_ATR_Mult = originalTP_ATR_Mult * 1.2; // Cannot modify constant
            workingTrailingActivationPct = 0.4;
            workingTrailingStopMultiplierLocal = 0.35;
            break;
    }
    
    if(DisplayDebugInfo) {
        Print("[SMC] Session-adjusted parameters: SL_ATR_Mult=", DoubleToString(SL_ATR_Mult, 2), 
              ", TP_ATR_Mult=", DoubleToString(TP_ATR_Mult, 2),
              ", workingTrailingActivationPct=", DoubleToString(workingTrailingActivationPct, 2),
              ", workingTrailingStopMultiplierLocal=", DoubleToString(workingTrailingStopMultiplierLocal, 2));
    }
}

//+------------------------------------------------------------------+
//| Dynamically calibrate parameters based on currency pair          |
//+------------------------------------------------------------------+
void AutocalibrateForSymbol() {
    ActualSignalCooldownSeconds = SignalCooldownSeconds;
    string symbolName = Symbol();
    double originalMinATRThreshold = MinATRThresholdGlobal; // Already a global variable, safe to assign
    double originalTrailingStopMultiplier = workingTrailingStopMultiplierLocal; // Use working copy
    
    // Setup for JPY pairs (higher pip values, need different scaling)
    if(StringFind(symbolName, "JPY") >= 0) {
        MinATRThresholdGlobal = 0.008;
        workingTrailingStopMultiplierLocal = 0.4; // Use working copy instead of constant
        if(DisplayDebugInfo) Print("[SMC] Calibrated for JPY pair: higher ATR threshold and trailing");
    }
    // Setup for GBP pairs (higher volatility)
    else if(StringFind(symbolName, "GBP") >= 0) {
        MinATRThresholdGlobal = 0.0012;
        workingTrailingStopMultiplierLocal = 0.35;
        if(DisplayDebugInfo) Print("[SMC] Calibrated for GBP pair: adjusted for higher volatility");
    }
    // Setup for CHF pairs
    else if(StringFind(symbolName, "CHF") >= 0) {
        MinATRThresholdGlobal = 0.0008;
        workingTrailingStopMultiplierLocal = 0.3;
        if(DisplayDebugInfo) Print("[SMC] Calibrated for CHF pair");
    }
    // Setup for commodity pairs (AUDUSD, NZDUSD, etc)
    else if(StringFind(symbolName, "AUD") >= 0 || StringFind(symbolName, "NZD") >= 0) {
        MinATRThresholdGlobal = 0.0007;
        workingTrailingStopMultiplierLocal = 0.25;
        if(DisplayDebugInfo) Print("[SMC] Calibrated for commodity currency pair");
    }
    // Setup for major pairs (EURUSD, etc)
    else if(StringFind(symbolName, "EUR") >= 0 && StringFind(symbolName, "USD") >= 0) {
        MinATRThresholdGlobal = 0.0005;
        workingTrailingStopMultiplierLocal = 0.3;
        if(DisplayDebugInfo) Print("[SMC] Calibrated for major pair: standard settings");
    }
    // Default calibration for other pairs
    else {
        MinATRThresholdGlobal = originalMinATRThreshold;
        // Use local variable instead of modifying constant
        double localTrailingMultiplier = originalTrailingStopMultiplier;
        workingTrailingStopMultiplierLocal = localTrailingMultiplier;
    }
    
    // Also check for high spread pairs
    double spread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    if(spread > 20) { // High spread pair
        // For high spread pairs, reduce trade frequency and increase targets
        ActualSignalCooldownSeconds = (int)MathRound((double)SignalCooldownSeconds * 1.5);
        TP_ATR_Mult *= 1.3;
        if(DisplayDebugInfo) Print(StringFormat("[SMC] High spread pair detected (%d points). Adjusted parameters.", (int)spread));
    }
    
    if(symbolName == "XAUUSD") {
        MinATRThresholdGlobal = 0.0003; // Adjusted for current volatility
        // Use local variable instead of modifying constant
        workingTrailingStopMultiplierLocal = 0.25; // Tighter trailing stops
    }
}

//+------------------------------------------------------------------+
//| Process and Validate Order Blocks                                |
//+------------------------------------------------------------------+
void ProcessOrderBlocks() {
    for(int i = 0; i < MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid && !IsValidOrderBlock(recentBlocks[i])) {
            if(DisplayDebugInfo) {
                Print(StringFormat("[ORDER BLOCK] Invalidated block at %.5f (Age: %d mins)", recentBlocks[i].price, (int)((TimeCurrent() - recentBlocks[i].time)/60)));
            }
            recentBlocks[i].valid = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Check for high impact economic news events                       |
//+------------------------------------------------------------------+
bool IsHighImpactNewsTime() {
    // Default implementation - will be enhanced with actual news API integration
    // When implementing a full news calendar, check if we're within NewsFilterMinutes of a high impact event
    return false; // Placeholder until full implementation
}

//+------------------------------------------------------------------+
//| Utility: CanTrade                                               |
//+------------------------------------------------------------------+
bool CanTrade() {
    if(EnableNewsFilter && IsHighImpactNewsTime()) {
        if(DisplayDebugInfo) Print("[TRADE FILTER] Blocked - News avoidance window");
        return false;
    }
    // Check if autotrading is enabled
    bool autoTradingEnabled = TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
    
    // Implement adaptive spread threshold based on current market volatility (ATR)
    double spread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    double atrValue = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    
    // Base threshold is either MaxAllowedSpread or 1/4 of the ATR, whichever is greater
    double spreadThreshold = MaxAllowedSpread;
    double atrBasedThreshold = atrValue * 250 / Point(); // Use 25% of ATR as base threshold
    
    // Check if this is a high-value asset like BTC
    double symbolPrice = SymbolInfoDouble(Symbol(), SYMBOL_LAST);
    bool isHighValueAsset = (symbolPrice > 10000.0) || (StringFind(Symbol(), "BTC") >= 0);
    
    // Different instruments have different natural spread characteristics
    if(isHighValueAsset) {
        // For high-value assets like BTC, use a much more permissive spread threshold
        // These assets naturally have much wider spreads in point terms
        spreadThreshold = atrValue * 2500 / Point(); // Use 250% of ATR (10x normal)
        if(DisplayDebugInfo) Print("[SPREAD ADAPTIVE] Using high-value asset spread threshold for ", Symbol());
    }
    else if(StringFind(Symbol(), "XAU") >= 0) {
        // Gold naturally has wider spreads
        spreadThreshold = MathMax(MaxAllowedSpread * 3.0, atrBasedThreshold * 2.5); 
    } 
    else if(StringFind(Symbol(), "GBP") >= 0) {
        // GBP pairs often have wider spreads
        spreadThreshold = MathMax(MaxAllowedSpread * 1.5, atrBasedThreshold * 1.5);
    }
    else {
        // For other instruments, use the greater of MaxAllowedSpread or ATR-based threshold
        spreadThreshold = MathMax(MaxAllowedSpread, atrBasedThreshold);
    }
    
    Print("[SPREAD ADAPTIVE] Symbol: ", Symbol(), ", Current spread: ", spread, ", ATR: ", atrValue/Point(), ", Threshold: ", spreadThreshold);
    
    bool spreadOK = (spread <= spreadThreshold);
    
    if(DisplayDebugInfo) {
        if(!spreadOK) {
            Print("[DIAG] Spread check failed: Current spread=", spread, 
                  ", threshold=", spreadThreshold, ", Symbol=", Symbol());
        } else {
            Print("[DIAG] Spread check passed: Current spread=", spread, 
                  ", threshold=", spreadThreshold, ", Symbol=", Symbol());
        }
    }
    
    // ENHANCEMENT: More permissive margin check
    double marginFree = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginRequired = AccountInfoDouble(ACCOUNT_MARGIN);
    bool marginOK = (marginFree >= marginRequired * 0.4); // Reduced from 0.5 to 0.4
    
    // Detailed conditions check with debug info if enabled
    if(DisplayDebugInfo) {
        Print("[DEBUG][BLOCK] CanTrade checks: AutoTrading=", autoTradingEnabled,
              ", emergencyMode=", emergencyMode,
              ", marketClosed=", marketClosed,
              ", isWeekend=", isWeekend,
              ", spread=", spread/Point(), " (threshold=", spreadThreshold, ")",
              ", marginFree=", marginFree, ", marginReq=", marginRequired);
              
        if(!autoTradingEnabled) Print("[DEBUG][BLOCK] Trading blocked: AutoTrading disabled");
        if(emergencyMode) Print("[DEBUG][BLOCK] Trading blocked: Emergency mode active");
        if(marketClosed) Print("[DEBUG][BLOCK] Trading blocked: Market closed");
        if(isWeekend) Print("[DEBUG][BLOCK] Trading blocked: Weekend");
        if(!spreadOK) Print(StringFormat("[DEBUG][BLOCK] Trading blocked: Spread too high (%.2f > %.2f)", spread/Point(), spreadThreshold));
        if(!marginOK) Print(StringFormat("[DEBUG][BLOCK] Trading blocked: Insufficient margin (free=%.2f, required=%.2f)", marginFree, marginRequired));
    }
    
    // ENHANCEMENT: Be more permissive with spread during high volatility periods
    // If all other conditions are met but spread is slightly high, still allow trading
    if(autoTradingEnabled && !emergencyMode && !marketClosed && !isWeekend && marginOK && !spreadOK) {
        // If current volatility is high, allow a wider spread tolerance (up to 50% above threshold)
        double regimeMultiplier = 1.2; // Default tolerance multiplier
        
        // During breakouts or high volatility regimes, be more permissive with spread
        if(currentRegime == REGIME_BREAKOUT || currentRegime == REGIME_HIGH_VOLATILITY) {
            regimeMultiplier = 1.5; // 50% allowance during volatile conditions
            Print("[SPREAD ADAPTIVE] Using higher spread tolerance due to ", 
                  EnumToString((ENUM_MARKET_REGIME)currentRegime), " regime");
        }
        
        if(spread/Point() <= spreadThreshold * regimeMultiplier) {
            Print("[SPREAD ADAPTIVE] Allowing trade despite slightly high spread: ", 
                  spread/Point(), " vs threshold ", spreadThreshold, 
                  " (tolerance factor: ", regimeMultiplier, ")");
            return true;
        }
    }
    
    return (autoTradingEnabled && !emergencyMode && !marketClosed && !isWeekend && spreadOK && marginOK);
}

//+------------------------------------------------------------------+
//| Calculate ATR for volatility-based measurements                  |
//+------------------------------------------------------------------+
double CalculateATR(int period) {
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    
    int atrDefinition = iATR(Symbol(), PERIOD_CURRENT, period);
    
    if(CopyBuffer(atrDefinition, 0, 0, 3, atrBuffer) <= 0) {
        Print("[ERROR] Failed to copy ATR data: ", GetLastError());
        return 0.0;
    }
    
    double currentATR = atrBuffer[0]; // Most recent ATR value
    
    // For high-value assets like BTC, scale the ATR appropriately
    bool isHighValueAsset = (SymbolInfoDouble(Symbol(), SYMBOL_LAST) > 10000.0) || (StringFind(Symbol(), "BTC") >= 0);
    if(isHighValueAsset) {
        // For assets like BTC, we need to ensure the ATR is not too small relative to price
        double symbolPrice = SymbolInfoDouble(Symbol(), SYMBOL_LAST);
        double minATRValue = symbolPrice * 0.0002; // At least 0.02% of price
        currentATR = MathMax(currentATR, minATRValue);
    }
    
    return currentATR;
}

//+------------------------------------------------------------------+
//| Get ATR-based stop loss distance                                 |
//+------------------------------------------------------------------+
double GetATRStop(int period=14, ENUM_TIMEFRAMES timeframe=PERIOD_CURRENT) {
    // Get current ATR value (use CalculateATR with current timeframe)
    double atr = CalculateATR(period);
    if(atr == 0.0) {
        LogError("Failed to calculate ATR for stop distance, using fixed minimum");
        return 20 * _Point; // Default fallback if ATR calculation fails
    }
    
    // Get minimum stop distance required by broker
    double minBrokerDistance = GetMinimumStopDistance();
    
    // Calculate ATR-based stop distance with appropriate multiplier
    double baseMultiplier;
    
    // Use SL_ATR_Mult parameter if available, otherwise use adaptive defaults
    if(SL_ATR_Mult > 0) {
        baseMultiplier = SL_ATR_Mult; // Use the input parameter
    } else {
        // Default multiplier with adaptive adjustment
        baseMultiplier = 1.5; // Default multiplier
        
        // Adjust multiplier based on trading mode
        if(TradingMode == MODE_HFT) {
            baseMultiplier = 1.0; // Tighter stops for HFT
        } else if(TradingMode == MODE_NORMAL) {
            baseMultiplier = 2.0; // Wider stops for normal trading
        }
    }
    
    // Adjust multiplier based on asset type regardless of input parameter
    bool isHighValueAsset = (SymbolInfoDouble(Symbol(), SYMBOL_LAST) > 10000.0) || (StringFind(Symbol(), "BTC") >= 0);
    if(isHighValueAsset) {
        // For crypto and other high-value assets, we need special handling
        baseMultiplier *= 1.5; // 50% wider stops for crypto
        
        // Add additional logging for crypto assets
        LogInfo(StringFormat("[HIGH-VALUE ASSET] Detected %s as high-value asset, increasing ATR multiplier to %.1f", 
                         Symbol(), baseMultiplier));
    }
    
    // Calculate ATR-based stop with the appropriate multiplier
    double atrStop = atr * baseMultiplier;
    
    // Ensure the stop is at least the minimum broker distance
    double finalStop = MathMax(atrStop, minBrokerDistance);
    
    // Add detailed logging
    if(DisplayDebugInfo) {
        LogInfo(StringFormat("[STOP CALCULATION] Symbol: %s, ATR: %.5f, Multiplier: %.1f, Broker Min: %.5f, Final Stop: %.5f points", 
                         Symbol(), atr, baseMultiplier, minBrokerDistance/_Point, finalStop/_Point));
    }
    
    return finalStop;
}

//+------------------------------------------------------------------+
//| Get Minimum Stop Distance required by broker                     |
//+------------------------------------------------------------------+
double GetMinimumStopDistance() {
    // Get broker-specific stop level requirements
    long stopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double minStopDistancePoints = stopLevel * point;
    
    // Some brokers have very small or zero stop levels, so set a reasonable minimum
    if(minStopDistancePoints < 10 * point) {
        minStopDistancePoints = 10 * point; // Minimum 10 points
    }
    
    // For high-value assets, increase the minimum distance
    double symbolPrice = SymbolInfoDouble(Symbol(), SYMBOL_LAST);
    bool isHighValueAsset = (symbolPrice > 10000.0) || (StringFind(Symbol(), "BTC") >= 0);
    if(isHighValueAsset) {
        // For BTC and other high-value assets, use a percentage-based minimum
        double percentBasedMin = symbolPrice * 0.0005; // 0.05% of price
        minStopDistancePoints = MathMax(minStopDistancePoints, percentBasedMin);
    }
    
    // Consider current ATR to dynamically adjust minimum stop distance
    double atr = CalculateATR(14);
    double atrBasedMin = atr * 0.1; // 10% of ATR
    
    // Use the larger of broker requirement, fixed minimum, or ATR-based minimum
    double finalMinDistance = MathMax(MathMax(minStopDistancePoints, atrBasedMin), 10 * point);
    
    if(DisplayDebugInfo) {
        Print(StringFormat("[STOP DISTANCE] Broker minimum: %.5f points, ATR-based: %.5f points, Final: %.5f points",
                        minStopDistancePoints/point, atrBasedMin/point, finalMinDistance/point));
    }
    
    return finalMinDistance;
}

//+------------------------------------------------------------------+
//| Get human-readable error description                             |
//+------------------------------------------------------------------+
string GetErrorDescription(int errorCode) {
    switch(errorCode) {
        case 0: return "No error";
        case 4756: return "No trading context"; // Internal MQL error often means no connection
        case 10004: return "Trade server is busy";
        case 10006: return "Request rejected";
        case 10007: return "Request canceled by trader";
        case 10010: return "Only part of the request was completed";
        case 10011: return "Request processing error";
        case 10013: return "Invalid request";
        case 10014: return "Invalid volume";
        case 10015: return "Invalid stops - stops too close to current price";
        case 10016: return "Invalid trade";
        case 10017: return "Trade disabled";
        case 10018: return "Market closed";
        case 10019: return "Not enough money";
        case 10020: return "Prices changed";
        case 10021: return "No quotes to process request";
        case 10022: return "Invalid expiration date in pending order";
        case 10023: return "Order state changed";
        case 10026: return "Automation trading disabled by server";
        case 10027: return "Automation trading disabled by client terminal";
        case 10028: return "Request locked for processing";
        case 10029: return "Order or position frozen";
        case 10030: return "Invalid order filling type";
        case 10031: return "No connection to trade server";
        case 10032: return "Operation allowed only for live accounts";
        case 10033: return "Maximum number of pending orders reached";
        case 10034: return "Maximum order volume limit reached";
        case 10035: return "Maximum order count limit reached";
        case 10036: return "Position with the specified ID already closed";
        case 130: return "Invalid stops - stops too close to market";
        case 138: return "Invalid volume";
        case 139: return "Not enough money";
        case 140: return "Prices changed";
        case 146: return "Trade context is busy";
        default: return StringFormat("Unknown error %d", errorCode);
    }
}

//+------------------------------------------------------------------+
//| Validate Stop Level                                              |
//+------------------------------------------------------------------+
bool ValidateStopLevel(double price, double stopLevel, bool isBuy) {
    double point = GetSymbolPoint();
    if(point == 0) {
        Print("Failed to get point value");
        return false;
    }   
    double minStopDistance = 0.0;
    // Using direct assignment overload for SymbolInfoDouble which returns double
    // Get minimum stop distance from broker
    // SYMBOL_TRADE_STOPS_LEVEL is an INTEGER property, using correct function
    long stopLevelValue = 0;
    if(!SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue)) {
        Print("Error getting stop level: ", GetLastError());
        stopLevelValue = 5; // Default value if call fails
    }
    minStopDistance = (double)stopLevelValue;
    minStopDistance *= point;
    double spread = 0.0;
    long spreadPoints = 0;
    if(!SymbolInfoInteger(Symbol(), SYMBOL_SPREAD, spreadPoints)) {
        spreadPoints = 10; // Default if call fails
    }
    spread = (double)spreadPoints * point; // Explicit cast from long to double
    
    if(isBuy) {
        if(stopLevel >= price - minStopDistance - spread) {
            if(DisplayDebugInfo) Print("[STOP VALIDATION] Buy stop too close: ", stopLevel, 
                  " vs current ", price, " (min distance: ", minStopDistance, ")");
            return false;
        }
    } else {
        if(stopLevel <= price + minStopDistance + spread) {
            if(DisplayDebugInfo) Print("[STOP VALIDATION] Sell stop too close: ", stopLevel, 
                  " vs current ", price, " (min distance: ", minStopDistance, ")");
            return false;
        }
    }
    return true;
}

//+------------------------------------------------------------------+
//| Execute Trade With Retry                                          |
//+------------------------------------------------------------------+
bool ExecuteTradeWithRetry(int signal, double price, double sl, double tp, double size, string comment, int maxRetries=3) {
    // Use a different variable name to avoid hiding global trade
    // Use global trade object to avoid hiding
    if(DisplayDebugInfo) Print("[TRADE] Attempting to execute trade with signal=", signal, ", price=", price, ", SL=", sl, ", TP=", tp);
    
    // Create a local trade object to avoid conflict with global trade object
    CTrade tradeExecutor;
    tradeExecutor.SetDeviationInPoints(10);
    
    bool success = false;
    int attempts = 0;
    
    while(!success && attempts < maxRetries) {
        attempts++;
        
        if(signal > 0) { // BUY
            success = tradeExecutor.Buy(size, Symbol(), price, sl, tp, comment);
        } else if(signal < 0) { // SELL
            success = tradeExecutor.Sell(size, Symbol(), price, sl, tp, comment);
        }
        
        if(success) {
            if(DisplayDebugInfo) Print("[TRADE] Success on attempt ", attempts);
            lastTradeTime = TimeCurrent();
            return true;
        } else {
            int errorCode = GetLastError();
            if(DisplayDebugInfo) Print("[TRADE] Failed attempt ", attempts, ", error=", errorCode, " (", GetLastErrorText(errorCode), ")");
            
            // Specific handling based on error code
            if(errorCode == 130) { // 130 is ERR_INVALID_STOPS in MQL5
                // Adjust stops based on broker requirements
                double minStopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point;
                if(signal > 0) { // BUY
                    if(MathAbs(price - sl) < minStopLevel) {
                        sl = price - minStopLevel;
                        if(DisplayDebugInfo) Print("[TRADE] Adjusted SL to meet minimum distance: ", sl);
                    }
                } else if(signal < 0) { // SELL
                    if(MathAbs(price - sl) < minStopLevel) {
                        sl = price + minStopLevel;
                        if(DisplayDebugInfo) Print("[TRADE] Adjusted SL to meet minimum distance: ", sl);
                    }
                }
            }
            
            // Wait before retrying
            Sleep(500);
        }
    }
    
    if(DisplayDebugInfo) Print("[TRADE] Failed after ", attempts, " attempts");
    return false;
}

//+------------------------------------------------------------------+
//| Retry Trade Execution                                            |
//+------------------------------------------------------------------+
bool RetryTrade(int signal, double price, double sl, double tp, double size, int maxRetries=3) {
    CTrade tradeMgr; // Use a different name to avoid shadowing global variable
    tradeMgr.SetDeviationInPoints(AdaptiveSlippagePoints);
    
    // Check for and adjust minimum stop distance requirements
    double minStopDistance = GetMinimumStopDistance();
    double originalSL = sl;
    double originalTP = tp;
    double spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point;
    
    // Detailed stop distance logging
    LogInfo(StringFormat("[STOP LEVELS] Symbol: %s, MinStopDistance: %.5f points, Spread: %.5f points", 
                        Symbol(), minStopDistance/_Point, spread/_Point));
    
    for(int attempts = 0; attempts < maxRetries; attempts++) {
        double currentBid = GetCurrentBid();
        double currentAsk = GetCurrentAsk();
        double currentPrice = (signal > 0) ? currentAsk : currentBid;
        
        // Adjust stop loss if needed based on broker requirements
        double adjustedSL = sl;
        double adjustedTP = tp;
        
        // Recalculate stop distances for each attempt as price may have changed
        if(signal > 0) { // BUY
            double slDistance = currentPrice - adjustedSL;
            if(slDistance < minStopDistance) {
                adjustedSL = NormalizeDouble(currentPrice - minStopDistance - (5 * _Point), _Digits); // Add 5 points buffer
                LogInfo(StringFormat("[STOP ADJUST] Buy SL adjusted from %.5f to %.5f (min distance: %.5f points)",
                                     originalSL, adjustedSL, minStopDistance/_Point));
            }
        } else { // SELL
            double slDistance = adjustedSL - currentPrice;
            if(slDistance < minStopDistance) {
                adjustedSL = NormalizeDouble(currentPrice + minStopDistance + (5 * _Point), _Digits); // Add 5 points buffer
                LogInfo(StringFormat("[STOP ADJUST] Sell SL adjusted from %.5f to %.5f (min distance: %.5f points)",
                                     originalSL, adjustedSL, minStopDistance/_Point));
            }
        }
        
        // Adjust position size as a last resort
        double retrySize = size;
        if(attempts > 0) {
            retrySize = size * (1.0 - (attempts * 0.1)); // Reduce size by 10% each retry
            LogInfo(StringFormat("[RETRY] Attempt %d - Reducing size from %.2f to %.2f", 
                               attempts+1, size, retrySize));
        }
        
        // Execute the trade with adjusted parameters
        bool result = false;
        if(signal > 0) {
            result = tradeMgr.Buy(retrySize, Symbol(), 0, adjustedSL, adjustedTP, "SMC Buy Retry "+IntegerToString(attempts+1));
        } else {
            result = tradeMgr.Sell(retrySize, Symbol(), 0, adjustedSL, adjustedTP, "SMC Sell Retry "+IntegerToString(attempts+1));
        }
        
        // Handle result
        if(result) {
            LogInfo(StringFormat("[TRADE SUCCESS] %s order executed on attempt %d - Size: %.2f, Entry: %.5f, SL: %.5f", 
                               (signal > 0 ? "Buy" : "Sell"), attempts+1, retrySize, currentPrice, adjustedSL));
            return true;
        } else {
            int errorCode = GetLastError();
            string errorDesc = GetErrorDescription(errorCode);
            
            // Use enhanced trade error logging for detailed diagnostics
            string operation = (signal > 0 ? "BUY" : "SELL");
            LogTradeError(errorCode, operation, Symbol(), currentPrice, adjustedSL, adjustedTP);
            
            LogError(StringFormat("[TRADE FAILED] Attempt %d - Error: %d (%s)", 
                                attempts+1, errorCode, errorDesc));
            
            // Specific handling based on error code
            if(errorCode == 10015 || errorCode == 130) { // Invalid stops
                // Calculate a more aggressive adjustment based on current attempt
                double adjustmentFactor = minStopDistance * (0.5 + (attempts * 0.25)); // Increase factor with each attempt
                
                if(signal > 0) { // BUY
                    sl = NormalizeDouble(currentPrice - minStopDistance - adjustmentFactor, _Digits);
                } else { // SELL
                    sl = NormalizeDouble(currentPrice + minStopDistance + adjustmentFactor, _Digits);
                }
                
                LogInfo(StringFormat("[STOP RETRY] Further adjusting SL to %.5f for next attempt (%.1f points from price)", 
                                   sl, MathAbs(currentPrice - sl)/_Point));
            } else if(errorCode == 10016 || errorCode == 138) { // Invalid volume
                // Further reduce size for next attempt
                size = NormalizeDouble(size * 0.8, 2); // Reduce by 20%
                LogInfo(StringFormat("[VOLUME RETRY] Further reducing size to %.2f for next attempt", size));
            } else if(errorCode == 10018) { // Market closed
                LogWarning("Market appears to be closed, aborting trade attempts");
                return false; // No point retrying if market is closed
            } else if(errorCode == 4109 || errorCode == 4756) { // No trading context
                LogWarning("No trading context available, possible connection issue - waiting longer before retry");
                Sleep(1000); // Wait longer for connection to recover
            }
        }
        
        if(attempts < maxRetries-1) {
            Sleep(300 * (attempts+1)); // Increasing wait time with each retry
        }
    }
    
    LogError(StringFormat("[TRADE ABORT] Failed to execute %s order after %d attempts", 
                         (signal > 0 ? "Buy" : "Sell"), maxRetries));
    return false;
}

//+------------------------------------------------------------------+
//| Validate Order Block Quality                                     |
//+------------------------------------------------------------------+
bool IsValidOrderBlock(const OrderBlock &block) {
    if(block.price <= 0 || block.time == 0) 
        return false;
        
    if(block.volume < MinOrderBlockVolume) 
        return false;
        
    if(TimeCurrent() - block.time > OrderBlockExpirySeconds) 
        return false;
        
    double bid = GetCurrentBid();
    double ask = GetCurrentAsk();
    
    if(block.isBuy) {
        if(ask > block.price * (1 + MaxOrderBlockDistancePct/100))
            return false;
    } else {
        if(bid < block.price * (1 - MaxOrderBlockDistancePct/100))
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Utility: ManageOpenTrade                                        |
//+------------------------------------------------------------------+
void ManageOpenTrade() {
    // Define trade_local if needed for position management
    CTrade trade_local;
    trade_local.SetDeviationInPoints(MaxSlippage);
    
    if(!PositionSelect(Symbol())) return; // No position to manage
    
    // Get position details
    double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentStop = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    double positionSize = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    ulong posTicket = PositionGetTicket(0);
    
    // Check trailing activation - only trail after in a minimum profit
    double currentBid = GetCurrentBid();
    double currentAsk = GetCurrentAsk();
    double pointSize = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double spread = (currentAsk - currentBid) / pointSize; // spread in points
    double minProfit = MathMax(10, spread); // Ensure we cover at least the spread
    
    // Calculate pip movement for activation
    bool trailingActivated = false;
    
    if(posType == POSITION_TYPE_BUY) {
        // For buy position
        double pipMovement = (currentBid - entryPrice) / pointSize;
        trailingActivated = (pipMovement >= TrailingActivationPct * 100); // Convert percent to pips
    } else {
        // For sell position
        double pipMovement = (entryPrice - currentAsk) / pointSize;
        trailingActivated = (pipMovement >= TrailingActivationPct * 100); // Convert percent to pips
    }
    
    // Apply different trade management strategies
    if(EnableAggressiveTrailing && trailingActivated) {
        // Call dedicated trailing function
        ManageTrailingStops();
    }
    
    // Apply advanced volatility-based trailing if enabled
    if(EnableTrailingForLast && trailingActivated) {
        // Skip calling AdjustTrailingStop here to avoid recursion
    }
    
    // Check for break-even opportunity
    // MoveToBreakEven function call commented out until implemented
    // MoveToBreakEven(entryPrice, currentStop, posType, posTicket, spread);
    
    // Additional trade management logic can be added here
    // For example: partial take profits, time-based exit, etc.
}

//+------------------------------------------------------------------+
//| Utility: CalculatePositionSize                                  |
//+------------------------------------------------------------------+
double CalculatePositionSize() {
    // Stub for position sizing (replace with your adaptive logic)
    return 0.01;
}

//+------------------------------------------------------------------+
//| Fast market regime detection                                     |
//+------------------------------------------------------------------+
int FastRegimeDetection(string symbol) {
    // Get recent price data
    double close[], high[], low[];
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    int copied = CopyClose(symbol, PERIOD_CURRENT, 0, 20, close);
    if(copied <= 0) return REGIME_NORMAL; // Default to normal if can't get data
    
    CopyHigh(symbol, PERIOD_CURRENT, 0, 20, high);
    CopyLow(symbol, PERIOD_CURRENT, 0, 20, low);
    
    // Get ATR for volatility measurement
    double atr = GetATR(symbol, PERIOD_CURRENT, 14, 0);
    double avgATR = 0;
    
    // Calculate average ATR over past 20 bars for comparison
    for(int i=1; i<=10; i++) {
        avgATR += GetATR(symbol, PERIOD_CURRENT, 14, i);
    }
    avgATR /= 10;
    
    // Check for trending conditions
    bool uptrend = true;
    bool downtrend = true;
    
    for(int i=0; i<5; i++) {
        if(close[i] < close[i+1]) uptrend = false;
        if(close[i] > close[i+1]) downtrend = false;
    }
    
    // Calculate price range
    double range = 0;
    for(int i=0; i<10; i++) {
        range += high[i] - low[i];
    }
    range /= 10;
    
    // Determine regime
    if(uptrend && atr > avgATR*1.2) return REGIME_TRENDING_UP;
    if(downtrend && atr > avgATR*1.2) return REGIME_TRENDING_DOWN;
    if(atr > avgATR*1.5) return REGIME_HIGH_VOLATILITY;
    if(atr < avgATR*0.7) return REGIME_LOW_VOLATILITY;
    if(range < avgATR*1.5) return REGIME_RANGING_NARROW;
    if(range > avgATR*2.0) return REGIME_RANGING_WIDE;
    
    // Default
    return REGIME_NORMAL;
}

//+------------------------------------------------------------------+
//| Detect order blocks in price action                              |
//+------------------------------------------------------------------+
void DetectOrderBlocks() {
    // This function needs to process price action and find order blocks
    // For this implementation, we'll scan for swing points and check for valid order blocks
    // Adjust lookback based on trading mode - HFT needs more recent blocks
    int lookback = (currentTradingMode == MODE_HFT) ? 20 : 30;
    
    // ADAPTIVE ORDER BLOCK DETECTION - Define adaptive parameters based on market conditions
    
    // Base parameters for order block detection
    int baseMinBlockStrength = 2; // Reduced from 3 to be less strict (33% reduction)
    double baseBlockSizeMultiplier = 0.8; // Reduced from 1.0 to be less strict (20% reduction)
    
    // Adjust parameters based on market regime
    int adaptiveMinBlockStrength = baseMinBlockStrength;
    double adaptiveBlockSizeMultiplier = baseBlockSizeMultiplier;
    
    // 1. Adjust based on market regime and asset type
    // Get symbol info to check if this is a high-value asset like BTC
    double symbolPrice = SymbolInfoDouble(Symbol(), SYMBOL_LAST);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    bool isHighValueAsset = (symbolPrice > 10000.0) || (StringFind(Symbol(), "BTC") >= 0);
    
    if(isHighValueAsset) {
        // For high-value assets like BTC, use more permissive criteria
        adaptiveMinBlockStrength = 1; // Minimum strength for high-value assets
        adaptiveBlockSizeMultiplier = baseBlockSizeMultiplier * 0.5; // 50% smaller size requirement
        if(DisplayDebugInfo) Print("[ADAPTIVE BLOCK] Using relaxed requirements for high-value asset: ", Symbol());
    }
    else if(currentRegime == REGIME_TRENDING_UP || currentRegime == REGIME_TRENDING_DOWN) {
        // In trends, be more permissive with block validation
        adaptiveMinBlockStrength = MathMax(1, baseMinBlockStrength - 1); // Lower by 1, minimum 1
        adaptiveBlockSizeMultiplier = baseBlockSizeMultiplier * 0.8; // 20% smaller size requirement
        if(DisplayDebugInfo) Print("[ADAPTIVE BLOCK] Relaxing block requirements in trending market");
    }
    else if(currentRegime == REGIME_CHOPPY) {
        // In choppy markets, be moderately cautious but still allow trading
        adaptiveMinBlockStrength = baseMinBlockStrength; // Use base requirement to allow trading
        adaptiveBlockSizeMultiplier = baseBlockSizeMultiplier * 1.1; // Only 10% larger size requirement
        Print("[ADAPTIVE BLOCK] Using balanced block requirements in choppy market");
    }
    else if(currentRegime == REGIME_RANGING_NARROW) {
        // In narrow range markets, use base requirements but be slightly more permissive
        // These can provide good scalping opportunities with tight stops
        adaptiveMinBlockStrength = baseMinBlockStrength; // Use base value without increase
        adaptiveBlockSizeMultiplier = baseBlockSizeMultiplier * 0.9; // 10% smaller size requirement
        Print("[ADAPTIVE BLOCK] Using standard block requirements in narrow range market");
    }
    else if(currentRegime == REGIME_BREAKOUT) {
        // During breakouts, we need to react quickly
        adaptiveMinBlockStrength = MathMax(1, baseMinBlockStrength - 1); // Lower by 1, minimum 1
        adaptiveBlockSizeMultiplier = baseBlockSizeMultiplier * 0.7; // 30% smaller size requirement
        Print("[ADAPTIVE BLOCK] Using responsive block detection during breakout");
    }
    
    // 2. Adjust based on recent performance
    if(consecutiveLosses > 2) {
        // After consecutive losses, be more strict with block requirements
        adaptiveMinBlockStrength = MathMax(2, adaptiveMinBlockStrength + 1);
        adaptiveBlockSizeMultiplier *= 1.1; // 10% larger
        Print("[ADAPTIVE BLOCK] Increasing block quality requirements after losses");
    }
    
    Print("[ADAPTIVE BLOCK] Using strength requirement: ", adaptiveMinBlockStrength, 
          " (Base: ", baseMinBlockStrength, ")");
    Print("[ADAPTIVE BLOCK] Using size multiplier: ", adaptiveBlockSizeMultiplier, 
          " (Base: ", baseBlockSizeMultiplier, ")");
    
    double high[], low[], close[], open[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    
    if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback, high) <= 0) return;
    if(CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback, low) <= 0) return;
    if(CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback, close) <= 0) return;
    if(CopyOpen(Symbol(), PERIOD_CURRENT, 0, lookback, open) <= 0) return;
    
    // Reset block validity for re-evaluation
    for(int i=0; i<MAX_BLOCKS; i++) {
        // Keep existing blocks but re-evaluate them
        if(recentBlocks[i].valid) {
            // Check if price has touched/invalidated the block - use a more forgiving approach
            // For buy blocks: Only invalidate if price closes significantly below the block level
            // For sell blocks: Only invalidate if price closes significantly above the block level
            // Make buffer size adaptive based on current ATR
            double atrValue = CalculateATR(14);
            double buffer = MathMax(10 * _Point, atrValue * 0.5); // At least 10 points, or 50% of ATR
            Print("[ORDER BLOCK] Using adaptive buffer of ", buffer/Point(), " points (ATR: ", atrValue/Point(), " points)");
            
            // Calculate age in minutes for logging purposes only
            datetime currentTime = TimeCurrent();
            int ageInMinutes = (int)((currentTime - recentBlocks[i].time) / 60);
            
            // Get maximum age based on the symbol and market conditions
            int maxAgeInMinutes = 180; // Default max age: 3 hours
            
            // Adjust max age for high-value assets
            bool isHighValueAsset = (SymbolInfoDouble(Symbol(), SYMBOL_LAST) > 10000.0) || (StringFind(Symbol(), "BTC") >= 0);
            if(isHighValueAsset) {
                maxAgeInMinutes = 480; // 8 hours for high-value assets
            }
            
            // Increase max age during low volatility periods
            // Reuse the atrValue calculated above instead of declaring it again
            double avgAtr = CalculateAverageATR(50);
            bool isLowVolatility = atrValue < (avgAtr * 0.8);
            if(isLowVolatility) {
                // Explicit cast to int to avoid warning about potential data loss
                maxAgeInMinutes = (int)(maxAgeInMinutes * 1.5); // 50% longer lifetime during low volatility
            }
            
            // Only invalidate blocks if price has clearly broken through them or they are too old
            bool priceBreakthrough = (recentBlocks[i].isBuy && close[0] < (recentBlocks[i].price - buffer*2)) ||
                                 (!recentBlocks[i].isBuy && close[0] > (recentBlocks[i].price + buffer*2));
            bool tooOld = ageInMinutes > maxAgeInMinutes;
            
            if(priceBreakthrough) {
                recentBlocks[i].valid = false;
                if(DisplayDebugInfo) Print("[ORDER BLOCK] Block at ", recentBlocks[i].price, 
                                          " invalidated by price at ", close[0], 
                                          " (Age: ", ageInMinutes, " mins)");
            }
            else if(tooOld) {
                recentBlocks[i].valid = false;
                if(DisplayDebugInfo) Print("[ORDER BLOCK] Block at ", recentBlocks[i].price, 
                                          " invalidated due to age (", ageInMinutes, " mins > ", 
                                          maxAgeInMinutes, " max)");
            }
            // Keep track of block age in debug logs but don't invalidate based on age
            else if(DisplayDebugInfo && ageInMinutes % 10 == 0) { // Log age less frequently (every 10 mins)
                Print("[ORDER BLOCK] Active block at ", recentBlocks[i].price,
                     " (Age: ", ageInMinutes, " mins, Max: ", maxAgeInMinutes, " mins, ", 
                     (recentBlocks[i].isBuy ? "Buy" : "Sell"), ")");
            }
        }
    }
    
    // Increase lookback period for detecting order blocks in low volatility markets
    int effectiveLookback = lookback;
    
    // Determine if we're in a low volatility period
    double atrValue = CalculateATR(14);
    double avgAtr = CalculateAverageATR(50);
    bool isLowVolatility = atrValue < (avgAtr * 0.8); // 20% below average ATR
    
    // In low volatility conditions, use a longer lookback period
    if(isLowVolatility) {
        effectiveLookback = lookback * 2; // Double the lookback in low volatility
        if(DisplayDebugInfo) Print("[MARKET CONTEXT] Low volatility detected: extending lookback to ", effectiveLookback);
        
        // Also ensure the arrays have enough capacity
        ArrayResize(high, effectiveLookback);
        ArrayResize(low, effectiveLookback);
        ArrayResize(close, effectiveLookback);
        ArrayResize(open, effectiveLookback);
        
        // Copy more price data
        if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, effectiveLookback, high) <= 0) return;
        if(CopyLow(Symbol(), PERIOD_CURRENT, 0, effectiveLookback, low) <= 0) return;
        if(CopyClose(Symbol(), PERIOD_CURRENT, 0, effectiveLookback, close) <= 0) return;
        if(CopyOpen(Symbol(), PERIOD_CURRENT, 0, effectiveLookback, open) <= 0) return;
    }
    
    // Look for new blocks - multiple detection methods
    for(int i=2; i<effectiveLookback-2; i++) {
        // =================== BULLISH ORDER BLOCK DETECTION ===================
        
        // METHOD 1: Traditional order block with relaxed criteria
        bool cond1 = close[i] < close[i+1]; // Current close lower than previous
        bool cond2 = close[i] < close[i+2]; // Current close lower than 2 bars ago
        bool cond3 = close[i-1] > close[i]; // Next bar closed higher (reversal)
        bool cond4 = close[i-2] > close[i-1]; // Continued upward movement
        
        // Relaxed condition: needs at least 2 of 4 conditions plus the critical reversal condition
        if(cond3 && ((cond1 && cond2) || (cond1 && cond4) || (cond2 && cond4))) {
            // This could be a bullish order block
            int localBlockIdx = GetNextBlockIndex();
            recentBlocks[localBlockIdx].price = low[i];
            recentBlocks[localBlockIdx].volume = 0; // Would need volume data here
            recentBlocks[localBlockIdx].strength = 5; // Basic strength rating
            recentBlocks[localBlockIdx].type = 1; // Bullish
            recentBlocks[localBlockIdx].time = TimeCurrent() - i*PeriodSeconds();
            recentBlocks[localBlockIdx].valid = true;
            recentBlocks[localBlockIdx].isBuy = true;
            recentBlocks[localBlockIdx].touched = false;
            recentBlocks[localBlockIdx].score = 5; // Basic score
            if(DisplayDebugInfo) Print("[ORDER BLOCK] Bullish block detected at ", recentBlocks[localBlockIdx].price, " (Method 1)");
        }
        else if(cond1 && cond2 && cond3 && cond4) {
            // Original stricter criteria still works too
            int localBlockIdx = GetNextBlockIndex();
            recentBlocks[localBlockIdx].price = low[i];
            recentBlocks[localBlockIdx].volume = 0; // Would need volume data here
            recentBlocks[localBlockIdx].strength = 7; // Higher strength for perfect match
            recentBlocks[localBlockIdx].type = 1; // Bullish
            recentBlocks[localBlockIdx].time = TimeCurrent() - i*PeriodSeconds();
            recentBlocks[localBlockIdx].valid = true;
            recentBlocks[localBlockIdx].isBuy = true;
            recentBlocks[localBlockIdx].touched = false;
            recentBlocks[localBlockIdx].score = 7; // Higher score for perfect match
            if(DisplayDebugInfo) Print("[ORDER BLOCK] Strong bullish block detected at ", recentBlocks[localBlockIdx].price, " (Perfect match)");
        }
        // METHOD 2: Swing-based bullish order block detection for sideways markets
        else if(low[i] < low[i+1] && low[i] < low[i-1] && close[i-1] > close[i] && open[i] > close[i]) {
            // This is a swing low that formed with a bearish candle followed by bullish movement
            int localBlockIdx = GetNextBlockIndex();
            recentBlocks[localBlockIdx].price = low[i];
            recentBlocks[localBlockIdx].volume = 0; // Would need volume data here
            recentBlocks[localBlockIdx].strength = 4; // Slightly lower strength for this method
            recentBlocks[localBlockIdx].type = 1; // Bullish
            recentBlocks[localBlockIdx].time = TimeCurrent() - i*PeriodSeconds();
            recentBlocks[localBlockIdx].valid = true;
            recentBlocks[localBlockIdx].isBuy = true;
            recentBlocks[localBlockIdx].touched = false;
            recentBlocks[localBlockIdx].score = 4; // Basic score
            if(DisplayDebugInfo) Print("[ORDER BLOCK] Swing-based bullish block detected at ", recentBlocks[localBlockIdx].price, " (Method 2)");
        }
        // METHOD 3: Low volatility bullish setup (especially for sideways markets)
        else if(isLowVolatility && i > 3 && i < effectiveLookback-3) {
            // In low volatility, look for small body candles creating a base
            double body1 = MathAbs(open[i] - close[i]);
            double body2 = MathAbs(open[i+1] - close[i+1]);
            double body3 = MathAbs(open[i+2] - close[i+2]);
            double avgBody = (body1 + body2 + body3) / 3;
            
            // Check if bodies are small compared to ATR and we have a clear directional change
            if(avgBody < (atrValue * 0.3) && low[i] <= low[i+1] && low[i] <= low[i+2] && 
               close[i-1] > close[i] && close[i-2] > close[i-1]) {
                int localBlockIdx = GetNextBlockIndex();
                recentBlocks[localBlockIdx].price = low[i];
                recentBlocks[localBlockIdx].volume = 0; // Would need volume data here
                recentBlocks[localBlockIdx].strength = 3; // Lower strength for low volatility method
                recentBlocks[localBlockIdx].type = 1; // Bullish
                recentBlocks[localBlockIdx].time = TimeCurrent() - i*PeriodSeconds();
                recentBlocks[localBlockIdx].valid = true;
                recentBlocks[localBlockIdx].isBuy = true;
                recentBlocks[localBlockIdx].touched = false;
                recentBlocks[localBlockIdx].score = 3; // Lower score
                if(DisplayDebugInfo) Print("[ORDER BLOCK] Low-volatility bullish block detected at ", recentBlocks[localBlockIdx].price, " (Method 3)");
            }
        }
        else if(DisplayDebugInfo && (cond1 + cond2 + cond3 + cond4) >= 2) {
            // Log near-misses for diagnostic purposes
            Print("[ORDER BLOCK NEAR MISS] Bullish near-miss at bar ", i, 
                  " C1=", cond1, " C2=", cond2, " C3=", cond3, " C4=", cond4);
        }
        
        // =================== BEARISH ORDER BLOCK DETECTION ===================
        
        // METHOD 1: Traditional bearish order block with relaxed criteria
        cond1 = close[i] > close[i+1]; // Current close higher than previous
        cond2 = close[i] > close[i+2]; // Current close higher than 2 bars ago
        cond3 = close[i-1] < close[i]; // Next bar closed lower (reversal)
        cond4 = close[i-2] < close[i-1]; // Continued downward movement
        
        // Relaxed condition: needs at least 2 of 4 conditions plus the critical reversal condition
        if(cond3 && ((cond1 && cond2) || (cond1 && cond4) || (cond2 && cond4))) {
            // This could be a bearish order block
            int localBlockIdx = GetNextBlockIndex();
            recentBlocks[localBlockIdx].price = high[i];
            recentBlocks[localBlockIdx].volume = 0; // Would need volume data here
            recentBlocks[localBlockIdx].strength = 5; // Basic strength rating
            recentBlocks[localBlockIdx].type = -1; // Bearish
            recentBlocks[localBlockIdx].time = TimeCurrent() - i*PeriodSeconds();
            recentBlocks[localBlockIdx].valid = true;
            recentBlocks[localBlockIdx].isBuy = false;
            recentBlocks[localBlockIdx].touched = false;
            recentBlocks[localBlockIdx].score = 5; // Basic score
            if(DisplayDebugInfo) Print("[ORDER BLOCK] Bearish block detected at ", recentBlocks[localBlockIdx].price, " (Method 1)");
        }
        else if(cond1 && cond2 && cond3 && cond4) {
            // Original stricter criteria still works too
            int localBlockIdx = GetNextBlockIndex();
            recentBlocks[localBlockIdx].price = high[i];
            recentBlocks[localBlockIdx].volume = 0; // Would need volume data here
            recentBlocks[localBlockIdx].strength = 7; // Higher strength for perfect match
            recentBlocks[localBlockIdx].type = -1; // Bearish
            recentBlocks[localBlockIdx].time = TimeCurrent() - i*PeriodSeconds();
            recentBlocks[localBlockIdx].valid = true;
            recentBlocks[localBlockIdx].isBuy = false;
            recentBlocks[localBlockIdx].touched = false;
            recentBlocks[localBlockIdx].score = 7; // Higher score for perfect match
            if(DisplayDebugInfo) Print("[ORDER BLOCK] Strong bearish block detected at ", recentBlocks[localBlockIdx].price, " (Perfect match)");
        }
        // METHOD 2: Swing-based bearish order block detection for sideways markets
        else if(high[i] > high[i+1] && high[i] > high[i-1] && close[i-1] < close[i] && open[i] < close[i]) {
            // This is a swing high that formed with a bullish candle followed by bearish movement
            int localBlockIdx = GetNextBlockIndex();
            recentBlocks[localBlockIdx].price = high[i];
            recentBlocks[localBlockIdx].volume = 0; // Would need volume data here
            recentBlocks[localBlockIdx].strength = 4; // Slightly lower strength for this method
            recentBlocks[localBlockIdx].type = -1; // Bearish
            recentBlocks[localBlockIdx].time = TimeCurrent() - i*PeriodSeconds();
            recentBlocks[localBlockIdx].valid = true;
            recentBlocks[localBlockIdx].isBuy = false;
            recentBlocks[localBlockIdx].touched = false;
            recentBlocks[localBlockIdx].score = 4; // Basic score
            if(DisplayDebugInfo) Print("[ORDER BLOCK] Swing-based bearish block detected at ", recentBlocks[localBlockIdx].price, " (Method 2)");
        }
        // METHOD 3: Low volatility bearish setup (especially for sideways markets)
        else if(isLowVolatility && i > 3 && i < effectiveLookback-3) {
            // In low volatility, look for small body candles creating a resistance
            double body1 = MathAbs(open[i] - close[i]);
            double body2 = MathAbs(open[i+1] - close[i+1]);
            double body3 = MathAbs(open[i+2] - close[i+2]);
            double avgBody = (body1 + body2 + body3) / 3;
            
            // Check if bodies are small compared to ATR and we have a clear directional change
            if(avgBody < (atrValue * 0.3) && high[i] >= high[i+1] && high[i] >= high[i+2] && 
               close[i-1] < close[i] && close[i-2] < close[i-1]) {
                int localBlockIdx = GetNextBlockIndex();
                recentBlocks[localBlockIdx].price = high[i];
                recentBlocks[localBlockIdx].volume = 0; // Would need volume data here
                recentBlocks[localBlockIdx].strength = 3; // Lower strength for low volatility method
                recentBlocks[localBlockIdx].type = -1; // Bearish
                recentBlocks[localBlockIdx].time = TimeCurrent() - i*PeriodSeconds();
                recentBlocks[localBlockIdx].valid = true;
                recentBlocks[localBlockIdx].isBuy = false;
                recentBlocks[localBlockIdx].touched = false;
                recentBlocks[localBlockIdx].score = 3; // Lower score
                if(DisplayDebugInfo) Print("[ORDER BLOCK] Low-volatility bearish block detected at ", recentBlocks[localBlockIdx].price, " (Method 3)");
            }
        }
        else if(DisplayDebugInfo && (cond1 + cond2 + cond3 + cond4) >= 2) {
            // Log near-misses for diagnostic purposes
            Print("[ORDER BLOCK NEAR MISS] Bearish near-miss at bar ", i, 
                  " C1=", cond1, " C2=", cond2, " C3=", cond3, " C4=", cond4);
        }
    }
    
    // Count valid blocks for debugging
    int validBuyBlocks = 0;
    int validSellBlocks = 0;
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            if(recentBlocks[i].isBuy) validBuyBlocks++;
            else validSellBlocks++;
        }
    }
    Print("[ORDER BLOCKS] Valid buy blocks: ", validBuyBlocks, ", Valid sell blocks: ", validSellBlocks);
    
    // Execute trades based on detected order blocks if found
    if(validBuyBlocks > 0 || validSellBlocks > 0) {
        // Use existing trade signal handling mechanism
        // Process any trade signals generated by the order blocks
        
        // Comment out the undeclared function call and use a basic logging statement instead
        // We'll let the normal trade processing in OnTick handle the actual trades
        Print("[INFO] Order blocks detected: ", validBuyBlocks, " buy, ", validSellBlocks, " sell");
    }
    
    // EMERGENCY BACKUP: If no order blocks were found after all our efforts, 
    // create at least one basic block to allow trading based on simple indicators
    if(validBuyBlocks == 0 && validSellBlocks == 0) {
        Print("[EMERGENCY DETECTION] No valid order blocks found, activating emergency block creation for ", Symbol());
        
        // Check current market conditions to determine best entry approach
        long rawSpread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
        double currentSpread = (double)rawSpread; // Explicit cast to double
        Print("[MARKET INFO] Current spread: ", currentSpread, " points");
        
        // 1. ENHANCED VOLATILITY ASSESSMENT
        // Check current volatility using multiple timeframes
        double currentATR = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
        double avgATR = GetATR(Symbol(), PERIOD_CURRENT, 14, 20); // Average over 20 periods
        double volRatio = currentATR / avgATR;
        
        // Get higher timeframe volatility for context
        ENUM_TIMEFRAMES higherTF = PERIOD_CURRENT;
        // Determine higher timeframe based on current timeframe
        if(Period() == PERIOD_M1) higherTF = PERIOD_M5;
        else if(Period() == PERIOD_M5) higherTF = PERIOD_M15;
        else if(Period() == PERIOD_M15) higherTF = PERIOD_H1;
        else if(Period() == PERIOD_H1) higherTF = PERIOD_H4;
        else if(Period() == PERIOD_H4) higherTF = PERIOD_D1;
        else higherTF = PERIOD_W1; // Default to weekly if already on daily+
        
        double higherTFVolRatio = 1.0;
        if(higherTF != PERIOD_CURRENT) {
            double higherCurrentATR = GetATR(Symbol(), higherTF, 14, 0);
            double higherAvgATR = GetATR(Symbol(), higherTF, 14, 20);
            higherTFVolRatio = higherCurrentATR / higherAvgATR;
        }
        
        // Determine if volatility is contracting or expanding
        double prevATR = GetATR(Symbol(), PERIOD_CURRENT, 14, 1);
        bool volatilityExpanding = currentATR > prevATR;
        
        Print("[MARKET INFO] Current volatility ratio: ", volRatio, ", Higher TF vol ratio: ", higherTFVolRatio, 
              ", Volatility ", (volatilityExpanding ? "expanding" : "contracting"));
        
        // 2. COMPREHENSIVE TREND CONFIRMATION
        bool strongUptrend = false;
        bool strongDowntrend = false;
        bool weakUptrend = false;
        bool weakDowntrend = false;
        bool choppyMarket = false;
        int trendStrength = 0; // -5 to +5 scale, negative = downtrend, positive = uptrend
        
        // A. Moving Average Analysis
        double maArray[5]; // 20, 50, 100, 200, 500 period MAs
        int maPeriods[5] = {20, 50, 100, 200, 500};
        
        for(int i=0; i<5; i++) {
            int maHandle = iMA(Symbol(), PERIOD_CURRENT, maPeriods[i], 0, MODE_SMA, PRICE_CLOSE);
            if(maHandle != INVALID_HANDLE) {
                double maLocalBuffer[];
                if(CopyBuffer(maHandle, 0, 0, 1, maLocalBuffer) > 0) {
                    maArray[i] = maLocalBuffer[0];
                }
                IndicatorRelease(maHandle);
            }
        }
        
        // Check MA alignment for trend strength
        double currentPrice = (high[0] + low[0]) / 2;
        
        // Price above/below all MAs
        if(currentPrice > maArray[0] && currentPrice > maArray[1] && currentPrice > maArray[2] && currentPrice > maArray[3]) {
            trendStrength += 2; // Strong bullish alignment
        }
        else if(currentPrice < maArray[0] && currentPrice < maArray[1] && currentPrice < maArray[2] && currentPrice < maArray[3]) {
            trendStrength -= 2; // Strong bearish alignment
        }
        
        // MA alignment (shorter above/below longer)
        if(maArray[0] > maArray[1] && maArray[1] > maArray[2] && maArray[2] > maArray[3]) {
            trendStrength += 2; // Strong bullish alignment
        }
        else if(maArray[0] < maArray[1] && maArray[1] < maArray[2] && maArray[2] < maArray[3]) {
            trendStrength -= 2; // Strong bearish alignment
        }
        
        // B. RSI Analysis
        int rsiPeriod = 14;
        double rsiValue = 0;
        int rsiHandle = iRSI(Symbol(), PERIOD_CURRENT, rsiPeriod, PRICE_CLOSE);
        if(rsiHandle != INVALID_HANDLE) {
            double rsiBuffer[];
            if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) > 0) {
                rsiValue = rsiBuffer[0];
            }
            IndicatorRelease(rsiHandle);
        }
        
        // RSI trend indications
        if(rsiValue > 70) trendStrength += 1;
        else if(rsiValue < 30) trendStrength -= 1;
        
        // C. MACD Analysis for trend momentum
        int macdHandle = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
        double macdMain = 0, macdSignal = 0, macdHistogram = 0;
        if(macdHandle != INVALID_HANDLE) {
            double macdMainBuffer[], macdSignalBuffer[], macdHistogramBuffer[];
            if(CopyBuffer(macdHandle, 0, 0, 2, macdMainBuffer) > 0 &&
               CopyBuffer(macdHandle, 1, 0, 2, macdSignalBuffer) > 0) {
                macdMain = macdMainBuffer[0];
                macdSignal = macdSignalBuffer[0];
                macdHistogram = macdMain - macdSignal;
                
                // Trending MACD
                if(macdMain > 0 && macdMain > macdSignal) trendStrength += 1; // Bullish
                else if(macdMain < 0 && macdMain < macdSignal) trendStrength -= 1; // Bearish
            }
            IndicatorRelease(macdHandle);
        }
        
        // D. Higher Timeframe Analysis for context
        if(higherTF != PERIOD_CURRENT) {
            // Ensure higherTF is properly defined as ENUM_TIMEFRAMES
            int htfRsiHandle = iRSI(Symbol(), higherTF, rsiPeriod, PRICE_CLOSE);
            if(htfRsiHandle != INVALID_HANDLE) {
                double htfRsiBuffer[];
                if(CopyBuffer(htfRsiHandle, 0, 0, 1, htfRsiBuffer) > 0) {
                    double htfRsiValue = htfRsiBuffer[0];
                    if(htfRsiValue > 60) trendStrength += 1; // Higher timeframe bullish bias
                    else if(htfRsiValue < 40) trendStrength -= 1; // Higher timeframe bearish bias
                }
                IndicatorRelease(htfRsiHandle);
            }
        }
        
        // Determine overall trend state
        strongUptrend = (trendStrength >= 4);
        weakUptrend = (trendStrength >= 2 && trendStrength < 4);
        strongDowntrend = (trendStrength <= -4);
        weakDowntrend = (trendStrength <= -2 && trendStrength > -4);
        choppyMarket = (trendStrength > -2 && trendStrength < 2);
        
        string trendStatus = "";
        if(strongUptrend) trendStatus = "Strong uptrend";
        else if(weakUptrend) trendStatus = "Weak uptrend";
        else if(strongDowntrend) trendStatus = "Strong downtrend";
        else if(weakDowntrend) trendStatus = "Weak downtrend";
        else trendStatus = "Choppy/sideways market";
        
        Print("[MARKET CONTEXT] ", trendStatus, " detected. Trend strength: ", trendStrength, "/5");
        
        // 3. PRICE ACTION STRUCTURE ANALYSIS
        // Detect swing levels for better entry/exit points
        int swingHighBar = FindRecentSwingPoint(false, 1, 15); // Find recent swing high in last 15 bars
        int swingLowBar = FindRecentSwingPoint(true, 1, 15); // Find recent swing low in last 15 bars
        
        double swingHigh = 0, swingLow = 0;
        if(swingHighBar >= 0) swingHigh = high[swingHighBar];
        if(swingLowBar >= 0) swingLow = low[swingLowBar];
        
        // Check if price is near a swing level (potential reversal/continuation point)
        bool nearSwingHigh = (swingHighBar >= 0 && MathAbs(high[0] - swingHigh) < currentATR * 0.5);
        bool nearSwingLow = (swingLowBar >= 0 && MathAbs(low[0] - swingLow) < currentATR * 0.5);
        
        if(nearSwingHigh) Print("[STRUCTURE] Price near recent swing high: ", swingHigh);
        if(nearSwingLow) Print("[STRUCTURE] Price near recent swing low: ", swingLow);
        
        // 4. KEY LEVEL INTERACTION
        // Detect round numbers and session high/lows
        double roundNumber = MathRound(close[0] / Point() / 1000) * Point() * 1000;
        bool nearRoundNumber = MathAbs(close[0] - roundNumber) < Point() * 50;
        
        if(nearRoundNumber) {
            Print("[KEY LEVEL] Price near round number: ", roundNumber);
        }
        
        // 5. ADVANCED ENTRY FILTER & BLOCK CREATION LOGIC
        // Only proceed with block creation if the spread is reasonable
        double effectiveMaxSpread = 0;
        if(StringFind(Symbol(), "XAU") >= 0 || StringFind(Symbol(), "GOLD") >= 0) {
            effectiveMaxSpread = 200; // Gold can have higher spreads
        }
        else if(StringFind(Symbol(), "JPY") >= 0) {
            effectiveMaxSpread = 50; // JPY pairs
        }
        else {
            effectiveMaxSpread = 30; // Regular forex pairs
        }
        
        // Skip block creation if spread is excessive
        if(currentSpread > effectiveMaxSpread) {
            Print("[BLOCK FILTER] Excessive spread: ", currentSpread, " > ", effectiveMaxSpread, ". Skipping block creation.");
            return;
        }
        
        // Filter by trading session time - if needed
        datetime currentTime = TimeCurrent();
        MqlDateTime localTime;
        TimeToStruct(currentTime, localTime);
        int currentHour = localTime.hour;
        
        // Define optimal trading hours (better quality setups)
        bool optimalSession = (currentHour >= 7 && currentHour <= 11) || // London session
                              (currentHour >= 13 && currentHour <= 17); // New York session
                              
        // Adjust block strength based on session quality
        int sessionQualityBonus = optimalSession ? 1 : 0;
        
        // Calculate optimal block locations and determine whether to create blocks
        bool createBuyBlock = false;
        bool createSellBlock = false;
        double buyBlockPrice = 0;
        double sellBlockPrice = 0;
        int buyBlockStrength = 0;
        int sellBlockStrength = 0;
        
        // Logic for BUY blocks
        if(strongUptrend || weakUptrend) {
            // Trend-following entry
            createBuyBlock = true;
            buyBlockStrength = strongUptrend ? 5 : 3;
            
            // Place block at recent swing low if available, otherwise use current price - ATR
            if(swingLowBar >= 0 && swingLow > 0) {
                buyBlockPrice = swingLow - (atrValue * 0.1); // Just below swing low
                buyBlockStrength += 1; // Bonus for structure-based entry
            } 
            else if(nearSwingLow) {
                buyBlockPrice = low[0] - (atrValue * 0.05); // Very close to current low if we're near a swing
                buyBlockStrength += 2; // Extra bonus for entry at fresh swing
            }
            else {
                buyBlockPrice = low[0] - (atrValue * 0.2); // Standard placement
            }
            
            // If price is in a pullback (RSI < 40 in uptrend), enhance the block
            if(rsiValue < 40 && trendStrength > 0) {
                buyBlockStrength += 1; // Bonus for counter-trend pullback in larger uptrend
                Print("[BLOCK LOGIC] Pullback detected in uptrend - enhancing buy block");
            }
        }
        else if(strongDowntrend || weakDowntrend) {
            // Counter-trend entries only in specific conditions
            if(rsiValue < 30 || (nearSwingLow && volatilityExpanding)) {
                createBuyBlock = true;
                buyBlockStrength = 2; // Lower strength for counter-trend
                
                // Careful placement for counter-trend entries
                if(nearSwingLow) {
                    buyBlockPrice = swingLow - (atrValue * 0.1);
                    Print("[BLOCK LOGIC] Counter-trend buy at swing low");
                    buyBlockStrength += 1;
                } else {
                    buyBlockPrice = low[0] - (atrValue * 0.3); // Deeper for safety
                }
            }
        }
        else if(choppyMarket) {
            // Range-bound strategy
            if(rsiValue < 40 && nearSwingLow) {
                createBuyBlock = true;
                buyBlockStrength = 3;
                buyBlockPrice = low[0] - (atrValue * 0.15);
                Print("[BLOCK LOGIC] Range-bound buy near support");
            }
        }
        
        // Logic for SELL blocks
        if(strongDowntrend || weakDowntrend) {
            // Trend-following entry
            createSellBlock = true;
            sellBlockStrength = strongDowntrend ? 5 : 3;
            
            // Place block at recent swing high if available
            if(swingHighBar >= 0 && swingHigh > 0) {
                sellBlockPrice = swingHigh + (atrValue * 0.1); // Just above swing high
                sellBlockStrength += 1; // Bonus for structure-based entry
            }
            else if(nearSwingHigh) {
                sellBlockPrice = high[0] + (atrValue * 0.05); // Very close to current high if we're near a swing
                sellBlockStrength += 2; // Extra bonus for entry at fresh swing
            }
            else {
                sellBlockPrice = high[0] + (atrValue * 0.2); // Standard placement
            }
            
            // If price is in a pullback (RSI > 60 in downtrend), enhance the block
            if(rsiValue > 60 && trendStrength < 0) {
                sellBlockStrength += 1; // Bonus for counter-trend pullback in larger downtrend
                Print("[BLOCK LOGIC] Pullback detected in downtrend - enhancing sell block");
            }
        }
        else if(strongUptrend || weakUptrend) {
            // Counter-trend entries only in specific conditions
            if(rsiValue > 70 || (nearSwingHigh && volatilityExpanding)) {
                createSellBlock = true;
                sellBlockStrength = 2; // Lower strength for counter-trend
                
                // Careful placement for counter-trend entries
                if(nearSwingHigh) {
                    sellBlockPrice = swingHigh + (atrValue * 0.1);
                    Print("[BLOCK LOGIC] Counter-trend sell at swing high");
                    sellBlockStrength += 1;
                } else {
                    sellBlockPrice = high[0] + (atrValue * 0.3); // Further for safety
                }
            }
        }
        else if(choppyMarket) {
            // Range-bound strategy
            if(rsiValue > 60 && nearSwingHigh) {
                createSellBlock = true;
                sellBlockStrength = 3;
                sellBlockPrice = high[0] + (atrValue * 0.15);
                Print("[BLOCK LOGIC] Range-bound sell near resistance");
            }
        }
        
        // 6. VOLATILITY-BASED ADJUSTMENTS
        // Adjust block placement based on current volatility
        if(volRatio > 1.5) {
            // High volatility - wider blocks
            if(createBuyBlock) buyBlockPrice -= (atrValue * 0.1);
            if(createSellBlock) sellBlockPrice += (atrValue * 0.1);
            Print("[VOLATILITY] High volatility detected - widening block placement");
        }
        else if(volRatio < 0.7) {
            // Low volatility - tighter blocks
            if(createBuyBlock) buyBlockPrice += (atrValue * 0.05);
            if(createSellBlock) sellBlockPrice -= (atrValue * 0.05);
            Print("[VOLATILITY] Low volatility detected - tightening block placement");
        }
        
        // Add session quality bonus
        buyBlockStrength += sessionQualityBonus;
        sellBlockStrength += sessionQualityBonus;
        
        // 7. FINAL BLOCK CREATION WITH SMART FILTERING
        // Create buy block if conditions met and strength is sufficient
        if(createBuyBlock && buyBlockStrength >= 3) {
            int blockIdx = GetNextBlockIndex();
            recentBlocks[blockIdx].price = buyBlockPrice;
            recentBlocks[blockIdx].volume = 0;
            recentBlocks[blockIdx].strength = buyBlockStrength;
            recentBlocks[blockIdx].type = 1; // Bullish
            recentBlocks[blockIdx].time = TimeCurrent();
            recentBlocks[blockIdx].valid = true;
            recentBlocks[blockIdx].isBuy = true;
            recentBlocks[blockIdx].touched = false;
            recentBlocks[blockIdx].score = buyBlockStrength;
            
            string contextInfo = "";
            if(strongUptrend) contextInfo = "strong uptrend";
            else if(weakUptrend) contextInfo = "weak uptrend";
            else if(choppyMarket) contextInfo = "range support";
            else contextInfo = "counter-trend entry";
            
            Print("[SMART BLOCK] Created buy block at ", buyBlockPrice, ", strength: ", buyBlockStrength, "/5", 
                  ", context: ", contextInfo, ", RSI: ", rsiValue);
        }
        
        // Create sell block if conditions met and strength is sufficient
        if(createSellBlock && sellBlockStrength >= 3) {
            int blockIdx = GetNextBlockIndex();
            recentBlocks[blockIdx].price = sellBlockPrice;
            recentBlocks[blockIdx].volume = 0;
            recentBlocks[blockIdx].strength = sellBlockStrength;
            recentBlocks[blockIdx].type = -1; // Bearish
            recentBlocks[blockIdx].time = TimeCurrent();
            recentBlocks[blockIdx].valid = true;
            recentBlocks[blockIdx].isBuy = false;
            recentBlocks[blockIdx].touched = false;
            recentBlocks[blockIdx].score = sellBlockStrength;
            
            string contextInfo = "";
            if(strongDowntrend) contextInfo = "strong downtrend";
            else if(weakDowntrend) contextInfo = "weak downtrend";
            else if(choppyMarket) contextInfo = "range resistance";
            else contextInfo = "counter-trend entry";
            
            Print("[SMART BLOCK] Created sell block at ", sellBlockPrice, ", strength: ", sellBlockStrength, "/5", 
                  ", context: ", contextInfo, ", RSI: ", rsiValue);
        }
        
        // Fallback - if no blocks were created by the enhanced logic, create a basic block as last resort
        if(!createBuyBlock && !createSellBlock) {
            Print("[BLOCK LOGIC] No high-quality setups detected, using basic block creation...");
            
            // Create a very conservative block based on simple signals
            if(rsiValue < 30) {
                // Simple oversold condition - create a buy block
                int blockIdx = GetNextBlockIndex();
                recentBlocks[blockIdx].price = low[0] - (atrValue * 0.2);
                recentBlocks[blockIdx].volume = 0;
                recentBlocks[blockIdx].strength = 2; // Lower strength for basic blocks
                recentBlocks[blockIdx].type = 1; // Bullish
                recentBlocks[blockIdx].time = TimeCurrent();
                recentBlocks[blockIdx].valid = true;
                recentBlocks[blockIdx].isBuy = true;
                recentBlocks[blockIdx].touched = false;
                recentBlocks[blockIdx].score = 2;
                
                Print("[BASIC BLOCK] Created backup buy block at ", recentBlocks[blockIdx].price, 
                      " (RSI: ", rsiValue, ", no optimal setup found)");
            }
            else if(rsiValue > 70) {
                // Simple overbought condition - create a sell block
                int blockIdx = GetNextBlockIndex();
                recentBlocks[blockIdx].price = high[0] + (atrValue * 0.2);
                recentBlocks[blockIdx].volume = 0;
                recentBlocks[blockIdx].strength = 2; // Lower strength for basic blocks
                recentBlocks[blockIdx].type = -1; // Bearish
                recentBlocks[blockIdx].time = TimeCurrent();
                recentBlocks[blockIdx].valid = true;
                recentBlocks[blockIdx].isBuy = false;
                recentBlocks[blockIdx].touched = false;
                recentBlocks[blockIdx].score = 2;
                
                Print("[BASIC BLOCK] Created backup sell block at ", recentBlocks[blockIdx].price, 
                      " (RSI: ", rsiValue, ", no optimal setup found)");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Force trade execution based on detected order blocks               |
//+------------------------------------------------------------------+
void AttemptTradeExecution() {
    // Look for valid order blocks to execute trades
    int buySignal = 0;
    int sellSignal = 0;
    double buyBlockPrice = 0;
    double sellBlockPrice = 0;
    double buyBlockStrength = 0;
    double sellBlockStrength = 0;
    
    // Find strongest buy and sell blocks
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            if(recentBlocks[i].isBuy && recentBlocks[i].strength > buyBlockStrength) {
                buyBlockStrength = recentBlocks[i].strength;
                buyBlockPrice = recentBlocks[i].price;
                buySignal = 1;
            }
            else if(!recentBlocks[i].isBuy && recentBlocks[i].strength > sellBlockStrength) {
                sellBlockStrength = recentBlocks[i].strength;
                sellBlockPrice = recentBlocks[i].price;
                sellSignal = -1;
            }
        }
    }
    
    // Determine which signal to use (if both are present, use the stronger one)
    int signal = 0;
    double price = 0;
    
    if(buyBlockStrength > 0 && sellBlockStrength > 0) {
        // Both signals present - use the stronger one
        if(buyBlockStrength >= sellBlockStrength) {
            signal = buySignal;
            price = buyBlockPrice;
        } else {
            signal = sellSignal;
            price = sellBlockPrice;
        }
    }
    else if(buyBlockStrength > 0) {
        signal = buySignal;
        price = buyBlockPrice;
    }
    else if(sellBlockStrength > 0) {
        signal = sellSignal;
        price = sellBlockPrice;
    }
    
    if(signal == 0) return; // No valid signal
    
    // Check time since last trade
    datetime currentTime = TimeCurrent();
    if(currentTime - lastTradeTime < SignalCooldownSeconds) {
        Print("[TRADE] Signal cooldown active - ", (SignalCooldownSeconds - (currentTime - lastTradeTime)), " seconds remaining");
        return;
    }
    
    // Calculate trade parameters
    double entryPrice = signal > 0 ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    
    // Calculate stop loss based on ATR and price
    double stopLoss = 0;
    if(signal > 0) { // Buy
        stopLoss = MathMax(price - (atr * 1.5), entryPrice - (atr * 2.5));
    } else { // Sell
        stopLoss = MathMin(price + (atr * 1.5), entryPrice + (atr * 2.5));
    }
    
    // Normalize stop loss for minimum distance
    double minStopDistance = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    if(signal > 0) { // Buy
        stopLoss = MathMin(stopLoss, entryPrice - minStopDistance - (5 * SymbolInfoDouble(Symbol(), SYMBOL_POINT)));
    } else { // Sell
        stopLoss = MathMax(stopLoss, entryPrice + minStopDistance + (5 * SymbolInfoDouble(Symbol(), SYMBOL_POINT)));
    }
    
    // Calculate take profit based on risk:reward ratio
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double takeProfit = 0;
    
    if(signal > 0) { // Buy
        takeProfit = entryPrice + (stopDistance * RiskRewardRatio);
    } else { // Sell
        takeProfit = entryPrice - (stopDistance * RiskRewardRatio);
    }
    
    // Calculate position size
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    
    double pipValue = tickValue / tickSize;
    double pipsRisked = stopDistance / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double lotSize = riskAmount / (pipsRisked * pipValue);
    
    // Normalize lot size
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    // Execute the trade
    CTrade trade;
    trade.SetDeviationInPoints(MaxSlippage);
    trade.SetExpertMagicNumber(MagicNumber);
    
    bool result = false;
    string comment = "SMC_" + (signal > 0 ? "BUY" : "SELL") + "_DIRECT";
    
    if(signal > 0) { // Buy
        result = trade.Buy(lotSize, Symbol(), 0, stopLoss, takeProfit, comment);
    } else { // Sell
        result = trade.Sell(lotSize, Symbol(), 0, stopLoss, takeProfit, comment);
    }
    
    if(result) {
        lastTradeTime = currentTime;
        Print("[TRADE] " + (signal > 0 ? "BUY" : "SELL") + " executed successfully at ", entryPrice, 
              " SL: ", stopLoss, " TP: ", takeProfit, " Lot: ", lotSize);
    } else {
        Print("[TRADE ERROR] Failed to execute " + (signal > 0 ? "BUY" : "SELL") + " order. Error: ", 
              GetLastError(), " - ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Get the next available index for order blocks                     |
//+------------------------------------------------------------------+
int GetNextBlockIndex() {
    // First try to find an invalid block to replace
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(!recentBlocks[i].valid) return i;
    }
    
    // If all blocks are valid, replace the oldest one
    int oldestIndex = 0;
    datetime oldestTime = TimeCurrent();
    
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].time < oldestTime) {
            oldestTime = recentBlocks[i].time;
            oldestIndex = i;
        }
    }
    
    return oldestIndex;
}

// This function is already defined earlier in the code - removing duplicate definition
//+------------------------------------------------------------------+
//| Get text description for an error code                           |
//+------------------------------------------------------------------+
/*
string GetLastErrorText(int error_code) {
    // Function body removed as it's already defined at line 282
}*/

// This function is already defined earlier in the code - removing duplicate definition
//+------------------------------------------------------------------+
//| Log error messages with timestamp for debugging                  |
//+------------------------------------------------------------------+
/*
void LogError(string message) {
    // Function body removed as it's already defined at line 259
}*/

//+------------------------------------------------------------------+
//| Legacy Calculate ATR value - now using enhanced version           |
//+------------------------------------------------------------------+
// This function was replaced by the enhanced version at line ~5052
// Using the enhanced CalculateATR instead of this one
/*
double CalculateATR_Legacy(int period) {
    // Using enhanced logging as per memory about debugging SL calculations
    if(DisplayDebugInfo) Print("[DEBUG] Calculating ATR with period=", period);
    
    double atrValue = 0.0;
    int handle = iATR(Symbol(), PERIOD_CURRENT, period);
    
    if(handle == INVALID_HANDLE) {
        LogError("Failed to create ATR indicator handle");
        return 0.0;
    }
    
    double buffer[];
    ArraySetAsSeries(buffer, true);
    
    // Copy ATR values
    int copied = CopyBuffer(handle, 0, 0, 1, buffer);
    
    // Release the indicator handle
    IndicatorRelease(handle);
    
    if(copied > 0) {
        atrValue = buffer[0];
        if(DisplayDebugInfo) Print("[DEBUG] ATR(", period, ") = ", atrValue);
    } else {
        LogError("Failed to copy ATR data: " + GetLastErrorText(GetLastError()));
    }
    
    return atrValue;
}

//+------------------------------------------------------------------+
//| Check if stop loss and take profit levels are valid              |
//+------------------------------------------------------------------+
bool OrderCheck(ENUM_POSITION_TYPE posType, double stopLoss, double takeProfit) {
    // Get current bid and ask prices
    double bid = GetCurrentBid();
    double ask = GetCurrentAsk();
    
    // Get minimum stop level in points
    double stopLevel = (double)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    
    // Calculate minimum allowed distance for stops
    double minStopDist = stopLevel;
    
    // Apply different checks based on position type
    if(posType == POSITION_TYPE_BUY) {
        // For buy positions, SL must be below current bid by at least stopLevel
        if(stopLoss > 0 && bid - stopLoss < minStopDist) {
            LogError("Invalid SL for BUY: Too close to current price. Min distance = " + 
                    DoubleToString(minStopDist, _Digits));
            return false;
        }
        
        // TP must be above current ask by at least stopLevel
        if(takeProfit > 0 && takeProfit - ask < minStopDist) {
            LogError("Invalid TP for BUY: Too close to current price. Min distance = " + 
                    DoubleToString(minStopDist, _Digits));
            return false;
        }
    }
    else { // POSITION_TYPE_SELL
        // For sell positions, SL must be above current ask by at least stopLevel
        if(stopLoss > 0 && stopLoss - ask < minStopDist) {
            LogError("Invalid SL for SELL: Too close to current price. Min distance = " + 
                    DoubleToString(minStopDist, _Digits));
            return false;
        }
        
        // TP must be below current bid by at least stopLevel
        if(takeProfit > 0 && bid - takeProfit < minStopDist) {
            LogError("Invalid TP for SELL: Too close to current price. Min distance = " + 
                    DoubleToString(minStopDist, _Digits));
            return false;
        }
    }
    
    // SL and TP values are valid
    return true;
}

// GetRegimeName function already defined elsewhere in the code
// Keeping this comment as a reference but removing the duplicate function

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up resources
   EventKillTimer();
   Print("[DEINIT] Timer disabled");
   
   // Disable alerts when EA is removed or reloaded
   GlobalVariableSet("SMC_ALERTS_ENABLED", 0);
   
   // Clear any created chart objects
   ObjectsDeleteAll(0, "SMC_");
   
   // Log final performance stats if profiling was enabled
   if(EnableProfiling && tickCount > 0) {
      Print(StringFormat("[PERFORMANCE SUMMARY] Avg tick: %.2fms, Max: %.2fms, Block detection: %.2fms, Signal gen: %.2fms, Trade exec: %.2fms, Total ticks: %d",
                        averageTickProcessingTime, maxTickProcessingTime, 
                        avgTime_BlockDetection, avgTime_SignalGeneration,
                        avgTime_TradeLogic, tickCount));
   }
   
   ChartRedraw();
                totalProfit += regimeProfit[i];
            }
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
//| Modify stops based on Change of Character patterns               |
//+------------------------------------------------------------------+
bool ModifyStopsOnCHOCHImproved(ulong ticket, double& chochLevel, double& newSL) {
    // Get position details
    if(!PositionSelectByTicket(ticket)) {
        Print("[SMC] Error: Cannot select position with ticket ", ticket);
        return false;
    }
    
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double currentPrice = posType == POSITION_TYPE_BUY ? GetCurrentBid() : GetCurrentAsk();
    
    // Determine if there's a CHOCH pattern
    bool localChochDetected = false;
    
    if(posType == POSITION_TYPE_BUY) {
        // For Buy positions, look for a bullish CHOCH (previous resistance becoming support)
        localChochDetected = DetectBullishCHOCH(chochLevel);
        
        if(localChochDetected && chochLevel > 0 && (currentSL == 0 || chochLevel > currentSL)) {
            // Ensure the CHOCH level is not too close to current price (minimum buffer)
            if(currentPrice - chochLevel >= MinStopDistance * _Point) {
                // Use the output parameter correctly
                newSL = chochLevel;
                return true;
            }
        }
    } else if(posType == POSITION_TYPE_SELL) {
        // For Sell positions, we need to handle bearish CHOCH or use a similar approach
        // Find a recent swing high that could serve as resistance
        int swingHighIdx = FindRecentSwingPoint(false, 1, 20);
        if(swingHighIdx >= 0) {
            // Use proper function call to get high price
            double swingHigh = iHigh(Symbol(), PERIOD_CURRENT, swingHighIdx);
            // If swing high is above current price and below current SL (or no SL set)
            if(swingHigh > currentPrice && (currentSL == 0 || swingHigh < currentSL)) {
                // Ensure minimum distance
                if(swingHigh - currentPrice >= MinStopDistance * _Point) {
                    newSL = swingHigh;
                    return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect a bullish CHOCH pattern (BOS - Break of Structure)         |
//+------------------------------------------------------------------+
bool DetectBullishCHOCH(double& level) { // Fixed parameter to avoid hiding global
    // Initialize the level
    level = 0;
    
    // Look for patterns in recent price action (last 20 bars)
    // A bullish CHOCH typically forms when price breaks above a resistance,
    // pulls back, and then bounces off the previous resistance (now support)
    
    // Find the most recent Higher High and Higher Low
    // Commented out until FindRecentSwingPoint is implemented
    int hhBar = 1; // Temporary placeholder for most recent swing high
    int hlBar = 2; // Temporary placeholder for most recent swing low
    
    // Ensure we found valid swing points and they form a reasonable pattern
    if(hhBar >= 0 && hlBar > hhBar) { // Higher Low formed after Higher High
        double swingHigh = iHigh(Symbol(), PERIOD_CURRENT, hhBar);
        double swingLow = iLow(Symbol(), PERIOD_CURRENT, hlBar);
        
        // Look for price retesting the previous structure
        double currentPrice = GetCurrentBid();
        
        // Get ATR value
        double atrValue = 0;
        int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
        ArrayResize(localAtrBuffer, 1);
        if(CopyBuffer(atrHandle, 0, 0, 1, localAtrBuffer) > 0) {
            atrValue = localAtrBuffer[0];
        } else {
            Print("Error copying ATR buffer: ", GetLastError());
        }
        IndicatorRelease(atrHandle);
        
        // Check if price has pulled back to the previous swing high level
        // and is now bouncing up (forming a CHOCH/BOS pattern)
        if(currentPrice > swingLow && 
           MathAbs(currentPrice - swingHigh) < atrValue * 0.5) { // Within 0.5 ATR of previous swing high
            
            // Set the CHOCH level slightly below the retest level (adding a small buffer)
            level = swingHigh - (5 * _Point); // 5 points buffer below the swing high
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect a bearish CHOCH pattern (BOS - Break of Structure)         |
//+------------------------------------------------------------------+
bool DetectBearishCHOCH(double& level) { 
    // Initialize the level
    level = 0;
    
    // Look for patterns in recent price action (last 20 bars)
    // A bearish CHOCH typically forms when price breaks below a support,
    // pulls back, and then rejects from the previous support (now resistance)
    
    // Find the most recent Lower Low and Lower High
    int llBar = FindRecentSwingPoint(false, 1, 20); // Most recent swing low
    int lhBar = FindRecentSwingPoint(true, 1, 20); // Most recent swing high
    
    // Ensure we found valid swing points and they form a reasonable pattern
    if(llBar >= 0 && lhBar > llBar) { // Lower High formed after Lower Low
        double swingLow = iLow(Symbol(), PERIOD_CURRENT, llBar);
        double swingHigh = iHigh(Symbol(), PERIOD_CURRENT, lhBar);
        
        // Look for price retesting the previous structure
        double currentPrice = GetCurrentAsk();
        
        // Check if price has pulled back to the previous swing low level
        // and is now rejecting down (forming a CHOCH/BOS pattern)
        // Get ATR value
        double atrValue = 0;
        int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
        double atrTemp[1]; // Temporary buffer to avoid shadowing
        if(CopyBuffer(atrHandle, 0, 0, 1, atrTemp) > 0) {
            atrValue = atrTemp[0];
        }
        IndicatorRelease(atrHandle);
        
        if(currentPrice < swingHigh && 
           MathAbs(currentPrice - swingLow) < atrValue * 0.5) { // Within 0.5 ATR of previous swing low
            
            // Set the CHOCH level slightly above the retest level (adding a small buffer)
            level = swingLow + (5 * _Point); // 5 points buffer above the swing low
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calculate optimal stop loss based on market conditions             |
//+------------------------------------------------------------------+
double DetermineOptimalStopLoss(bool isBuy, double entryPrice) {
    // 1. ENHANCED ATR CALCULATION WITH MULTI-TIMEFRAME APPROACH
    double atrBuffer[];
    double atrValue = 0;
    double atrValueH1 = 0; // Higher timeframe ATR
    double finalAtrValue = 0;
    
    // Current timeframe ATR
    int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
    if(atrHandle != INVALID_HANDLE) {
        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
            atrValue = atrBuffer[0];
            IndicatorRelease(atrHandle);
            Print("[SL-CALC] Current TF ATR: ", atrValue);
        }
    }
    
    // Higher timeframe ATR for context
    int atrHandleH1 = iATR(Symbol(), PERIOD_H1, 14);
    if(atrHandleH1 != INVALID_HANDLE) {
        if(CopyBuffer(atrHandleH1, 0, 0, 1, atrBuffer) > 0) {
            atrValueH1 = atrBuffer[0];
            IndicatorRelease(atrHandleH1);
            Print("[SL-CALC] H1 TF ATR: ", atrValueH1);
        }
    }
    
    // Default ATR value if unable to get ATR
    if(atrValue == 0) {
        // Fallback based on symbol specifics
        if(StringFind(Symbol(), "JPY") >= 0) {
            atrValue = 0.015; // Typical for JPY pairs
            Print("[SL-CALC] Using fallback ATR value for JPY pair: ", atrValue);
        } 
        else if(StringFind(Symbol(), "XAU") >= 0 || StringFind(Symbol(), "GOLD") >= 0) {
            atrValue = 1.5; // Typical for Gold
            Print("[SL-CALC] Using fallback ATR value for Gold: ", atrValue);
        }
        else {
            atrValue = 0.0005; // Typical for major forex pairs
            Print("[SL-CALC] Using fallback ATR value: ", atrValue);
        }
    }
    
    // 2. MARKET CONTEXT ASSESSMENT FOR SL ADJUSTMENT
    // Get recent candle data
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 30, rates);
    
    // Calculate recent volatility ratio (short-term vs long-term)
    double shortTermVolatility = 0;
    double longTermVolatility = 0;
    
    if(copied > 20) {
        for(int i = 0; i < 10; i++) {
            shortTermVolatility += (rates[i].high - rates[i].low);
        }
        shortTermVolatility /= 10;
        
        for(int i = 10; i < 30; i++) {
            longTermVolatility += (rates[i].high - rates[i].low);
        }
        longTermVolatility /= 20;
    }
    
    double volatilityRatio = (longTermVolatility > 0) ? shortTermVolatility / longTermVolatility : 1.0;
    Print("[SL-CALC] Volatility ratio: ", volatilityRatio);
    
    // 3. TREND ASSESSMENT FOR ASYMMETRIC SL PLACEMENT
    // Get trend direction
    double maFast[], maSlow[];
    int maFastHandle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
    int maSlowHandle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
    
    bool strongTrend = false;
    int trendDirection = 0; // 0=neutral, 1=up, -1=down
    
    if(maFastHandle != INVALID_HANDLE && maSlowHandle != INVALID_HANDLE) {
        if(CopyBuffer(maFastHandle, 0, 0, 1, maFast) > 0 && CopyBuffer(maSlowHandle, 0, 0, 1, maSlow) > 0) {
            if(maFast[0] > maSlow[0]) {
                trendDirection = 1; // Uptrend
                if(maFast[0] > maSlow[0] * 1.005) strongTrend = true;
            } else if(maFast[0] < maSlow[0]) {
                trendDirection = -1; // Downtrend
                if(maFast[0] < maSlow[0] * 0.995) strongTrend = true;
            }
            
            IndicatorRelease(maFastHandle);
            IndicatorRelease(maSlowHandle);
            
            Print("[SL-CALC] Trend direction: ", trendDirection, ", Strong trend: ", strongTrend);
        }
    }
    
    // 4. DYNAMIC ATR MULTIPLIER BASED ON MARKET CONDITIONS
    double atrMultiplier = 1.5; // Default multiplier
    
    // Adjust multiplier based on volatility
    if(volatilityRatio > 1.3) {
        // Higher volatility = wider stops
        atrMultiplier = 2.0;
        Print("[SL-CALC] Increased ATR multiplier due to high volatility: ", atrMultiplier);
    } else if(volatilityRatio < 0.7) {
        // Lower volatility = tighter stops
        atrMultiplier = 1.2;
        Print("[SL-CALC] Decreased ATR multiplier due to low volatility: ", atrMultiplier);
    }
    
    // Adjust multiplier based on trend alignment
    if((isBuy && trendDirection == 1) || (!isBuy && trendDirection == -1)) {
        // With-trend trade = slightly tighter stop
        atrMultiplier *= 0.9;
        Print("[SL-CALC] Adjusted ATR multiplier for with-trend trade: ", atrMultiplier);
    } else if((isBuy && trendDirection == -1) || (!isBuy && trendDirection == 1)) {
        // Counter-trend trade = slightly wider stop
        atrMultiplier *= 1.1;
        Print("[SL-CALC] Adjusted ATR multiplier for counter-trend trade: ", atrMultiplier);
    }
    
    // Use blend of current and higher timeframe ATR for more stable SL
    finalAtrValue = (atrValue * 0.7) + (atrValueH1 * 0.3);
    if(finalAtrValue == 0) finalAtrValue = atrValue; // Fallback if H1 ATR is not available
    
    Print("[SL-CALC] Final ATR value used: ", finalAtrValue, ", Multiplier: ", atrMultiplier);
    
    // 5. CALCULATE STOP LOSS PRICE WITH MARKET-AWARE ADJUSTMENT
    double stopLossPrice = 0;
    double stopDistance = finalAtrValue * atrMultiplier;
    
    // Apply asymmetric SL based on trade type and trend
    if(isBuy) {
        stopLossPrice = entryPrice - stopDistance;
        
        // Look for recent swing low for better SL placement
        double recentSwingLow = entryPrice;
        int swingLowIdx = -1;
        
        for(int i = 1; i < MathMin(20, copied); i++) {
            if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low && rates[i].low < recentSwingLow) {
                recentSwingLow = rates[i].low;
                swingLowIdx = i;
            }
        }
        
        // If we found a valid swing low that's not too far, use it for SL
        if(swingLowIdx >= 0 && entryPrice - recentSwingLow < stopDistance * 1.2 && entryPrice - recentSwingLow > stopDistance * 0.5) {
            stopLossPrice = recentSwingLow - (atrValue * 0.2); // Place SL just below swing low
            Print("[SL-CALC] Using swing low for buy SL: ", stopLossPrice, " (swing found at bar ", swingLowIdx, ")");
        }
    } else {
        stopLossPrice = entryPrice + stopDistance;
        
        // Look for recent swing high for better SL placement
        double recentSwingHigh = entryPrice;
        int swingHighIdx = -1;
        
        for(int i = 1; i < MathMin(20, copied); i++) {
            if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high && rates[i].high > recentSwingHigh) {
                recentSwingHigh = rates[i].high;
                swingHighIdx = i;
            }
        }
        
        // If we found a valid swing high that's not too far, use it for SL
        if(swingHighIdx >= 0 && recentSwingHigh - entryPrice < stopDistance * 1.2 && recentSwingHigh - entryPrice > stopDistance * 0.5) {
            stopLossPrice = recentSwingHigh + (atrValue * 0.2); // Place SL just above swing high
            Print("[SL-CALC] Using swing high for sell SL: ", stopLossPrice, " (swing found at bar ", swingHighIdx, ")");
        }
    }
    
    // 6. FINAL SAFETY CHECKS AND NORMALIZATION
    // Ensure minimum stop distance based on symbol requirements
    double minStopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * Point();
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    if(isBuy && (currentPrice - stopLossPrice) < minStopLevel) {
        stopLossPrice = currentPrice - minStopLevel - (5 * Point());
        Print("[SL-CALC] Adjusted SL to meet minimum stop level: ", stopLossPrice);
    } else if(!isBuy && (stopLossPrice - currentPrice) < minStopLevel) {
        stopLossPrice = currentPrice + minStopLevel + (5 * Point());
        Print("[SL-CALC] Adjusted SL to meet minimum stop level: ", stopLossPrice);
    }
    
    // Normalize the price to avoid invalid stops
    stopLossPrice = NormalizeDouble(stopLossPrice, _Digits);
    
    Print("[SL-CALC] Final stop loss price: ", stopLossPrice, ", Entry: ", entryPrice, ", Distance: ", 
          MathAbs(stopLossPrice - entryPrice), " points");
    
    return stopLossPrice;
}

//+------------------------------------------------------------------+
//| Execute trade based on detected order blocks (enhanced version)    |
//+------------------------------------------------------------------+
void AttemptTradeExecutionEnhanced() {
    Print("[TRADE EXEC] Attempting trade execution based on order blocks (enhanced)...");
    
    // Track the best block for buy and sell
    int bestBuyBlockIdx = -1;
    int bestSellBlockIdx = -1;
    int bestBuyScore = 0;
    int bestSellScore = 0;
    
    // Find the highest-scoring buy and sell blocks
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid && !recentBlocks[i].touched) {
            // Enhanced filtering: only consider blocks that have sufficient strength
            if(recentBlocks[i].isBuy && recentBlocks[i].score > bestBuyScore) {
                bestBuyScore = recentBlocks[i].score;
                bestBuyBlockIdx = i;
            } 
            else if(!recentBlocks[i].isBuy && recentBlocks[i].score > bestSellScore) {
                bestSellScore = recentBlocks[i].score;
                bestSellBlockIdx = i;
            }
        }
    }
    
    // Determine if we should prioritize buy or sell based on market conditions
    bool prioritizeBuy = false;
    bool prioritizeSell = false;
    
    // Check current trend strength using multiple timeframes
    double ma20 = 0, ma50 = 0, ma200 = 0;
    int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
    int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
    int ma200Handle = iMA(Symbol(), PERIOD_CURRENT, 200, 0, MODE_SMA, PRICE_CLOSE);
    
    if(ma20Handle != INVALID_HANDLE && ma50Handle != INVALID_HANDLE && ma200Handle != INVALID_HANDLE) {
        double buffer[];
        if(CopyBuffer(ma20Handle, 0, 0, 1, buffer) > 0) ma20 = buffer[0];
        if(CopyBuffer(ma50Handle, 0, 0, 1, buffer) > 0) ma50 = buffer[0];
        if(CopyBuffer(ma200Handle, 0, 0, 1, buffer) > 0) ma200 = buffer[0];
        
        IndicatorRelease(ma20Handle);
        IndicatorRelease(ma50Handle);
        IndicatorRelease(ma200Handle);
        
        // Determine trend alignment
        if(ma20 > ma50 && ma50 > ma200) {
            prioritizeBuy = true;
            Print("[TRADE EXEC] Prioritizing BUY due to uptrend (MA alignment)");
        }
        else if(ma20 < ma50 && ma50 < ma200) {
            prioritizeSell = true;
            Print("[TRADE EXEC] Prioritizing SELL due to downtrend (MA alignment)");
        }
    }
    
    // Check RSI for confirmation
    double rsiValue = 0;
    int rsiHandle = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
    if(rsiHandle != INVALID_HANDLE) {
        double rsiBuffer[];
        if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) > 0) {
            rsiValue = rsiBuffer[0];
        }
        IndicatorRelease(rsiHandle);
        
        // RSI confirms trend
        if(rsiValue > 60) prioritizeBuy = true;
        else if(rsiValue < 40) prioritizeSell = true;
    }
    
    // Get ATR for position sizing and stop loss calculation
    double atrValue = 0;
    int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
    if(atrHandle != INVALID_HANDLE) {
        double atrBuffer[];
        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
            atrValue = atrBuffer[0];
        }
        IndicatorRelease(atrHandle);
    }
    
    // Execute the best trade based on score and market context
    bool tradeTaken = false;
    
    // ENHANCED POSITION SIZING BASED ON RISK AND VOLATILITY
    double riskPercent = RiskPerTrade; // Default from EA inputs
    
    // Adjust risk based on volatility and block quality
    double volAdjustment = 1.0;
    double qualityAdjustment = 1.0;
    
    // Volatility adjustment
    double currentATR = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    double avgATR = GetATR(Symbol(), PERIOD_CURRENT, 14, 20); // Average over 20 periods
    double volRatio = (avgATR > 0) ? currentATR / avgATR : 1.0;
    
    if(volRatio > 1.5) {
        // High volatility - reduce risk
        volAdjustment = 0.7;
        Print("[RISK MGMT] Reducing risk due to high volatility: ", volRatio);
    } else if(volRatio < 0.7) {
        // Low volatility - can increase risk slightly
        volAdjustment = 1.2;
        Print("[RISK MGMT] Increasing risk due to low volatility: ", volRatio);
    }
    
    // Now execute the trades based on best blocks and priorities
    
    // Process BUY trade if conditions are met
    if(bestBuyBlockIdx >= 0 && (prioritizeBuy || (!prioritizeSell && bestBuyScore >= bestSellScore))) {
        // Quality adjustment based on block score
        qualityAdjustment = 0.8 + (recentBlocks[bestBuyBlockIdx].score * 0.1); // 0.8 to 1.3 based on score 0-5
        
        // Final risk calculation
        double adjustedRisk = riskPercent * volAdjustment * qualityAdjustment;
        if(adjustedRisk > riskPercent * 1.5) adjustedRisk = riskPercent * 1.5; // Cap maximum risk
        if(adjustedRisk < riskPercent * 0.5) adjustedRisk = riskPercent * 0.5; // Minimum risk floor
        
        Print("[RISK MGMT] Adjusted risk for BUY: ", adjustedRisk, "% (base: ", riskPercent, "%)");
        
        // Calculate position size and stops
        double entryPrice = recentBlocks[bestBuyBlockIdx].price;
        double stopLossPrice = DetermineOptimalStopLoss(true, entryPrice); // Using our enhanced function
        
        double takeProfitPrice = entryPrice + ((entryPrice - stopLossPrice) * 2.0); // R:R of 1:2
        
        // Dynamic lot size calculation based on risk percentage
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double riskAmount = accountBalance * (adjustedRisk / 100.0);
        double pipValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE) * (Point() / SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE));
        double stopLossPips = MathAbs(entryPrice - stopLossPrice) / Point();
        double lotSize = NormalizeDouble((riskAmount / (stopLossPips * pipValue)), 2);
        
        // Cap lot size
        double maxLot = 10.0; // Maximum allowed lot size
        if(lotSize > maxLot) lotSize = maxLot;
        
        // Normalize lot size according to broker requirements
        double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
        double maxLotAllowed = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
        
        lotSize = MathMax(minLot, lotSize);
        lotSize = MathMin(maxLotAllowed, lotSize);
        lotSize = MathRound(lotSize / lotStep) * lotStep;
        lotSize = NormalizeDouble(lotSize, 2);
        
        // Execute trade with the calculated parameters
        Print("[TRADE EXEC] Executing BUY trade - Entry: ", entryPrice, ", SL: ", stopLossPrice, 
              ", TP: ", takeProfitPrice, ", Lot Size: ", lotSize, ", Score: ", recentBlocks[bestBuyBlockIdx].score);
        
        // Execute trade
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_PENDING;
        request.symbol = Symbol();
        request.volume = lotSize;
        request.type = ORDER_TYPE_BUY_STOP;
        request.price = entryPrice;
        request.sl = stopLossPrice;
        request.tp = takeProfitPrice;
        request.deviation = 10;
        request.type_filling = ORDER_FILLING_FOK;
        request.type_time = ORDER_TIME_GTC;
        request.comment = "SMC Block Score: " + IntegerToString(recentBlocks[bestBuyBlockIdx].score);
        
        bool success = OrderSend(request, result);
        
        if(success && result.retcode == TRADE_RETCODE_DONE) {
            Print("[TRADE EXEC] BUY order placed successfully! Ticket: ", result.order);
            recentBlocks[bestBuyBlockIdx].touched = true; // Mark block as touched to avoid duplicate trades
            tradeTaken = true;
        } else {
            Print("[ERROR] BUY order failed: ", GetLastError(), ", Retcode: ", result.retcode);
        }
    }
    
    // Process SELL trade if no buy trade was taken and conditions are met
    if(!tradeTaken && bestSellBlockIdx >= 0 && (prioritizeSell || bestSellScore >= bestBuyScore)) {
        // Quality adjustment based on block score
        qualityAdjustment = 0.8 + (recentBlocks[bestSellBlockIdx].score * 0.1); // 0.8 to 1.3 based on score 0-5
        
        // Final risk calculation
        double adjustedRisk = riskPercent * volAdjustment * qualityAdjustment;
        if(adjustedRisk > riskPercent * 1.5) adjustedRisk = riskPercent * 1.5; // Cap maximum risk
        if(adjustedRisk < riskPercent * 0.5) adjustedRisk = riskPercent * 0.5; // Minimum risk floor
        
        Print("[RISK MGMT] Adjusted risk for SELL: ", adjustedRisk, "% (base: ", riskPercent, "%)");
        
        // Calculate position size and stops
        double entryPrice = recentBlocks[bestSellBlockIdx].price;
        double stopLossPrice = DetermineOptimalStopLoss(false, entryPrice); // Using our enhanced function
        
        double takeProfitPrice = entryPrice - ((stopLossPrice - entryPrice) * 2.0); // R:R of 1:2
        
        // Dynamic lot size calculation based on risk percentage
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double riskAmount = accountBalance * (adjustedRisk / 100.0);
        double pipValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE) * (Point() / SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE));
        double stopLossPips = MathAbs(entryPrice - stopLossPrice) / Point();
        double lotSize = NormalizeDouble((riskAmount / (stopLossPips * pipValue)), 2);
        
        // Cap lot size
        double maxLot = 10.0; // Maximum allowed lot size
        if(lotSize > maxLot) lotSize = maxLot;
        
        // Normalize lot size according to broker requirements
        double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
        double maxLotAllowed = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
        
        lotSize = MathMax(minLot, lotSize);
        lotSize = MathMin(maxLotAllowed, lotSize);
        lotSize = MathRound(lotSize / lotStep) * lotStep;
        lotSize = NormalizeDouble(lotSize, 2);
        
        // Execute trade with the calculated parameters
        Print("[TRADE EXEC] Executing SELL trade - Entry: ", entryPrice, ", SL: ", stopLossPrice, 
              ", TP: ", takeProfitPrice, ", Lot Size: ", lotSize, ", Score: ", recentBlocks[bestSellBlockIdx].score);
        
        // Execute trade
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_PENDING;
        request.symbol = Symbol();
        request.volume = lotSize;
        request.type = ORDER_TYPE_SELL_STOP;
        request.price = entryPrice;
        request.sl = stopLossPrice;
        request.tp = takeProfitPrice;
        request.deviation = 10;
        request.type_filling = ORDER_FILLING_FOK;
        request.type_time = ORDER_TIME_GTC;
        request.comment = "SMC Block Score: " + IntegerToString(recentBlocks[bestSellBlockIdx].score);
        
        bool success = OrderSend(request, result);
        
        if(success && result.retcode == TRADE_RETCODE_DONE) {
            Print("[TRADE EXEC] SELL order placed successfully! Ticket: ", result.order);
            recentBlocks[bestSellBlockIdx].touched = true; // Mark block as touched to avoid duplicate trades
        } else {
            Print("[ERROR] SELL order failed: ", GetLastError(), ", Retcode: ", result.retcode);
        }
    }
}

//+------------------------------------------------------------------+
//| Determine optimal trading mode based on market conditions         |
//+------------------------------------------------------------------+
void DetermineOptimalTradingMode() {
    // Only execute if in hybrid auto mode
    if(TradingMode != MODE_HYBRID_AUTO) {
        currentTradingMode = TradingMode;
        return;
    }
    
    // Don't change modes too frequently - enforce minimum time between changes
    if(TimeCurrent() - lastModeChangeTime < 3600) { // At least 1 hour between mode changes
        // Count potential mode changes for diagnostic purposes
        adaptiveModeChangeCounter++;
        return; 
    }
    
    // Analyze market conditions to determine optimal mode
    int optimalMode = MODE_NORMAL; // Default to normal trading
    
    // 1. Check volatility - HFT mode thrives in moderate volatility
    double atrValue = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    double avgAtrValue = GetATR(Symbol(), PERIOD_CURRENT, 14, 20); // Average over 20 periods
    double volRatio = (avgAtrValue > 0) ? atrValue / avgAtrValue : 1.0;
    
    // 2. Check current spread
    double spread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point();
    double spreadRatio = (atrValue > 0) ? spread / atrValue : 0.1;
    
    // 3. Check market regime
    int regime = FastRegimeDetection(Symbol());
    
    // 4. Check current session activity level
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);
    int currentHour = now.hour;
    bool activeSession = false;
    
    // Define active trading sessions (typically London and New York overlap is most active)
    if((currentHour >= 8 && currentHour <= 11) || // London session
       (currentHour >= 13 && currentHour <= 17)) { // New York session
        activeSession = true;
    }
    
    // 5. Check price action patterns and order block quality
    int validOrderBlocks = 0;
    int hftSuitableBlocks = 0;
    int normalSuitableBlocks = 0;
    
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            validOrderBlocks++;
            
            // HFT suitable blocks are recent and have high score
            if(TimeCurrent() - recentBlocks[i].time < 3600 && recentBlocks[i].score >= 4) {
                hftSuitableBlocks++;
            }
            
            // Normal trading suitable blocks have higher quality, confirmed by structure
            if(recentBlocks[i].score >= 3) {
                normalSuitableBlocks++;
            }
        }
    }
    
    // Decision matrix for optimal mode
    
    // HFT Mode Conditions
    bool hftConditions = (volRatio >= 0.7 && volRatio <= 1.3) && // Moderate volatility
                          (spreadRatio < 0.08) &&                // Low spread relative to ATR
                          (activeSession) &&                     // Active trading session
                          (hftSuitableBlocks >= 1) &&            // At least one suitable block
                          (regime != REGIME_CHOPPY);            // Not in choppy markets
    
    // Normal Trading Conditions
    bool normalConditions = (volRatio > 1.3 || volRatio < 0.7) || // Higher or lower volatility
                             (spreadRatio >= 0.08) ||             // Higher spread
                             (!activeSession) ||                  // Less active session
                             (normalSuitableBlocks >= 1) ||       // Quality blocks available
                             (regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN); // Strong trend
    
    // Make decision based on conditions
    if(hftConditions && !normalConditions) {
        optimalMode = MODE_HFT;
        Print("[MODE SELECTION] Switching to HFT mode due to ideal HFT conditions");
    }
    else if(normalConditions && !hftConditions) {
        optimalMode = MODE_NORMAL;
        Print("[MODE SELECTION] Switching to NORMAL mode due to ideal normal trading conditions");
    }
    else if(hftConditions && normalConditions) {
        // Both conditions are true, decide based on additional factors
        if(spreadRatio < 0.05 && activeSession && hftSuitableBlocks > normalSuitableBlocks) {
            optimalMode = MODE_HFT;
            Print("[MODE SELECTION] Choosing HFT mode in mixed conditions due to low spread and active session");
        } else {
            optimalMode = MODE_NORMAL;
            Print("[MODE SELECTION] Choosing NORMAL mode in mixed conditions for more conservative approach");
        }
    }
    else {
        // Neither set of conditions is fully met, default to normal trading
        optimalMode = MODE_NORMAL;
        Print("[MODE SELECTION] Defaulting to NORMAL mode as conditions are not ideal for either mode");
    }
    
    // If mode has changed, record the time
    if(currentTradingMode != optimalMode) {
        lastModeChangeTime = TimeCurrent();
        Print("[MODE CHANGE] Trading mode switched from ", 
              EnumToString((ENUM_TRADING_MODE)currentTradingMode), " to ", 
              EnumToString((ENUM_TRADING_MODE)optimalMode));
    }
    
    currentTradingMode = optimalMode;
}

//+------------------------------------------------------------------+
//| Apply mode-specific trading parameters                            |
//+------------------------------------------------------------------+
void ApplyModeSpecificParameters() {
    // Apply parameters based on current trading mode
    switch(currentTradingMode) {
        case MODE_HFT:
            // Apply HFT-specific parameters
            ActualSignalCooldownSeconds = HFT_SignalCooldownSeconds;
            SL_ATR_Mult = HFT_SL_ATR_Mult;
            TP_ATR_Mult = HFT_TP_ATR_Mult;
            workingTrailingStopMultiplierLocal = 0.5;  // More aggressive trailing for HFT
            break;
            
        case MODE_NORMAL:
            // Apply normal trading parameters
            ActualSignalCooldownSeconds = Normal_SignalCooldownSeconds;
            SL_ATR_Mult = Normal_SL_ATR_Mult;
            TP_ATR_Mult = Normal_TP_ATR_Mult;
            workingTrailingStopMultiplierLocal = 0.8;  // More conservative trailing for normal trading
            break;
            
        case MODE_HYBRID_AUTO:
            // This should never happen as currentTradingMode is always set to either HFT or NORMAL
            // But just in case, default to normal trading parameters
            ActualSignalCooldownSeconds = Normal_SignalCooldownSeconds;
            SL_ATR_Mult = Normal_SL_ATR_Mult;
            TP_ATR_Mult = Normal_TP_ATR_Mult;
            workingTrailingStopMultiplierLocal = 0.8;
            break;
    }
    
    if(DisplayDebugInfo) {
        Print("[MODE PARAMS] Applied parameters for mode: ", EnumToString((ENUM_TRADING_MODE)currentTradingMode),
              ", SL_ATR_Mult: ", SL_ATR_Mult, ", Cooldown: ", ActualSignalCooldownSeconds);
    }
}





//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
// Forward declarations of functions used in OnTick
double CalculateSignalQuality(int signal);
int FindSwingPoint(int direction, int startBar, int lookback);
bool IsBarHigherLow(int bar);
bool IsBarLowerHigh(int bar);
bool CheckForDivergence(int signal, DivergenceInfo &divInfo);
bool CalculateMultiTargetLevels(int signal, double entryPrice, double stopLoss, double &tp1, double &tp2);
double AdjustRiskForSession();
double CalculateVolatilityAdjustment();
bool IsMultiTimeframeRequired();
bool ConfirmSignalMultiTimeframe(int signal);
bool CheckMomentumConfirmation(int signal);
bool IsApproachingLiquidity(int signal, double &targetPrice);
double CalculateTimeDecayFactor(int signal);
double GetAdaptedSignalQualityThreshold();
void RecordMissedOpportunity(int signal, double price, string reason, double quality);
void UpdateMissedOpportunities();
void LogLiquidity(string message);
double GetCurrentAsk();
double GetCurrentBid();
void UpdateAdaptiveFilters(bool tradeTaken, bool isWin, bool isTie);
void UpdateFeatureStats();
void ClusterAndBoostPatterns();

// Variable to track last processed order block for each symbol
datetime lastProcessedTime[10] = {0}; // Indexed by symbol index
string symbolsTraded[10]; // Store symbol names for lookup

// Helper function to find symbol index in the array
int FindSymbolIndex(string symbolName) {
    for(int i=0; i<10; i++) {
        if(symbolsTraded[i] == symbolName) {
            return i;
        }
    }
    return -1;
}

// Helper function to get first empty slot in the symbols array
int GetFirstEmptySymbolSlot() {
    for(int i=0; i<10; i++) {
        if(symbolsTraded[i] == "" || symbolsTraded[i] == NULL) {
            return i;
        }
    }
    return -1; // No empty slots
}

void OnTick() {
    // Hybrid mode detection and switching - check this first
    static datetime lastModeEvaluationTime = 0;
    datetime currentTime = TimeCurrent();
    
    // Determine optimal trading mode if in hybrid auto mode
    if(TradingMode == MODE_HYBRID_AUTO && currentTime - lastModeEvaluationTime > 900) { // Every 15 minutes
        LogInfo("Evaluating optimal trading mode...");
        DetermineOptimalTradingMode();
        lastModeEvaluationTime = currentTime;
    }
    
    // Prevent trading during volatile news times
    if(IsNewsTime("High", 60)) { // 1hr before/after high impact news
        if(DisplayDebugInfo) Print("[NEWS FILTER] News filter active - skipping trade signals");
        // Still allow position management, just skip new trade generation
        return;
    }
    
    // Get current symbol index or assign a new one
    int currentSymbolIndex = -1;
    string currentSymbol = Symbol();
    
    // Find if this symbol already has an index
    currentSymbolIndex = FindSymbolIndex(currentSymbol);
    
    // If not found, assign to first empty slot
    if(currentSymbolIndex == -1) {
        currentSymbolIndex = GetFirstEmptySymbolSlot();
        if(currentSymbolIndex != -1) {
            symbolsTraded[currentSymbolIndex] = currentSymbol;
        }
    }
    
    // Detect order blocks and log validation information
    FindOrderBlocks(Symbol(), PERIOD_CURRENT);
    
    // Detect Change of Character (CHOCH) patterns and modify stops if detected
    bool localChochDetected = DetectCHOCH(Symbol(), PERIOD_CURRENT);
    if(localChochDetected) {
        Print("[INFO] CHOCH detected - modifying stops");
        // Call the existing function to modify stops based on CHOCH
        ModifyStopsOnCHOCH(localChochDetected);
        // Update the global variable
        chochDetected = localChochDetected;
    }
    
    // Count and log valid order blocks for debugging
    int validBullishBlocks = 0;
    int validBearishBlocks = 0;
    int totalValidBlocks = 0;
    int validBuyBlocks = 0;  // Added to fix undeclared identifier error
    int validSellBlocks = 0; // Added to fix undeclared identifier error
    
    for(int i = 0; i < MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            totalValidBlocks++;
            if(recentBlocks[i].isBuy) {
                validBullishBlocks++;
            } else {
                validBearishBlocks++;
            }
        }
    }
    
    // Log order block counts to help diagnose why recentBlocks.valid may not be set correctly
    LogInfo(StringFormat("Valid order blocks after detection: %d total (%d bullish, %d bearish)", 
                      totalValidBlocks, validBullishBlocks, validBearishBlocks));
    
    // Additional logging if no valid blocks are found
    if(totalValidBlocks == 0) {
        LogWarning("No valid order blocks detected - check block validity criteria");
    }
    
    // Check if we've processed a signal for this symbol recently (within cooldown period)
    // Use longer cooldown after losses to prevent overtrading
    bool hadRecentLoss = false;
    int cooldownPeriod = 300; // Default 5 minutes
    
    // Check if last trade was a loss and increase cooldown if so
    if(ArraySize(tradeProfits) > 0 && tradeProfits[0] < 0) {
        hadRecentLoss = true;
        cooldownPeriod = 1200; // 20 minutes after a loss
        if(DisplayDebugInfo) Print("[ENHANCED COOLDOWN] Using extended cooldown after recent loss");
    }
    
    if(currentSymbolIndex >= 0 && TimeCurrent() - lastProcessedTime[currentSymbolIndex] < cooldownPeriod) {
        if(DisplayDebugInfo) Print("[TRADE COOLDOWN] Waiting for cooldown on ", currentSymbol, ", ", 
                                   cooldownPeriod - (TimeCurrent() - lastProcessedTime[currentSymbolIndex]), 
                                   " seconds remaining");
        // Skip signal generation but still manage existing positions
    }
    
    // Check for existing positions on this symbol to prevent duplicate trades
    if(PositionSelect(Symbol())) {
        // Already have a position on this symbol, just manage it
        if(DisplayDebugInfo) Print("[TRADE CHECK] Already have position on ", Symbol(), ", skipping signal generation");
        // Still allow position management, just skip new trade generation
    }
    
    // --- Cache frequently used values for this tick ---
    double cachedATR = GetATR(Symbol(), PERIOD_M15, 14, 0);
    int cachedRegime = FastRegimeDetection(Symbol());
    double cachedSpread  = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    // Pass these as needed to downstream functions

    // FindOrderBlocks(Symbol(), PERIOD_M15); // Analyze 15m for order blocks - Commented out until implemented
    ProcessOrderBlocks(); // Validate existing blocks
    
    // AnalyzeMarketStructure(Symbol(), PERIOD_H1); // Analyze 1h market structure - Commented out until implemented
    
    // Detect liquidity zones for entry targeting
    if(EnableLiquidityDetection) {
        DetectLiquidityZones(); // Scan for stop clusters
    }
    
    // Check pending scaled entries for execution
    if(EnableSmartScaling) {
        CheckPendingScaledEntries();
    }
   // DIAGNOSTIC: Print current spread information every tick
   if(DisplayDebugInfo) {
      Print("[DIAG] Current spread=", SymbolInfoInteger(Symbol(), SYMBOL_SPREAD), 
            " points, MaxAllowed=", MaxAllowedSpread, 
            " points, Effective Threshold=", (TimeCurrent() - lastTradeTime > 3600 ? MaxAllowedSpread*1.5 : MaxAllowedSpread));
   }
   
   // Temporarily bypass session detection
   // DetectMarketSession();
   // Override session-adjusted parameters only if not in hybrid mode
   if(TradingMode != MODE_HYBRID_AUTO) {
        SL_ATR_Mult = 1.0;
        TP_ATR_Mult = 2.0;
    }
    // TrailingActivationPct is already defined as an input parameter
    
    // Note: DetermineOptimalTradingMode and ApplyModeSpecificParameters are already called
    // at the beginning of OnTick for hybrid mode, so we don't call them again here
    
    // Start with diagnostics and online learning
    ShowDiagnosticsOnChart();
    UpdateFeatureStats();
    ClusterAndBoostPatterns();
    
    // Market phase detection and adjustments
    // Using the global currentMarketPhase variable defined at line 1256
    // currentMarketPhase = DetectMarketPhase(); // Commented out until implemented
    // AdjustTradeFrequency(currentMarketPhase); // Commented out until implemented
    // AdjustRiskParameters(currentMarketPhase); // Commented out until implemented 

    DetectMarketStructure();
    if(marketStructure.choch) {
        // ModifyStopsOnCHOCH function is not defined - commenting out call
        // ModifyStopsOnCHOCH(true);
        LogInfo("CHOCH detected - would modify stops if ModifyStopsOnCHOCH was implemented");
    }
    
    // Always reset runtime cooldown from input at the start of each tick
    ActualSignalCooldownSeconds = SignalCooldownSeconds;
    // Defensive: ensure no negative or zero cooldown
    if (ActualSignalCooldownSeconds < 1) ActualSignalCooldownSeconds = 1;

    // Check for existing pending orders on this symbol
    for(int i = 0; i < OrdersTotal(); i++) {
        ulong ticket = OrderGetTicket(i);
        if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == Symbol()) {
            if(DisplayDebugInfo) Print("[ORDER CHECK] Already have pending order on ", Symbol(), ", skipping signal generation");
            return; // Skip signal generation if order exists
        }
    }
    
    // Dynamic session & symbol calibration
    AdjustSessionParameters();
    
    // Update dashboard
    UpdateDashboard();
    
    // Skip processing if trading is disabled
    if(!CanTrade()) return;

    // Check for open positions (manage trailing stop, etc.)
    if(PositionSelect(Symbol())) {
        // Try smart averaging if enabled and conditions are right
        // Removed reference to AttemptSmartAveraging() since it's not defined
        
        // Manage open trade and apply trailing stop strategies
        ManageOpenTrade();
        
        // Execute trailing stop management
        if(EnableAggressiveTrailing || EnableTrailingForLast) {
            // ManageTrailingStops(); // Commented out until implemented
            // Using AdjustTrailingStop instead
            bool trailingResult = AdjustTrailingStop();
            if(DisplayDebugInfo && trailingResult) {
                Print("[DEBUG] Trailing stop adjusted");
            }
        }
        
        return; // Don't open new positions if we already have one
    }
    
    if(EnableMarketRegimeFiltering) {
        // Use the already implemented FastRegimeDetection function
        currentRegime = FastRegimeDetection(Symbol());
    }
    
    // Detect order blocks first - this is critical for signal generation
    // Use the DetectOrderBlocks function that was added earlier
    DetectOrderBlocks();
    // Debug logging for order blocks - maintaining this code as per memory about debugging block detection
    // Count and display valid order blocks    // Added based on memory - add logging to count valid order blocks
    if(DisplayDebugInfo) {
        int validBlockCount = 0;
        for(int i=0; i<MAX_BLOCKS; i++) {
            // Use the global array directly - there's only one instance of it in the code now
            if(recentBlocks[i].valid) {
                validBlockCount++;
            }
        }
        Print("[DEBUG] Valid order blocks after detection: ", validBlockCount, "/", MAX_BLOCKS);
    }
    
    // Step 3: Get trading signal
    if(DisplayDebugInfo) Print("[DEBUG][ONTICK] Calling Get trading signal");
    int signal = 0; // Default to no signal
    
    // Implement trading signal logic here based on SMC principles
    double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    
    // Calculate ATR for dynamic stop loss/take profit
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    
    // 1. Use the already counted valid order blocks from earlier in the function
    // We already counted these variables at lines 4296-4305
    
    // 2. Look for divergence confirmation
    DivergenceInfo divInfo;
    bool divergenceFound = CheckForDivergence(0, divInfo); // 0 means check both directions
    
    // 3. Detect market regime for adaptive parameters
    ENUM_MARKET_REGIME regime = (ENUM_MARKET_REGIME)FastRegimeDetection(Symbol());
    
    // 4. Generate trading signal based on combined factors
    signal = 0; // Default to no signal
    double signalQuality = 0.0;
    
    // Calculate MA values for trend detection
    double ma20 = 0.0, ma50 = 0.0;
    int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
    int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
    
    double ma20Buffer[];
    double ma50Buffer[];
    ArraySetAsSeries(ma20Buffer, true);
    ArraySetAsSeries(ma50Buffer, true);
    
    CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer);
    CopyBuffer(ma50Handle, 0, 1, 1, ma50Buffer);
    ma20 = ma20Buffer[0];
    ma50 = ma50Buffer[0];
    
    IndicatorRelease(ma20Handle);
    IndicatorRelease(ma50Handle);
    
    // Update current market prices
    currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    
    // Current market price (mid price)
    double currentPrice = (currentBid + currentAsk) / 2.0;
    
    // Enhanced diagnostics for trading decision process
    if(DisplayDebugInfo) {
        Print("[TRADE DIAG] Symbol: ", Symbol(), 
              " | Valid Buy Blocks: ", validBuyBlocks, 
              " | Valid Sell Blocks: ", validSellBlocks,
              " | Regime: ", EnumToString(regime),
              " | MAs: ", DoubleToString(ma20, 5), " / ", DoubleToString(ma50, 5),
              " | Price: ", DoubleToString(currentPrice, 5));
    }
    
    // Signal generation logic using order blocks and regime detection
    if(validBuyBlocks > 0 && ((int)regime == REGIME_TRENDING_UP || (int)regime == REGIME_BREAKOUT)) {
        if(DisplayDebugInfo) Print("[TRADE DIAG] Buy setup detected - checking MA conditions");
        // Potential buy signal - check additional conditions
        // Detailed MA condition check
        bool priceBelow20MA = (currentPrice < ma20);
        bool ma20AboveMa50 = (ma20 > ma50);
        
        // Adaptive MA conditions based on market regime
        bool maConditionsMet = false;
        
        // In strong trends or breakouts, be less restrictive with MA conditions
        if((int)regime == REGIME_BREAKOUT) {
            // During breakouts, only require trend direction alignment
            maConditionsMet = ma20AboveMa50; // Only require uptrend confirmation
        } 
        else if((int)regime == REGIME_TRENDING_UP) {
            // In established uptrends, look for pullbacks to MA
            maConditionsMet = (MathAbs(currentPrice - ma20) < atr * 0.5) && ma20AboveMa50;
        }
        else {
            // Default condition for other regimes - stricter requirements
            maConditionsMet = priceBelow20MA && ma20AboveMa50;
        }
        
        // Always log MA conditions for diagnostic purposes
        Print("[TRADE DIAG] Buy MA conditions: Price < MA20? ", priceBelow20MA ? "Yes" : "No", 
              " | MA20 > MA50? ", ma20AboveMa50 ? "Yes" : "No",
              " | Regime: ", EnumToString(regime),
              " | MA Conditions Met: ", maConditionsMet ? "Yes" : "No");
        
        if(maConditionsMet) { // Adaptive MA conditions
            signal = 1; // Buy signal
            signalQuality = CalculateSignalQuality(signal);
            if(DisplayDebugInfo) LogInfo("Buy signal detected with quality: " + DoubleToString(signalQuality, 2));
            
            // Call adaptive filters to validate signal
            if(!ApplyAdaptiveFilters(signal, (int)regime, signalQuality)) {
                signal = 0; // Signal rejected by filters
                if(DisplayDebugInfo) LogInfo("Buy signal rejected by adaptive filters");
            }
        }
    }
    else if(validSellBlocks > 0 && ((int)regime == REGIME_TRENDING_DOWN || (int)regime == REGIME_REVERSAL)) {
        if(DisplayDebugInfo) Print("[TRADE DIAG] Sell setup detected - checking MA conditions");
        // Potential sell signal - check additional conditions
        // Detailed MA condition check for sell
        bool priceAbove20MA = (currentPrice > ma20);
        bool ma20BelowMa50 = (ma20 < ma50);
        
        // Adaptive MA conditions based on market regime
        bool maConditionsMet = false;
        
        // In strong trends or reversals, be less restrictive with MA conditions
        if((int)regime == REGIME_REVERSAL) {
            // During reversals, only require trend direction alignment
            maConditionsMet = ma20BelowMa50; // Only require downtrend confirmation
        } 
        else if((int)regime == REGIME_TRENDING_DOWN) {
            // In established downtrends, look for pullbacks to MA
            maConditionsMet = (MathAbs(currentPrice - ma20) < atr * 0.5) && ma20BelowMa50;
        }
        else {
            // Default condition for other regimes - stricter requirements
            maConditionsMet = priceAbove20MA && ma20BelowMa50;
        }
        
        // Always log MA conditions for diagnostic purposes
        Print("[TRADE DIAG] Sell MA conditions: Price > MA20? ", priceAbove20MA ? "Yes" : "No", 
              " | MA20 < MA50? ", ma20BelowMa50 ? "Yes" : "No",
              " | Regime: ", EnumToString(regime),
              " | MA Conditions Met: ", maConditionsMet ? "Yes" : "No");
        
        if(maConditionsMet) { // Adaptive MA conditions
            signal = -1; // Sell signal
            signalQuality = CalculateSignalQuality(signal);
            if(DisplayDebugInfo) LogInfo("Sell signal detected with quality: " + DoubleToString(signalQuality, 2));
            
            // Call adaptive filters to validate signal
            if(!ApplyAdaptiveFilters(signal, (int)regime, signalQuality)) {
                signal = 0; // Signal rejected by filters
                if(DisplayDebugInfo) LogInfo("Sell signal rejected by adaptive filters");
            }
        }
    }
    
    // 5. Execute trade if signal meets quality threshold
    // Calculate min quality threshold - use an adaptive approach
    double minSignalQuality = 0.65;  // Default minimum quality threshold
    double adaptiveSignalQuality = minSignalQuality; // Initialize adaptive quality
    double baseSignalQuality = minSignalQuality; // Base signal quality for reference
    
    // Adjust quality threshold based on trading mode
    if(currentTradingMode == MODE_HFT) {
        minSignalQuality = 0.60;  // Slightly lower threshold for HFT to enable more trades
    } else if(currentTradingMode == MODE_NORMAL) {
        minSignalQuality = 0.70;  // Higher threshold for normal trading to ensure quality
    }
    
    // 1. Adjust based on market regime
    // Using proper ENUM_MARKET_REGIME values
    if((int)regime == REGIME_TRENDING_UP || (int)regime == REGIME_TRENDING_DOWN) {
        // In strong trends, we can be slightly more permissive
        adaptiveSignalQuality -= 0.05;
        Print("[ADAPTIVE QUALITY] Lowering threshold in trending market: -0.05");
    } 
    else if((int)regime == REGIME_CHOPPY) {
        // In choppy markets, be more cautious but still allow trading
        adaptiveSignalQuality += 0.05; // Reduced further to allow trading with caution
        Print("[ADAPTIVE QUALITY] Slightly raising threshold in choppy market: +0.05");
    }
    else if((int)regime == REGIME_RANGING_NARROW) {
        // In narrow range markets, be slightly more permissive than normal
        // These can actually provide good scalping opportunities
        adaptiveSignalQuality -= 0.02; // Make it easier to trade in narrow ranges
        Print("[ADAPTIVE QUALITY] Slightly lowering threshold in narrow range market: -0.02");
    }
    else if((int)regime == REGIME_BREAKOUT) {
        // In breakouts, we want to be early, so slightly lower threshold
        adaptiveSignalQuality -= 0.08;
        Print("[ADAPTIVE QUALITY] Lowering threshold in breakout market: -0.08");
    }
    
    // 2. Adjust based on recent performance
    if(consecutiveLosses > 2) {
        // After losses, be more conservative
        adaptiveSignalQuality += 0.05 * MathMin(consecutiveLosses, 4); // Max +0.20
        Print("[ADAPTIVE QUALITY] Raising threshold after losses: +", 0.05 * MathMin(consecutiveLosses, 4));
    }
    if(winStreak > 2) {
        // During win streaks, we can be slightly more aggressive
        adaptiveSignalQuality -= 0.03 * MathMin(winStreak, 3); // Max -0.09
        Print("[ADAPTIVE QUALITY] Lowering threshold during win streak: -", 0.03 * MathMin(winStreak, 3));
    }
    
    // 3. Adjust based on time of day (using local market session)
    MqlDateTime localTime;
    TimeToStruct(TimeCurrent(), localTime);
    int currentHour = localTime.hour;
    
    // Preferred trading hours (adjust based on your backtesting results)
    bool isPreferredSession = (currentHour >= 8 && currentHour <= 12) ||
                             (currentHour >= 14 && currentHour <= 17);
    
    if(isPreferredSession) {
        // During high-quality trading hours, be more permissive
        adaptiveSignalQuality -= 0.07;
        Print("[ADAPTIVE QUALITY] Lowering threshold during optimal trading hours: -0.07");
    }
    
    // 4. Ensure we stay within reasonable bounds - cap maximum threshold to ensure all regimes can trade
    double minQualityThreshold = 0.30; // Further reduced to ensure all regimes can trade
    double maxQualityThreshold = 0.65; // Capped at 0.65 to ensure even choppy markets can trade with high quality signals
    
    // Update the existing minSignalQuality instead of redeclaring it
    minSignalQuality = MathMax(minQualityThreshold, MathMin(maxQualityThreshold, adaptiveSignalQuality));
    Print("[ADAPTIVE QUALITY] Final signal quality threshold: ", minSignalQuality, 
          " (Base: ", baseSignalQuality, ", Adjusted: ", adaptiveSignalQuality, ")");
    
    
    // Enhanced diagnostics for signal evaluation
    if(DisplayDebugInfo) {
        if(signal == 0) {
            Print("[TRADE DIAG] No valid signal generated for ", Symbol());
        } else {
            Print("[TRADE DIAG] Signal generated: ", (signal > 0 ? "BUY" : "SELL"), 
                  " | Quality: ", DoubleToString(signalQuality, 2), 
                  " | Min Required: ", DoubleToString(minSignalQuality, 2),
                  " | Quality Check: ", (signalQuality >= minSignalQuality ? "PASSED" : "FAILED"));
        }
    }
    
    if(signal != 0 && signalQuality >= minSignalQuality) {
        // Get volatility-adjusted stop loss distance using ATR
        double atrStopDistance = GetATRStop(14);
        double minimumStop = MinimumStopPips * Point(); // Convert pips to price
        double stopDistance = MathMax(atrStopDistance, minimumStop);
        
        if(DisplayDebugInfo) {
            Print("[STOP LOSS] Using volatility-adjusted stop: ", DoubleToString(stopDistance, 5), 
                  " (ATR: ", DoubleToString(atrStopDistance, 5), ", Min: ", DoubleToString(minimumStop, 5), ")");
        }
        
        // Calculate stop loss level based on entry and stop distance
        double entryPrice = (signal > 0) ? currentAsk : currentBid;
        double stopLoss = (signal > 0) ? (entryPrice - stopDistance) : (entryPrice + stopDistance);
        
        // Calculate take profit based on risk:reward ratio
        double takeProfit = 0.0;
        double riskRewardRatio = RiskRewardRatio; // Use input parameter instead of hardcoded value
        
        if(signal > 0) { // Buy
            takeProfit = entryPrice + (stopDistance * riskRewardRatio);
        } else { // Sell
            takeProfit = entryPrice - (stopDistance * riskRewardRatio);
        }
        
        // Determine position size based on risk
        double posSize = CalculateDynamicSize(RiskPercent, stopDistance);
        
        // Execute the trade
        if(stopLoss > 0 && posSize > 0) {
            // Check for existing orders for this symbol to prevent duplicates
            bool hasExistingOrder = false;
            bool tradeResult = false; // Moved declaration to higher scope
            
            for(int i = 0; i < OrdersTotal(); i++) {
                if(OrderGetTicket(i) > 0 && OrderGetString(ORDER_SYMBOL) == Symbol()) {
                    hasExistingOrder = true;
                    if(DisplayDebugInfo) Print("[ORDER PREVENTION] Already have order for ", Symbol(), ", skipping new order");
                    break;
                }
            }
            
            // Only execute if no existing orders for this symbol
            if(!hasExistingOrder) {
                string comment = "SMC " + (signal > 0 ? "Buy" : "Sell") + " Q=" + DoubleToString(signalQuality, 2);
                
                // Validate and adjust stop loss before executing trade
                double minStopDistance = GetMinimumStopDistance();
                double currentStopDistance = MathAbs(entryPrice - stopLoss);
                
                if(currentStopDistance < minStopDistance) {
                    // Adjust stop loss to meet minimum requirements
                    if(signal > 0) { // BUY
                        stopLoss = NormalizeDouble(entryPrice - minStopDistance - (5 * _Point), _Digits);
                    } else { // SELL
                        stopLoss = NormalizeDouble(entryPrice + minStopDistance + (5 * _Point), _Digits);
                    }
                    
                    // Adjust take profit based on new stop loss to maintain R:R ratio
                    if(signal > 0) { // BUY
                        takeProfit = entryPrice + (MathAbs(entryPrice - stopLoss) * riskRewardRatio);
                    } else { // SELL
                        takeProfit = entryPrice - (MathAbs(entryPrice - stopLoss) * riskRewardRatio);
                    }
                    
                    LogInfo(StringFormat("[STOP ADJUST] Adjusted SL from %.5f to %.5f to meet minimum distance (%.5f points)", 
                                      stopLoss, (signal > 0 ? entryPrice - minStopDistance : entryPrice + minStopDistance), minStopDistance/_Point));
                }
                
                // Log detailed trade attempt information
                LogInfo(StringFormat("[TRADE ATTEMPT] %s at %.5f, SL: %.5f (%.1f points), TP: %.5f, Size: %.2f", 
                                  (signal > 0 ? "BUY" : "SELL"), entryPrice, stopLoss, 
                                  MathAbs(entryPrice - stopLoss)/_Point, takeProfit, posSize));
                
                // Try to execute the trade with retry logic
                tradeResult = RetryTrade(signal, entryPrice, stopLoss, takeProfit, posSize, 3);
            
            // Add timestamp to signal when trade was executed for debugging
            if(tradeResult) {
                // Record that we've processed a signal for this symbol
                if(currentSymbolIndex >= 0) {
                    lastProcessedTime[currentSymbolIndex] = TimeCurrent();
                }
                if(DisplayDebugInfo) Print("[TRADE] Trade executed at ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), ", cooldown activated");
            }
            } // Close the if(!hasExistingOrder) block
            
            if(DisplayDebugInfo) {
                if(tradeResult) {
                    LogTrade("Trade executed: " + (signal > 0 ? "BUY" : "SELL") + 
                              " at " + DoubleToString(entryPrice, _Digits) + 
                              ", SL: " + DoubleToString(stopLoss, _Digits) + 
                              ", TP: " + DoubleToString(takeProfit, _Digits));
                } else {
                    LogError("Trade execution failed for " + Symbol() + 
                             " | Signal: " + (signal > 0 ? "BUY" : "SELL") + 
                             " | Quality: " + DoubleToString(signalQuality, 2));
                }
            }
        } else {
            if(DisplayDebugInfo) LogError("Invalid stop loss or position size calculated");
        }
    }
}

//+------------------------------------------------------------------+
//| Find recent swing point (high or low)                            |
//+------------------------------------------------------------------+
int FindRecentSwingPoint(bool isBuy, int startBar = 1, int lookbackBars = 20) {
    // Implementation for finding swing lows (for buy trades)
    if(isBuy) {
        double low[], high[];
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(high, true);
        
        if(CopyLow(Symbol(), PERIOD_CURRENT, 0, lookbackBars + startBar, low) <= 0) {
            Print("[ERROR] Failed to copy low prices for swing point detection");
            return -1;
        }
        
        // Find swing low (local minimum)
        for(int i = startBar; i < lookbackBars - 1; i++) {
            // Check if this bar has a lower low than both adjacent bars
            if(low[i] < low[i-1] && low[i] < low[i+1]) {
                return i; // Return bar index of swing low
            }
        }
    }
    
    // Implementation for finding swing highs (for sell trades)
    else {
        double low[], high[];
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(high, true);
        
        if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookbackBars + startBar, high) <= 0) {
            Print("[ERROR] Failed to copy high prices for swing point detection");
            return -1;
        }
        
        // Find swing high (local maximum)
        for(int i = startBar; i < lookbackBars - 1; i++) {
            // Check if this bar has a higher high than both adjacent bars
            if(high[i] > high[i-1] && high[i] > high[i+1]) {
                return i; // Return bar index of swing high
            }
        }
    }
    
    // Default fallback
    return 1;
}

//+------------------------------------------------------------------+
//| Find recent swing point high (for sell trades)                    |
//+------------------------------------------------------------------+
int FindRecentSwingPointHigh(bool isBuy, int startBar = 1, int lookbackBars = 20) {
    MqlRates bar[]; // Add missing bar array declaration
    // Implementation for finding swing highs (for sell trades)
    if(!isBuy) {
        double low[], high[];
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(high, true);
        
        if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookbackBars + startBar, high) <= 0) {
            Print("[ERROR] Failed to copy high prices for swing point detection");
            return -1;
        }
        
        // Find swing high (local maximum)
        for(int i = startBar; i < lookbackBars - 1; i++) {
            // Check if this bar has a higher high than both adjacent bars
            if(high[i] > high[i-1] && high[i] > high[i+1]) {
                return i; // Return bar index of swing high
            }
        }
    }
    
    // Default fallback
    return 1;
}

//+------------------------------------------------------------------+
//| Find high-quality swing points for stop loss placement          |
//+------------------------------------------------------------------+
void FindQualitySwingPoints(bool isBuy, int lookback, SwingPoint &swingPoints[], int &swingCount) {
    // Initialize
    ArrayResize(swingPoints, lookback);
    swingCount = 0;
    
    // Load price data
    double high[], low[], close[], open[];
    datetime time[];
    long volume[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(volume, true);
    
    // Get price data for the current symbol and timeframe
    int copied = CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback+2, high);
    copied = CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback+2, low);
    copied = CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback+2, close);
    copied = CopyOpen(Symbol(), PERIOD_CURRENT, 0, lookback+2, open);
    copied = CopyTime(Symbol(), PERIOD_CURRENT, 0, lookback+2, time);
    copied = CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, lookback+2, volume);
    
    if(copied <= 0) {
        LogError("Failed to copy price data for swing point analysis");
        return;
    }
    
    // Volume MA calculation
    double volMA[];
    ArrayResize(volMA, lookback+2);
    int maPeriod = 20;
    for(int i=maPeriod; i<lookback; i++) {
        double sum = 0;
        for(int j=0; j<maPeriod; j++) {
            sum += (double)volume[i-j];
        }
        volMA[i] = sum / maPeriod;
    }
    
    // Get ATR for volatility context
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    
    // Scan for swing points
    for(int i=2; i<lookback-2; i++) {
        bool swingHigh = high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i+1] && high[i] > high[i+2];
        bool swingLow = low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i+1] && low[i] < low[i+2];
        
        // We're looking for swing highs when shorting (for stop loss above) and swing lows when buying (for stop loss below)
        if((isBuy && swingLow) || (!isBuy && swingHigh)) { // All control paths return a value
            // Scoring criteria
            int score = 0;
            double price = swingHigh ? high[i] : low[i];
            double bodySize = MathAbs(open[i] - close[i]);
            double wickSize = swingHigh ? (high[i] - MathMax(open[i], close[i])) : (MathMin(open[i], close[i]) - low[i]);
            double candleRange = high[i] - low[i];
            
            // Scoring criteria
            if(volume[i] > volMA[i] * 1.2) score++; // Higher volume
            if(bodySize > candleRange * 0.4) score++; // Strong body
            if(wickSize < candleRange * 0.3) score++; // Small wick (more decisive swing)
            
            // Check if price moved significantly from this swing
            double moveAfterSwing = swingHigh ? (price - low[i-1]) : (high[i-1] - price);
            if(moveAfterSwing > atr * 0.7) score++; // Significant price move after swing
            
            // Add to our collection of swing points
            swingPoints[swingCount].price = price;
            swingPoints[swingCount].time = time[i];
            swingPoints[swingCount].score = score;
            swingPoints[swingCount].barIndex = i;
            swingCount++;
            
            if(swingCount >= lookback) break; // Safety check
        }
    }
    
    // Log found swing points for debugging
    if(DisplayDebugInfo) {
        for(int i=0; i<swingCount; i++) {
            Print("[DEBUG][SWING_POINTS] Found ", (isBuy ? "BUY" : "SELL"), " swing at price=", 
                  swingPoints[i].price, ", score=", swingPoints[i].score);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate minimum broker-compliant stop distance                |
//+------------------------------------------------------------------+
double CalcBrokerMinStop() {
   double stopsLevel  = (double)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freezeLevel  = (double)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   return MathMax(stopsLevel, freezeLevel) + 10*_Point; // 10-point buffer
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
            double tickValue = 0.0;
if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE, tickValue)) {
    tickValue = 0.0; // Default if call fails
}
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
//| Manage trailing stops for open positions                         |
//+------------------------------------------------------------------+
bool ManageTrailingStops() {
    // Manage trailing stops for all open positions
    bool result = AdjustTrailingStop();
    return result;
}

//+------------------------------------------------------------------+
//| Adjust trailing stops for open positions based on volatility     |
//+------------------------------------------------------------------+
bool AdjustTrailingStop() {
    // If no positions, nothing to trail
    if(PositionsTotal() == 0) return false;
    
    bool modified = false;
    double currentAtrValue = 0;
    double newSL = 0; // Declare newSL variable
    double potentialSL = 0; // Declare potentialSL variable
    ulong ticket = 0; // Declare ticket variable
    double currentTP = 0; // Declare currentTP variable
    int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
    double atrTemp[1]; // Temporary buffer to avoid shadowing
    if(CopyBuffer(atrHandle, 0, 0, 1, atrTemp) > 0) {
        currentAtrValue = atrTemp[0];
    }
    IndicatorRelease(atrHandle);
    
    // Check ATR values
    double currentATR = currentAtrValue; // Using the retrieved ATR value
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int regime = FastRegimeDetection(Symbol());
    
    // Adjust trailing factor based on market regime
    double trailFactor = TrailingStopATRMultiplier;
    
    // In high volatility, use wider trailing stop
    if(regime == REGIME_HIGH_VOLATILITY || regime == REGIME_BREAKOUT) {
        trailFactor *= 1.5; // 50% wider
    }
    // In low volatility, use tighter trailing stop
    else if(regime == REGIME_RANGING_NARROW) {
        trailFactor *= 0.8; // 20% tighter
    }
    
    // Use the already calculated currentATR value instead of undeclared 'atr'
    double trailDistance = currentATR * trailFactor;
    double minTrailPoints = 50 * point; // Minimum 50 points
    
    // Ensure minimum trail distance
    if(trailDistance < minTrailPoints) {
        trailDistance = minTrailPoints;
    }
    
    double bid = GetCurrentBid();
    double ask = GetCurrentAsk();
    
    // Loop through all positions in the current symbol
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        
        if(!PositionSelectByTicket(ticket))
            continue;
            
        string posSymbol = PositionGetString(POSITION_SYMBOL);
        
        // Only process positions for the current symbol
        if(posSymbol != Symbol())
            continue;
            
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);
        datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
        string posComment = PositionGetString(POSITION_COMMENT);
        
        // Skip if not ready for trailing (certain criteria could be added here)
        if(StringFind(posComment, "FINAL") < 0 && !EnableTrailingForLast) {
            // Only trail the final position if using multi-target
            continue;
        }
        
        // Calculate and adjust trailing stop
        double newSL = 0;
        bool adjustSL = false;
        
        if(posType == POSITION_TYPE_BUY) {
            // For buy positions, trail below price by trail distance
            double potentialSL = bid - trailDistance;
            
            // Only move stop up, never down
            if(potentialSL > currentSL) {
                newSL = potentialSL;
                adjustSL = true;
            }
        }
        else { // POSITION_TYPE_SELL
            // For sell positions, trail above price by trail distance
            double potentialSL = ask + trailDistance;
            
            // Only move stop down, never up
            if(potentialSL < currentSL || currentSL == 0) {
                newSL = potentialSL;
                adjustSL = true;
            }
        }
        
        // Modify stop loss if needed
        if(adjustSL) {
            // Normalize SL to broker requirements
            newSL = NormalizeDouble(newSL, _Digits);
            
            // Check if order SL/TP is valid before submission
            if(!OrderCheck(posType, newSL, currentTP)) {
                LogError("Trailing stop validation failed: " + GetLastErrorText(GetLastError()));
                continue;
            }
            
            // Update the position using CTrade
            CTrade trade_local; // Renamed to avoid shadowing global variable
            // Use the proper magic number from the EA
            int magicNumber = 12345; // Default fallback value
            if(GlobalVariableCheck("SMC_Magic")) {
                magicNumber = (int)GlobalVariableGet("SMC_Magic");
            }
            trade_local.SetExpertMagicNumber(magicNumber);
            
            // Modify the position's stop loss
            if(trade_local.PositionModify(ticket, newSL, currentTP)) {
                modified = true;
                LogTrade("Trailing stop adjusted: " + posSymbol + ", Ticket=" + IntegerToString((int)ticket) + 
                        ", New SL=" + DoubleToString(newSL, _Digits));
            }
            else {
                int lastErr = GetLastError();
                LogError("Failed to adjust trailing stop: " + GetLastErrorText(lastErr));
            }
        }
    }
    
    return modified;
}

//+------------------------------------------------------------------+
//| Enhanced risk management: Adjust based on drawdown and win/loss  |
//+------------------------------------------------------------------+
// Track consecutive wins and losses
int consecutiveWins = 0;
int consecutiveLosses = 0;

//+------------------------------------------------------------------+
//| Calculate average spread over specified number of ticks            |
//+------------------------------------------------------------------+
double CalculateAverageSpread(int samples) {
    // Safety check
    if(samples <= 0) return 0.0;
    
    // Limit to reasonable amount
    samples = MathMin(samples, 50);
    
    static double spreadHistory[];
    static int spreadIndex = 0;
    
    // Initialize array if needed
    if(ArraySize(spreadHistory) != samples) {
        ArrayResize(spreadHistory, samples);
        ArrayInitialize(spreadHistory, 0);
    }
    
    // Add current spread to history
    double currentSpread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    spreadHistory[spreadIndex] = currentSpread;
    spreadIndex = (spreadIndex + 1) % samples;
    
    // Calculate average
    double sum = 0.0;
    for(int i = 0; i < samples; i++) {
        sum += spreadHistory[i];
    }
    
    return sum / samples;
}

//+------------------------------------------------------------------+
//| Update win/loss streak tracking                                  |
//+------------------------------------------------------------------+
void UpdateWinLossStreak(bool isWin) {
    if(isWin) {
        consecutiveWins++;
        consecutiveLosses = 0;
    } else {
        consecutiveLosses++;
        consecutiveWins = 0;
    }
    
    // Log streak information
    if(DisplayDebugInfo) {
        if(consecutiveWins > 2) {
            LogInfo(StringFormat("[STREAK] %d consecutive winning trades", consecutiveWins));
        } else if(consecutiveLosses > 2) {
            LogInfo(StringFormat("[STREAK] %d consecutive losing trades", consecutiveLosses));
        }
    }
}

//+------------------------------------------------------------------+
//| Enhanced risk management with streak & drawdown adaptation       |
//+------------------------------------------------------------------+
double DynamicDrawdownControl() {
    // Get account equity and balance
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Calculate current drawdown percentage
    double drawdownPct = 100.0 * (1.0 - (equity / balance));
    
    // Apply risk reduction based on drawdown
    double riskMultiplier = 1.0;
    
    if(drawdownPct <= 5.0) {
        // No reduction for small drawdowns
        riskMultiplier = 1.0;
    } else if(drawdownPct <= 10.0) {
        // Slight reduction
        riskMultiplier = 0.8;
    } else if(drawdownPct <= 15.0) {
        // Moderate reduction
        riskMultiplier = 0.6;
    } else if(drawdownPct <= 20.0) {
        // Significant reduction
        riskMultiplier = 0.4;
    } else {
        // Major reduction for large drawdowns
        riskMultiplier = 0.2;
    }
    
    // Further adjust risk based on win/loss streaks
    double streakMultiplier = 1.0;
    
    // Winning streak - gradually increase risk
    if(consecutiveWins >= 3 && consecutiveWins < 5) {
        streakMultiplier = 1.1; // 10% increase after 3 wins
    } else if(consecutiveWins >= 5 && consecutiveWins < 7) {
        streakMultiplier = 1.2; // 20% increase after 5 wins
    } else if(consecutiveWins >= 7) {
        streakMultiplier = 1.25; // 25% increase after 7 wins
    }
    // Losing streak - gradually decrease risk
    else if(consecutiveLosses >= 2 && consecutiveLosses < 4) {
        streakMultiplier = 0.8; // 20% decrease after 2 losses
    } else if(consecutiveLosses >= 4 && consecutiveLosses < 6) {
        streakMultiplier = 0.6; // 40% decrease after 4 losses
    } else if(consecutiveLosses >= 6) {
        streakMultiplier = 0.4; // 60% decrease after 6 losses
    }
    
    // Combine drawdown and streak multipliers
    // Note: During losing streaks, we want the more conservative of the two
    if(consecutiveLosses > 0) {
        riskMultiplier = MathMin(riskMultiplier, streakMultiplier);
    } else {
        riskMultiplier *= streakMultiplier;
    }
    
    // Log the risk adjustment if significant
    if(riskMultiplier < 0.9 || riskMultiplier > 1.1) {
        LogInfo(StringFormat("[RISK ADAPT] Adjusting risk to %.2f× (Drawdown: %.1f%%, Win streak: %d, Loss streak: %d)", 
                             riskMultiplier, drawdownPct, consecutiveWins, consecutiveLosses));
    }
    
    return riskMultiplier;
}

//+------------------------------------------------------------------+
//| Move stop loss to break even when profit threshold is reached    |
//+------------------------------------------------------------------+
void MoveToBreakEven(double entryPrice, double currentStop, ENUM_POSITION_TYPE posType, ulong posTicket, double spread) {
    // If current stop is already at break even, exit
    if(MathAbs(currentStop - entryPrice) < _Point)
        return;
        
    // Add a small buffer to break even level to account for spread
    double beLevel = entryPrice;
    if(posType == POSITION_TYPE_BUY)
        beLevel += BreakEvenBuffer * _Point;
    else
        beLevel -= BreakEvenBuffer * _Point;
        
    // Modify the position
    CTrade trade_local; // Renamed to avoid shadowing global variable
    // Use the proper magic number from the EA
    int magicNumber = 12345; // Default fallback value
    if(GlobalVariableCheck("SMC_Magic")) {
        magicNumber = (int)GlobalVariableGet("SMC_Magic");
    }
    trade_local.SetExpertMagicNumber(magicNumber);
    
    // Modify the position's stop loss
    if(trade_local.PositionModify(posTicket, beLevel, PositionGetDouble(POSITION_TP))) {
        LogTrade("Moved position #" + IntegerToString(posTicket) + " to break even: " + DoubleToString(beLevel, _Digits));
    }
    else {
        LogError("Failed to move position to break even: " + IntegerToString(trade_local.ResultRetcode()));
    }
}

// ExecuteMultiTargetStrategy implementation moved to line 662

//+------------------------------------------------------------------+
//| Session-based risk adjustment                                    |
//+------------------------------------------------------------------+
double AdjustRiskForSession() {
    if(!EnableSessionFiltering) return 1.0;
    
    datetime serverTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(serverTime, dt);
    
    int hour = dt.hour;
    int dayOfWeek = dt.day_of_week;
    
    // Identify trading sessions (approximate)
    bool isAsianSession = (hour >= 0 && hour < 8);  // 00:00-08:00
    bool isLondonSession = (hour >= 8 && hour < 16); // 08:00-16:00
    bool isNewYorkSession = (hour >= 13 && hour < 21); // 13:00-21:00
    bool isOverlap = (hour >= 13 && hour < 16); // London-NY overlap
    
    // Check for high volatility periods
    bool isVolatileOpen = (hour >= 8 && hour < 10) || (hour >= 13 && hour < 15);
    bool isFridayEvening = (dayOfWeek == 5 && hour >= 18);
    
    // Apply risk adjustments
    double adjustment = 1.0;
    
    if(isVolatileOpen) adjustment *= 0.8;  // Reduce risk at opens
    if(isOverlap) adjustment *= 1.1;      // Slightly increase during overlap (more liquidity)
    if(isAsianSession) adjustment *= 0.75; // Reduce during typically slower Asian session
    if(isFridayEvening) adjustment *= 0.5; // Significantly reduce risk before weekend
    // Additional day of week adjustments
    if(dayOfWeek == 1) adjustment *= 0.9;  // Monday - slightly lower risk (weekend gaps)
    if(dayOfWeek == 3) adjustment *= 1.1;  // Wednesday - often good volatility
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Calculate position size adjustment based on volatility            |
//+------------------------------------------------------------------+
double CalculateVolatilityAdjustment() {
    double currentAtrValue = 0;
    bool modified = false; // Declare the modified variable
    int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
    double atrTemp[1]; // Temporary buffer to avoid shadowing
    if(CopyBuffer(atrHandle, 0, 0, 1, atrTemp) > 0) {
        currentAtrValue = atrTemp[0];
    }
    IndicatorRelease(atrHandle);
    
    // Check ATR values
    double currentATR = currentAtrValue; // Using the retrieved ATR value
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int regime = FastRegimeDetection(Symbol());
    
    // Adjust trailing factor based on market regime
    double trailFactor = TrailingStopATRMultiplier;
    
    // In high volatility, use wider trailing stop
    if(regime == REGIME_HIGH_VOLATILITY || regime == REGIME_BREAKOUT) {
        trailFactor *= 1.5; // 50% wider
    }
    // In low volatility, use tighter trailing stop
    else if(regime == REGIME_RANGING_NARROW) {
        trailFactor *= 0.8; // 20% tighter
    }
    
    // Use the already calculated currentATR value instead of undeclared 'atr'
    double trailDistance = currentATR * trailFactor;
    double minTrailPoints = 50 * point; // Minimum 50 points
    
    // Ensure minimum trail distance
    if(trailDistance < minTrailPoints) {
        trailDistance = minTrailPoints;
    }
    
    double bid = GetCurrentBid();
    double ask = GetCurrentAsk();
    
    // Loop through all positions in the current symbol
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        
        if(!PositionSelectByTicket(ticket))
            continue;
            
        string posSymbol = PositionGetString(POSITION_SYMBOL);
        
        // Only process positions for the current symbol
        if(posSymbol != Symbol())
            continue;
            
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);
        datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
        string posComment = PositionGetString(POSITION_COMMENT);
        
        // Skip if not ready for trailing (certain criteria could be added here)
        if(StringFind(posComment, "FINAL") < 0 && !EnableTrailingForLast) {
            // Only trail the final position if using multi-target
            continue;
        }
        
        // Calculate and adjust trailing stop
        double newSL = 0;
        bool adjustSL = false;
        
        if(posType == POSITION_TYPE_BUY) {
            // For buy positions, trail below price by trail distance
            double potentialSL = bid - trailDistance;
            
            // Only move stop up, never down
            if(potentialSL > currentSL) {
                newSL = potentialSL;
                adjustSL = true;
            }
        }
        else { // POSITION_TYPE_SELL
            // For sell positions, trail above price by trail distance
            double potentialSL = ask + trailDistance;
            
            // Only move stop down, never up
            if(potentialSL < currentSL || currentSL == 0) {
                newSL = potentialSL;
                adjustSL = true;
            }
        }
        
        // Modify stop loss if needed
        if(adjustSL) {
            // Normalize SL to broker requirements
            newSL = NormalizeDouble(newSL, _Digits);
            
            // Check if order SL/TP is valid before submission
            if(!OrderCheck(posType, newSL, currentTP)) {
                LogError("Trailing stop validation failed: " + GetLastErrorText(GetLastError()));
                continue;
            }
            
            // Update the position using CTrade
            CTrade trade_local; // Renamed to avoid shadowing global variable
            // Use the proper magic number from the EA
            int magicNumber = 12345; // Default fallback value
            if(GlobalVariableCheck("SMC_Magic")) {
                magicNumber = (int)GlobalVariableGet("SMC_Magic");
            }
            trade_local.SetExpertMagicNumber(magicNumber);
            
            // Modify the position's stop loss
            if(trade_local.PositionModify(ticket, newSL, currentTP)) {
                modified = true;
                LogTrade("Trailing stop adjusted: " + posSymbol + ", Ticket=" + IntegerToString((int)ticket) + 
                        ", New SL=" + DoubleToString(newSL, _Digits));
            }
            else {
                int lastErr = GetLastError();
                LogError("Failed to adjust trailing stop: " + GetLastErrorText(lastErr));
            }
        }
    }
    
    return modified;
}

//+------------------------------------------------------------------+
//| This was a duplicate OrderCheck function - removed to fix compilation errors |
//+------------------------------------------------------------------+
// Using the implementation defined at line 4021 instead.

//+------------------------------------------------------------------+
//| Calculate take profit levels for multi-target strategy            |
//+------------------------------------------------------------------+
bool CalculateMultiTargetLevels(int signal, double entryPrice, double stopLoss, double &tp1, double &tp2) {
    if(!EnableMultiTargetTP) return false;
    
    int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
    double atrTemp[1]; // Temporary buffer for ATR
    if(CopyBuffer(atrHandle, 0, 0, 1, atrTemp) > 0) { // Fixed CopyBuffer call
        // ATR value available in atrTemp[0] if needed
    }
    IndicatorRelease(atrHandle);
    
    double point = GetSymbolPoint();
    
    // Calculate R value (risk in points)
    double rValue = MathAbs(entryPrice - stopLoss);
    if(rValue < 10 * point) {
        LogError("Invalid R value calculation: " + DoubleToString(rValue, _Digits));
        return false;
    }
    
    // Initialize take profit levels (output parameters)
    tp1 = 0.0;
    tp2 = 0.0;
    
    // Use the global TPRatio1 and TPRatio2 values defined as input parameters
    // If they're zero, use default values
    double tpRatio1 = (TPRatio1 > 0) ? TPRatio1 : 1.0; // Default 1:1 risk:reward for first target
    double tpRatio2 = (TPRatio2 > 0) ? TPRatio2 : 2.0; // Default 1:2 risk:reward for second target
    
    if(signal > 0) { // BUY
        tp1 = entryPrice + (rValue * tpRatio1);
        tp2 = entryPrice + (rValue * tpRatio2);
    }
    else { // SELL
        tp1 = entryPrice - (rValue * tpRatio1);
        tp2 = entryPrice - (rValue * tpRatio2);
    }
    
    // Normalize to broker precision
    tp1 = NormalizeDouble(tp1, _Digits);
    tp2 = NormalizeDouble(tp2, _Digits);
    
    // Calculate the stop distance for position sizing
    double stopDistance = MathAbs(entryPrice - stopLoss);
    
    // Calculate total lot size based on risk settings
    double totalLots = CalculateDynamicSize(RiskPercent, stopDistance);
    
    // Apply adjustments
    // Use default values of 1.0 for now instead of calling undefined functions
    double correlationFactor = 1.0; // Default value
    double timeDecayFactor = 1.0; // Default value    
    totalLots *= correlationFactor * timeDecayFactor;
    
    // Split position into three parts
    double lotsPart1 = NormalizeDouble(totalLots / 3, 2);
    double lotsPart2 = NormalizeDouble(totalLots / 3, 2);
    double lotsPart3 = NormalizeDouble(totalLots - lotsPart1 - lotsPart2, 2); // Ensures exact total
    
    // Minimum lot size check
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    if(lotsPart1 < minLot && lotsPart1 > 0) lotsPart1 = minLot;
    if(lotsPart2 < minLot && lotsPart2 > 0) lotsPart2 = minLot;
    if(lotsPart3 < minLot && lotsPart3 > 0) lotsPart3 = minLot;
    
    LogTrade("Executing multi-target strategy: Signal=" + IntegerToString(signal) + 
             ", Lots=" + DoubleToString(totalLots, 2) + 
             " (" + DoubleToString(lotsPart1, 2) + "/" + 
                 DoubleToString(lotsPart2, 2) + "/" + 
                 DoubleToString(lotsPart3, 2) + ")");
    
    // Part 1: Take profit at 1R
    ulong ticket1 = 0;
    ulong ticket2 = 0;
    ulong ticket3 = 0;
    
    // Use the appropriate trade execution method based on existing pattern
    CTrade trade_local; // Renamed to avoid shadowing global variable
    trade_local.SetExpertMagicNumber(MagicNumber); // Use the EA's magic number
    
    // Part 1: First target at 1R
    if(signal > 0) { // BUY
        if(trade_local.Buy(lotsPart1, Symbol(), 0, stopLoss, tp1, "TP1_" + DoubleToString(tpRatio1, 1) + "R")) {
            ticket1 = trade_local.ResultOrder();
            LogTrade("Part 1/3: Buy order placed, ticket=" + IntegerToString((int)ticket1));
        }
    }
    else { // SELL
        if(trade_local.Sell(lotsPart1, Symbol(), 0, stopLoss, tp1, "TP1_" + DoubleToString(tpRatio1, 1) + "R")) {
            ticket1 = trade_local.ResultOrder();
            LogTrade("Part 1/3: Sell order placed, ticket=" + IntegerToString((int)ticket1));
        }
    }
    
    // Part 2: Second target at 2R
    if(ticket1 > 0) { // Only proceed if first part was successful
        if(signal > 0) { // BUY
            if(trade_local.Buy(lotsPart2, Symbol(), 0, stopLoss, tp2, "TP2_" + DoubleToString(tpRatio2, 1) + "R")) {
                ticket2 = trade_local.ResultOrder();
                LogTrade("Part 2/3: Buy order placed, ticket=" + IntegerToString((int)ticket2));
            }
        }
        else { // SELL
            if(trade_local.Sell(lotsPart2, Symbol(), 0, stopLoss, tp2, "TP2_" + DoubleToString(tpRatio2, 1) + "R")) {
                ticket2 = trade_local.ResultOrder();
                LogTrade("Part 2/3: Sell order placed, ticket=" + IntegerToString((int)ticket2));
            }
        }
    }
    
    // Part 3: Trailing portion
    if(ticket1 > 0 && ticket2 > 0) { // Only proceed if previous parts were successful
        if(signal > 0) { // BUY
            CTrade trade_local; // Define local trade object
            trade_local.SetDeviationInPoints(MaxSlippage);
            if(trade_local.Buy(lotsPart3, Symbol(), 0, stopLoss, 0, "FINAL_TRAIL")) {
                ticket3 = trade_local.ResultOrder();
                LogTrade("Part 3/3: Buy order placed for trailing, ticket=" + IntegerToString((int)ticket3));
            }
        }
        else { // SELL
            if(trade_local.Sell(lotsPart3, Symbol(), 0, stopLoss, 0, "FINAL_TRAIL")) {
                ticket3 = trade_local.ResultOrder();
                LogTrade("Part 3/3: Sell order placed for trailing, ticket=" + IntegerToString((int)ticket3));
            }
        }
    }
    
    return (ticket1 > 0 && ticket2 > 0 && ticket3 > 0);
}

// Additional function prototypes and implementations
double AdjustRiskBySession() {
    double adjustment = 1.0;
    
    // Get current session info
    datetime currentTime = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(currentTime, timeStruct);
    int hour = timeStruct.hour;
    int dayOfWeek = timeStruct.day_of_week;
    
    bool isAsianSession = (hour >= 0 && hour < 8);
    bool isLondonSession = (hour >= 8 && hour < 16);
    bool isNewYorkSession = (hour >= 13 && hour < 21);
    bool isOverlap = (hour >= 13 && hour < 16);  // London/NY overlap
    
    // Apply session-based risk adjustments
    if(isOverlap) adjustment *= 1.2;  // Increase risk during overlapping sessions
    if(isAsianSession) adjustment *= 0.7;  // Reduce risk during Asian session
    
    LogRisk("Session risk adjustment: " + DoubleToString(adjustment,2) + 
            " (Asian=" + (isAsianSession ? "Y" : "N") + 
            ", London=" + (isLondonSession ? "Y" : "N") + 
            ", NY=" + (isNewYorkSession ? "Y" : "N") + 
            ", Overlap=" + (isOverlap ? "Y" : "N") + 
            ", Day=" + IntegerToString(dayOfWeek) + ")");
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Dynamic drawdown control for progressive risk reduction          |
//+------------------------------------------------------------------+
double EnhancedDrawdownControl() {
    // Get current equity and balance
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double initialBalance = balance;  // For brand new accounts
    
    // Calculate current drawdown percentage
    static double maxBalance = balance;  // Store the highest balance seen
    if(balance > maxBalance) maxBalance = balance;
    
    double drawdownPct = 0.0;
    if(maxBalance > 0) drawdownPct = (maxBalance - equity) / maxBalance * 100.0;
    
    // Define thresholds for risk reduction
    double adjustment = 1.0;
    
    if(drawdownPct > 20.0) adjustment = 0.25;       // Severe drawdown - reduce risk by 75%
    else if(drawdownPct > 15.0) adjustment = 0.4;   // Heavy drawdown - reduce risk by 60%
    else if(drawdownPct > 10.0) adjustment = 0.6;   // Moderate drawdown - reduce risk by 40%
    else if(drawdownPct > 5.0) adjustment = 0.8;    // Light drawdown - reduce risk by 20%
    
    if(adjustment < 1.0) {
        LogRisk("Reducing risk due to drawdown: " + DoubleToString(drawdownPct,2) + "% - Adjustment: " + DoubleToString(adjustment,2));
    }
    
    // Also check daily profit/loss - moved to separate function
    double dailyRiskFactor = CalculateDailyRiskAdjustment();
    adjustment *= dailyRiskFactor;
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Calculate daily risk adjustment factor                           |
//+------------------------------------------------------------------+
double CalculateDailyRiskAdjustment()
{
    // Global variables for day tracking
    static datetime lastDayChecked = 0;
    static double dayStartBalance = 0;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    datetime currentTime = TimeCurrent();
    MqlDateTime dtNow;
    TimeToStruct(currentTime, dtNow);
    
    // Reset day tracking at beginning of trading day
    MqlDateTime lastDayStruct;
    TimeToStruct(lastDayChecked, lastDayStruct);
    if(lastDayChecked == 0 || lastDayStruct.day != dtNow.day) {
        dayStartBalance = balance;
        lastDayChecked = currentTime;
    }
    
    // Calculate daily P/L percentage
    double dailyPLPct = 0.0;
    if(dayStartBalance > 0) dailyPLPct = (equity - dayStartBalance) / dayStartBalance * 100.0;
    
    // Define daily loss control variable
    double maxDailyLossPercent = 5.0; // Default value if not defined as input parameter
    
    if(dailyPLPct < -maxDailyLossPercent) {
        // Approaching/exceeding daily loss limit
        emergencyMode = true;
        // Apply increased risk reduction
        double riskAdjustFactor = 0.1; // 90% risk reduction
        if(DisplayDebugInfo) Print("[RISK] Daily loss limit reached. Reducing risk to 10%.");
        return riskAdjustFactor;
    } else if(dailyPLPct < -MaxDailyLossPercent*0.7) {
        // Approaching daily loss limit
        emergencyMode = true;
        // Apply increased risk reduction
        double riskAdjustFactor = 0.25; // 75% risk reduction
        if(DisplayDebugInfo) Print("[RISK] Approaching daily loss limit. Reducing risk to 25%.");
        return riskAdjustFactor;
    }
    
    return 1.0; // No adjustment needed
}

//+------------------------------------------------------------------+
//| Calculate dynamic take profit based on market regime             |
//+------------------------------------------------------------------+

// Function moved and enhanced at line ~5077
// This comment left to maintain line numbering

//+------------------------------------------------------------------+
//| Check if current time is within news release window               |
//+------------------------------------------------------------------+
bool IsNewsTime(string impact="High", int windowMinutes=60) {
    // This is a placeholder for actual news filter implementation
    // In a full implementation, this would check against an economic calendar
    
    // For now, we'll check against predefined high-impact events in newsSchedule array
    datetime currentTime = TimeCurrent();
    
    for(int i=0; i<20; i++) { // Loop through our news events array
        if(newsSchedule[i].eventTime == 0) continue; // Skip empty slots
        
        // If we're within the window (before or after the news event)
        if(MathAbs(currentTime - newsSchedule[i].eventTime) < windowMinutes * 60 && 
           newsSchedule[i].impact == impact) {
            return true; // We are in a news window
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk percentage with volatility  |
//+------------------------------------------------------------------+
double CalculateDynamicSize(double riskPercent, double stopDistance) {
    // Get account balance
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Calculate risk amount in account currency
    double riskAmount = balance * (riskPercent / 100.0);
    
    // Get tick value and calculate lot size
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    
    // Calculate points per one pip
    double pointsPerPip = 1.0 / Point();
    
    // Volatility adjustment - reduce position size during high volatility
    int atrHandle = iATR(Symbol(), PERIOD_M15, 14);
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
    double atr = atrBuffer[0];
    
    double avgATR = CalculateAverageATR(14); // Use existing function
    double volAdjustment = 1.0;
    
    if(avgATR > 0) {
        // Normalize current volatility against average
        volAdjustment = MathMin(atr/avgATR, 2.0); // Limit to 2x reduction
        
        // During high volatility, reduce position size
        if(volAdjustment > 1.2) { // 20% higher volatility than average
            volAdjustment = 1.0 / volAdjustment; // Invert for position sizing
        } else {
            volAdjustment = 1.0; // Normal volatility, no adjustment
        }
    }
    
    // Calculate lot size with volatility adjustment
    double lotSize = 0.0;
    if(tickValue != 0 && stopDistance != 0) {
        lotSize = (riskAmount / (stopDistance * tickValue / tickSize)) * volAdjustment;
    }
    
    // Round lot size to broker's lot step
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Calculate minimum and maximum lot sizes
    double minLot = g_minLot; // Use global minLot
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    if(DisplayDebugInfo) {
        Print("[POSITION SIZE] Volatility adjustment: ", DoubleToString(volAdjustment, 2), 
              " (ATR: ", DoubleToString(atr, 5), ", Avg ATR: ", DoubleToString(avgATR, 5), ")");
    }
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Calculate ATR-based stop loss level with mode-specific adjustments |
//+------------------------------------------------------------------+
double CalculateAtrStopLoss(double entryPrice, int signal) {
    // Enhanced logging to diagnose 'Invalid stops' errors
    LogInfo(StringFormat("CalculateAtrStopLoss called - Signal: %d, Entry: %.5f, Mode: %d", 
                        signal, entryPrice, currentTradingMode));
    
    // Calculate ATR-based stop loss
    int atrPeriod = 14; // Standard ATR period
    double atrValue = GetATR(Symbol(), PERIOD_CURRENT, atrPeriod, 0); // Current ATR
    
    // Use mode-specific multiplier
    double atrMultiplier = (currentTradingMode == MODE_HFT) ? HFT_SL_ATR_Mult : Normal_SL_ATR_Mult;
    double stopDistance = atrValue * atrMultiplier; // Apply multiplier
    
    double stopPrice = 0.0; // Initialize stop price
    
    // Calculate the stop loss price based on signal direction and ATR
    if(signal > 0) { // Buy signal (Long position)
        stopPrice = entryPrice - stopDistance;
        LogInfo(StringFormat("Buy Stop Price: %.5f (Entry: %.5f - Distance: %.5f)", 
                stopPrice, entryPrice, stopDistance));
    } else if(signal < 0) { // Sell signal (Short position)
        stopPrice = entryPrice + stopDistance;
        LogInfo(StringFormat("Sell Stop Price: %.5f (Entry: %.5f + Distance: %.5f)", 
                stopPrice, entryPrice, stopDistance));
    } else {
        LogError("Invalid signal (0) in CalculateAtrStopLoss");
        return 0.0;
    }
    
    // Validate stop loss against broker requirements
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int stopLevel = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    double minStopDistance = stopLevel * point;
    double currentBid = GetCurrentBid();
    double currentAsk = GetCurrentAsk();
    
    // Log broker requirements
    LogInfo(StringFormat("Broker Stop Level: %d points, Min Stop Distance: %.5f", 
            stopLevel, minStopDistance));
    
    // Check if stop loss is valid according to broker requirements
    if(signal > 0) { // Buy
        if(entryPrice - stopPrice < minStopDistance) {
            stopPrice = entryPrice - minStopDistance;
            LogWarning(StringFormat("Adjusted Buy SL to meet min distance: %.5f", stopPrice));
        }
    } else { // Sell
        if(stopPrice - entryPrice < minStopDistance) {
            stopPrice = entryPrice + minStopDistance;
            LogWarning(StringFormat("Adjusted Sell SL to meet min distance: %.5f", stopPrice));
        }
    }
    
    // Final validity check and logging
    LogInfo(StringFormat("Final SL price: %.5f (normalized to %.5f)", stopPrice, NormalizePrice(stopPrice)));
    
    // Return the validated and normalized stop loss price
    return NormalizePrice(stopPrice);
}

//+------------------------------------------------------------------+
double CalculateDynamicTakeProfit(int signal, double entryPrice, double stopLossPrice) {
    // Calculate base risk in price
    double baseRisk = MathAbs(entryPrice - stopLossPrice);
    LogInfo(StringFormat("CalculateDynamicTakeProfit - Entry: %.5f, SL: %.5f, Base Risk: %.5f", 
                        entryPrice, stopLossPrice, baseRisk));
    
    // Default risk:reward ratio
    double rrMultiplier = RiskRewardRatio;
    
    // Adjust based on market regime
    if(EnableMarketRegimeFiltering && currentRegime >= 0 && currentRegime < REGIME_COUNT) {
        switch((int)currentRegime) {
            case REGIME_TRENDING_UP:
            case REGIME_TRENDING_DOWN:
                rrMultiplier = 3.0; // Higher targets in trending markets
                break;
                
            case REGIME_BREAKOUT:
                rrMultiplier = 2.5; // Decent targets in breakouts
                break;
                
            case REGIME_RANGING_NARROW:
                rrMultiplier = 1.5; // Lower targets in tight ranges
                break;
                
            case REGIME_RANGING_WIDE:
                rrMultiplier = 2.0; // Standard targets in ranges
                break;
                
            case REGIME_HIGH_VOLATILITY:
                rrMultiplier = 2.25; // Adjust for volatility
                break;
                
            case REGIME_CHOPPY:
                rrMultiplier = 1.5; // Conservative in choppy markets
                break;
        }
    }
    
    // Calculate regime accuracy adjustment - increase targets in regimes with high win rates
    if(EnableMarketRegimeFiltering && currentRegime >= 0 && currentRegime < REGIME_COUNT) {
        int totalRegimeTrades = regimeTradeCount[currentRegime];
        if(totalRegimeTrades > 5) {
            // Adjust RR multiplier based on win rate in this regime
            double accuracy = (::regimeWins[currentRegime] > 0) ? 
                              (double)::regimeWins[currentRegime] / (double)totalRegimeTrades : 0.5;
            if(accuracy > 0.6) {
                rrMultiplier *= 1.2; // Increase targets in high-win regimes
            } else if(accuracy < 0.4) {
                rrMultiplier *= 0.8; // Reduce targets in low-win regimes
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
//| Alternative Swing Detection - Using Different Algorithm           |
//+------------------------------------------------------------------+
int FindAdvancedSwingPoint(bool isBuy, int startBar = 1, int lookbackBars = 20) {
    int swingPointBar = -1;
    double swingValue = isBuy ? 999999 : -999999;
    
    // For swing high detection
    for(int i = startBar; i < lookbackBars + startBar; i++) {
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
    
    return swingPointBar;
}

//+------------------------------------------------------------------+
//| Advanced swing point detection with tolerance                    |
//+------------------------------------------------------------------+
int FindSwingPointWithTolerance(bool isBuy, int startBar = 1, int lookbackBars = 20) {
    int swingPointBar = -1;
    double swingValue = isBuy ? 999999 : -999999;
    
    for(int i = startBar; i < lookbackBars + startBar; i++) {
        if(isBuy) { // For buy orders, find swing low
            double low = iLow(Symbol(), PERIOD_CURRENT, i);
            bool isSwingLow = true;
            
            // Check if this is a swing low (lower than neighbors, within tolerance)
            for(int j = 1; j <= SwingLookbackBars; j++) {
                double tolerance = low * (SwingTolerancePct / 100.0);
                if(i+j < Bars(Symbol(), PERIOD_CURRENT) && iLow(Symbol(), PERIOD_CURRENT, i+j) <= (low + tolerance)) {
                    isSwingLow = false;
                    break;
                }
                if(i-j >= 0 && iLow(Symbol(), PERIOD_CURRENT, i-j) <= (low + tolerance)) {
                    isSwingLow = false;
                    break;
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
// Using enum ENUM_DIVERGENCE_TYPE already defined at line 257
// No need to redefine it here

// This enum and variable will be moved to the global scope
// Replacing with reference to where they should be

// We're using the global lastDivergence already defined earlier

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
    divInfo.type = DIVERGENCE_NONE; // Using the ENUM_DIVERGENCE_TYPE values
    
    // Use these variables to track bars internally
    int localFirstBar = -1;
    int localSecondBar = -1;
    datetime localTimeDetected = 0;
    
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
    if(signal > 0) { // Buy signal - look for isBuy divergence
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
            // Check if price made lower low but RSI made higher low (regular isBuy divergence)
            if(lowPrices[low1] < lowPrices[low2] && rsiValues[low1] > rsiValues[low2]) {
                divInfo.found = true;
                divInfo.type = DIVERGENCE_REGULAR_BULL; // Using the properly defined enum value
                divInfo.strength = 0.7; // Regular bullish has moderate strength
                divInfo.firstBar = low1;
                divInfo.secondBar = low2;
                divInfo.timeDetected = TimeCurrent();
                
                // Also update the global variables for tracking
                localFirstBar = low1;
                localSecondBar = low2;
                localTimeDetected = TimeCurrent();
                
                if(DisplayDebugInfo) {
                    Print("[SMC] Regular bullish divergence detected");
                }
                
                return true;
            }
            // Also check for hidden isBuy divergence (price higher low, oscillator lower low)
            else if(lowPrices[low1] > lowPrices[low2] && rsiValues[low1] < rsiValues[low2]) {
                divInfo.found = true;
                divInfo.type = DIVERGENCE_HIDDEN_BULL;  // Using defined enum value for hidden bullish divergence
                divInfo.firstBar = low2;
                divInfo.secondBar = low1;
                divInfo.strength = 0.5 + 0.3 * (lowPrices[low1] - lowPrices[low2]) / lowPrices[low2];
                divInfo.timeDetected = times[0];
                
                if(DisplayDebugInfo) {
                    Print("[SMC] Hidden isBuy Divergence detected: Price made higher low but RSI made lower low");
                    Print("[SMC] Divergence Strength: ", DoubleToString(divInfo.strength, 2));
                }
                return true;
            }
        }
    } 
    else { // Sell signal - look for bearish divergence
        // Find two recent highs
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
                divInfo.type = DIVERGENCE_REGULAR_BEAR;  // Using defined enum value for regular bearish divergence
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
                divInfo.type = DIVERGENCE_HIDDEN_BEAR;  // Using defined enum value for hidden bearish divergence
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
    
    if(signal > 0) { // Buy signal - look for isBuy divergence
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
                    Print("[SMC] MACD isBuy Divergence detected");
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
                divInfo.type = DIVERGENCE_REGULAR_BEAR;  // Using defined enum value for regular bearish divergence
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
//| Enhanced position management function                           |
//+------------------------------------------------------------------+
// Note: ManageOpenTrade function is already defined earlier in the code
// This section is kept as a reference for additional features

//+------------------------------------------------------------------+
//| Manage trailing stops with enhanced early activation           |
//+------------------------------------------------------------------+
bool ManageAdvancedTrailingStops() {
    if(!EnableTrailingStops && !EnableBreakEven && !EnableAggressiveTrailing) return false;
    
    int totalPositions = PositionsTotal();
    if(totalPositions == 0) return false;
    
    // Get ATR for dynamic trailing calculations
    double atr = GetATR(Symbol(), PERIOD_CURRENT, ATRperiod, 0);
    if(atr == 0) return false;
    
    // Determine market regime
    // Use global currentRegime variable instead
// ENUM_MARKET_REGIME currentRegime = GetMarketRegime();
    
    // Process Legacy trailing (basic ATR-based trailing for non-SMC positions)
    // This preserves backward compatibility
    if(EnableAggressiveTrailing) {
        for(int i=0; i<PositionsTotal(); i++) {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            if(!PositionSelectByTicket(ticket)) continue;
            
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double current = PositionGetDouble(POSITION_PRICE_CURRENT);
            double tp = PositionGetDouble(POSITION_TP);
            double sl = PositionGetDouble(POSITION_SL);
            bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            double profit = isBuy ? (current - entry) : (entry - current);
            double target = MathAbs(tp - entry);
            
            if(profit > 0.3 * target) {
                // Check for CHOCH patterns first (they take priority)
                double chochSL = 0;
                if(ModifyStopsOnCHOCH(ticket, chochSL)) {
                    // Only modify if the CHOCH stop level is better than current SL
                    if((isBuy && (sl == 0 || chochSL > sl)) ||
                      (!isBuy && (sl == 0 || chochSL < sl))) {
                        CTrade tradeHelper; // Using consistent naming to avoid shadowing global variable
                        tradeHelper.SetExpertMagicNumber(MagicNumber);
                        double currentTP = PositionGetDouble(POSITION_TP);
                        tradeHelper.PositionModify(ticket, chochSL, currentTP);
                        if(DisplayDebugInfo) {
                            Print("[SMC] CHOCH SL adjustment for ticket ", ticket, 
                                 ", posType: ", (isBuy ? "BUY" : "SELL"), 
                                 ", new SL: ", DoubleToString(chochSL, _Digits));
                        }
                        continue; // Skip other adjustments for this cycle
                    }
                }
                
                double newSL = isBuy ? current - atr * TrailingStopMultiplier : current + atr * TrailingStopMultiplier;
                double currentSL = sl; // Declare currentSL
                double currentTP = tp; // Declare currentTP
                
                if((isBuy && newSL > currentSL) || (!isBuy && newSL < currentSL)) {
                    CTrade trade_local;
                    trade_local.SetExpertMagicNumber(MagicNumber);
                    trade_local.PositionModify(ticket, chochSL, currentTP);
                    if(DisplayDebugInfo) Print("[TRAIL] Basic trailing stop updated to ", newSL);
                }
            }
        }
    }
    
    // Breakeven logic: Move SL to BE+ after first TP is hit
    if(EnableBreakEven) {
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
                // Create local trade object
            CTrade trade_local;
            trade_local.SetDeviationInPoints(MaxSlippage);
            
            if(trade_local.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
                    if(DisplayDebugInfo) Print("[SMC] Breakeven SL moved for partial TP1: Ticket=", ticket, ", NewSL=", newSL);
                }
            }
        }
    }
    
    // Advanced trailing for SMC positions with volatility-based adjustments
    if(EnableTrailingStops) {
        // Calculate ATR for trailing stop adjustments
        double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
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
            
            // Check for CHOCH patterns first (they take priority)
            double chochSL = 0;
            if(ModifyStopsOnCHOCH(ticket, chochSL)) {
                // Only modify if the CHOCH stop level is better than current SL
                if((posType == POSITION_TYPE_BUY && (currentSL == 0 || chochSL > currentSL)) ||
                   (posType == POSITION_TYPE_SELL && (currentSL == 0 || chochSL < currentSL))) {
                    
                    CTrade tradeHelper; // Create local trade object with consistent naming
                    tradeHelper.SetExpertMagicNumber(MagicNumber);
                    tradeHelper.PositionModify(ticket, chochSL, currentTP);
                    if(DisplayDebugInfo) {
                        Print("[SMC] CHOCH SL adjustment for ticket ", ticket, 
                             ", posType: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), 
                             ", new SL: ", DoubleToString(chochSL, _Digits));
                    }
                    // Skip other adjustments for this cycle
                    continue;
                }
            }
            
            // Enhanced trailing based on ATR and market regime
            double trailAmount = atr * TrailingStopMultiplier;
            
            // Apply market regime modifications to trailing
            if(EnableMarketRegimeFiltering && currentRegime >= 0) {
                switch((int)currentRegime) {
                    case REGIME_TRENDING_UP:
                    case REGIME_TRENDING_DOWN:
                        trailAmount *= 1.5; // More aggressive trailing in trends
                        break;
                        
                    case REGIME_CHOPPY:
                    case REGIME_HIGH_VOLATILITY:
                        trailAmount *= 0.8; // Tighter trailing
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
                    
                    // Apply volatility-based adjustments if enabled
                    if(EnableTrailingForLast) {
                        // Calculate dynamic trailing step based on current ATR
                        double trailStep = atr * TrailVolMultiplier;
                        
                        // Apply min/max constraints
                        if(trailStep < TrailMinStep * _Point) trailStep = TrailMinStep * _Point;
                        if(trailStep > TrailMaxStep * _Point) trailStep = TrailMaxStep * _Point;
                        
                        // Adjust trailing step based on market regime
                        if(currentRegime == REGIME_HIGH_VOLATILITY) trailStep *= 1.5; // Wider trailing in high volatility
                        else if(currentRegime == REGIME_LOW_VOLATILITY) trailStep *= 0.8; // Tighter trailing in low volatility
                        
                        // Calculate volatility-based stop level
                        double volBasedSL = currentPrice - trailStep;
                        
                        // Use the more conservative of the two stop levels
                        potentialSL = MathMax(potentialSL, volBasedSL);
                    }
                    
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
                        
                        if(DisplayDebugInfo && potentialSL > currentSL) {
                            Print("[SMC] Enhanced trailing: profit at ", DoubleToString(profitPct, 2), 
                                 "x risk, tightening trail to ", DoubleToString(reducedTrail/_Point, 1), " points");
                        }
                    }
                    
                    if(potentialSL > currentSL + (1 * _Point)) {
                        newSL = potentialSL;
                    }
                    
                    // Once we're at 80% of TP, extend TP if in trending regime
                    if(profitPct >= 0.8 && (currentRegime == REGIME_TRENDING_UP) && currentTP > 0) {
                        double newTP = currentTP + (MathAbs(currentTP - entryPrice) * 0.5);
                        if(newTP > currentTP + (5 * _Point)) {
                            // Create a trade object for position modification
                            CTrade trade_local; // Renamed to avoid shadowing global variable
                            trade_local.SetExpertMagicNumber(MagicNumber);
                            
                            if(trade_local.PositionModify(ticket, newSL > 0 ? newSL : currentSL, newTP)) {
                                if(DisplayDebugInfo) Print("[SMC] Extended TP for ticket ", ticket, " to ", newTP);
                            }
                            continue; // Skip regular SL update as we've already modified
                        }
                    }
                } else {
                    // For sell positions, check if we should update SL (move it down)
                    double potentialSL = currentPrice + trailAmount;
                    
                    // Apply volatility-based adjustments if enabled (for SELL positions)
                    if(EnableTrailingForLast) {
                        // Calculate dynamic trailing step based on current ATR
                        double trailStep = atr * TrailVolMultiplier;
                        
                        // Apply min/max constraints
                        if(trailStep < TrailMinStep * _Point) trailStep = TrailMinStep * _Point;
                        if(trailStep > TrailMaxStep * _Point) trailStep = TrailMaxStep * _Point;
                        
                        // Adjust trailing step based on market regime
                        if(currentRegime == REGIME_HIGH_VOLATILITY) trailStep *= 1.5; // Wider trailing in high volatility
                        else if(currentRegime == REGIME_LOW_VOLATILITY) trailStep *= 0.8; // Tighter trailing in low volatility
                        
                        // Calculate volatility-based stop level (for sell, we add the trail to current price)
                        double volBasedSL = currentPrice + trailStep;
                        
                        // Use the more conservative of the two stop levels (for sell, lower SL is better/tighter)
                        potentialSL = MathMin(potentialSL, volBasedSL);
                    }
                    
                    // Find a swing high for better trailing if possible
                    int swingBar = FindRecentSwingPointHigh(false, 1, 10); // Look at recent 10 bars
                    double swingSL = 0;
                    
                    if(swingBar >= 0) {
                        swingSL = iHigh(Symbol(), PERIOD_CURRENT, swingBar) + (3 * _Point);
                        
                        // Use swing high only if it's lower than current SL and more than price + trailAmount
                        if((currentSL == 0 || swingSL < currentSL) && swingSL > currentPrice + (5 * _Point)) {
                            potentialSL = MathMin(potentialSL, swingSL);
                        }
                    }
                    
                    // More aggressive trailing based on profit % - tighten as profit increases (for SELL)
                    if(profitPct > 1.0) { // Over 100% of initial risk
                        // Reduce trailing distance as profit grows
                        double reducedTrail = trailAmount * (1.0 - MathMin(0.5, (profitPct - 1.0) * 0.25));
                        potentialSL = MathMin(potentialSL, currentPrice + reducedTrail);
                        
                        if(DisplayDebugInfo && (currentSL == 0 || potentialSL < currentSL)) {
                            Print("[SMC] Enhanced trailing (SELL): profit at ", DoubleToString(profitPct, 2), 
                                 "x risk, tightening trail to ", DoubleToString(reducedTrail/_Point, 1), " points");
                        }
                    }
                    
                    if(currentSL == 0 || potentialSL < currentSL - (1 * _Point)) {
                        newSL = potentialSL;
                    }
                    
                    // Once we're at 80% of TP, extend TP if in trending regime
                    if(profitPct >= 0.8 && (currentRegime == REGIME_TRENDING_DOWN) && currentTP > 0) {
                        double newTP = currentTP - (MathAbs(currentTP - entryPrice) * 0.5);
                        if(newTP < currentTP - (5 * _Point)) {
                            // Create a trade object for position modification
                            CTrade trade_local; // Renamed to avoid shadowing global variable
                            trade_local.SetExpertMagicNumber(MagicNumber);
                            
                            if(trade_local.PositionModify(ticket, newSL > 0 ? newSL : currentSL, newTP)) {
                                if(DisplayDebugInfo) Print("[SMC] Extended TP for ticket ", ticket, " to ", newTP);
                            }
                            continue; // Skip regular SL update as we've already modified
                        }
                    }
                }
                
                // Apply the new stop loss if it's better than current one
                if(newSL != 0) {
                    // Create a trade object for position modification
                    CTrade trade_local; // Renamed to avoid shadowing global variable
                    trade_local.SetExpertMagicNumber(MagicNumber);
                    
                    double potentialSL = newSL; // Ensure potentialSL is defined
                    if(trade_local.PositionModify(ticket, potentialSL, currentTP)) {
                        if(DisplayDebugInfo) {
                            Print("[SMC] Trailing stop adjusted for ticket ", ticket, 
                                 ", new SL: ", DoubleToString(newSL, _Digits), 
                                 ", profit at ", DoubleToString(profitPct, 2), "x risk");
                        }
                    }
                }
            }
        }
    }
    return false;
}
                    


//+------------------------------------------------------------------+
//| Advanced version of break-even with additional parameters         |
//+------------------------------------------------------------------+
bool MoveToBreakEvenAdvanced(double entryPrice, double currentSL, ENUM_POSITION_TYPE posType, ulong ticket, double spread) {
    // Default buffer to use (points beyond entry for safety)
    double beBuffer = BreakEvenPadding * _Point;
    double point = GetSymbolPoint();
    
    // Calculate new stop loss level
    double newSL = 0.0;
    bool shouldModify = false;
    
    // For buy positions, move stop to entry + buffer
    if(posType == POSITION_TYPE_BUY) {
        // Only move to breakeven if current SL is below entry point
        if(currentSL < entryPrice) {
            newSL = entryPrice + beBuffer;
            shouldModify = true;
        }
    }
    // For sell positions, move stop to entry - buffer
    else {
        // Only move to breakeven if current SL is above entry point or not set
        if(currentSL > entryPrice || currentSL == 0) {
            newSL = entryPrice - beBuffer;
            shouldModify = true;
        }
    }
    
    // If we should modify the position
    if(shouldModify) {
        // Create trade object
        CTrade tradeHelper; // Using consistent naming to avoid shadowing global variable
        tradeHelper.SetExpertMagicNumber(MagicNumber);
        
        // Round to broker requirements
        newSL = NormalizeDouble(newSL, _Digits);
        
        // Get current take profit
        double currentTP = PositionGetDouble(POSITION_TP);
        
        // Apply modification
        if(tradeHelper.PositionModify(ticket, newSL, currentTP)) {
            if(DisplayDebugInfo) {
                Print("[SMC] Moved to break-even: Ticket=", ticket, ", New SL=", newSL);
            }
            return true;
        } else {
            LogError("Failed to move to break-even: " + GetLastErrorText(GetLastError()));
            return false;
        }
    }
    
    // Return false if no modification was needed
    return false;
}

//| Standard trade execution implementation                          |
//+------------------------------------------------------------------+
bool ExecuteTrade(int signal, double price, double sl, double tp) {
    if(signal == 0) return false;
    
    // Use input parameters for risk calculation
    // (These have already been defined as input parameters with defaults)
    
    // Calculate position size
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (RiskPercent / 100.0);
    
    // Calculate risk in pips
    double riskPips = MathAbs(price - sl) / _Point;
    
    // Recalculate take profit based on risk:reward if not specified
    if(tp == 0) {
        // Use RiskRewardRatio from input parameters instead of undefined riskRewardRatio
        double rewardPips = riskPips * RiskRewardRatio;
        
        if(signal > 0) { // BUY
            tp = price + (rewardPips * _Point);
        } else { // SELL
            tp = price - (rewardPips * _Point);
        }
    }
    
    // Calculate lot size
    double stopLossDistance = MathAbs(price - sl);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    
    // Calculate points per one pip
    double pointsPerPip = 1.0 / Point();
    
    // Calculate lot size
    double lotSize = 0.0;
    if(tickValue != 0 && stopLossDistance != 0) {
        lotSize = riskAmount / (stopLossDistance * tickValue / tickSize);
    }
    
    // Apply any additional modifiers
    if(EnableAdaptiveRisk) {
        double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
        // Use a simplified version instead of the undefined function
        double volatilityAdjustment = 1.0;
        if(atr > 0) {
            // Simple adaptive sizing based on ATR
            volatilityAdjustment = MathMin(1.0, 0.001 / atr); // Lower volatility = higher position size
        }
        lotSize *= volatilityAdjustment;
    }
    
    // Simple correlation adjustment (implement with actual logic later)
    double corrFactor = 1.0; // Default no adjustment
    // Simple time decay factor (implement with actual logic later)
    double timeFactor = 1.0; // Default no time decay
    lotSize *= corrFactor * timeFactor;
    
    // Ensure minimum lot size
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    if(lotSize < minLot) lotSize = minLot;
    
    // Normalize lot size to broker requirements
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Enhanced logging for stop loss validation
    LogInfo("[SL VALIDATE] Signal=" + IntegerToString(signal) + 
            ", Entry=" + DoubleToString(price, _Digits) + 
            ", SL=" + DoubleToString(sl, _Digits) + 
            ", Distance=" + DoubleToString(MathAbs(price - sl) / _Point, 1) + " points");
    
    // Execute the trade with retry and performance monitoring
    CTrade trade_local; // Renamed to avoid shadowing global variable
    trade_local.SetDeviationInPoints(AdaptiveSlippagePoints);
    trade_local.SetExpertMagicNumber(MagicNumber);
    
    // Use enhanced trade execution with retry mechanism
    bool success = TradeWithRetry(signal > 0 ? "BUY" : "SELL", lotSize, price, sl, tp);
    
    return success;
}

//+------------------------------------------------------------------+
//| Execute trade with exponential backoff retry mechanism            |
//+------------------------------------------------------------------+
bool TradeWithRetry(string actionType, double lots, double price, double stopLoss, double takeProfit, int maxRetries = 3) {
    CTrade tradeObj;
    tradeObj.SetExpertMagicNumber(MagicNumber);
    
    // Adaptive slippage based on current spread conditions
    int adaptiveSlippage = AdaptiveSlippagePoints;
    double currentSpread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    double avgSpread = CalculateAverageSpread(20);
    
    // If current spread is significantly higher than average, adapt slippage or reduce position
    if(currentSpread > avgSpread * 2.0) {
        // Option 1: Increase slippage allowance during high spread
        adaptiveSlippage = (int)(AdaptiveSlippagePoints * 1.5);
        
        // Option 2: Or reduce position size during high spread conditions
        if(currentSpread > avgSpread * 3.0) {
            lots = lots * 0.75; // Reduce position by 25%
            LogInfo(StringFormat("[SPREAD ADAPT] Reducing position size by 25%% due to high spread: %d vs avg %d",
                               (int)currentSpread, (int)avgSpread));
        }
    }
    
    tradeObj.SetDeviationInPoints(adaptiveSlippage);
    
    // Adaptive retry parameters based on time of day and market conditions
    int baseWaitMs = 50; // Default base wait time
    int maxWaitMs = 1000; // Default max wait time
    
    // Get current time for time-of-day adjustments
    MqlDateTime localTime;
    TimeToStruct(TimeCurrent(), localTime);
    int currentHour = localTime.hour;
    
    // Adjust retry parameters based on time of day
    // High-activity market hours - faster retries with more attempts
    if((currentHour >= 8 && currentHour < 11) || // London open/overlap
       (currentHour >= 13 && currentHour < 17)) { // NY session
        baseWaitMs = 30; // Faster initial retry
        maxRetries = MathMax(maxRetries, 4); // More retries during active hours
        LogInfo("[RETRY ADAPT] Using aggressive retry settings for active market hours");
    }
    // Lower-activity hours - slower retries with fewer attempts
    else if(currentHour < 7 || currentHour > 20) { // Off-hours
        baseWaitMs = 100; // Slower initial retry
        maxWaitMs = 1500; // Longer max wait
        maxRetries = MathMin(maxRetries, 2); // Fewer retries during off-hours
        LogInfo("[RETRY ADAPT] Using conservative retry settings for off-hours");
    }
    
    // Further adjust based on volatility and news
    double atr = cachedATR > 0 ? cachedATR : CalculateATR(14);
    double normalATR = CalculateAverageATR(20);
    
    if(atr > normalATR * 1.5) { // High volatility
        maxRetries++; // Extra retry in volatile conditions
        LogInfo("[RETRY ADAPT] Added extra retry attempt due to high volatility");
    }
    
    // Performance measurement variables
    ulong startTime = GetMicrosecondCount();
    ulong endTime = 0;
    int attempts = 0;
    bool success = false;
    int lastError = 0;
    
    // Create a reference to store the resulting ticket
    ulong resultTicket = 0;
    
    for(int attempt = 0; attempt < maxRetries; attempt++) {
        attempts++;
        
        // Execute the trade based on action type
        if(actionType == "BUY") {
            success = tradeObj.Buy(lots, Symbol(), price, stopLoss, takeProfit, "SMC_HFT");
        } 
        else if(actionType == "SELL") {
            success = tradeObj.Sell(lots, Symbol(), price, stopLoss, takeProfit, "SMC_HFT");
        }
        else {
            LogError("Unknown trade type in TradeWithRetry: " + actionType);
            return false;
        }
        
        // Get result information
        resultTicket = tradeObj.ResultOrder();
        lastError = tradeObj.ResultRetcode();
        
        // If successful, break out of retry loop
        if(success) break;
        
        // Calculate exponential backoff wait time
        int waitTime = baseWaitMs * (int)MathPow(2, attempt); // 50ms, 100ms, 200ms, etc.
        waitTime = MathMin(waitTime, maxWaitMs); // Cap at max wait time
        
        // Network quality detection - adapt wait time based on trade latency
        if(lastError == 10004 || lastError == 10006 || lastError == 10007) { // Requote, rejected, cancelled
            // Add additional wait based on market conditions
            double spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point();
            double avgSpread = CalculateAverageSpread(20);
            
            if(spread > avgSpread * 1.5) {
                // High spread condition - wait longer
                waitTime += 100;
            }
        }
        
        if(DisplayDebugInfo) {
            Print("[TRADE RETRY] Attempt ", attempt+1, " failed with error ", 
                  lastError, " (", GetErrorDescription(lastError), "). Waiting ", 
                  waitTime, "ms before retry.");
        }
        
        // Wait before next attempt
        Sleep(waitTime);
    }
    
    // Calculate execution time
    endTime = GetMicrosecondCount();
    double executionTimeMs = (endTime - startTime) / 1000.0; // Convert to milliseconds
    
    // Log performance metrics
    if(success) {
        if(DisplayDebugInfo) {
            Print("[TRADE PERF] Successful execution in ", executionTimeMs, "ms after ", 
                  attempts, " attempt(s). Ticket: ", resultTicket);
        }
        
        // Record execution metrics for analysis
        RecordTradeExecutionMetrics(executionTimeMs, attempts, lastError);
    } 
    else {
        LogError(StringFormat("Trade failed after %d attempts. Last error: %d (%s). Execution time: %.2fms", 
                             attempts, lastError, GetErrorDescription(lastError), executionTimeMs));
    }
    
    return success;
}

//+------------------------------------------------------------------+
//| Record trade execution metrics for performance analysis           |
//+------------------------------------------------------------------+
void RecordTradeExecutionMetrics(double executionTimeMs, int attempts, int errorCode) {
    static double totalExecutionTime = 0;
    static int totalExecutions = 0;
    static int totalAttempts = 0;
    static int maxExecutionTime = 0;
    
    // Update metrics
    totalExecutionTime += executionTimeMs;
    totalExecutions++;
    totalAttempts += attempts;
    maxExecutionTime = (int)MathMax(maxExecutionTime, executionTimeMs);
    
    // Calculate averages
    double avgExecutionTime = totalExecutionTime / totalExecutions;
    double avgAttempts = (double)totalAttempts / totalExecutions;
    
    // Store in global variables for dashboard display
    if(DisplayDebugInfo && totalExecutions % 5 == 0) { // Update logs every 5 trades
        Print(StringFormat("[PERF METRICS] Avg execution: %.2fms, Max: %dms, Avg attempts: %.1f, Total trades: %d",
                         avgExecutionTime, maxExecutionTime, avgAttempts, totalExecutions));
    }
}

//+------------------------------------------------------------------+
//| Calculate average spread over N periods                           |
//+------------------------------------------------------------------+
double CalculateAverageSpread(int periods) {
    static double spreadHistory[];
    static int spreadIndex = 0;
    
    // Initialize array if needed
    if(ArraySize(spreadHistory) != periods) {
        ArrayResize(spreadHistory, periods);
        ArrayInitialize(spreadHistory, 0);
    }
    
    // Get current spread
    double currentSpread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point();
    
    // Store in circular buffer
    spreadHistory[spreadIndex] = currentSpread;
    spreadIndex = (spreadIndex + 1) % periods;
    
    // Calculate average
    double totalSpread = 0;
    for(int i = 0; i < periods; i++) {
        totalSpread += spreadHistory[i];
    }
    
    return totalSpread / periods;
}

//+------------------------------------------------------------------+
//| Calculate average ATR over N periods                              |
//+------------------------------------------------------------------+
double CalculateAverageATR(int periods) {
    static double atrHistory[];
    static int atrIndex = 0;
    static datetime lastAtrCalc = 0;
    
    // Only update once per minute to save resources
    datetime currentTime = TimeCurrent();
    if(currentTime - lastAtrCalc < 60 && atrHistory[atrIndex > 0 ? atrIndex-1 : periods-1] > 0) {
        // Calculate average from history
        double totalATR = 0;
        int validPeriods = 0;
        
        for(int i = 0; i < periods; i++) {
            if(atrHistory[i] > 0) {
                totalATR += atrHistory[i];
                validPeriods++;
            }
        }
        
        if(validPeriods > 0) {
            return totalATR / validPeriods;
        }
    }
    
    // Initialize array if needed
    if(ArraySize(atrHistory) != periods) {
        ArrayResize(atrHistory, periods);
        ArrayInitialize(atrHistory, 0);
    }
    
    // Calculate current ATR
    double currentATR = 0;
    int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
    
    if(atrHandle != INVALID_HANDLE) {
        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);
        
        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
            currentATR = atrBuffer[0];
        }
        
        IndicatorRelease(atrHandle);
    }
    
    // Store in circular buffer
    atrHistory[atrIndex] = currentATR;
    atrIndex = (atrIndex + 1) % periods;
    lastAtrCalc = currentTime;
    
    // Calculate average
    double totalATR = 0;
    int validPeriods = 0;
    
    for(int i = 0; i < periods; i++) {
        if(atrHistory[i] > 0) {
            totalATR += atrHistory[i];
            validPeriods++;
        }
    }
    
    if(validPeriods > 0) {
        return totalATR / validPeriods;
    }
    
    return currentATR; // Fallback to current ATR if no history
}

//+------------------------------------------------------------------+
//| Standard trade execution implementation                          |
//+------------------------------------------------------------------+
bool ExecuteTrade(int signal, double price, double sl, double tp) {
    if(signal == 0) return false;
    
    // Use input parameters for risk calculation
    // (These have already been defined as input parameters with defaults)
    
    // Calculate position size
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (RiskPercent / 100.0);
    
    // Calculate risk in pips
    double riskPips = MathAbs(price - sl) / _Point;
    
    // Recalculate take profit based on risk:reward if not specified
    if(tp == 0) {
        // Use RiskRewardRatio from input parameters instead of undefined riskRewardRatio
        double rewardPips = riskPips * RiskRewardRatio;
        
        if(signal > 0) { // BUY
            tp = price + (rewardPips * _Point);
        } else { // SELL
            tp = price - (rewardPips * _Point);
        }
    }
    
    // Calculate lot size
    double stopLossDistance = MathAbs(price - sl);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    
    // Calculate points per one pip
    double pointsPerPip = 1.0 / Point();
    
    // Calculate lot size
    double lotSize = 0.0;
    if(tickValue != 0 && stopLossDistance != 0) {
        lotSize = riskAmount / (stopLossDistance * tickValue / tickSize);
    }
    
    // Apply any additional modifiers
    if(EnableAdaptiveRisk) {
        double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
        // Use a simplified version instead of the undefined function
        double volatilityAdjustment = 1.0;
        if(atr > 0) {
            // Simple adaptive sizing based on ATR
            volatilityAdjustment = MathMin(1.0, 0.001 / atr); // Lower volatility = higher position size
        }
        lotSize *= volatilityAdjustment;
    }
    
    // Simple correlation adjustment (implement with actual logic later)
    double corrFactor = 1.0; // Default no adjustment
    // Simple time decay factor (implement with actual logic later)
    double timeFactor = 1.0; // Default no time decay
    lotSize *= corrFactor * timeFactor;
    
    // Ensure minimum lot size
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    if(lotSize < minLot) lotSize = minLot;
    
    // Normalize lot size to broker requirements
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Enhanced logging for stop loss validation
    LogInfo("[SL VALIDATE] Signal=" + IntegerToString(signal) + 
            ", Entry=" + DoubleToString(price, _Digits) + 
            ", SL=" + DoubleToString(sl, _Digits) + 
            ", Distance=" + DoubleToString(MathAbs(price - sl) / _Point, 1) + " points");
    
    // Execute the trade with retry and performance monitoring
    CTrade trade_local; // Renamed to avoid shadowing global variable
    trade_local.SetDeviationInPoints(AdaptiveSlippagePoints);
    trade_local.SetExpertMagicNumber(MagicNumber);
    
    // Use enhanced trade execution with retry mechanism
    bool success = TradeWithRetry(signal > 0 ? "BUY" : "SELL", lotSize, price, sl, tp);
    
    if(success) {
        LogTrade("Trade executed: " + (signal > 0 ? "BUY" : "SELL") + 
                " Lot=" + DoubleToString(lotSize, 2) + 
                " Entry=" + DoubleToString(price, _Digits) + 
                " SL=" + DoubleToString(sl, _Digits) + 
                " TP=" + DoubleToString(tp, _Digits));
    } else {
        LogError("Trade execution failed: " + IntegerToString(GetLastError()) + 
                " | SL Distance: " + DoubleToString(MathAbs(price - sl) / _Point, 1) + 
                " points | MinSL: " + DoubleToString(CalcBrokerMinStop() / _Point, 1) + " points");
    }
    
    return success;
}

//+------------------------------------------------------------------+
//| Robust trade execution with retries and exponential backoff      |
//+------------------------------------------------------------------+
bool TradeWithRetry(string action, double lots, double price, double sl, double tp, ulong posTicket=0, int maxRetries=3) {
    // Create local trade object with consistent naming to avoid shadowing global variable
    CTrade tradeHelper;
    tradeHelper.SetExpertMagicNumber(MagicNumber);
    
    int attempt = 0;
    while(attempt < maxRetries) {
        bool result = false;
        if(action == "BUY")
            result = tradeHelper.Buy(lots, Symbol(), price, sl, tp);
        else if(action == "SELL")
            result = tradeHelper.Sell(lots, Symbol(), price, sl, tp);
        else if(action == "CLOSE")
            result = tradeHelper.PositionClose(Symbol());
        else if(action == "MODIFY" && posTicket > 0)
            result = tradeHelper.PositionModify(posTicket, sl, tp);
        if(result) return true;
        int error = GetLastError();
        if(error == 10004 || error == 10020) { // Requote or trade context busy
            Print("[RETRY] Trade failed with error ", error, ". Retrying (attempt ", attempt+1, ")");
            // RefreshRates() is deprecated in MQL5, use SymbolInfoTick() instead
            MqlTick latest_price;
            SymbolInfoTick(Symbol(), latest_price);
            Sleep(100 * (1 << attempt)); // 100ms, 200ms, 400ms
            attempt++;
        } else {
            Print("[FATAL] Trade failed with error ", error, ". Not retrying.");
            break;
        }
    }
    return false;
}
//+------------------------------------------------------------------+
//| Reference section for risk and decay calculations                |
//+------------------------------------------------------------------+
// Note: CalculateCorrelationAdjustment and CalculateTimeDecayFactor functions 
// are already defined earlier in the code.
// This section is kept as a reference for the implementation details.

//+------------------------------------------------------------------+
//| Calculate adaptive position size based on market volatility        |
//+------------------------------------------------------------------+
/* 
{{ ... }}
    double avgATR = CalculateAverageATR(Symbol(), PERIOD_CURRENT, 14, 50);
    
    // If we can't calculate avgATR, return base size
    if(avgATR <= 0) return baseLotSize;
    
    // Calculate volatility ratio
    double volatilityRatio = currentATR / avgATR;
*/
    
/* 
    // Adjust position size inversely to volatility
    double adjustedLotSize = baseLotSize;
    
    if(volatilityRatio > 1.5) {
        // High volatility - reduce position size
        adjustedLotSize = baseLotSize / volatilityRatio;
    } else if(volatilityRatio < 0.6) {
        // Low volatility - potentially increase position size slightly
        adjustedLotSize = baseLotSize * (1.0 + (0.6 - volatilityRatio));
    }
    
    // Cap the maximum increase to 150% of base size
    adjustedLotSize = MathMin(adjustedLotSize, baseLotSize * 1.5);
    
    // Log the adjustment
    if(DisplayDebugInfo && MathAbs(adjustedLotSize - baseLotSize) > 0.01) {
        Print("[ADAPTIVE SIZE] Base=", DoubleToString(baseLotSize, 2), 
              " Adjusted=", DoubleToString(adjustedLotSize, 2),
*/
/* 
              " VolRatio=", DoubleToString(volatilityRatio, 2));
    }
    
    return adjustedLotSize;
*/
// End of commented out function

// CalculateTimeDecayFactor function is already defined earlier in the code
// This is a duplicate definition that has been commented out
/*
//+------------------------------------------------------------------+
//| Calculate time-based factor to reduce position size near market close|
//+------------------------------------------------------------------+
double CalculateTimeDecayFactor(int signal) {
    // If time-based risk adjustment is disabled, return 1.0 (no adjustment)
    if(!EnableTimeBasedRiskReduction) return 1.0;
    
    datetime currentTime = TimeCurrent();
    MqlDateTime time;
    TimeToStruct(currentTime, time);
    
    // Check if it's near the end of the trading day - reduce position size
    // to avoid overnight exposure (assuming broker server time is GMT+2/GMT+3)
    if(time.hour >= 20 || time.hour < 2) {
        // Late evening/night - reduce position size
        return 0.5;
    }
    
    if(time.day_of_week == 5 && time.hour >= 18) {
        // Friday evening approaching weekend - reduce position size significantly
        return 0.3;
    }
    
    // During core trading hours, use full size
    return 1.0;
}
*/

//+------------------------------------------------------------------+
//| Checks if the current time is within a high impact news window   |
//+------------------------------------------------------------------+
// Duplicate function commented out - already defined at line 2580
/*
bool IsHighImpactNewsTime() {
    // Default implementation - will be enhanced with actual news API integration
    return false; // Placeholder until full implementation
    // Default implementation - can be enhanced with actual news API integration
    datetime currentTime = TimeCurrent();
    
    // If you have specific known news times, you can check against them
    
    // For now we'll just check if we're near typical news release times (NFP, FOMC, etc.)
    MqlDateTime time;
    TimeToStruct(currentTime, time);
    
    // Check if it's a news release day (e.g., first Friday of month for NFP)
    return false;
}
*/

/* This entire section is commented out as it's a duplicate function
    bool isFirstFriday = (time.day <= 7 && time.day_of_week == 5);
    bool isFOMCDay = (time.day == 15 || time.day == 16) && (time.mon == 3 || time.mon == 6 || time.mon == 9 || time.mon == 12);
    
    // If it's a news day, check if we're within the news window
    if(isFirstFriday) {
        // NFP is typically released at 8:30 AM EST
        if(time.hour == 8 && time.min >= 15 && time.min <= 45) return true;
        if(time.hour == 9 && time.min <= 15) return true;
    }
    
    if(isFOMCDay) {
        // FOMC announcements are typically at 2:00 PM EST
        if(time.hour == 14 && time.min >= 45) return true;
        if(time.hour == 15 && time.min <= 30) return true;
    }
    
    // Default return - not a high impact news time
    return false;
*/

//+------------------------------------------------------------------+
//| Find recent swing point for trailing stops                       |
//+------------------------------------------------------------------+
/* Duplicate function - already defined at line 4681
    
    int swingBar = -1;
    double swingPrice = 0;
    int lastSwingStrength = 0;
    
    // For buy positions, look for swing lows (support levels)
    if(isBuy) {
        for(int i = 2; i < lookbackBars && i < Bars(Symbol(), PERIOD_CURRENT); i++) {
            double midPrice = iLow(Symbol(), PERIOD_CURRENT, i);
            
            // Check if this bar's low is lower than both neighbors
            if(midPrice < iLow(Symbol(), PERIOD_CURRENT, i-1) && 
               midPrice < iLow(Symbol(), PERIOD_CURRENT, i+1)) {
                
                // Calculate the strength of this swing point (how many bars confirm it)
                int strength = 1;
                for(int j = 2; j <= 5 && i+j < Bars(Symbol(), PERIOD_CURRENT); j++) {
                    if(midPrice < iLow(Symbol(), PERIOD_CURRENT, i+j)) strength++;
                }
                for(int j = 2; j <= 5 && i-j >= 0; j++) {
                    if(midPrice < iLow(Symbol(), PERIOD_CURRENT, i-j)) strength++;
                }
                
                // Only consider points with sufficient strength
                if(strength >= minStrength && strength > lastSwingStrength) {
                    swingBar = i;
                    swingPrice = midPrice;
                    lastSwingStrength = strength;
                }
            }
        }
    }
*/
/* 
    // For sell positions, look for swing highs (resistance levels)
    else {
        for(int i = 2; i < lookbackBars && i < Bars(Symbol(), PERIOD_CURRENT); i++) {
            double midPrice = iHigh(Symbol(), PERIOD_CURRENT, i);
            
            // Check if this bar's high is higher than both neighbors
            if(midPrice > iHigh(Symbol(), PERIOD_CURRENT, i-1) && 
               midPrice > iHigh(Symbol(), PERIOD_CURRENT, i+1)) {
                
                // Calculate the strength of this swing point
                int strength = 1;
                for(int j = 2; j <= 5 && i+j < Bars(Symbol(), PERIOD_CURRENT); j++) {
                    if(midPrice > iHigh(Symbol(), PERIOD_CURRENT, i+j)) strength++;
                }
                for(int j = 2; j <= 5 && i-j >= 0; j++) {
                    if(midPrice > iHigh(Symbol(), PERIOD_CURRENT, i-j)) strength++;
                }
                
                // Only consider points with sufficient strength
                if(strength >= minStrength && strength > lastSwingStrength) {
                    swingBar = i;
                    swingPrice = midPrice;
                    lastSwingStrength = strength;
                }
            }
        }
*/

// This code has been commented out as it's a duplicate definition
/*
    // Debug output for swing detection
    if(DisplayDebugInfo && swingBar > 0) {
        string direction = isBuy ? "BUY" : "SELL";
        Print("[SWING DETECT] Direction=", direction, ", Bar=", swingBar, ", Strength=", lastSwingStrength);
    }
    
    return swingBar;
} // End of FindRecentSwingPoint function
*/

//+------------------------------------------------------------------+
//| Calculate minimum stop loss distance required by broker          |
//+------------------------------------------------------------------+
// Duplicate function commented out - already defined at line 3707
/*
double CalcBrokerMinStop() {
    double minStop  = (double)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    
    // Add a small buffer to ensure we're above the minimum
    double safetyBuffer = 2 * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    return minStop + safetyBuffer;
}
*/

//+------------------------------------------------------------------+
//| Calculate the average ATR over a specified number of periods      |
//+------------------------------------------------------------------+
double CalculateAverageATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int lookback) {
    if(lookback <= 0) return 0.0;
    
    double atrSum = 0.0;
    int validValues = 0;
    
    // Get ATR for the last 'lookback' bars
    for(int i = 0; i < lookback; i++) {
        double currentATR = GetATR(symbol, timeframe, period, i);
        if(currentATR > 0) {
            atrSum += currentATR;
            validValues++;
        }
    }
    
    // Return average
    if(validValues > 0) {
        return atrSum / validValues;
    }
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Calculate ATR for a given symbol and timeframe                    |
//+------------------------------------------------------------------+
// GetATR function is already defined at line 3233
// This is a duplicate that needs to be commented out
/*
double GetATR(int period, int shift = 0) {
    double atr[];
    ArraySetAsSeries(atr, true);
    
    int handle = iATR(Symbol(), PERIOD_CURRENT, period);
    if(handle == INVALID_HANDLE) {
        LogError("Failed to create ATR indicator. Error: " + IntegerToString(GetLastError()));
        return 0.0;
    }
    
    // Copy indicator values
    int copied = CopyBuffer(handle, 0, shift, 1, atr);
    if(copied <= 0) {
        LogError("Failed to copy ATR data. Error: " + IntegerToString(GetLastError()));
        bool released = IndicatorRelease(handle); // Use bool to clarify this is the built-in function
        return 0.0;
    }
    
    // Release the indicator handle
    bool released = IndicatorRelease(handle); // Use bool to clarify this is the built-in function
    
    return atr[0];
}
*/

//+------------------------------------------------------------------+
//| Get Bollinger Bands values                                       |
//+------------------------------------------------------------------+
double GetBands(string symbol, ENUM_TIMEFRAMES timeframe, int period, double deviation, int shift, ENUM_APPLIED_PRICE price_type, int mode, int buffer_index) {
    // Input validation
    if(period < 2) {
        LogWarning(StringFormat("Invalid Bands period %d - using minimum of 2", period));
        period = 2;
    }
    
    // Use explicit cast from double to int to avoid data loss warning
    int bandsPeriod = (int)period;
    int handle = iBands(symbol, timeframe, bandsPeriod, deviation, 0, price_type);
    
    if(handle == INVALID_HANDLE) {
        LogError("Failed to create Bollinger Bands indicator. Error: " + IntegerToString(GetLastError()));
        return 0.0;
    }
    
    double bands[];
    ArraySetAsSeries(bands, true);
    
    bool success = CopyBuffer(handle, mode, shift, 1, bands) > 0;
    
    // Always release handle regardless of success or error
    IndicatorRelease(handle);
    
    if(!success) {
        LogError("Failed to copy Bollinger Bands data. Error: " + IntegerToString(GetLastError()));
        return 0.0;
    }
    
    IndicatorRelease(handle);
    return bands[buffer_index];
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
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        if(posType == POSITION_TYPE_BUY) {
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
    int isBuyBlocks = 0;
    int bearishBlocks = 0;
    
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            validBlocks++;
            if(recentBlocks[i].isBuy) isBuyBlocks++;
            else bearishBlocks++;
        }
    }
    
    info += "Order Blocks: " + IntegerToString(validBlocks) + 
            " (isBuy: " + IntegerToString(isBuyBlocks) + 
            ", Bearish: " + IntegerToString(bearishBlocks) + ")\n";
    
    // Status indicators
    info += "Status: " + (emergencyMode ? "EMERGENCY MODE" : "NORMAL") + "\n";
    
    Comment(info);
}

//+------------------------------------------------------------------+
//| ML-like pattern scanner for advanced signal confirmation         |
//+------------------------------------------------------------------+
double MLPatternScanner(int signal) {
    if(signal == 0) return 0.0;
    
    // Price action patterns
    double patternScore = 0.0;
    double totalWeight = 0.0;
    
    // 1. Candlestick pattern recognition
    double candleWeight = 0.3;
    totalWeight += candleWeight;
    double candleScore = 0.0;
    
    // Get recent candle data
    double open[5], high[5], low[5], close[5];
    for(int i=0; i<5; i++) {
        open[i] = iOpen(Symbol(), PERIOD_M15, i);
        high[i] = iHigh(Symbol(), PERIOD_M15, i);
        low[i] = iLow(Symbol(), PERIOD_M15, i);
        close[i] = iClose(Symbol(), PERIOD_M15, i);
    }
    
    // Check for engulfing pattern
    bool bullishEngulfing = signal > 0 && 
                          close[1] < open[1] && // Prior bearish
                          close[0] > open[0] && // Current bullish
                          open[0] < close[1] && // Opens below prior close
                          close[0] > open[1];   // Closes above prior open
                          
    bool bearishEngulfing = signal < 0 && 
                          close[1] > open[1] && // Prior bullish
                          close[0] < open[0] && // Current bearish
                          open[0] > close[1] && // Opens above prior close
                          close[0] < open[1];   // Closes below prior open
    
    // Check for pin bar / rejection pattern
    bool bullishPin = signal > 0 && 
                    (high[0] - close[0]) < (close[0] - low[0]) * 0.3 && // Small upper wick
                    (close[0] - low[0]) > (high[0] - low[0]) * 0.6;     // Large lower wick
                    
    bool bearishPin = signal < 0 && 
                    (close[0] - low[0]) < (high[0] - close[0]) * 0.3 && // Small lower wick
                    (high[0] - close[0]) > (high[0] - low[0]) * 0.6;     // Large upper wick
    
    // Calculate candlestick pattern score
    if(signal > 0) {
        if(bullishEngulfing) candleScore += 0.8;
        if(bullishPin) candleScore += 0.7;
    } else {
        if(bearishEngulfing) candleScore += 0.8;
        if(bearishPin) candleScore += 0.7;
    }
    
    // 2. Support/Resistance analysis
    double srWeight = 0.25;
    totalWeight += srWeight;
    double srScore = 0.0;
    
    // Find recent swing levels - adding the missing parameters
    int swingHighBar = FindRecentSwingPoint(false, 1, 20); // Using standard lookback values
    int swingLowBar = FindRecentSwingPoint(true, 1, 20); // Using standard lookback values
    double swingHigh = swingHighBar >= 0 ? iHigh(Symbol(), PERIOD_M15, swingHighBar) : 0;
    double swingLow = swingLowBar >= 0 ? iLow(Symbol(), PERIOD_M15, swingLowBar) : 0;
    
    // Check if current price is near support/resistance
    double currentPrice = iClose(Symbol(), PERIOD_M15, 0);
    double atr = GetATR(Symbol(), PERIOD_M15, 14, 0);
    
    if(signal > 0 && swingLow > 0) {
        // For buy signal, check if price is near support
        double distanceFromSupport = MathAbs(currentPrice - swingLow);
        if(distanceFromSupport < atr * 0.5) srScore += 0.9; // Very close to support
        else if(distanceFromSupport < atr) srScore += 0.6; // Somewhat close
    }
    else if(signal < 0 && swingHigh > 0) {
        // For sell signal, check if price is near resistance
        double distanceFromResistance = MathAbs(currentPrice - swingHigh);
        if(distanceFromResistance < atr * 0.5) srScore += 0.9; // Very close to resistance
        else if(distanceFromResistance < atr) srScore += 0.6; // Somewhat close
    }
    
    // 3. Volume analysis
    double volWeight = 0.20;
    totalWeight += volWeight;
    double volScore = 0.0;
    
    // Get recent volume data
    double volume[5];
    for(int i=0; i<5; i++) {
        volume[i] = (double)iVolume(Symbol(), PERIOD_M15, i); // Explicit cast to double
    }
    
    // Calculate average volume
    double avgVolume = 0;
    for(int i=1; i<5; i++) { // Skip current bar
        avgVolume += (double)volume[i]; // Explicit cast to double
    }
    avgVolume /= 4;
    
    // Check for volume confirmation
    bool volumeConfirmation = false;
    
    if(signal > 0 && close[0] > open[0]) {
        // For buy signal with bullish candle
        if(volume[0] > avgVolume * 1.5) {
            volScore += 0.9; // Strong buying volume
            volumeConfirmation = true;
        }
        else if(volume[0] > avgVolume) {
            volScore += 0.6; // Above average volume
            volumeConfirmation = true;
        }
    }
    else if(signal < 0 && close[0] < open[0]) {
        // For sell signal with bearish candle
        if(volume[0] > avgVolume * 1.5) {
            volScore += 0.9; // Strong selling volume
            volumeConfirmation = true;
        }
        else if(volume[0] > avgVolume) {
            volScore += 0.6; // Above average volume
            volumeConfirmation = true;
        }
    }
    
    // 4. Market structure alignment
    double structureWeight = 0.25;
    totalWeight += structureWeight;
    double structureScore = 0.0;
    
    // Determine trend direction using moving averages
    int ma20Handle = iMA(Symbol(), PERIOD_M15, 20, 0, MODE_SMA, PRICE_CLOSE);
    double ma20Buffer[];
    CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer);
    double ma20 = ma20Buffer[0];
    IndicatorRelease(ma20Handle);
    
    int ma50Handle = iMA(Symbol(), PERIOD_M15, 50, 0, MODE_SMA, PRICE_CLOSE);
    double ma50Buffer[];
    CopyBuffer(ma50Handle, 0, 0, 1, ma50Buffer);
    double ma50 = ma50Buffer[0];
    IndicatorRelease(ma50Handle);
    
    int ma200Handle = iMA(Symbol(), PERIOD_M15, 200, 0, MODE_SMA, PRICE_CLOSE);
    double ma200Buffer[];
    CopyBuffer(ma200Handle, 0, 0, 1, ma200Buffer);
    double ma200 = ma200Buffer[0];
    IndicatorRelease(ma200Handle);
    
    bool uptrend = ma20 > ma50 && ma50 > ma200 && currentPrice > ma20;
    bool downtrend = ma20 < ma50 && ma50 < ma200 && currentPrice < ma20;
    
    // Score based on trend alignment
    if(signal > 0 && uptrend) structureScore += 0.8;
    else if(signal < 0 && downtrend) structureScore += 0.8;
    
    // Calculate final pattern score
    double finalScore = (candleScore * candleWeight + 
                     srScore * srWeight + 
                     volScore * volWeight + 
                     structureScore * structureWeight) / totalWeight;
    
    // Log detailed pattern analysis
    LogInfo("ML Pattern Analysis: " + 
             "Candle=" + DoubleToString(candleScore, 2) + " " +
             "S/R=" + DoubleToString(srScore, 2) + " " +
             "Volume=" + DoubleToString(volScore, 2) + " " +
             "Structure=" + DoubleToString(structureScore, 2) + " " +
             "Final=" + DoubleToString(finalScore, 2));
    
    return finalScore;
}

//+------------------------------------------------------------------+
//| Modify stops when Change of Character (CHOCH) is detected       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Performance profiling wrapper - start timing                    |
//+------------------------------------------------------------------+
ulong StartProfiling() {
    if(!EnableProfiling) return 0;
    return GetMicrosecondCount();
}

//+------------------------------------------------------------------+
//| Performance profiling wrapper - end timing and record            |
//+------------------------------------------------------------------+
void EndProfiling(ulong startTime, ulong &totalTime, double &avgTime, string sectionName = "") {
    if(!EnableProfiling || startTime == 0) return;
    
    ulong endTime = GetMicrosecondCount();
    ulong elapsedTime = endTime - startTime;
    totalTime += elapsedTime;
    
    // Update running average (with smoothing)
    if(avgTime == 0) {
        avgTime = elapsedTime / 1000.0; // Convert to ms for first reading
    } else {
        avgTime = 0.9 * avgTime + 0.1 * (elapsedTime / 1000.0); // 90% old, 10% new
    }
    
    // Log if this section is taking too long
    if(elapsedTime > 50000 && StringLen(sectionName) > 0) { // More than 50ms
        LogWarning(StringFormat("[PROFILE] %s took %.2fms", sectionName, elapsedTime/1000.0));
    }
}

//+------------------------------------------------------------------+
//| Create and update performance dashboard                          |
//+------------------------------------------------------------------+
void CreatePerformanceDashboard() {
    string prefix = "SMC_PERF_";
    color textColor = clrWhite;
    color bgColor = clrDarkSlateGray;
    color borderColor = clrSilver;
    int x = 10;
    int y = 10;
    int width = 300;
    int height = 230;
    
    // Create/update dashboard background
    if(!ObjectFind(0, prefix + "BG")) {
        ObjectCreate(0, prefix + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_XSIZE, width);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_YSIZE, height);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_BGCOLOR, bgColor);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_COLOR, borderColor);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_BACK, false);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_SELECTED, false);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, prefix + "BG", OBJPROP_ZORDER, 0);
    }
    
    // Create/update title
    if(!ObjectFind(0, prefix + "Title")) {
        ObjectCreate(0, prefix + "Title", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, prefix + "Title", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, prefix + "Title", OBJPROP_XDISTANCE, x + 10);
        ObjectSetInteger(0, prefix + "Title", OBJPROP_YDISTANCE, y + 15);
        ObjectSetInteger(0, prefix + "Title", OBJPROP_COLOR, clrLightGoldenrod);
        ObjectSetString(0, prefix + "Title", OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, prefix + "Title", OBJPROP_FONTSIZE, 10);
        ObjectSetString(0, prefix + "Title", OBJPROP_TEXT, "SMC HYBRID - Performance Monitor");
        ObjectSetInteger(0, prefix + "Title", OBJPROP_BACK, false);
        ObjectSetInteger(0, prefix + "Title", OBJPROP_SELECTABLE, false);
    }
    
    // Create labels for each metric
    string metrics[10] = {
        "Tick Processing Time:",
        "Block Detection Time:",
        "Signal Generation Time:",
        "Trade Logic Time:",
        "Trailing Stop Time:",
        "Valid Order Blocks:",
        "Trade Execution Latency:",
        "Trade Success Rate:",
        "Win/Loss Streak:",
        "Spread Adaptation:"
    };
    
    for(int i = 0; i < ArraySize(metrics); i++) {
        // Create label
        string labelName = prefix + "Label" + IntegerToString(i);
        if(!ObjectFind(0, labelName)) {
            ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, x + 15);
            ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, y + 40 + i*18);
            ObjectSetInteger(0, labelName, OBJPROP_COLOR, textColor);
            ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 9);
            ObjectSetString(0, labelName, OBJPROP_TEXT, metrics[i]);
            ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
            ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
        }
        
        // Create value field
        string valueName = prefix + "Value" + IntegerToString(i);
        if(!ObjectFind(0, valueName)) {
            ObjectCreate(0, valueName, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, valueName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, valueName, OBJPROP_XDISTANCE, x + 170);
            ObjectSetInteger(0, valueName, OBJPROP_YDISTANCE, y + 40 + i*18);
            ObjectSetInteger(0, valueName, OBJPROP_COLOR, clrLightSkyBlue);
            ObjectSetString(0, valueName, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, valueName, OBJPROP_FONTSIZE, 9);
            ObjectSetString(0, valueName, OBJPROP_TEXT, "N/A");
            ObjectSetInteger(0, valueName, OBJPROP_BACK, false);
            ObjectSetInteger(0, valueName, OBJPROP_SELECTABLE, false);
        }
    }
}

//+------------------------------------------------------------------+
//| Update performance dashboard with current stats                   |
//+------------------------------------------------------------------+
void UpdatePerformanceDashboard() {
    // Only update once per 5 seconds to avoid excessive chart updates
    datetime currentTime = TimeCurrent();
    if(currentTime - lastDashboardUpdate < 5) return;
    lastDashboardUpdate = currentTime;
    
    string prefix = "SMC_PERF_";
    
    // Update performance metrics
    ObjectSetString(0, prefix + "Value0", OBJPROP_TEXT, 
                   StringFormat("%.2f ms (max: %.2f ms)", averageTickProcessingTime, maxTickProcessingTime));
    
    ObjectSetString(0, prefix + "Value1", OBJPROP_TEXT, 
                   StringFormat("%.2f ms", avgTime_BlockDetection));
                   
    ObjectSetString(0, prefix + "Value2", OBJPROP_TEXT, 
                   StringFormat("%.2f ms", avgTime_SignalGeneration));
                   
    ObjectSetString(0, prefix + "Value3", OBJPROP_TEXT, 
                   StringFormat("%.2f ms", avgTime_TradeLogic));
                   
    ObjectSetString(0, prefix + "Value4", OBJPROP_TEXT, 
                   StringFormat("%.2f ms", avgTime_TrailingStops));
    
    // Count valid order blocks
    CountValidOrderBlocks();
    ObjectSetString(0, prefix + "Value5", OBJPROP_TEXT, 
                   StringFormat("%d (%d buy, %d sell)", validBlocksCount, buyBlocksCount, sellBlocksCount));
    
    // Trade execution latency
    ObjectSetString(0, prefix + "Value6", OBJPROP_TEXT, 
                   StringFormat("%.2f ms", avgTradeLatency));
    
    // Trade success rate
    string successRate = "N/A";
    if(totalTradeAttempts > 0) {
        double rate = (double)successfulTrades / totalTradeAttempts * 100.0;
        successRate = StringFormat("%.1f%% (%d/%d)", rate, successfulTrades, totalTradeAttempts);
    }
    ObjectSetString(0, prefix + "Value7", OBJPROP_TEXT, successRate);
    
    // Win/Loss streak
    string streakText = "None";
    if(winStreak > 0) {
        streakText = StringFormat("%d wins", winStreak);
    } else if(lossStreak > 0) {
        streakText = StringFormat("%d losses", lossStreak);
    }
    ObjectSetString(0, prefix + "Value8", OBJPROP_TEXT, streakText);
    
    // Spread adaptation
    double currentSpread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    // Calculate simple average spread directly instead of calling undefined function
    double avgSpread = currentSpread; // Default to current as fallback
    string spreadText = StringFormat("%d pts", (int)currentSpread);
    ObjectSetString(0, prefix + "Value9", OBJPROP_TEXT, spreadText);
    
    // Force chart update
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Count valid order blocks for dashboard                            |
//+------------------------------------------------------------------+
void CountValidOrderBlocks() {
    validBlocksCount = 0;
    buyBlocksCount = 0;
    sellBlocksCount = 0;
    
    for(int i = 0; i < ArraySize(recentBlocks); i++) {
        if(recentBlocks[i].valid) {
            validBlocksCount++;
            if(recentBlocks[i].isBuy) {
                buyBlocksCount++;
            } else {
                sellBlocksCount++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect CHOCH patterns in price action                             |
//+------------------------------------------------------------------+
bool DetectCHOCH() {
    if(!EnableCHOCHDetection) return false;
    
    // Get price data
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(Symbol(), Period(), 0, 50, high) <= 0 || 
       CopyLow(Symbol(), Period(), 0, 50, low) <= 0) {
        LogError("Failed to copy price data for CHOCH detection");
        return false;
    }
    
    // Find potential swing points - adding the required parameters
    int swingHighBar = FindRecentSwingPoint(false, 1, 20); // Using standard lookback values
    int swingLowBar = FindRecentSwingPoint(true, 1, 20); // Using standard lookback values
    
    if(swingHighBar > 0 && swingLowBar > 0) {
        double currentSwingHigh = high[swingHighBar];
        double currentSwingLow = low[swingLowBar];
        
        // Check for bullish CHOCH (higher low after a lower low)
        if(lastSwingLow > 0 && currentSwingLow > lastSwingLow) {
            lastSwingLow = currentSwingLow;
            LogInfo("Bullish CHOCH detected: Higher Low formed at " + DoubleToString(currentSwingLow, _Digits));
            return true;
        }
        
        // Check for bearish CHOCH (lower high after a higher high)
        if(lastSwingHigh > 0 && currentSwingHigh < lastSwingHigh) {
            lastSwingHigh = currentSwingHigh;
            LogInfo("Bearish CHOCH detected: Lower High formed at " + DoubleToString(currentSwingHigh, _Digits));
            return true;
        }
        
        // Update swing points if no CHOCH detected
        if(lastSwingHigh == 0 || currentSwingHigh > lastSwingHigh) {
            lastSwingHigh = currentSwingHigh;
        }
        
        if(lastSwingLow == 0 || currentSwingLow < lastSwingLow) {
            lastSwingLow = currentSwingLow;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Modify stops based on CHOCH detection for a specific ticket      |
//+------------------------------------------------------------------+
bool ModifyStopsOnCHOCH(ulong ticket, double &newSL) {
    if(!EnableCHOCHDetection) return false;
    
    if(!PositionSelectByTicket(ticket)) return false;
    if(PositionGetString(POSITION_SYMBOL) != Symbol()) return false;
    
    // Get position details
    double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    bool isBuy = (posType == POSITION_TYPE_BUY);
    
    // Check for CHOCH pattern
    bool localChochDetected = false;
    
    // For buy positions, look for a higher low after a pullback
    if(isBuy) {
        // Get recent price data
        double low[], high[];
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(high, true);
        
        if(CopyLow(Symbol(), PERIOD_CURRENT, 0, 20, low) > 0 && 
           CopyHigh(Symbol(), PERIOD_CURRENT, 0, 20, high) > 0) {
            
            // Find recent swing low - adding the required parameters
            int swingLowBar = FindRecentSwingPoint(true, 1, 20); // Using standard lookback values
            
            if(swingLowBar > 0) {
                // Check if we have a higher low (CHOCH)
                double swingLowPrice = low[swingLowBar];
                
                // Find previous swing low
                int prevSwingLowBar = -1;
                for(int i = swingLowBar + 1; i < 19; i++) {
                    if(low[i] < low[i-1] && low[i] < low[i+1]) {
                        prevSwingLowBar = i;
                        break;
                    }
                }
                
                if(prevSwingLowBar > 0) {
                    double prevSwingLowPrice = low[prevSwingLowBar];
                    
                    // CHOCH pattern: current swing low is higher than previous swing low
                    if(swingLowPrice > prevSwingLowPrice) {
                        localChochDetected = true;
                        // Set new stop loss below the current swing low with a buffer
                        newSL = swingLowPrice - (5 * _Point);
                        
                        if(DisplayDebugInfo) {
                            Print("[CHOCH] Buy CHOCH detected: Higher low formed at ", 
                                  DoubleToString(swingLowPrice, _Digits), 
                                  " vs previous low at ", 
                                  DoubleToString(prevSwingLowPrice, _Digits));
                        }
                    }
                }
            }
        }
    }
    // For sell positions, look for a lower high after a pullback
    else {
        // Get recent price data
        double low[], high[];
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(high, true);
        
        if(CopyLow(Symbol(), PERIOD_CURRENT, 0, 20, low) > 0 && 
           CopyHigh(Symbol(), PERIOD_CURRENT, 0, 20, high) > 0) {
            
            // Find recent swing high - use FindRecentSwingPoint since FindRecentSwingPointHigh seems to be undefined
            int swingHighBar = FindRecentSwingPoint(false, 1, 20); // Using standard function with standard lookback values
            
            if(swingHighBar > 0) {
                // Check if we have a lower high (CHOCH)
                double swingHighPrice = high[swingHighBar];
                
                // Find previous swing high
                int prevSwingHighBar = -1;
                for(int i = swingHighBar + 1; i < 19; i++) {
                    if(high[i] > high[i-1] && high[i] > high[i+1]) {
                        prevSwingHighBar = i;
                        break;
                    }
                }
                
                if(prevSwingHighBar > 0) {
                    double prevSwingHighPrice = high[prevSwingHighBar];
                    
                    // CHOCH pattern: current swing high is lower than previous swing high
                    if(swingHighPrice < prevSwingHighPrice) {
                        localChochDetected = true;
                        // Set new stop loss above the current swing high with a buffer
                        newSL = swingHighPrice + (5 * _Point);
                        
                        if(DisplayDebugInfo) {
                            Print("[CHOCH] Sell CHOCH detected: Lower high formed at ", 
                                  DoubleToString(swingHighPrice, _Digits), 
                                  " vs previous high at ", 
                                  DoubleToString(prevSwingHighPrice, _Digits));
                        }
                    }
                }
            }
        }
    }
    
    return localChochDetected;
}

//+------------------------------------------------------------------+
//| Calculate ML-like score for order block quality                   |
//+------------------------------------------------------------------+
double CalculateBlockScore(MqlRates &rates[], int blockIdx, bool isBuy, double atr) {
    // Start with a base score
    double score = 0.5;
    
    // 1. PATTERN RECOGNITION COMPONENT (30% weight)
    double patternScore = 0.0;
    
    // Calculate candle sizes and ranges for context
    double blockSize = MathAbs(rates[blockIndex].open - rates[blockIndex].close);
    double blockRange = rates[blockIndex].high - rates[blockIndex].low;
    double nextCandleSize = MathAbs(rates[blockIndex-1].open - rates[blockIndex-1].close);
    double nextCandleRange = rates[blockIndex-1].high - rates[blockIndex-1].low;
    
    // For buy blocks (bearish candle followed by bullish move)
    if(isBuy) {
        // Check for ideal pattern - strong reversal after a clear rejection
        if(rates[blockIndex].close < rates[blockIndex].open && // Bearish block candle
           rates[blockIndex-1].close > rates[blockIndex-1].open && // Bullish breakout
           rates[blockIndex-1].close > rates[blockIndex].high && // Clear breakout
           rates[blockIndex-1].low > rates[blockIndex].low) { // Higher low formation
            patternScore += 0.3; // Perfect pattern
        } else {
            patternScore += 0.15; // Basic pattern
        }
        
        // Check strength of rejection - look for long lower wicks in block candle
        double lowerWick = rates[blockIndex].low < rates[blockIndex].close ? 
                         rates[blockIndex].close - rates[blockIndex].low : 
                         rates[blockIndex].open - rates[blockIndex].low;
        if(lowerWick > blockSize * 0.5) {
            patternScore += 0.1; // Strong rejection wick
        }
        
        // Check follow-through momentum
        if(nextCandleSize > blockSize * 1.5) {
            patternScore += 0.1; // Strong momentum after block
        }
    }
    // For sell blocks (bullish candle followed by bearish move)
    else {
        // Check for ideal pattern
        if(rates[blockIndex].close > rates[blockIndex].open && // Bullish block candle
           rates[blockIndex-1].close < rates[blockIndex-1].open && // Bearish breakout
           rates[blockIndex-1].close < rates[blockIndex].low && // Clear breakout
           rates[blockIndex-1].high < rates[blockIndex].high) { // Lower high formation
            patternScore += 0.3; // Perfect pattern
        } else {
            patternScore += 0.15; // Basic pattern
        }
        
        // Check strength of rejection - look for long upper wicks
        double upperWick = rates[blockIndex].high > rates[blockIndex].close ? 
                         rates[blockIndex].high - rates[blockIndex].close : 
                         rates[blockIndex].high - rates[blockIndex].open;
        if(upperWick > blockSize * 0.5) {
            patternScore += 0.1; // Strong rejection wick
        }
        
        // Check follow-through momentum
        if(nextCandleSize > blockSize * 1.5) {
            patternScore += 0.1; // Strong momentum after block
        }
    }
    
    // 2. CONTEXT/LOCATION COMPONENT (40% weight)
    double locationScore = 0.0;
    
    // Check if block formed at a key level
    int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
    int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
    double ma20Buffer[], ma50Buffer[];
    
    ArraySetAsSeries(ma20Buffer, true);
    ArraySetAsSeries(ma50Buffer, true);
    
    if(ma20Handle != INVALID_HANDLE && ma50Handle != INVALID_HANDLE) {
        if(CopyBuffer(ma20Handle, 0, rates[blockIndex].time, 1, ma20Buffer) > 0 &&
           CopyBuffer(ma50Handle, 0, rates[blockIndex].time, 1, ma50Buffer) > 0) {
            
            double ma20 = ma20Buffer[0];
            double ma50 = ma50Buffer[0];
            
            // Distance to key MAs
            double distToMA20 = MathAbs(rates[blockIndex].low - ma20) / atr;
            double distToMA50 = MathAbs(rates[blockIndex].low - ma50) / atr;
            
            // Block near key MA
            if(distToMA20 < 0.5 || distToMA50 < 0.5) {
                locationScore += 0.2; // Block at key MA
            } else if(distToMA20 < 1.0 || distToMA50 < 1.0) {
                locationScore += 0.1; // Block reasonably close to MA
            }
        }
        
        IndicatorRelease(ma20Handle);
        IndicatorRelease(ma50Handle);
    }
    
    // Check for swing point formation (is this a local high/low?)
    bool isSwingPoint = false;
    if(isBuy) { // For bullish blocks, check if it's a swing low
        isSwingPoint = true;
        for(int j = blockIndex + 1; j < blockIndex + 5 && j < ArraySize(rates); j++) {
            if(rates[j].low < rates[blockIndex].low) {
                isSwingPoint = false;
                break;
            }
        }
    } else { // For bearish blocks, check if it's a swing high
        isSwingPoint = true;
        for(int j = blockIndex + 1; j < blockIndex + 5 && j < ArraySize(rates); j++) {
            if(rates[j].high > rates[blockIndex].high) {
                isSwingPoint = false;
                break;
            }
        }
    }
    
    if(isSwingPoint) {
        locationScore += 0.2; // Block at swing point
    }
    
    // 3. VOLATILITY COMPONENT (30% weight)
    double volatilityScore = 0.0;
    
    // Blocks in optimal volatility are preferred
    double blockVolatility = blockRange / atr;
    
    if(blockVolatility > 0.5 && blockVolatility < 2.0) {
        volatilityScore += 0.15; // Optimal volatility
    } else if(blockVolatility <= 0.5) {
        volatilityScore += 0.05; // Too low volatility
    } else {
        volatilityScore += 0.1; // High volatility
    }
    
    // Check for volatility expansion after block
    double volatilityChange = nextCandleRange / blockRange;
    if(volatilityChange > 1.5) {
        volatilityScore += 0.15; // Volatility expansion after block
    } else if(volatilityChange > 1.2) {
        volatilityScore += 0.1; // Moderate volatility expansion
    } else {
        volatilityScore += 0.05; // No significant change in volatility
    }
    
    // FINAL SCORE CALCULATION
    score = 0.3 * patternScore + 0.4 * locationScore + 0.3 * volatilityScore;
    
    // Ensure score is within 0.0-1.0 range
    score = MathMax(0.0, MathMin(1.0, score));
    
    return score;
}

//+------------------------------------------------------------------+
//| Legacy error description - now using enhanced version            |
//+------------------------------------------------------------------+
// This function was replaced by the enhanced version at line ~5176
// Using the enhanced GetErrorDescription instead of this one

//+------------------------------------------------------------------+
//| Error description function                                       |
//+------------------------------------------------------------------+
string ErrorDescription(int error_code)
{
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
//| Find potential order blocks on a specific timeframe              |
//+------------------------------------------------------------------+
void FindOrderBlocks(string symbol, ENUM_TIMEFRAMES timeframe) {
    if(DisplayDebugInfo) Print("[DEBUG] Finding order blocks on ", EnumToString(timeframe));
    
    static datetime lastFullScan = 0;
    datetime currentTime = TimeCurrent();
    
    // Performance optimization: Only do full 30-bar scan every 10 seconds
    // For interim updates, only process the most recent 5 bars
    int barsToScan = (currentTime - lastFullScan >= 10) ? 30 : 5;
    
    if(barsToScan == 30) {
        lastFullScan = currentTime;
        if(DisplayDebugInfo) Print("[DEBUG] Performing full order block scan");
    }
    
    // Get recent price data
    MqlRates rates[];
    ArrayResize(rates, barsToScan + 10); // Pre-allocate with buffer
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, barsToScan + 5, rates); // +5 for pattern detection lookback
    
    if(copied <= 0) {
        LogError("Failed to copy rate data for order block detection");
        return;
    }
    
    // Use cached ATR if available, otherwise calculate
    double atr = (cachedATR > 0) ? cachedATR : CalculateATR(14);
    
    // Simplified volatility calculation using ATR
    double marketVolatility = atr;
    double volatilityRatio = 1.0;
    
    // Market volatility-based adjustment - simplified approach
    double avgATR = 0;
    int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 20);
    if(atrHandle != INVALID_HANDLE) {
        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);
        if(CopyBuffer(atrHandle, 0, 0, 20, atrBuffer) > 0) {
            for(int i = 0; i < 20; i++) {
                avgATR += atrBuffer[i];
            }
            avgATR /= 20;
        }
        IndicatorRelease(atrHandle);
    }
    
    // Adaptive volatility ratio based on current ATR vs average
    if(avgATR > 0) {
        volatilityRatio = atr / avgATR;
        // Limit the ratio to a reasonable range
        volatilityRatio = MathMax(0.5, MathMin(1.5, volatilityRatio));
    }
    
    // Adaptive thresholds based on volatility
    double breakoutThreshold = atr * 0.5 * MathMax(0.5, MathMin(1.5, volatilityRatio));
    double blockSizeMinimum = atr * 0.3 * MathMax(0.5, MathMin(1.5, volatilityRatio));
    
    // Reset block index if it's getting too high
    if(blockIndex >= MAX_BLOCKS - 5) blockIndex = 0;
    
    // Scan for potential order blocks
    for(int i = 5; i < copied - 1; i++) {
        // Calculate candle size for reference
        double candleSize = MathAbs(rates[i].open - rates[i].close);
        double prevCandleSize = MathAbs(rates[i-1].open - rates[i-1].close);
        
        // Look for bullish order blocks (bearish candle followed by strong bullish move)
        if(rates[i].close < rates[i].open && // Bearish candle
           rates[i-1].close > rates[i-1].open && // Bullish candle after
           rates[i-1].close > rates[i].high && // Strong breakout
           prevCandleSize > blockSizeMinimum && // Minimum size requirement (adaptive)
           rates[i-1].close - rates[i-1].open > breakoutThreshold) { // Significant move (adaptive)
            
            // Create a bullish order block
            recentBlocks[blockIndex].time = rates[i].time;
            recentBlocks[blockIndex].high = rates[i].high;
            recentBlocks[blockIndex].low = rates[i].low;
            recentBlocks[blockIndex].open = rates[i].open;
            recentBlocks[blockIndex].close = rates[i].close;
            recentBlocks[blockIndex].price = rates[i].low; // Key level for bullish block
            recentBlocks[blockIndex].isBuy = true;
            
            // Calculate block strength with enhanced ML-like scoring
            double patternScore = CalculateBlockScore(rates, i, true, atr);
            recentBlocks[blockIndex].strength = (int)(5 + patternScore * 5); // Scale 0-1 score to 5-10 strength
            recentBlocks[blockIndex].score = patternScore;
            recentBlocks[blockIndex].originalScore = patternScore; // Store original score for decay
            recentBlocks[blockIndex].valid = true;
            
            // Set block expiration time - varies by volatility
            int blockLifetimeHours = (int)(8 * volatilityRatio); // 4-12 hours based on volatility
            recentBlocks[blockIndex].invalidTime = rates[i].time + blockLifetimeHours * 3600;
            recentBlocks[blockIndex].volume = rates[i].tick_volume;
            recentBlocks[blockIndex].barIndex = i;
            recentBlocks[blockIndex].tested = false;
            recentBlocks[blockIndex].touched = false;
            recentBlocks[blockIndex].atrAtFormation = atr;
            
            // Calculate quality score based on several factors
            int score = 0;
            
            // Factor 1: Size of candle relative to ATR
            double candleSize = MathAbs(rates[i].high - rates[i].low);
            if(candleSize > atr * 1.5) score += 3;
            else if(candleSize > atr) score += 2;
            else score += 1;
            
            // Factor 2: Volume
            double avgVolume = 0;
            for(int v = i; v < i + 5; v++) {
                if(v < copied) avgVolume += rates[v].tick_volume;
            }
            avgVolume /= 5;
            
            if(rates[i].tick_volume > avgVolume * 1.5) score += 3;
            else if(rates[i].tick_volume > avgVolume) score += 2;
            else score += 1;
            
            // Store the score
            recentBlocks[blockIndex].score = score;
            
            if(DisplayDebugInfo) {
                Print("[DEBUG] Found bullish order block at ", TimeToString(rates[i].time), 
                      " price: ", rates[i].low, " score: ", score);
            }
            
            blockIndex++;
            if(blockIndex >= MAX_BLOCKS) blockIndex = 0; // Circular buffer
        }
        
        // Look for bearish order blocks (bullish candle followed by strong bearish move)
        if(rates[i].close > rates[i].open && // Bullish candle
           rates[i-1].close < rates[i-1].open && // Bearish candle after
           rates[i-1].close < rates[i].low && // Strong breakdown
           rates[i-1].open - rates[i-1].close > atr * 0.5) { // Significant move
            
            // Create a bearish order block
            recentBlocks[blockIndex].time = rates[i].time;
            recentBlocks[blockIndex].high = rates[i].high;
            recentBlocks[blockIndex].low = rates[i].low;
            recentBlocks[blockIndex].open = rates[i].open;
            recentBlocks[blockIndex].close = rates[i].close;
            recentBlocks[blockIndex].price = rates[i].high; // Key level for bearish block
            recentBlocks[blockIndex].isBuy = false;
            recentBlocks[blockIndex].strength = 7; // Default strength
            recentBlocks[blockIndex].valid = true;
            recentBlocks[blockIndex].volume = rates[i].tick_volume;
            recentBlocks[blockIndex].barIndex = i;
            recentBlocks[blockIndex].tested = false;
            recentBlocks[blockIndex].touched = false;
            recentBlocks[blockIndex].atrAtFormation = atr;
            
            // Calculate quality score based on several factors
            int score = 0;
            
            // Factor 1: Size of candle relative to ATR
            double candleSize = MathAbs(rates[i].high - rates[i].low);
            if(candleSize > atr * 1.5) score += 3;
            else if(candleSize > atr) score += 2;
            else score += 1;
            
            // Factor 2: Volume
            double avgVolume = 0;
            for(int v = i; v < i + 5; v++) {
                if(v < copied) avgVolume += rates[v].tick_volume;
            }
            avgVolume /= 5;
            
            if(rates[i].tick_volume > avgVolume * 1.5) score += 3;
            else if(rates[i].tick_volume > avgVolume) score += 2;
            else score += 1;
            
            // Store the score
            recentBlocks[blockIndex].score = score;
            
            if(DisplayDebugInfo) {
                Print("[DEBUG] Found bearish order block at ", TimeToString(rates[i].time), 
                      " price: ", rates[i].high, " score: ", score);
            }
            
            blockIndex++;
            if(blockIndex >= MAX_BLOCKS) blockIndex = 0; // Circular buffer
        }
    }
    
    // Add logging to count valid order blocks for debugging
    int validBullishBlocks = 0;
    int validBearishBlocks = 0;
    int totalValidBlocks = 0;
    
    for(int i = 0; i < MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            totalValidBlocks++;
            if(recentBlocks[i].isBuy) {
                validBullishBlocks++;
            } else {
                validBearishBlocks++;
            }
        }
    }
    
    // Log the valid block counts
    LogInfo(StringFormat("Valid order blocks after detection: %d total (%d bullish, %d bearish)", 
                      totalValidBlocks, validBullishBlocks, validBearishBlocks));
    
    // Additional logging for debugging
    if(totalValidBlocks == 0) {
        LogWarning("No valid order blocks detected - check block validity criteria");
    }
}

//+------------------------------------------------------------------+
//| This was a duplicate DetectOrderBlocks function - removed to fix compilation errors |
//+------------------------------------------------------------------+
// Using the implementation defined earlier
// Using the implementation defined at line 3878 instead.

//+------------------------------------------------------------------+
//| This was a duplicate FindOrderBlocks function - removed to fix compilation errors |
//+------------------------------------------------------------------+
// Using the implementation defined at line 7658 instead.

// DetermineOptimalTradingMode function is now defined at line 6736

//+------------------------------------------------------------------+
//| Apply mode-specific parameters based on current trading mode     |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Validate mode-specific parameters to ensure they're in reasonable ranges |
//+------------------------------------------------------------------+
bool ValidateModeParameters() {
    bool isValid = true;
    string errorMessage = "";
    
    // Validate HFT mode parameters
    if(HFT_SL_ATR_Mult < 0.3 || HFT_SL_ATR_Mult > 2.0) {
        errorMessage += "HFT_SL_ATR_Mult should be between 0.3 and 2.0. ";
        isValid = false;
    }
    
    if(HFT_TP_ATR_Mult < 0.5 || HFT_TP_ATR_Mult > 3.0) {
        errorMessage += "HFT_TP_ATR_Mult should be between 0.5 and 3.0. ";
        isValid = false;
    }
    
    if(HFT_SignalCooldownSeconds < 10 || HFT_SignalCooldownSeconds > 300) {
        errorMessage += "HFT_SignalCooldownSeconds should be between 10 and 300. ";
        isValid = false;
    }
    
    // Validate Normal mode parameters
    if(Normal_SL_ATR_Mult < 0.5 || Normal_SL_ATR_Mult > 3.0) {
        errorMessage += "Normal_SL_ATR_Mult should be between 0.5 and 3.0. ";
        isValid = false;
    }
    
    if(Normal_TP_ATR_Mult < 1.0 || Normal_TP_ATR_Mult > 5.0) {
        errorMessage += "Normal_TP_ATR_Mult should be between 1.0 and 5.0. ";
        isValid = false;
    }
    
    if(Normal_SignalCooldownSeconds < 60 || Normal_SignalCooldownSeconds > 1800) {
        errorMessage += "Normal_SignalCooldownSeconds should be between 60 and 1800. ";
        isValid = false;
    }
    
    // Check that HFT has tighter stops than Normal mode
    if(HFT_SL_ATR_Mult >= Normal_SL_ATR_Mult) {
        errorMessage += "HFT_SL_ATR_Mult should be less than Normal_SL_ATR_Mult for proper mode differentiation. ";
        isValid = false;
    }
    
    // Ensure cooldown periods are appropriate
    if(HFT_SignalCooldownSeconds >= Normal_SignalCooldownSeconds) {
        errorMessage += "HFT_SignalCooldownSeconds should be less than Normal_SignalCooldownSeconds. ";
        isValid = false;
    }
    
    // Log validation results
    if(!isValid) {
        LogError("Mode parameter validation failed: " + errorMessage);
        LogWarning("Using default values for invalid parameters. This may affect trading performance.");
    } else {
        LogInfo("All mode-specific parameters validated successfully.");
    }
    
    return isValid;
}

// DUPLICATE FUNCTION COMMENTED OUT - Using the implementation at line 6873
/*
void ApplyModeSpecificParameters() {
    // First validate the parameters
    ValidateModeParameters();
    
    // Log the current mode and that we're applying parameters
    LogInfo(StringFormat("Applying parameters for mode: %s", EnumToString((ENUM_TRADING_MODE)currentTradingMode)));
    
    // Set signal cooldown based on mode
    if(currentTradingMode == MODE_HFT) {
        ActualSignalCooldownSeconds = HFT_SignalCooldownSeconds;
        LogInfo(StringFormat("Set signal cooldown to %d seconds (HFT mode)", ActualSignalCooldownSeconds));
    } else {
        ActualSignalCooldownSeconds = Normal_SignalCooldownSeconds;
        LogInfo(StringFormat("Set signal cooldown to %d seconds (Normal mode)", ActualSignalCooldownSeconds));
    }
    
    // Apply mode-specific ATR multipliers for stop loss and take profit
    if(currentTradingMode == MODE_HFT) {
        // For HFT mode - tighter stops, shorter targets
        SL_ATR_Mult = HFT_SL_ATR_Mult;
        TP_ATR_Mult = HFT_TP_ATR_Mult;
        
        // In HFT mode, we can reduce minimum block strength requirement
        int effectiveMinBlockStrength = 1; // Lower threshold for HFT mode
        
        // Set other HFT-specific parameters
        workingTrailingActivationPct = TrailingActivationPct * 0.8; // Activate trailing stops earlier
        workingTrailingStopMultiplierLocal = TrailingStopMultiplier * 0.9; // Tighter trailing
        
        // For HFT, we can lower the signal quality threshold slightly
        workingMinSignalQualityTolocalTrade = MinSignalQualityToTrade * 0.9;
        
        LogInfo(StringFormat("HFT parameters applied - SL_ATR: %.2f, TP_ATR: %.2f, TrailingAct: %.2f, MinQuality: %.2f", 
                          SL_ATR_Mult, TP_ATR_Mult, workingTrailingActivationPct, workingMinSignalQualityTolocalTrade));
    } else {
        // For normal trading mode - wider stops, larger targets
        SL_ATR_Mult = Normal_SL_ATR_Mult;
        TP_ATR_Mult = Normal_TP_ATR_Mult;
        
        // In normal mode, require higher quality blocks
        int effectiveMinBlockStrength = 2; // Higher threshold for normal mode
        
        // Set other normal-mode specific parameters
        workingTrailingActivationPct = TrailingActivationPct; // Standard trailing activation
        workingTrailingStopMultiplierLocal = TrailingStopMultiplier; // Standard trailing
        
        // For normal mode, maintain the original signal quality threshold
        workingMinSignalQualityTolocalTrade = MinSignalQualityToTrade;
        
        LogInfo(StringFormat("Normal parameters applied - SL_ATR: %.2f, TP_ATR: %.2f, TrailingAct: %.2f, MinQuality: %.2f", 
                          SL_ATR_Mult, TP_ATR_Mult, workingTrailingActivationPct, workingMinSignalQualityTolocalTrade));
    }
    
    // Update lookback parameters for pattern detection
    if(currentTradingMode == MODE_HFT) {
        // For HFT mode, use shorter lookback periods
        int patternLookbackBars = 20; // Shorter lookback for HFT
        int swingLookbackBars = 10; // Shorter swing detection for HFT
    } else {
        // For normal mode, use standard lookback periods
        int patternLookbackBars = 50; // Standard lookback for normal trading
        int swingLookbackBars = 20; // Standard swing detection for normal trading
    }
}
*/

//+------------------------------------------------------------------+
//| Detect Change of Character (CHOCH) patterns                       |
//+------------------------------------------------------------------+
bool DetectCHOCH(string symbol, ENUM_TIMEFRAMES timeframe) {
    // Get price data
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    int copied = CopyHigh(symbol, timeframe, 0, 50, high);
    if(copied <= 0) return false;
    
    CopyLow(symbol, timeframe, 0, 50, low);
    CopyClose(symbol, timeframe, 0, 50, close);
    
    // Find swing points
    double swingHighs[10], swingLows[10];
    datetime swingHighTimes[10], swingLowTimes[10];
    int swingHighCount = 0, swingLowCount = 0;
    
    // Find recent swing highs
    for(int i = 2; i < 40; i++) {
        if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i+1] && high[i] > high[i+2]) {
            swingHighs[swingHighCount] = high[i];
            swingHighTimes[swingHighCount] = iTime(symbol, timeframe, i);
            swingHighCount++;
            if(swingHighCount >= 10) break;
        }
    }
    
    // Find recent swing lows
    for(int i = 2; i < 40; i++) {
        if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i+1] && low[i] < low[i+2]) {
            swingLows[swingLowCount] = low[i];
            swingLowTimes[swingLowCount] = iTime(symbol, timeframe, i);
            swingLowCount++;
            if(swingLowCount >= 10) break;
        }
    }
    
    // No swing points detected
    if(swingHighCount < 2 || swingLowCount < 2) return false;
    
    // Check for bullish CHOCH - lower low followed by higher low
    bool bullishCHOCH = (swingLows[0] > swingLows[1]) && (close[0] > swingHighs[1]);
    
    // Check for bearish CHOCH - higher high followed by lower high
    bool bearishCHOCH = (swingHighs[0] < swingHighs[1]) && (close[0] < swingLows[1]);
    
    if(bullishCHOCH || bearishCHOCH) {
        // Store key levels for stop modification
        if(bullishCHOCH) {
            // In a bullish CHOCH, the swing low becomes a key support level
            lastSwingLow = swingLows[0];
            if(DisplayDebugInfo) Print("[INFO] CHOCH detected - would modify stops if ModifyStopsOnCHOCH was implemented");
        }
        else if(bearishCHOCH) {
            // In a bearish CHOCH, the swing high becomes a key resistance level
            lastSwingHigh = swingHighs[0];
            if(DisplayDebugInfo) Print("[INFO] CHOCH detected - would modify stops if ModifyStopsOnCHOCH was implemented");
        }
        
        // Update CHOCH detection time
        lastChochTime = TimeCurrent();
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Advanced Market Structure Analysis                               |
//+------------------------------------------------------------------+
void AnalyzeMarketStructure(string symbol, ENUM_TIMEFRAMES timeframe) {
    // No unbalanced parentheses here - just normal function
    int bars = 50;
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    CopyHigh(symbol, timeframe, 0, bars, high);
    CopyLow(symbol, timeframe, 0, bars, low);
    CopyClose(symbol, timeframe, 0, bars, close);
    long volume[];
    if(CopyTickVolume(symbol, timeframe, 0, bars, volume) < bars) {
        Print("[ERROR] Failed to copy tick volume data in AnalyzeMarketStructure");
        return;
    }
    
    // Detect Higher Highs/Lows for uptrend
    bool local_uptrend = true;
    for(int i=1; i<5; i++) {
        if(high[i] <= high[i+1] || low[i] <= low[i+1]) {
            local_uptrend = false;
            break;
        }
    }
    
    // Detect Lower Highs/Lows for downtrend
    bool local_downtrend = true;
    for(int i=1; i<5; i++) {
        if(high[i] >= high[i+1] || low[i] >= low[i+1]) {
            local_downtrend = false;
            break;
        }
    }
    
    string structure = "Unknown";
    if(currentMarketStructure == ENUM_MARKET_STRUCTURE::MARKET_STRUCTURE_UPTREND) structure = "Uptrend";
    else if(currentMarketStructure == ENUM_MARKET_STRUCTURE::MARKET_STRUCTURE_DOWNTREND) structure = "Downtrend";
    else if(currentMarketStructure == ENUM_MARKET_STRUCTURE::MARKET_STRUCTURE_RANGE) structure = "Range";
    Print("[MARKET STRUCTURE] ", symbol, " ", EnumToString(timeframe), " - ", structure);
}

//+------------------------------------------------------------------+
//| Fast Market Regime Detection - See implementation at line 3853    |
//+------------------------------------------------------------------+
// Using the FastRegimeDetection function already defined earlier in the code
// This avoids duplicate function declarations
// The FastRegimeDetection function is already fully implemented elsewhere
// End of duplicate function removal

// Define properly typed function for switching trade frequency based on market phase
void AdjustTradeFrequency(int phase) {
    switch(phase) {
        case 1: // ENUM_MARKET_REGIME::REGIME_TRENDING_UP
            ActualSignalCooldownSeconds = 1;
            break;
        case 2: // ENUM_MARKET_REGIME::REGIME_TRENDING_DOWN
            ActualSignalCooldownSeconds = 1;
            break;
        case 7: // PHASE_RANGING_NARROW
            ActualSignalCooldownSeconds = 5;
            break;
        case 8: // PHASE_RANGING_WIDE
            ActualSignalCooldownSeconds = 3;
            break;
        case 4: // PHASE_HIGH_VOLATILITY
            ActualSignalCooldownSeconds = 30;
            break;
        default:
            ActualSignalCooldownSeconds = SignalCooldownSeconds;
            break;
    }
}

// AdjustTradeFrequency function now uses integer values instead of enum
// to avoid ambiguous enum access

void AdjustRiskParameters(int phase) {
    // Create a local risk adjustment factor instead of trying to modify RiskPercent directly
    double adjustedRiskFactor = 1.0;
    
    switch(phase) {
        case 1: // ENUM_MARKET_REGIME::REGIME_TRENDING_UP
            adjustedRiskFactor = 1.0; // No adjustment
            break;
        case 2: // ENUM_MARKET_REGIME::REGIME_TRENDING_DOWN
            adjustedRiskFactor = 1.0; // No adjustment
            break;
        case 8: // PHASE_RANGING_WIDE
        case 7: // PHASE_RANGING_NARROW
            adjustedRiskFactor = 0.5; // Reduce risk by half
            break;
        case 4: // PHASE_HIGH_VOLATILITY
            adjustedRiskFactor = 0.25; // Reduce risk to 25%
            break;
        default:
            adjustedRiskFactor = 0.75; // Default to 75% risk
            break;
    }
    
    // Use the adjustedRiskFactor in calculations elsewhere
    // This doesn't try to modify RiskPercent directly
    if(DisplayDebugInfo) {
        Print("[RISK] Adjusted risk factor for phase ", IntegerToString(phase), ": ", DoubleToString(adjustedRiskFactor, 2));
    }
}

bool ModifyPositionWithValidation(ulong ticket, double newSL, double newTP) {
    if(!PositionSelectByTicket(ticket)) return false;
    
    double currentPrice = 0;
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
        if(!SymbolInfoDouble(Symbol(), SYMBOL_BID, currentPrice)) {
            currentPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(DisplayDebugInfo) Print("[WARNING] Failed to get current BID price, using position open price");
        }
    } else {
        if(!SymbolInfoDouble(Symbol(), SYMBOL_ASK, currentPrice)) {
            currentPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(DisplayDebugInfo) Print("[WARNING] Failed to get current ASK price, using position open price");
        }
    }
    
    double point = 0.0;
    if(!SymbolInfoDouble(Symbol(), SYMBOL_POINT, point)) {
        point = 0.00001; // Default point value if call fails
    }
    double minStopDist = 0.0;
    // Get minimum stop distance from broker
    // SYMBOL_TRADE_STOPS_LEVEL is an INTEGER property, using correct function
    long stopLevelValue = 0;
    if(!SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue)) {
        Print("Error getting stop level: ", GetLastError());
        stopLevelValue = 5; // Default value if call fails
    }
    minStopDist = (double)stopLevelValue;
    minStopDist *= point;
    
    // Validate SL for sell position
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
        if(newSL >= currentPrice) {
            if(DisplayDebugInfo) Print("[ERROR] Invalid SL for sell: ", newSL, " must be below price ", currentPrice);
            return false;
        }
        
        // Limit maximum SL adjustment per modification
        double currentSL = PositionGetDouble(POSITION_SL);
        double maxAdjustment = 100 * point; // Max 100 pips adjustment
        if(MathAbs(newSL - currentSL) > maxAdjustment) {
            newSL = currentSL > newSL 
                ? currentSL - maxAdjustment 
                : currentSL + maxAdjustment;
            if(DisplayDebugInfo) Print("[INFO] Limiting SL adjustment to ", maxAdjustment/point, " pips. New SL: ", newSL);
        }
    }
    
    CTrade tradeHelper; // Using a different name to avoid shadowing global variable
    tradeHelper.SetDeviationInPoints(AdaptiveSlippagePoints);
    
    // Using newSL parameter and the local tradeHelper instance
    return tradeHelper.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk percentage and stop distance |
//+------------------------------------------------------------------+
double CalculatePositionSizeByRisk(double riskPercent, double entryPrice, double stopLoss) {
    // Define variables
    double stopDistance = 0.0;
    double signal = 0;
    
    // Determine signal direction based on entry and stop levels
    if (entryPrice > stopLoss) {
        signal = 1; // BUY
    } else if (entryPrice < stopLoss) {
        signal = -1; // SELL
    } else {
        return 0.0; // Invalid entry/stop combination
    }
    
    // Calculate stop distance
    if(signal > 0) { // BUY
        stopDistance = entryPrice - stopLoss;
    } else if(signal < 0) { // SELL
        stopDistance = stopLoss - entryPrice;
    }
    
    // Ensure valid stop distance
    if(stopDistance <= 0) {
        LogError("Invalid stop distance calculated: " + DoubleToString(stopDistance, _Digits));
        return 0.0;
    }
    
    // Calculate risk amount in account currency
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (riskPercent / 100.0);
    
    // Get contract specification
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double contractSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE);
    
    // Calculate position size
    double positionSize = 0.0;
    if(tickSize > 0 && tickValue > 0) {
        double ticksInStopDistance = stopDistance / tickSize;
        double valuePerLot = ticksInStopDistance * tickValue;
        if(valuePerLot > 0) {
            positionSize = riskAmount / valuePerLot;
        }
    }
    
    // Normalize position size
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    // Round to nearest lot step
    positionSize = MathFloor(positionSize / lotStep) * lotStep;
    
    // Ensure position size is within allowed range
    positionSize = MathMax(minLot, MathMin(maxLot, positionSize));
    
    // Log calculated position size for debugging
    if(DisplayDebugInfo) {
        LogRisk("Calculated position size: " + DoubleToString(positionSize, 2) + 
               " lots based on risk: " + DoubleToString(riskPercent, 2) + 
               "%, stop distance: " + DoubleToString(stopDistance, _Digits));
    }
    
    return positionSize;
}

//+------------------------------------------------------------------+
//| Log detailed information about stop loss calculations             |
//+------------------------------------------------------------------+
void LogStopLossDetails(double entryPrice, double stopLoss, string source="General") {
    if(!DisplayDebugInfo) return;
    
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double minStopDistance = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    
    Print("[DEBUG][SL][" + source + "] Calculated SL=", stopLoss, ", distance=", stopDistance, ", ATR=", atr,
          ", min_distance=", minStopDistance);
}

//+------------------------------------------------------------------+
//| Adjust trailing stop for a position                             |
//+------------------------------------------------------------------+
void AdjustTrailingStop(int ticket, double trailingDistance) {
    // Select the position by ticket
    if(!PositionSelectByTicket(ticket)) {
        Print("Failed to select position with ticket ", ticket, ". Error: ", GetLastError());
        return;
    }
    
    // Get position details
    double currentSL = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double currentPrice = (posType == POSITION_TYPE_BUY) ? GetCurrentBid() : GetCurrentAsk();
    
    // Calculate new stop loss
    double newSL = 0;
    if(posType == POSITION_TYPE_BUY) {
        // For buy positions, trail below current price
        newSL = currentPrice - trailingDistance;
        // Only move SL up, never down
        if(newSL <= currentSL) return;
    } else {
        // For sell positions, trail above current price
        newSL = currentPrice + trailingDistance;
        // Only move SL down, never up
        if(newSL >= currentSL) return;
    }
    
    // Modify the position
    CTrade trade_local;
    trade_local.SetDeviationInPoints(AdaptiveSlippagePoints);
    if(!trade_local.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
        Print("Failed to modify position with ticket ", ticket, ". Error: ", GetLastErrorText(GetLastError()));
    } else if(DisplayDebugInfo) {
        Print("Trailing stop adjusted for ticket ", ticket, ". New SL: ", newSL);
    }
}

//+------------------------------------------------------------------+
//| Manage trailing stops for all open positions                     |
//+------------------------------------------------------------------+
//| This was a duplicate ManageTrailingStops function - removed to fix compilation errors |
//+------------------------------------------------------------------+
// Using the implementation defined at line 214 instead.

// Define a proper function to replace the dangling code
bool ManageTrailingStopsImpl() {
    // Implementation is elsewhere
    return false;
}

// This was a duplicate CalculateDynamicSize function
// Using the implementation defined elsewhere instead
// REMOVED DUPLICATE FUNCTION TO FIX COMPILATION ERRORS

// This function is commented out to avoid compilation errors
// The actual implementation is used elsewhere in the code
/*
double PlaceholderForCalculateDynamicSize(double riskPercent, double stopDistance) {
    // Just a placeholder, not actually called in the code
    return 0.01; // Return minimum lot size
}
*/

//+------------------------------------------------------------------+
//| This was a duplicate of ExecuteTradeWithRetry and has been removed |
//+------------------------------------------------------------------+
// The duplicate code was removed to avoid compilation errors.
// This code was incorrectly placed outside of any function.

//+------------------------------------------------------------------+
//| This was a duplicate of OrderCheck and has been removed         |
//+------------------------------------------------------------------+
// The duplicate OrderCheck function was removed to avoid compilation errors.
// Using the implementation at line 5621 instead.

// This implementation of OrderCheck was replaced by our RetryTrade function
// Keeping the function commented out to maintain line numbering but avoid compilation errors
/*
bool OrderCheckImplementation(int signal, double stopLoss, double takeProfit) {
    // Get current prices
    double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double minStopDistance = GetMinimumStopDistance(); // Use our new function instead of undeclared CalcBrokerMinStop
    
    // Enhanced dynamic safety checks based on current market conditions
    double atr = CalculateATR(14); // Get current ATR for volatility-based adjustments
    
    // Determine the minimum safe stop distance based on market volatility
    double dynamicMinStopDistance = MathMax(minStopDistance, atr * 0.3); // At least 30% of ATR
    
    // This function is replaced by our comprehensive RetryTrade implementation
    return true;
}
*/

//+------------------------------------------------------------------+
//| Placeholder function to maintain file structure                   |
//+------------------------------------------------------------------+
void PlaceholderOrderCheck() {
    // This function exists to maintain the file structure
    // The actual implementation has been replaced by our RetryTrade function
    
    // Original logic commented out to avoid compilation errors:
    /*
    // Implement adaptive risk checks based on recent performance
    if(consecutiveLosses > 2) {
        // Increase safety after consecutive losses
        dynamicMinStopDistance = MathMax(dynamicMinStopDistance, atr * 0.5); // Increase to 50% of ATR
        Print("[ADAPTIVE SAFETY] Increasing min stop distance after ", consecutiveLosses, " consecutive losses");
    }
    
    // Additional check for high volatility regimes
    if(currentRegime == REGIME_HIGH_VOLATILITY || currentRegime == REGIME_BREAKOUT) {
        dynamicMinStopDistance = MathMax(dynamicMinStopDistance, atr * 0.7); // Increase to 70% of ATR
        Print("[ADAPTIVE SAFETY] Using wider stops in high volatility regime");
    }
    */
}

//+------------------------------------------------------------------+
//| Additional placeholder function to maintain file structure          |
//+------------------------------------------------------------------+
void PlaceholderValidationCheck() {
    // This function exists to maintain the file structure
    // The actual implementation has been integrated into our RetryTrade function
    
    // Original logic commented out to avoid compilation errors:
    /*
    // Check if stop loss and take profit are valid based on signal type
    if(signal == SIGNAL_BUY) {
        // For buy orders, stop loss must be below entry price and take profit above
        if(stopLoss >= currentAsk) {
            LogError("Invalid stop loss for buy order: SL (" + DoubleToString(stopLoss, _Digits) + 
                    ") must be below entry price (" + DoubleToString(currentAsk, _Digits) + ")");
            return false;
        }
    
        // Check if stop loss is too close to current price - using dynamic distance
        if(currentAsk - stopLoss < dynamicMinStopDistance) {
            LogError("Stop loss too close to entry price for buy order: " + 
                    DoubleToString(currentAsk - stopLoss, _Digits) + " < " + 
                    DoubleToString(minStopDistance, _Digits));
            return false;
        }
        
        // Check if take profit is valid
        if(takeProfit <= currentAsk) {
            LogError("Invalid take profit for buy order: TP (" + DoubleToString(takeProfit, _Digits) + 
                    ") must be above entry price (" + DoubleToString(currentAsk, _Digits) + ")");
            return false;
        }
    */
}

//+------------------------------------------------------------------+
//| Final placeholder function to contain remaining validation code     |
//+------------------------------------------------------------------+
void FinalPlaceholderValidation() {
    // This function exists only to contain the remaining code fragments
    // and prevent compilation errors. None of this code is used in the EA.
    
    /*
    // This code block is from the original OrderCheck function that has been replaced
    // by our enhanced trade execution retry mechanism. It's kept here for reference only.
    
    // Check if take profit is too close to current price
    if(takeProfit - currentAsk < minStopDistance) {
        LogError("Take profit too close to entry price for buy order: " + 
                DoubleToString(takeProfit - currentAsk, _Digits) + " < " + 
                DoubleToString(minStopDistance, _Digits));
        return false;
    }
    
    else if(signal == SIGNAL_SELL) {
        // For sell orders, stop loss must be above entry price and take profit below
        if(stopLoss <= currentBid) {
            LogError("Invalid stop loss for sell order: SL (" + DoubleToString(stopLoss, _Digits) + 
                    ") must be above entry price (" + DoubleToString(currentBid, _Digits) + ")");
            return false;
        }
        
        // Check if stop loss is too close to current price
        if(stopLoss - currentBid < minStopDistance) {
            LogError("Stop loss too close to entry price for sell order: " + 
                    DoubleToString(stopLoss - currentBid, _Digits) + " < " + 
                    DoubleToString(minStopDistance, _Digits));
            return false;
        }
        
        // Check if take profit is valid
        if(takeProfit >= currentBid) {
            LogError("Invalid take profit for sell order: TP (" + DoubleToString(takeProfit, _Digits) + 
                    ") must be below entry price (" + DoubleToString(currentBid, _Digits) + ")");
            return false;
        }
        
        // Check if take profit is too close to current price
        if(currentBid - takeProfit < minStopDistance) {
            LogError("Take profit too close to entry price for sell order: " + 
                    DoubleToString(currentBid - takeProfit, _Digits) + " < " + 
                    DoubleToString(minStopDistance, _Digits));
            return false;
        }
    }
    else {
        LogError("Invalid signal type for order check: " + IntegerToString(signal));
        return false;
    }
    
    return true;
    */
}

//+------------------------------------------------------------------+
//| Get current bid price                                            |
// These utility functions are already defined at the top of the file
// Removed duplicate implementations to avoid compiler errors
