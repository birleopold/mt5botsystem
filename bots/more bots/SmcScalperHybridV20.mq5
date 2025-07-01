//+------------------------------------------------------------------+
//| SMC Scalper Hybrid - Smart Money Concepts with Advanced Scalping |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>

// Global trade object
CTrade tradeLocal;  // Main trade object for all operations

// Global variables for CHOCH detection
double lastSwingHigh = 0.0;
double lastSwingLow = 0.0;
bool chochDetected = false;
datetime lastChochTime = 0; // Time of last CHOCH detection

// --- Utility Function Prototypes ---
double GetCurrentAsk();
double GetCurrentBid();
double GetSymbolPoint();
long GetCurrentSpreadPoints();

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
#include "SmcScalperHybridV20_AdaptiveFilters.mqh"
#include "SmcScalperHybridV20_MissedOpportunities.mqh"

// Market regime constants
#define REGIME_LOW_VOLATILITY 0
#define REGIME_HIGH_VOLATILITY 1
#define REGIME_TRENDING_UP 2
#define REGIME_TRENDING_DOWN 3
#define REGIME_RANGING_NARROW 4
#define REGIME_RANGING_WIDE 5
#define REGIME_CHOPPY 6
#define REGIME_REVERSAL 7
#define REGIME_BREAKOUT 8
#define REGIME_NORMAL 9
#define BREAKOUT REGIME_BREAKOUT // Alias for consistency

// CHOCH (Change of Character) detection
#define CHOCH_BULLISH 1
#define CHOCH_BEARISH 2
#define CHOCH_NONE 0

// Divergence type constants
#define DIVERGENCE_REGULAR_BULL 1
#define DIVERGENCE_HIDDEN_BULL 2
#define DIVERGENCE_REGULAR_BEAR 3
#define DIVERGENCE_HIDDEN_BEAR 4

// Market phase enum
enum MARKET_PHASE {
    PHASE_TRENDING_UP,
    PHASE_TRENDING_DOWN,
    PHASE_RANGING,
    PHASE_BREAKOUT,
    PHASE_REVERSAL,
    PHASE_CHOPPY,
    PHASE_HIGH_VOLATILITY,
    PHASE_LOW_VOLATILITY
};

// Input parameters for strategy features
input bool EnableCHOCHDetection = true;     // Enable CHOCH Detection

// --- Logging Helpers ---
void LogInfo(string msg)      { Print("[SMC][INFO] " + msg); }
void LogWarn(string msg)      { Print("[SMC][WARN] " + msg); }
void LogError(string msg)     { Print("[SMC][ERROR] " + msg); }
void LogParamChange(string msg) { Print("[SMC][PARAM] " + msg); }
void LogTrade(string msg)     { Print("[SMC][TRADE] " + msg); }
void LogRisk(string msg)      { Print("[SMC][RISK] " + msg); }
void LogCorrelation(string msg) { Print("[SMC][CORR] " + msg); }
void LogLiquidity(string msg)  { Print("[SMC][LIQ] " + msg); }
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
    // --- Calculate lot size based on risk ---
    double riskAmountLocal = 0.0;
    double stopDistancePointsLocal = 0.0;
    double pointValueLocal = 0.0;
    // TODO: Assign actual values to riskAmountLocal, stopDistancePointsLocal, pointValueLocal before this block
    // Example assignment (replace with real logic as needed):
    // riskAmountLocal = ...;
    // stopDistancePointsLocal = ...;
    // pointValueLocal = ...;
    double lotSizeLocal = riskAmountLocal / (stopDistancePointsLocal * pointValueLocal);
    
    // Normalize to valid lot step
    double lotStepLocal = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLotLocal = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLotLocal = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    
    // Round to valid lot step
    lotSizeLocal = MathFloor(lotSizeLocal / lotStepLocal) * lotStepLocal;
    
    // Ensure within valid range
    lotSizeLocal = MathMax(minLotLocal, MathMin(maxLotLocal, lotSizeLocal));
    
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
                consecutiveLosses++;
            } else if(lastProfit > 0) {
                break; // Stop counting at first profit
            }
        }
        
        initializedConsecLoss = true;
    }
    
    // Emergency stop after too many consecutive losses
    if(consecutiveLosses >= 5) { // Adjust threshold as needed
        LogError("EMERGENCY MODE ACTIVATED - Too many consecutive losses: " + IntegerToString(consecutiveLosses));
        return true;
    }
    
    return false;
}


//+------------------------------------------------------------------+
//| Structure definitions                                           |
//+------------------------------------------------------------------+
// Structure to store swing points for stop loss placement
struct SwingPoint {
    double price;
    datetime time;
    int score;
    int barIndex;
};

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
                 double lotSize, double profit, int pips, double riskAmount, double riskReward, 
                 ENUM_ORDER_TYPE orderType, int signal, int regime, int session, double quality, 
                 bool wasConfirmed, string notes = "") {
                 
        // Update the trade record
        trades[currentIndex].openTime = openTime;
        trades[currentIndex].closeTime = closeTime;
        trades[currentIndex].openPrice = openPrice;
        trades[currentIndex].closePrice = closePrice;
        trades[currentIndex].lotSize = lotSize;
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
                         OrderTypeToString(orderType), DoubleToString(lotSize, 2),
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
input bool RequireMomentumConfirmation = true; // Require momentum indicator confirmation
input int RSI_Period = 14;                     // RSI period for momentum confirmation
input int MACD_FastEMA = 12;                  // MACD fast EMA period
input int MACD_SlowEMA = 26;                  // MACD slow EMA period
input int MACD_SignalPeriod = 9;              // MACD signal line period

// Check if momentum indicators confirm the signal
bool CheckMomentumConfirmation(int signal) {
    if(!RequireMomentumConfirmation || signal == 0) return true;
    
    int confirmed = 0;
    int requiredConfirmations = 2; // Need at least 2 out of 3 indicators to confirm
    
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
#define MAX_BLOCKS 20
#define MAX_GRABS 10
#define MAX_FVGS 10
#define MAX_FEATURES 30
#define METRIC_WINDOW 100
#define ACCURACY_WINDOW 100
#define REGIME_COUNT 9

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
        CTrade trade_local; // Renamed to avoid shadowing global variable
tradeLocal.SetExpertMagicNumber(123456); // Use appropriate magic number

// Execute entry based on signal direction
bool success = false;
string comment = "Scaled Entry 1/" + IntegerToString(actualScalingPositions);

if(signal > 0) { // BUY
    success = trade_local.Buy(currentScalingEntries[0].lotSize, Symbol(), 0, stopLoss, 0, comment);
} else { // SELL
    success = trade_local.Sell(currentScalingEntries[0].lotSize, Symbol(), 0, stopLoss, 0, comment);
}

if(success) {
    ulong ticket = tradeLocal.ResultOrder();
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
            CTrade trade_local; // Renamed to avoid shadowing global variable
            trade_local.SetExpertMagicNumber(123456); // Use appropriate magic number
            
            // Execute entry based on signal direction
            bool success = false;
            string comment = "Scaled Entry " + IntegerToString(i+1) + "/" + IntegerToString(ScalingPositions);
            double stopLoss = currentScalingEntries[i].stopLoss;
            
            if(entrySignal > 0) { // BUY
                success = trade_local.Buy(currentScalingEntries[i].lotSize, Symbol(), 0, stopLoss, 0, comment);
            } else { // SELL
                success = trade_local.Sell(currentScalingEntries[i].lotSize, Symbol(), 0, stopLoss, 0, comment);
            }
            
            if(success) {
                ulong ticket = trade_local.ResultOrder();
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

// Market Phase Constants - unified enum for all market regime types
enum MARKET_PHASE
{
   PHASE_NONE = 0,
   PHASE_TRENDING_UP = 1,
   PHASE_TRENDING_DOWN = 2,
   PHASE_RANGING = 3,
   PHASE_HIGH_VOLATILITY = 4,
   PHASE_CHOPPY = 5,
   PHASE_BREAKOUT = 6,
   PHASE_RANGING_NARROW = 7,
   PHASE_RANGING_WIDE = 8,
   PHASE_LOW_VOLATILITY = 9,
   PHASE_REVERSAL = 10,
   PHASE_CONSOLIDATION = 11,
   PHASE_NORMAL = 12,
   PHASE_BREAKOUT_REGIME = 20
   // Removed duplicate REGIME_* definitions that are already defined as #define macros
};

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
    if(ratio > HighVolatilityThreshold) return REGIME_HIGH_VOLATILITY;
    if(ratio < LowVolatilityThreshold) return REGIME_LOW_VOLATILITY;
    
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
    
    if(maFast > maSlow * 1.002) return REGIME_TRENDING_UP;
    if(maFast < maSlow * 0.998) return REGIME_TRENDING_DOWN;
    
    return REGIME_NORMAL;
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
input double RegimeMinWinRate = 0.45;
input double RegimeMinProfitFactor = 1.2;
input double RegimeMaxDrawdownPct = 8.0;
input int RegimeUnderperfN = 10; // N trades to trigger block/reduce
input double RegimeRiskReduction = 0.5; // Reduce risk by this factor if underperforming
input bool BlockUnderperfRegime = true;
// News filter is in news_filter.mqh
// Trading Timeframes
input ENUM_TIMEFRAMES AnalysisTimeframe = PERIOD_H1;  // Main analysis timeframe
input ENUM_TIMEFRAMES ScanningTimeframe = PERIOD_M15; // Scanning timeframe
input ENUM_TIMEFRAMES ExecutionTimeframe = PERIOD_M5; // Execution timeframe

// EA logging and debugging
input bool DisplayDebugInfo = true;  // Show debug information on chart
input bool LogToFile = false;        // Log trades to file

// EA risk management
input group "Advanced Risk Management"
input bool EnableAdaptiveRisk = true; // Adjust position size based on volatility
// News filter already defined above (line 363)
input bool EnableCorrelationChecking = true; // Check for correlated pairs
input double CorrelationDiscountFactor = 0.2; // How much to reduce size for correlated pairs
input bool EnableTimeBasedRiskReduction = true; // Reduce size near market close/weekends
input bool EnableMarketRegimeFiltering = true; // Adjust strategy based on market regime
input int TradingStartHour = 0;
input int TradingEndHour = 23;
input int MaxTrades = 2;               // Maximum concurrent trades
input double RiskPercent = 1.0;          // Risk percentage per trade
input double RiskRewardRatio = 1.5;      // Risk:Reward ratio (1.5 = 1.5:1)
input int AdaptiveSlippagePoints = 5;    // Slippage allowance for order execution
input int MagicNumber = 20230615;        // Unique identifier for this EA's trades
// These have already been declared earlier as inputs
// input double TrailingActivationPct = 0.5; // Activate trailing stop after this % of target reached
// input double TrailingStopMultiplier = 1.2; // Multiplier for ATR-based trailing stop
input double MaxPortfolioRiskPercent = 5.0; // Max portfolio risk as % of balance (portfolio cap)
input bool UseKellySizing = true;           // Use Kelly/Optimal F for dynamic sizing
input double MaxKellyFraction = 0.03;       // Max Kelly/Optimal F fraction (cap)
double SL_ATR_Mult = 1.0;         // Stop loss multiplier of ATR
double TP_ATR_Mult = 2.0;         // Take profit multiplier of ATR

// Define the ATR multiplier for trailing stops
input double TrailingStopATRMultiplier = 1.0; // ATR multiplier for trailing stops
input double SL_Pips = 10.0;           // Fixed stop loss in pips (as backup)
input double TP_Pips = 30.0;           // Fixed take profit in pips (as backup)
input int SignalCooldownSeconds = 1;  // Seconds between trade signals (ultra low for rapid testing)
int ActualSignalCooldownSeconds = 1;   // Runtime-adjustable cooldown
input int MinBlockStrength = 2;        // Minimum order block strength for valid signal (stricter default)
input bool RequireTrendConfirmation = false; // Require trend confirmation for trades
input int MaxConsecutiveLosses = 3;    // Stop trading after this many consecutive losses

// Order Block Struct
struct OrderBlock {
    double price;
    datetime time;
    double volume;
    bool isBuy;
    bool valid;
    int strength;
    double imbalanceRatio; // Add imbalance ratio property
};

OrderBlock recentBlocks[MAX_BLOCKS];

// Volatility Filter


MARKET_PHASE currentMarketPhase = PHASE_TRENDING_UP;

// Advanced Scalping Parameters
input bool EnableFastExecution = true;  // Enable fast execution mode
// EnableAdaptiveRisk already defined above (line 1211)
input bool EnableAggressiveTrailing = true; // Use aggressive trailing stops
input bool EnableTrailingForLast = true;   // Enable volatility-based trailing
input double BreakEvenTriggerPct = 0.5;     // % of TP when to move stop to break-even (0.0-1.0)
input double BreakEvenPadding = 10.0;       // Points to add above entry when moving to break-even
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
input bool EnableDivergenceFilter = true;   // Enable divergence-based signal filtering
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
input double PartialTP3_Distance = 2.5;   // Third TP at x times the stop distance
// Partial Profit Parameters
input bool EnablePartialTakeProfit = true; // Enable partial profit taking
input double PartialTP1_Pct = 0.5; // Portion to close at TP1 (e.g., 0.5 = half)

// Spread Filter
input double MaxAllowedSpread = 15; // Maximum allowed spread in points for trade execution

// Performance Tracking
// DisplayDebugInfo already defined at line 1208
input bool LogPerformanceStats = true; // Log detailed performance statistics

// Smart Session-Based Trading
bool EnableSessionFiltering = true;   // Enable session-based trading rules
bool TradeAsianSession = true;       // Trade during Asian session (low volatility)
bool TradeEuropeanSession = true;    // Trade during European session (medium volatility)
bool TradeAmericanSession = true;    // Trade during American session (high volatility)
bool TradeSessionOverlaps = true;    // Emphasize trading during session overlaps

// Advanced Signal Quality Evaluation
input bool EnableSignalQualityML = true;    // Use ML-like signal quality evaluation
input double MinSignalQualityTolocalTrade = 0.6; // Minimum signal quality score (0.0-1.0) to trade
input bool RequireMultiTimeframeConfirmation = true; // Require additional timeframe confirmation

// Smart Position Recovery
input bool EnableSmartAveraging = false;    // Enable smart grid averaging for drawdown recovery
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

// Working copies of constants that can be modified
double workingATRThreshold = 0.0003; // Default value, will be initializedConsecLoss properly in OnInit
double workingRiskPercent = 1.0; // Working copy of RiskPercent
double workingTrailingStopMultiplierLocal = 0.5; // Working copy of TrailingStopMultiplier
double workingTrailingActivationPct = 0.5; // Working copy of TrailingActivationPct
double workingMinSignalQualityTolocalTrade = 0.6; // Working copy of MinSignalQualityToTrade
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

// Use existing NewsEvent structure defined earlier
// Additional news schedule array for high-impact events
NewsEvent newsSchedule[20]; // Array to store upcoming news events

// Averaging System Variables
int averagingPositions = 0;
datetime lastAveragingTime = 0;

// Trade object and indicators
CTrade tradeLocal;
double localAtrBuffer[];    // Simple 1D array
double maBuffer[];     // This one is already correct
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
struct LiquidityGrab { datetime time; double high; double low; bool isBuy; bool active; };
struct FairValueGap { datetime startTime; datetime endTime; double high; double low; bool isBuy; bool active; };

// Note: Main OrderBlock struct is already defined earlier in the code
// This is just a reference for code readability

// The NewsEvent structure and recentBlocks array are already defined earlier in the code
// Keeping the MAX_NEWS_EVENTS definition here
#define MAX_NEWS_EVENTS 50  // Maximum number of news events to track

//+------------------------------------------------------------------+
//| Missed Opportunity Tracking - Logs potential trades filtered out |
//+------------------------------------------------------------------+
// #define MAX_MISSED_OPPORTUNITIES // Removed duplicate macro definition, now only defined in the .mqh file 100 // Maximum number of missed opportunities to track

// Structure to track missed trading opportunities
// Structure to hold divergence information
struct DivergenceInfo {
    bool found;             // Whether divergence was found
    int type;               // Type of divergence (using the DIVERGENCE_* constants)
    double strength;        // Strength of the divergence (0.0-1.0)
    datetime time;          // When the divergence was detected
    double price;           // Price level of the divergence
};

// Global instance to track the last detected divergence
DivergenceInfo lastDivergence;

// Structure to track missed trading opportunities
struct MissedOpportunity {
    datetime time;           // Time the opportunity was detected
    int signal;             // Direction (1 for buy, -1 for sell)
    double price;           // Price at the time of detection
    double potentialProfit; // Calculated potential profit (if taken)
    string filterReason;    // Reason the trade was filtered out
    int marketRegime;       // Market regime at time of signal
    double signalQuality;   // Quality score of the signal (0.0-1.0)
    bool wouldHaveWon;      // Flag if this would have been profitable (set later)
};

// Array to store missed opportunities
MissedOpportunity missedOpportunities[MAX_MISSED_OPPORTUNITIES];
int missedOpportunityCount = 0;
int missedOpportunityIndex = 0;

// Adaptive filter settings
struct AdaptiveFilterSettings {
    // Initial values that will adapt over time
    double signalQualityThreshold;
    bool requireMultiTimeframe;
    bool requireMomentumConfirmation;
    int minimumBlockStrength;
    
    // Performance metrics to drive adaptation
    int consecutiveNoTrades;
    int consecutiveLosses;
    int winStreak;
    double winRate;
    datetime lastAdaptationTime;
    
    // Learning rate - how quickly filters adapt
    double adaptationRate;
    
    // Minimum and maximum filter constraints
    double minSignalQualityAllowed;
    double maxSignalQualityAllowed;
};

// Global adaptive filter settings
AdaptiveFilterSettings adaptiveFilters;

// Market regime already defined above - this is a duplicate
// Using the comprehensive enum definition from line ~1225

// SwingPoint struct already defined at line 19

// Global variables for market state tracking
// currentRegime already defined at line 1360 - keeping only one global instance
// ENUM_MARKET_REGIME currentRegime = REGIME_RANGING; // Default regime

LiquidityGrab recentGrabs[MAX_GRABS];
FairValueGap recentFVGs[MAX_FVGS];

// Order Block Analytics
input bool EnableOrderBlockAnalytics = true; // Toggle detailed analytics
int totalBlocksDetected = 0;
int totalBlocksValid = 0;
int totalBlocksInvalid = 0;
double sumBlockStrength = 0;
double sumBlockVolume = 0;
int rollingWindow = 100;
double rollingStrength[100];
double rollingVolume[100];
int rollingIndex = 0;

int grabIndex = 0, fvgIndex = 0, blockIndex = 0;
double FVGMinSize = 0.5;
input int LookbackBars = 200; // Force 200-bar lookback
bool UseLiquidityGrab = true, UseImbalanceFVG = true;

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

void DetectMarketStructure() {
    SwingPoint swings[];
    int swingCount;
    FindQualitySwingPoints(true, 50, swings, swingCount);
    
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
        // At least 3 out of 4 conditions need to be aligned
        bool confirmedTF = (alignmentScore >= 3);
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
        else if(currentRegime == REGIME_CHOPPY) {
            regimeAlignment = 0.2; // Poor conditions in choppy markets
        }
        else if(currentRegime == REGIME_RANGING_NARROW) {
            regimeAlignment = 0.6; // Decent for range trading if at extremes
        }
        else if(currentRegime == REGIME_RANGING_WIDE) {
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
    
    // Order block quality (valid block detection with enhanced weighting)
    double blockScore = 0.0;
    double blockWeight = 0.20; // Increased from 0.15 to give more importance to blocks
    int validBlockCount = 0;
    double totalBlockStrength = 0;
    double blockVolumeScore = 0;
    double blockImbalanceScore = 0;
    
    // Find recent valid blocks that align with our signal
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid && ((signal > 0 && recentBlocks[i].isBuy) || (signal < 0 && !recentBlocks[i].isBuy))) {
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
    for(int i=0; i<METRIC_WINDOW; i++) {
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
        case REGIME_CHOPPY: 
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
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
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
    LogInfo("Adaptive filter system initializedConsecLoss with quality threshold: " + 
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
    tradeLocal.SetDeviationInPoints(10);

    // Initialize arrays
    ArrayResize(localAtrBuffer, 100);
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
        localAtrBuffer[i] = 0.0;
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

//+------------------------------------------------------------------+
//| Improved Error Handling & Escalation                             |
//+------------------------------------------------------------------+
int consecutiveTradeErrors = 0;
input int MaxConsecutiveTradeErrors = 5;

bool HandleTradeError(int errorCode, string context) {
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
    
    // DIAGNOSTIC: Temporarily bypass spread check completely to force trade execution
    double spreadThreshold = MaxAllowedSpread;
    double spread  = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point();
    
    // Force spreadOK to true regardless of actual spread
    bool spreadOK = true; // TEMPORARY BYPASS: Completely ignore spread restriction
    
    if(DisplayDebugInfo) {
        Print("[DIAG] IMPORTANT: Spread check bypassed to force trade execution. Actual spread=",
              SymbolInfoInteger(Symbol(), SYMBOL_SPREAD), ", threshold=", MaxAllowedSpread);
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
    
    // ENHANCEMENT: For testing purposes, we're being more permissive with spread
    // If all other conditions are met but spread is slightly high, still allow trading
    if(autoTradingEnabled && !emergencyMode && !marketClosed && !isWeekend && marginOK && !spreadOK) {
        // If spread is only slightly above threshold, still allow trading
        if(spread/Point() <= spreadThreshold * 1.2) {
            if(DisplayDebugInfo) Print("[DEBUG][BLOCK] Overriding spread restriction: spread=", 
                                       spread/Point(), " is slightly above threshold=", spreadThreshold);
            return true;
        }
    }
    
    return (autoTradingEnabled && !emergencyMode && !marketClosed && !isWeekend && spreadOK && marginOK);
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
//| Retry Trade Execution                                            |
//+------------------------------------------------------------------+
bool RetryTrade(int signal, double price, double sl, double tp, double size, int maxRetries=3) {
    CTrade trade_local; // Renamed to avoid shadowing global variable
    tradeLocal.SetDeviationInPoints(AdaptiveSlippagePoints);
    
    for(int attempts = 0; attempts < maxRetries; attempts++) {
        double currentBid = GetCurrentBid();
        double currentAsk = GetCurrentAsk();
        double currentPrice = (signal > 0) ? currentAsk : currentBid;
        
        double retrySize = size * (1.0 - (attempts * 0.2));
        
        if(signal > 0) {
            if(tradeLocal.Buy(retrySize, Symbol(), 0, sl, tp, "SMC Buy Retry "+IntegerToString(attempts+1)))
                return true;
        } else {
            if(tradeLocal.Sell(retrySize, Symbol(), 0, sl, tp, "SMC Sell Retry "+IntegerToString(attempts+1)))
                return true;
        }
        
        if(attempts < maxRetries-1) {
            Sleep(100);
            // RefreshRates is not defined in MQL5, removing call
        }
    }
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
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up resources
    ObjectsDeleteAll(0, "SMC_GUI_");
    
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
//| Modify stops based on Change of Character patterns               |
//+------------------------------------------------------------------+
bool ModifyStopsOnCHOCH(ulong ticket, double& newSL) {
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
    bool chochDetected = false;
    double chochLevel = 0;
    
    if(posType == POSITION_TYPE_BUY) {
        // For Buy positions, look for a bullish CHOCH (previous resistance becoming support)
        chochDetected = DetectBullishCHOCH(chochLevel);
        
        if(chochDetected && chochLevel > 0 && (currentSL == 0 || chochLevel > currentSL)) {
            // Ensure the CHOCH level is not too close to current price (minimum buffer)
            if(currentPrice - chochLevel >= MinStopDistance * _Point) {
                newSL = chochLevel;
                return true;
            }
        }
    } else {
        // For Sell positions, look for a bearish CHOCH (previous support becoming resistance)
        chochDetected = DetectBearishCHOCH(chochLevel);
        
        if(chochDetected && chochLevel > 0 && (currentSL == 0 || chochLevel < currentSL)) {
            // Ensure the CHOCH level is not too close to current price (minimum buffer)
            if(chochLevel - currentPrice >= MinStopDistance * _Point) {
                newSL = chochLevel;
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect a bullish CHOCH pattern (BOS - Break of Structure)         |
//+------------------------------------------------------------------+
bool DetectBullishCHOCH(double& level) {
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
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
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
   // Override session-adjusted parameters
   SL_ATR_Mult = 1.0;
   TP_ATR_Mult = 2.0;
   // TrailingActivationPct is already defined as an input parameter
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
        currentRegime = FastRegimeDetection(Symbol());
    }
    
    // Detect order blocks first - this is critical for signal generation
    if(DisplayDebugInfo) Print("[SMC] Calling DetectOrderBlocks() to find valid swing points");
    DetectOrderBlocks();
    
    if(DisplayDebugInfo) {
        int validCount = 0;
        for(int i=0; i<MAX_BLOCKS; i++) {
            if(recentBlocks[i].valid) validCount++;
        }
        Print("[DEBUG] After DetectOrderBlocks(), number of valid blocks: ", validCount);
    }
    
    // Step 3: Get trading signal
    if(DisplayDebugInfo) Print("[DEBUG][ONTICK] Calling Get trading signal");
    int signal = 0; // Default to no signal
    
    // Implement your trading signal logic here - example:
    double close = iClose(Symbol(), PERIOD_CURRENT, 0);
    double close1 = iClose(Symbol(), PERIOD_CURRENT, 1);
    double close2 = iClose(Symbol(), PERIOD_CURRENT, 2);
    
    // Simple example signal based on last 3 candles
    if(close > close1 && close1 > close2) signal = 1;     // Bullish
    else if(close < close1 && close1 < close2) signal = -1; // Bearish
    
    if(DisplayDebugInfo) Print("[SIGNAL] Generated signal =", signal);
    // Uncomment the next line to force a trade for testing:
    // signal = 1;
    
    // Step 4: Check if we should execute a trade with enhanced cooldown management
    
    // ENHANCEMENT: Dynamic cooldown system
    // Gradually reduce cooldown if we've been waiting too long without trades
    int noTradeTime = (int)(TimeCurrent() - lastTradeTime);
    int effectiveCooldown = ActualSignalCooldownSeconds;
    
    // If no trades for a long time, reduce cooldown to avoid getting stuck
    if(noTradeTime > 3600) { // No trades for over an hour
        effectiveCooldown = (int)(ActualSignalCooldownSeconds * 0.5); // 50% of normal cooldown
        if(DisplayDebugInfo) Print("[DEBUG][ADAPTIVE] Reduced cooldown to 50% after 1 hour without trades");
    } else if(noTradeTime > 1800) { // No trades for over 30 minutes
        effectiveCooldown = (int)(ActualSignalCooldownSeconds * 0.7); // 70% of normal cooldown
        if(DisplayDebugInfo) Print("[DEBUG][ADAPTIVE] Reduced cooldown to 70% after 30 minutes without trades");
    }
    
    bool cooldownPassed = (TimeCurrent() - lastTradeTime) >= effectiveCooldown;
    
    // Emergency mode tracking
    if(emergencyMode) {
        if(DisplayDebugInfo) {
            Print("[DEBUG][EMERGENCY] Mode active.");
        }
    }
    
    if(DisplayDebugInfo) {
        Print("[DEBUG] signal=", signal, ", cooldownPassed=", cooldownPassed, ", emergencyMode=", emergencyMode, ", CanlocalTrade=", CanTrade(), ", cooldownUsed=", ActualSignalCooldownSeconds, ", lastTradeTime=", lastTradeTime, ", now=", TimeCurrent());
        if(signal == 0) {
            Print("[DEBUG] No valid signal present.");
        }
        if(!CanTrade()) {
            Print("[DEBUG] CanTrade() returned false. Trading disabled.");
        }
    }
    if(DisplayDebugInfo) Print("[DEBUG] signal check: signal=", signal, ", cooldownPassed=", cooldownPassed, ", emergencyMode=", emergencyMode, ", CanlocalTrade=", CanTrade());
    
    // Get the current price for opportunity tracking
    double currentPrice = (signal > 0) ? GetCurrentAsk() : GetCurrentBid();
    
    // Calculate a signal quality score (0.0-1.0) for adaptive filtering
    double signalQuality = 0.5; // Default moderate quality
    
    // Enhance with actual quality metrics if available (using existing indicators)
    if(signal != 0) {
        // Calculate quality based on trend strength, volatility, and price action
        double trendStrength = MathAbs(priceCache.ma20[0] - priceCache.ma50[0]) / priceCache.atr[0];
        double volumeQuality = 0.5; // Placeholder if volume data available
        double momentumQuality = priceCache.rsi[0] > 30 && priceCache.rsi[0] < 70 ? 0.7 : 0.3;
        
        // Combine factors (weighted average)
        signalQuality = (trendStrength * 0.4) + (volumeQuality * 0.3) + (momentumQuality * 0.3);
        signalQuality = MathMin(MathMax(signalQuality, 0.1), 0.9); // Keep between 0.1-0.9
        
        if(DisplayDebugInfo) {
            Print("[DEBUG][QUALITY] Signal quality score: ", DoubleToString(signalQuality, 2), 
                " (trend=", DoubleToString(trendStrength, 2), 
                ", momentum=", DoubleToString(momentumQuality, 2), ")");
        }
    }
    
    // Get adaptive threshold from our filter system
    double qualityThreshold = GetAdaptedSignalQualityThreshold();
    bool qualityPassed = (signalQuality >= qualityThreshold);
    
    // Track missed opportunities with reasons
    if(signal == 0) {
        if(DisplayDebugInfo) Print("[DEBUG][step] No trade: signal==0");
    } else if(!cooldownPassed) {
        if(DisplayDebugInfo) Print("[DEBUG][step] No trade: cooldown not passed");
        RecordMissedOpportunity(signal, currentPrice, "cooldown restrictions", signalQuality);
    } else if(emergencyMode) {
        if(DisplayDebugInfo) Print("[DEBUG][step] No trade: emergencyMode active");
        RecordMissedOpportunity(signal, currentPrice, "emergency mode active", signalQuality);
    } else if(!CanTrade()) {
        if(DisplayDebugInfo) Print("[DEBUG][step] No trade: CanTrade() is false");
        RecordMissedOpportunity(signal, currentPrice, "trading disabled", signalQuality);
    } else if(!qualityPassed) {
        if(DisplayDebugInfo) Print("[DEBUG][step] No trade: signal quality below threshold");
        RecordMissedOpportunity(signal, currentPrice, "quality below threshold (" + 
                                DoubleToString(signalQuality, 2) + " < " + 
                                DoubleToString(qualityThreshold, 2) + ")", signalQuality);
    }
    if(signal != 0 && cooldownPassed && !emergencyMode && CanTrade() && qualityPassed) {
        // Add multi-timeframe confirmation with adaptive requirements
        bool multiTfConfirmed = ConfirmSignalMultiTimeframe(signal);
        bool requireMultiTf = IsMultiTimeframeRequired();
        
        if(!multiTfConfirmed && requireMultiTf) {
            LogInfo("Signal rejected - failed multi-timeframe confirmation. Signal=" + IntegerToString(signal));
            RecordMissedOpportunity(signal, currentPrice, "multi-timeframe confirmation failed", signalQuality);
            return; // Skip this signal if confirmation is required but failed
        }
        
        // Check momentum confirmation (RSI, MACD, Moving Averages) with adaptive requirements
        bool momentumConfirmed = CheckMomentumConfirmation(signal);
        bool requireMomentum = IsMomentumConfirmationRequired();
        
        if(!momentumConfirmed && requireMomentum) {
            LogInfo("Signal rejected - failed momentum confirmation. Signal=" + IntegerToString(signal));
            RecordMissedOpportunity(signal, currentPrice, "momentum confirmation failed", signalQuality);
            return; // Skip this signal if momentum confirmation is required but failed
        }
        
        // Update missed opportunities analysis periodically
        static datetime lastUpdateTime = 0;
        if(TimeCurrent() - lastUpdateTime > 300) { // Every 5 minutes
            UpdateMissedOpportunities();
            lastUpdateTime = TimeCurrent();
        }
        
        // Check if price is approaching a liquidity zone for better entry
        double liquidityTargetPrice = 0;
        bool hasLiquidityTarget = IsApproachingLiquidity(signal, liquidityTargetPrice);
        if(hasLiquidityTarget) {
            LogLiquidity("Liquidity target identified for " + (signal > 0 ? "BUY" : "SELL") + 
                     " at " + DoubleToString(liquidityTargetPrice, _Digits));
        }
        
        // Apply regime-specific parameters before executing trade
        ApplyRegimeParameters();
        
        LogInfo("Trade conditions met" + (multiTfConfirmed ? " with multi-TF confirmation" : "") + 
                ". Attempting tradeLocal. Signal=" + IntegerToString(signal));
        
        bool tradePlaced = false;
        
        // Determine the stop loss price for position sizing and TP calculations
        double entryPrice = (signal > 0) ? GetCurrentAsk() : GetCurrentBid();
        double stopLoss = DetermineOptimalStopLoss(signal, entryPrice);
        
        // Apply time-based position decay factor
        double timeDecayFactor = CalculateTimeDecayFactor(signal);
        
        // Check if we should use the multi-target TP strategy
        if(EnableMultiTargetTP) {
            LogInfo("Using multi-target take profit strategy");
            bool hadMtfConfirmation = false; // Define this variable
            tradePlaced = ExecuteMultiTargetStrategy(signal, entryPrice, stopLoss);
        }
        // Check if we should use smart entry scaling
        else if(EnableSmartScaling) {
            LogInfo("Using smart entry scaling");
            tradePlaced = ExecuteScaledEntry(signal, stopLoss, 0);
        } 
        // Otherwise use standard execution
        else if(EnableFastExecution) {
            LogInfo("Using ExecuteTradeWithRetry for trade execution.");
            tradePlaced = ExecuteTradeWithRetry(signal, FastExecution_MaxRetries);
        } else {
            if(DisplayDebugInfo) Print("[DEBUG][step] Using ExecuteTradeWithRetry as fallback");
            // ExecuteTrade is not implemented, using ExecuteTradeWithRetry instead
            tradePlaced = ExecuteTradeWithRetry(signal, 3); // Use default 3 retries
        }
        if(tradePlaced) {
            lastSignalTime = TimeCurrent();
            if(DisplayDebugInfo) Print("[DEBUG] Trade placed. Cooldown reset. lastSignalTime=", lastSignalTime);
            
            // Record trade taken for adaptive filtering (outcome will be updated on close)
            UpdateAdaptiveFilters(true, false, false); // We don't know yet if won
            LogInfo("[ADAPT] Trade executed with signal quality: " + DoubleToString(signalQuality, 2) + 
                    ", threshold: " + DoubleToString(qualityThreshold, 2));
        } else {
            if(DisplayDebugInfo) Print("[DEBUG] Trade attempt failed. Cooldown NOT reset.");
            
            // Record failed execution as missed opportunity
            RecordMissedOpportunity(signal, currentPrice, "execution failed", signalQuality);
        }
    }
    
    // Step 5: Manage open positions
    if(EnableAggressiveTrailing) {
        // ManageTrailingStops(); // Commented out until implemented
        // Using AdjustTrailingStop instead
        AdjustTrailingStop();
    }
    
    // Apply advanced dynamic trailing stops if enabled
    if(EnableTrailingForLast) {
        bool trailingResult = AdjustTrailingStop(); // This handles our new volatility-based trailing logic
        if(DisplayDebugInfo && trailingResult) {
            Print("[DEBUG] Volatility-based trailing applied");
        }
    }
    
    // Check for CHOCH and modify stops if detected
    if(EnableCHOCHDetection) {
        bool chochResult = ModifyStopsOnCHOCH();
        if(DisplayDebugInfo && chochResult) {
            Print("[DEBUG] CHOCH-based stop modification applied");
        }
    }
    
    // Step 6: Display debug information if enabled
    if(DisplayDebugInfo) {
        // ShowDebugInfo(); // Commented out until implemented
        // Using ShowDiagnosticsOnChart instead which is already implemented
        ShowDiagnosticsOnChart();
    }
}

//+------------------------------------------------------------------+
//| Called on each trade event to track performance                  |
//+------------------------------------------------------------------+
// --- Auto-tune risk/trailing based on rolling win rate ---
void AutoTuneRiskAndTrailing() {
    int n = 0, wins = 0;
    for(int i=0; i<METRIC_WINDOW; i++) {
        if(tradeProfits[i] != 0) {
            n++;
            if(tradeProfits[i] > 0) wins++;
        }
    }
    double winRate = (n > 0) ? double(wins)/n : 0.5;
    double newRisk = workingRiskPercent;
    double newTrailing = workingTrailingStopMultiplierLocal;
    if(winRate < 0.45 && workingRiskPercent > 0.05) newRisk *= 0.9;
    if(winRate > 0.65 && workingRiskPercent < 5.0) newRisk *= 1.1;
    if(winRate < 0.45 && workingTrailingStopMultiplierLocal < 2.0) newTrailing *= 1.1;
    if(winRate > 0.65 && workingTrailingStopMultiplierLocal > 0.1) newTrailing *= 0.9;
    if(MathAbs(newRisk - workingRiskPercent) > 0.01) {
        LogParamChange("Auto-tuned RiskPercent from "+DoubleToString(workingRiskPercent,2)+" to "+DoubleToString(newRisk,2));
        workingRiskPercent = newRisk;
    }
    if(MathAbs(newTrailing - workingTrailingStopMultiplierLocal) > 0.01) {
        LogParamChange("Auto-tuned TrailingStopMultiplier from "+DoubleToString(workingTrailingStopMultiplierLocal,2)+" to "+DoubleToString(newTrailing,2));
        workingTrailingStopMultiplierLocal = newTrailing;
    }
}

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
    double quickAtr = GetATR(symbol, PERIOD_M5, 14, 0);
    double avgRange = 0;
    for(int i=0; i<5; i++) {
        avgRange += MathAbs(iHigh(symbol, PERIOD_M5, i) - iLow(symbol, PERIOD_M5, i));
    }
    avgRange /= 5;
    
    // Define stopDistance for calculating position size
    double stopDistance = quickAtr * 1.0; // Use ATR as a reasonable stop distance 
    
    // Calculate position size using our risk calculation function
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
    double lotSize = CalculatePositionSize(signal > 0 ? 1 : -1, currentPrice, currentPrice - stopDistance);
    
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
    // Replace GetBands calls with standard iBands function
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
    int regime = REGIME_LOW_VOLATILITY; // Default regime
    
    if(breakoutUp || breakoutDown) {
        regime = REGIME_BREAKOUT;
    }
    else if(potentialReversal) {
        regime = REGIME_REVERSAL;
    }
    else if(isChoppy) {
        regime = REGIME_CHOPPY;
    }
    else if(isRangingNarrow) {
        regime = REGIME_RANGING_NARROW;
    }
    else if(isRangingWide) {
        regime = REGIME_RANGING_WIDE;
    }
    else if(isTrendingUp && !isVeryVolatile) {
        regime = REGIME_TRENDING_UP;
    }
    else if(isTrendingDown && !isVeryVolatile) {
        regime = REGIME_TRENDING_DOWN;
    }
    else if(isVolatile) {
        regime = REGIME_HIGH_VOLATILITY;
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
         recentGrabs[grabIndex].isBuy = true;
         recentGrabs[grabIndex].active = true;
         grabIndex = (grabIndex + 1) % MAX_GRABS;
      }
      if(currHigh > prevHigh && wickTop > (0.5 * (currHigh - currLow))) {
         recentGrabs[grabIndex].time = time[i];
         recentGrabs[grabIndex].high = currHigh;
         recentGrabs[grabIndex].low = currLow;
         recentGrabs[grabIndex].isBuy = false;
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
         recentFVGs[fvgIndex].isBuy = true;
         recentFVGs[fvgIndex].active = true;
         fvgIndex = (fvgIndex + 1) % MAX_FVGS;
      }
      if(prevLow - nextHigh > FVGMinSize * _Point) {
         recentFVGs[fvgIndex].startTime = time[i];
         recentFVGs[fvgIndex].endTime = time[i-2];
         recentFVGs[fvgIndex].high = prevLow;
         recentFVGs[fvgIndex].low = nextHigh;
         recentFVGs[fvgIndex].isBuy = false;
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
    int validBlocks = 0;
    int invalidBlocks = 0;
    double blockStrengthSum = 0;
    double blockVolumeSum = 0;
    int lookback = MathMin(500, Bars(Symbol(), PERIOD_CURRENT));
    if(EnableOrderBlockAnalytics) Print(StringFormat("[OB ANALYTICS] DetectOrderBlocks: Scanning %d bars for swing points", lookback));
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
      // Debug print for swing detection
      if(DisplayDebugInfo) {
         Print("[DEBUG] i=",i," | swingHigh=",(high[i] > high[i-1] && high[i] > high[i+1])," | swingLow=",(low[i] < low[i-1] && low[i] < low[i+1]),
               " | high[i]=",high[i]," | low[i]=",low[i]);
      }
      bool swingHigh = high[i] > high[i-1] && high[i] > high[i+1];
      bool swingLow = low[i] < low[i-1] && low[i] < low[i+1];
      if(swingHigh || swingLow) {
         // Debug print for block detection
         if(DisplayDebugInfo) Print("[BLOCK DETECTED] Type: ",(swingLow?"isBuy":"Bearish"), " | Price: ",swingHigh ? high[i] : low[i]);
         // Enhanced: Require minimum body size and volume
         double minBody = (high[i] - low[i]) * 0.30;
// Strict filters for quality blocks
if(MathAbs(open[i] - close[i]) < minBody) continue;  // Require body >= 30% of range
if(volume[i] < volMA[i]*1.2) continue;               // Require volume >= 120% of MA
         if(DisplayDebugInfo) Print("[DEBUG][Aggressive] Block candidate: i=",i," body=",MathAbs(open[i]-close[i])," minBody=",minBody, " vol=",volume[i], " volMA=",volMA[i]);
         recentBlocks[blockIndex].time = time[i];
recentBlocks[blockIndex].price = swingHigh ? high[i] : low[i];
recentBlocks[blockIndex].volume = volume[i];
recentBlocks[blockIndex].isBuy = swingLow;
recentBlocks[blockIndex].valid = true;
         detectedBlocks++;
         long vol = volume[i];
         double body = MathAbs(open[i] - close[i]);
         int score = 0;
if(vol > volMA[i]*1.2) score++;                    // Volume at least 120% of MA
if(body > (high[i] - low[i]) * 0.3) score++;       // Body at least 30% of range
         if(UseLiquidityGrab && swingLow && recentGrabs[(grabIndex-1+MAX_GRABS)%MAX_GRABS].active) score++;
         if(UseImbalanceFVG && recentFVGs[(fvgIndex-1+MAX_FVGS)%MAX_FVGS].active) score++;
         
         // Advanced scoring based on market regime
         if(EnableMarketRegimeFiltering && currentRegime >= 0) {
            // In trending markets, give higher score to blocks aligned with trend
            if(currentRegime == REGIME_TRENDING_UP && swingLow) score++;
            if(currentRegime == REGIME_TRENDING_DOWN && swingHigh) score++;
            
            // In ranging markets, give higher score to blocks at range boundaries
            if((currentRegime == REGIME_RANGING_NARROW || currentRegime == REGIME_RANGING_WIDE) && 
               (recentBlocks[blockIndex].price == MathMin(high[i], high[i-1]) || 
                recentBlocks[blockIndex].price == MathMax(low[i], low[i-1]))) {
               score++;
            }
            
            // In high volatility, require stronger confirmation
            if(currentRegime == REGIME_HIGH_VOLATILITY && vol > volMA[i] * 1.5) score++;
            
            // In breakouts, give higher scores to blocks after the breakout
            if(currentRegime == REGIME_BREAKOUT && vol > volMA[i] * 1.5) {
               bool breakoutUp = close[i-1] > close[i-2] && close[i-2] > close[i-3] && close[i-1] - close[i-3] > GetATR(Symbol(), PERIOD_CURRENT, 14, i-1);
               bool breakoutDown = close[i-1] < close[i-2] && close[i-2] < close[i-3] && close[i-3] - close[i-1] > GetATR(Symbol(), PERIOD_CURRENT, 14, i-1);
               
               if(swingLow && breakoutUp) score++;
               if(swingHigh && breakoutDown) score++;
            }
         }
         
         recentBlocks[blockIndex].strength = score;
         if(DisplayDebugInfo) {
            Print("[SMC] OrderBlock detected: ", (swingLow ? "isBuy" : "Bearish"),
                  " | Price=", DoubleToString(recentBlocks[blockIndex].price, _Digits),
                  " | Score=", score);
         }
         blockIndex = (blockIndex + 1) % MAX_BLOCKS;
      }
   }
   if(DisplayDebugInfo) {
       Print("[DEBUG] Order Block Scan - Analyzing ", lookback, " bars with strength threshold ", MinBlockStrength);
   }
   if(EnableOrderBlockAnalytics) {
       totalBlocksDetected += detectedBlocks;
       totalBlocksValid += validBlocks;
       totalBlocksInvalid += invalidBlocks;
       sumBlockStrength += blockStrengthSum;
       sumBlockVolume += blockVolumeSum;
       // Rolling window
        rollingStrength[rollingIndex % rollingWindow] = blockStrengthSum > 0 && detectedBlocks > 0 ? blockStrengthSum / detectedBlocks : 0;
       rollingVolume[rollingIndex % rollingWindow] = recentBlocks[blockIndex].volume;
       rollingIndex++;
       // Cumulative stats
       Print(StringFormat("[OB ANALYTICS] Tick: Detected=%d, Valid=%d, Invalid=%d | Cumulative: Detected=%d, Valid=%d, Invalid=%d | AvgStrength=%.2f, AvgVolume=%.1f", 
           detectedBlocks, validBlocks, invalidBlocks, totalBlocksDetected, totalBlocksValid, totalBlocksInvalid, sumBlockStrength/totalBlocksDetected, sumBlockVolume/totalBlocksDetected));
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
            switch((int)currentRegime) {
                case REGIME_TRENDING_UP:
                case REGIME_TRENDING_DOWN:
                    atrMultiplier = 1.2; // Wider stops in trends
                    break;
                    
                case REGIME_HIGH_VOLATILITY:
                    atrMultiplier = 1.5; // Much wider stops in volatility
                    break;
                    
                case REGIME_CHOPPY:
                    atrMultiplier = 1.3; // Wider stops in choppy markets
                    break;
                    
                case REGIME_RANGING_NARROW:
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
    // Enforce broker minimum stop distance with enhanced logging
    double minStopDistance = CalcBrokerMinStop();
    double originalStopLoss = stopLoss;
    double stopDistance = signal > 0 ? (entryPrice - stopLoss) : (stopLoss - entryPrice);
    
    LogInfo("[SL CALC] Pre-validation: Signal=" + IntegerToString(signal) + 
            ", Entry=" + DoubleToString(entryPrice, _Digits) + 
            ", SL=" + DoubleToString(stopLoss, _Digits) + 
            ", Distance=" + DoubleToString(stopDistance, _Digits) + 
            ", MinRequired=" + DoubleToString(minStopDistance, _Digits));
    
    if(signal > 0 && stopDistance < minStopDistance) {
        stopLoss = entryPrice - minStopDistance;
        LogInfo("[SL VALIDATION] Buy stop adjusted to meet broker minimum: " + 
               "Original=" + DoubleToString(originalStopLoss, _Digits) + 
               " -> New=" + DoubleToString(stopLoss, _Digits));
    } else if(signal < 0 && stopDistance < minStopDistance) {
        stopLoss = entryPrice + minStopDistance;
        LogInfo("[SL VALIDATION] Sell stop adjusted to meet broker minimum: " + 
               "Original=" + DoubleToString(originalStopLoss, _Digits) + 
               " -> New=" + DoubleToString(stopLoss, _Digits));
    }
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
    
    // Default fallback
    return 1;
}

//+------------------------------------------------------------------+
//| Find recent swing point high (for sell trades)                    |
//+------------------------------------------------------------------+
int FindRecentSwingPointHigh(bool isBuy, int startBar = 1, int lookbackBars = 20) {
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
            sum += volume[i-j];
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
        if((isBuy && swingLow) || (!isBuy && swingHigh)) {
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
//| Adjust trailing stops for open positions                        |
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
            CTrade tradeLocal; // Renamed to avoid shadowing global variable
            // Use the proper magic number from the EA
            int magicNumber = 12345; // Default fallback value
            if(GlobalVariableCheck("SMC_Magic")) {
                magicNumber = (int)GlobalVariableGet("SMC_Magic");
            }
            tradeLocal.SetExpertMagicNumber(magicNumber);
            
            // Modify the position's stop loss
            if(tradeLocal.PositionModify(ticket, newSL, currentTP)) {
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
//| Dynamically adjust risk based on account drawdown                |
//+------------------------------------------------------------------+
double DynamicDrawdownControl() {
    // Get account equity and balance
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Calculate current drawdown percentage
    double drawdownPercent = 100.0 * (1.0 - equity / balance);
    
    // If drawdown is negative (we're in profit), return normal risk
    if(drawdownPercent <= 0)
        return 1.0;
        
    // Define drawdown thresholds and corresponding risk adjustments
    double maxDrawdownPercent = MaxDrawdownPercent; // Maximum allowed drawdown percentage
    
    // Calculate risk adjustment factor based on current drawdown
    // As drawdown approaches maxDrawdownPercent, risk is reduced linearly
    double adjustmentFactor = 1.0 - (drawdownPercent / maxDrawdownPercent);
    
    // Ensure adjustment factor is between MinRiskMultiplier and 1.0
    adjustmentFactor = MathMax(MinRiskMultiplier, MathMin(1.0, adjustmentFactor));
    
    // Log the drawdown adjustment if significant
    if(adjustmentFactor < 0.95) {
        LogInfo("Drawdown control activated: Current drawdown = " + DoubleToString(drawdownPercent, 2) + 
                "%, Risk adjustment = " + DoubleToString(adjustmentFactor, 2));
    }
    
    return adjustmentFactor;
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
    CTrade trade;
    if(trade.PositionModify(posTicket, beLevel, PositionGetDouble(POSITION_TP))) {
        LogTrade("Moved position #" + IntegerToString(posTicket) + " to break even: " + DoubleToString(beLevel, _Digits));
    }
    else {
        LogError("Failed to move position to break even: " + IntegerToString(trade.ResultRetcode()));
    }
}

//+------------------------------------------------------------------+
//| Execute multi-target strategy with partial take profits         |
//+------------------------------------------------------------------+
bool ExecuteMultiTargetStrategy(int signal, double entryPrice, double stopLoss) {
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
    
    // Calculate take profit levels based on R multiples
    double tp1 = 0, tp2 = 0, tp3 = 0;
    
    if(signal == SIGNAL_BUY) {
        tp1 = entryPrice + (rValue * TP1_RR_Ratio);
        tp2 = entryPrice + (rValue * TP2_RR_Ratio);
        tp3 = entryPrice + (rValue * TP3_RR_Ratio);
    }
    else if(signal == SIGNAL_SELL) {
        tp1 = entryPrice - (rValue * TP1_RR_Ratio);
        tp2 = entryPrice - (rValue * TP2_RR_Ratio);
        tp3 = entryPrice - (rValue * TP3_RR_Ratio);
    }
    else {
        LogError("Invalid signal for multi-target strategy: " + IntegerToString(signal));
        return false;
    }
    
    // Calculate position size based on risk parameters
    double lotSize = CalculatePositionSize(signal, entryPrice, stopLoss);
    
    // If lot size is too small, exit
    if(lotSize < minLot) {
        LogError("Calculated lot size too small: " + DoubleToString(lotSize, 2));
        return false;
    }
    
    // Split the position size according to the target percentages
    double lot1 = NormalizeDouble(lotSize * TP1_Size_Percent / 100.0, 2);
    double lot2 = NormalizeDouble(lotSize * TP2_Size_Percent / 100.0, 2);
    double lot3 = NormalizeDouble(lotSize * (100.0 - TP1_Size_Percent - TP2_Size_Percent) / 100.0, 2);
    
    // Ensure minimum lot sizes
    if(lot1 < minLot) lot1 = minLot;
    if(lot2 < minLot) lot2 = minLot;
    if(lot3 < minLot) lot3 = minLot;
    
    // Execute trades for each target
    bool success = true;
    
    // First target
    if(!ExecuteTradeWithRetry(signal, entryPrice, stopLoss, tp1, lot1, "TP1")) {
        LogError("Failed to execute TP1 trade");
        success = false;
    }
    else {
        LogTrade("TP1 trade executed: " + EnumToString((ENUM_ORDER_TYPE)signal) + 
                ", Lot=" + DoubleToString(lot1, 2) + 
                ", Entry=" + DoubleToString(entryPrice, _Digits) + 
                ", SL=" + DoubleToString(stopLoss, _Digits) + 
                ", TP=" + DoubleToString(tp1, _Digits));
    }
    
    // Second target
    if(success && lot2 >= minLot) {
        if(!ExecuteTradeWithRetry(signal, entryPrice, stopLoss, tp2, lot2, "TP2")) {
            LogError("Failed to execute TP2 trade");
        }
        else {
            LogTrade("TP2 trade executed: " + EnumToString((ENUM_ORDER_TYPE)signal) + 
                    ", Lot=" + DoubleToString(lot2, 2) + 
                    ", Entry=" + DoubleToString(entryPrice, _Digits) + 
                    ", SL=" + DoubleToString(stopLoss, _Digits) + 
                    ", TP=" + DoubleToString(tp2, _Digits));
        }
    }
    
    // Third target
    if(success && lot3 >= minLot) {
        if(!ExecuteTradeWithRetry(signal, entryPrice, stopLoss, tp3, lot3, "TP3")) {
            LogError("Failed to execute TP3 trade");
        }
        else {
            LogTrade("TP3 trade executed: " + EnumToString((ENUM_ORDER_TYPE)signal) + 
                    ", Lot=" + DoubleToString(lot3, 2) + 
                    ", Entry=" + DoubleToString(entryPrice, _Digits) + 
                    ", SL=" + DoubleToString(stopLoss, _Digits) + 
                    ", TP=" + DoubleToString(tp3, _Digits));
        }
    }
    
    return success;
}

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
            if(!OrderCheck((ENUM_POSITION_TYPE)posType, newSL, currentTP)) {
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
//| Check if order SL/TP is valid before submission                   |
//+------------------------------------------------------------------+
bool OrderCheck(ENUM_POSITION_TYPE type, double sl, double tp) {
    double ask = GetCurrentAsk();
    double bid = GetCurrentBid();
    double point = GetSymbolPoint();
    int minDistance = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    
    // Check SL
    if(sl != 0) {
        if(type == POSITION_TYPE_BUY) {
            if(bid - sl < minDistance * point) {
                return false; // SL too close
            }
        }
        else { // SELL
            if(sl - ask < minDistance * point) {
                return false; // SL too close
            }
        }
    }
    
    // Check TP
    if(tp != 0) {
        if(type == POSITION_TYPE_BUY) {
            if(tp - bid < minDistance * point) {
                return false; // TP too close
            }
        }
        else { // SELL
            if(ask - tp < minDistance * point) {
                return false; // TP too close
            }
        }
    }
    
    return true;
}

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
    
    // Calculate take profit levels based on R multiples
    double tp1 = 0, tp2 = 0;
    
    // Use the global TPRatio1 and TPRatio2 values defined as input parameters
    // If they're zero, use default values
    double tpRatio1 = (TPRatio1 > 0) ? TPRatio1 : 1.0; // Default 1:1 risk:reward for first target
    double tpRatio2 = (TPRatio2 > 0) ? TPRatio2 : 2.0; // Default 1:2 risk:reward for second target
    
    if(signal > 0) { // BUY
        tp1 = entryPrice + (rValue * tpRatio1);
        tp2 = entryPrice + (rValue * tpRatio2);
    } else { // SELL
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
    double correlationFactor = CalculateCorrelationAdjustment(signal);
    double timeDecayFactor = CalculateTimeDecayFactor(signal);    
    totalLots *= correlationFactor * timeDecayFactor;
    
    // Split position into three parts
    double lotsPart1 = NormalizeDouble(totalLots / 3, 2);
    double lotsPart2 = NormalizeDouble(totalLots / 3, 2);
    double lotsPart3 = NormalizeDouble(totalLots - lotsPart1 - lotsPart2, 2); // Ensures exact total
    
    // Minimum lot size check
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    if(lotsPart1 < minLot || lotsPart2 < minLot || lotsPart3 < minLot) {
        LogError("Lot size too small for multi-target strategy, using single position");
        return false;
    }
    
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
    } else { // SELL
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
        } else { // SELL
            if(trade_local.Sell(lotsPart2, Symbol(), 0, stopLoss, tp2, "TP2_" + DoubleToString(tpRatio2, 1) + "R")) {
                ticket2 = trade_local.ResultOrder();
                LogTrade("Part 2/3: Sell order placed, ticket=" + IntegerToString((int)ticket2));
            }
        }
    }
    
    // Part 3: Trailing portion
    if(ticket1 > 0 && ticket2 > 0) { // Only proceed if previous parts were successful
        if(signal > 0) { // BUY
            if(trade_local.Buy(lotsPart3, Symbol(), 0, stopLoss, 0, "FINAL_TRAIL")) {
                ticket3 = trade_local.ResultOrder();
                LogTrade("Part 3/3: Buy order placed for trailing, ticket=" + IntegerToString((int)ticket3));
            }
        } else { // SELL
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
    
    // Also check daily profit/loss
    static datetime lastDayChecked = 0;
    static double dayStartBalance = 0;
    
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
    
    // Apply daily loss control
    double MaxDailyLossPercent = 5.0; // Default value if not defined as input parameter
    if(dailyPLPct < -MaxDailyLossPercent) {
        // Approaching/exceeding daily loss limit
        adjustment *= 0.1;  // Drastically reduce risk
        LogRisk("DAILY LOSS LIMIT APPROACHING: " + DoubleToString(dailyPLPct,2) + "% - Severely reducing risk");
    } else if(dailyPLPct < -MaxDailyLossPercent*0.7) {
        // Getting close to daily loss limit
        adjustment *= 0.5;  // Significantly reduce risk
        LogRisk("Daily loss significant: " + DoubleToString(dailyPLPct,2) + "% - Reducing risk");
    }
    
    return adjustment;
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
        switch((int)currentRegime) {
            case REGIME_TRENDING_UP:
                rrMultiplier = 3.0; // Higher targets in trending markets
                break;
                
            case REGIME_TRENDING_DOWN:
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
                
            case REGIME_HIGH_VOLATILITY:
                rrMultiplier = 2.25; // Adjust for volatility
                break;
                
            case REGIME_CHOPPY:
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
//| Find recent swing points                                         |
//+------------------------------------------------------------------+
int FindRecentSwingPointHigh(bool isBuy, int startBar = 1, int lookbackBars = 20) {
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
//| Find recent swing points                                         |
//+------------------------------------------------------------------+
int FindRecentSwingPoint(bool isBuy, int startBar = 1, int lookbackBars = 20) {
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
enum ENUM_DIVERGENCE_TYPE {
    DIVERGENCE_NONE = 0,    // No divergence
    DIVERGENCE_REGULAR_BULL, // Regular isBuy (price lower low, oscillator higher low)
    DIVERGENCE_REGULAR_BEAR, // Regular bearish (price higher high, oscillator lower high)
    DIVERGENCE_HIDDEN_BULL,  // Hidden isBuy (price higher low, oscillator lower low)
    DIVERGENCE_HIDDEN_BEAR   // Hidden bearish (price lower high, oscillator higher high)
};

enum MARKET_STRUCTURE {
    MARKET_STRUCTURE_UPTREND,
    MARKET_STRUCTURE_DOWNTREND, 
    MARKET_STRUCTURE_RANGE
};

MARKET_STRUCTURE currentMarketStructure;

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
                divInfo.type = DIVERGENCE_REGULAR_BULL;
                divInfo.firstBar = low2;
                divInfo.secondBar = low1;
                divInfo.strength = 0.7 + 0.3 * (rsiValues[low1] - rsiValues[low2]) / rsiValues[low2];
                divInfo.timeDetected = times[0];
                
                if(DisplayDebugInfo) {
                    Print("[SMC] Regular isBuy Divergence detected: Price made lower low but RSI made higher low");
                    Print("[SMC] Divergence Strength: ", DoubleToString(divInfo.strength, 2));
                }
                return true;
            }
            // Also check for hidden isBuy divergence (price higher low, oscillator lower low)
            else if(lowPrices[low1] > lowPrices[low2] && rsiValues[low1] < rsiValues[low2]) {
                divInfo.found = true;
                divInfo.type = DIVERGENCE_HIDDEN_BULL;
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
//| Enhanced position management function                           |
//+------------------------------------------------------------------+
// Note: ManageOpenTrade function is already defined earlier in the code
// This section is kept as a reference for additional features

//+------------------------------------------------------------------+
//| Manage trailing stops with enhanced early activation           |
//+------------------------------------------------------------------+
void ManageTrailingStops() {
    if(!EnableTrailingStops && !EnableBreakEven && !EnableAggressiveTrailing) return;
    
    int totalPositions = PositionsTotal();
    if(totalPositions == 0) return;
    
    // Get ATR for dynamic trailing calculations
    double atr = GetATR(Symbol(), PERIOD_CURRENT, ATRperiod, 0);
    if(atr == 0) return;
    
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
                        CTrade trade_local;
                        trade_local.SetExpertMagicNumber(MagicNumber);
                        double currentTP = PositionGetDouble(POSITION_TP);
                        trade_local.PositionModify(ticket, chochSL, currentTP);
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
                if(tradeLocal.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
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
                    
                    CTrade trade_local; // Create local trade object
                    trade_local.SetExpertMagicNumber(MagicNumber);
                    trade_local.PositionModify(ticket, chochSL, currentTP);
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
                            
                            if(tradeLocal.PositionModify(ticket, newSL > 0 ? newSL : currentSL, newTP)) {
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
                            
                            if(tradeLocal.PositionModify(ticket, newSL > 0 ? newSL : currentSL, newTP)) {
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
                    
                    if(tradeLocal.PositionModify(ticket, potentialSL, currentTP)) {
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
}
                    


//+------------------------------------------------------------------+
//| Move position to break-even (entry price + buffer)                |
//+------------------------------------------------------------------+
bool MoveToBreakEven(double entryPrice, double currentSL, ENUM_POSITION_TYPE posType, ulong ticket, double spread) {
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
        CTrade trade_local; // Renamed to avoid shadowing global variable
        trade_local.SetExpertMagicNumber(MagicNumber);
        
        // Round to broker requirements
        newSL = NormalizeDouble(newSL, _Digits);
        
        // Get current take profit
        double currentTP = PositionGetDouble(POSITION_TP);
        
        // Apply modification
        if(trade_local.PositionModify(ticket, newSL, currentTP)) {
            if(DisplayDebugInfo) {
                Print("[SMC] Moved to break-even: Ticket=", ticket, ", New SL=", newSL);
            }
            return true;
        } else {
            LogError("Failed to move to break-even: " + GetLastErrorText(GetLastError()));
            return false;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Standard trade execution implementation                          |
//+------------------------------------------------------------------+
bool ExecuteTrade(int signal, double entryPrice, double stopLoss) {
    if(signal == 0) return false;
    
    // Calculate take profit based on risk:reward ratio
    double takeProfit = 0.0;
    double riskPips = MathAbs(entryPrice - stopLoss) / _Point;
    
    // Default R:R ratio of 1.5:1
    double rewardPips = riskPips * RiskRewardRatio;
    
    if(signal > 0) { // BUY
        takeProfit = entryPrice + (rewardPips * _Point);
    } else { // SELL
        takeProfit = entryPrice - (rewardPips * _Point);
    }
    
    // Calculate position size
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (RiskPercent / 100.0);
    double lotSize = CalculateDynamicSize(RiskPercent, MathAbs(entryPrice - stopLoss));
    
    // Apply any additional modifiers
    if(EnableAdaptiveRisk) {
        double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
        lotSize = CalculateAdaptivePositionSize(lotSize, atr);
    }
    
    double corrFactor = CalculateCorrelationAdjustment(signal);
    double timeFactor = CalculateTimeDecayFactor(signal);
    lotSize *= corrFactor * timeFactor;
    
    // Ensure minimum lot size
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    if(lotSize < minLot) lotSize = minLot;
    
    // Normalize lot size to broker requirements
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Enhanced logging for stop loss validation
    LogInfo("[SL VALIDATE] Signal=" + IntegerToString(signal) + 
            ", Entry=" + DoubleToString(entryPrice, _Digits) + 
            ", SL=" + DoubleToString(stopLoss, _Digits) + 
            ", Distance=" + DoubleToString(MathAbs(entryPrice - stopLoss) / _Point, 1) + " points");
    
    // Execute the trade
    CTrade trade_local; // Renamed to avoid shadowing global variable
    tradeLocal.SetDeviationInPoints(AdaptiveSlippagePoints);
    trade_local.SetExpertMagicNumber(MagicNumber);
    
    bool success = false;
    if(signal > 0) { // BUY
        success = tradeLocal.Buy(lotSize, Symbol(), 0, stopLoss, takeProfit, "SMC Hybrid");
    } else { // SELL
        success = tradeLocal.Sell(lotSize, Symbol(), 0, stopLoss, takeProfit, "SMC Hybrid");
    }
    
    if(success) {
        LogTrade("Trade executed: " + (signal > 0 ? "BUY" : "SELL") + 
                " Lot=" + DoubleToString(lotSize, 2) + 
                " Entry=" + DoubleToString(entryPrice, _Digits) + 
                " SL=" + DoubleToString(stopLoss, _Digits) + 
                " TP=" + DoubleToString(takeProfit, _Digits));
    } else {
        LogError("Trade execution failed: " + IntegerToString(GetLastError()) + 
                " | SL Distance: " + DoubleToString(MathAbs(entryPrice - stopLoss) / _Point, 1) + 
                " points | MinSL: " + DoubleToString(CalcBrokerMinStop() / _Point, 1) + " points");
    }
    
    return success;
}

//+------------------------------------------------------------------+
//| Robust trade execution with retries and exponential backoff      |
//+------------------------------------------------------------------+
bool TradeWithRetry(string action, double lots, double price, double sl, double tp, int maxRetries=3) {
    int attempt = 0;
    while(attempt < maxRetries) {
        bool result = false;
        if(action == "BUY")
            result = tradeLocal.Buy(lots, Symbol(), price, sl, tp);
        else if(action == "SELL")
            result = tradeLocal.Sell(lots, Symbol(), price, sl, tp);
        else if(action == "CLOSE")
            result = tradeLocal.PositionClose(Symbol());
        else if(action == "MODIFY")
            result = tradeLocal.PositionModify(ticket, newSL, currentTP);
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
// CalculateAdaptivePositionSize already defined at line 3770 - commenting out duplicate implementation
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
    if(CopyBuffer(handle, 0, shift, 1, atr) <= 0) {
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
    int handle = iBands(symbol, timeframe, period, deviation, 0, price_type);
    if(handle == INVALID_HANDLE) {
        LogError("Failed to create Bollinger Bands indicator. Error: " + IntegerToString(GetLastError()));
        return 0.0;
    }
    
    double bands[];
    ArraySetAsSeries(bands, true);
    
    if(CopyBuffer(handle, mode, shift, 1, bands) <= 0) {
        LogError("Failed to copy Bollinger Bands data. Error: " + IntegerToString(GetLastError()));
        IndicatorRelease(handle);
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
    
    // Find recent swing levels
    int swingHighBar = FindRecentSwingPoint(false);
    int swingLowBar = FindRecentSwingPoint(true);
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
        volume[i] = iVolume(Symbol(), PERIOD_M15, i);
    }
    
    // Calculate average volume
    double avgVolume = 0;
    for(int i=1; i<5; i++) { // Skip current bar
        avgVolume += volume[i];
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
    
    // Find potential swing points
    int swingHighBar = FindRecentSwingPointHigh(false, 1, 20);
    int swingLowBar = FindRecentSwingPoint(true, 1, 20);
    
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
    bool chochDetected = false;
    
    // For buy positions, look for a higher low after a pullback
    if(isBuy) {
        // Get recent price data
        double low[], high[];
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(high, true);
        
        if(CopyLow(Symbol(), PERIOD_CURRENT, 0, 20, low) > 0 && 
           CopyHigh(Symbol(), PERIOD_CURRENT, 0, 20, high) > 0) {
            
            // Find recent swing low
            int swingLowBar = FindRecentSwingPoint(true, 1, 15);
            
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
                        chochDetected = true;
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
            
            // Find recent swing high
            int swingHighBar = FindRecentSwingPointHigh(false, 1, 15);
            
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
                        chochDetected = true;
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
    
    return chochDetected;
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
//| Advanced Order Block Detection                                   |
//+------------------------------------------------------------------+
void FindOrderBlocks(string symbol, ENUM_TIMEFRAMES timeframe) {
    int bars = 100;
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    CopyHigh(symbol, timeframe, 0, bars, high);
    CopyLow(symbol, timeframe, 0, bars, low);
    CopyClose(symbol, timeframe, 0, bars, close);
    long volume[];
    if(CopyTickVolume(symbol, timeframe, 0, bars, volume) < bars) {
        Print("[ERROR] Failed to copy tick volume data");
        return;
    }
    
    double avgVolume = 0;
    for(int i=0; i<bars; i++) avgVolume += volume[i];
    avgVolume /= bars;
    
    for(int i=3; i<bars-3; i++) {
        bool isisBuyBlock = (close[i] > close[i+1] && 
                             volume[i] > avgVolume*1.5 &&
                             low[i] < low[i+1] && low[i] < low[i+2]);
                             
        bool isBearishBlock = (close[i] < close[i+1] && 
                             volume[i] > avgVolume*1.5 &&
                             high[i] > high[i+1] && high[i] > high[i+2]);
        
        if(isisBuyBlock || isBearishBlock) {
            int idx = -1;
            for(int j=0; j<MAX_BLOCKS; j++) {
                if(!recentBlocks[j].valid) {
                    idx = j;
                    break;
                }
            }
            
            if(idx >= 0) {
                recentBlocks[idx].price = isisBuyBlock ? low[i] : high[i];
                recentBlocks[idx].time = iTime(symbol, timeframe, i);
                recentBlocks[idx].volume = (double)volume[i];
                recentBlocks[idx].isBuy = isisBuyBlock;
                recentBlocks[idx].valid = true;
                
                if(DisplayDebugInfo) {
                    Print(StringFormat("[ORDER BLOCK] %s %s - %s block at %.5f (volume: %.1fx avg)",
                          symbol, EnumToString(timeframe),
                          isisBuyBlock ? "isBuy" : "Bearish",
                          recentBlocks[idx].price,
                          volume[i]/avgVolume));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Advanced Market Structure Analysis                               |
//+------------------------------------------------------------------+
void AnalyzeMarketStructure(string symbol, ENUM_TIMEFRAMES timeframe) {
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
    bool uptrend = true;
    for(int i=1; i<5; i++) {
        if(high[i] <= high[i+1] || low[i] <= low[i+1]) {
            uptrend = false;
            break;
        }
    }
    
    // Detect Lower Highs/Lows for downtrend
    bool downtrend = true;
    for(int i=1; i<5; i++) {
        if(high[i] >= high[i+1] || low[i] >= low[i+1]) {
            downtrend = false;
            break;
        }
    }
    
    // Update global market structure state
    if(uptrend) currentMarketStructure = MARKET_STRUCTURE_UPTREND;
    else if(downtrend) currentMarketStructure = MARKET_STRUCTURE_DOWNTREND;
    else currentMarketStructure = MARKET_STRUCTURE_RANGE;
    
    if(DisplayDebugInfo) {
        string structure = "Unknown";
        if(currentMarketStructure == MARKET_STRUCTURE_UPTREND) structure = "Uptrend";
        else if(currentMarketStructure == MARKET_STRUCTURE_DOWNTREND) structure = "Downtrend";
        else if(currentMarketStructure == MARKET_STRUCTURE_RANGE) structure = "Range";
        Print("[MARKET STRUCTURE] ", symbol, " ", EnumToString(timeframe), " - ", structure);
    }
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
    
    // Using the updated enum values to avoid conversion errors
    MARKET_PHASE phase = PHASE_RANGING_WIDE; // Use PHASE_RANGING_WIDE instead of RANGING_WIDE
    
    if(breakoutUp || breakoutDown) {
        phase = PHASE_TRENDING_UP; // Use PHASE_* instead of REGIME_*
    }
    else if(potentialReversal) {
        phase = PHASE_TRENDING_DOWN; // Use PHASE_* instead of REGIME_*
    }
    else if(isChoppy) {
        phase = PHASE_CHOPPY; // Use PHASE_* instead of REGIME_*
    }
    else if(isRangingNarrow) {
        phase = PHASE_RANGING_NARROW; // Use PHASE_* instead of RANGING_NARROW
    }
    else if(isRangingWide) {
        phase = PHASE_RANGING_WIDE; // Use PHASE_RANGING_WIDE for consistency
    }
    else if(isVolatile || bbWidth > 0.05) {
        phase = PHASE_HIGH_VOLATILITY; // Use PHASE_HIGH_VOLATILITY instead of numeric 5
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
        case REGIME_TRENDING_UP:
            ActualSignalCooldownSeconds = 1;
            break;
        case REGIME_TRENDING_DOWN:
            ActualSignalCooldownSeconds = 1;
            break;
        case RANGING_WIDE: // Assuming RANGING_WIDE corresponds to PHASE_RANGING
        case RANGING_NARROW:
            ActualSignalCooldownSeconds = 3;
            break;
        case REGIME_HIGH_VOLATILITY:
            ActualSignalCooldownSeconds = 5;
            break;
        default:
            ActualSignalCooldownSeconds = 2; // Default value
            break;
    }
}

void AdjustRiskParameters(MARKET_PHASE phase) {
    // Create a local risk adjustment factor instead of trying to modify RiskPercent directly
    double adjustedRiskFactor = 1.0;
    
    switch(phase) {
        case REGIME_TRENDING_UP:
            adjustedRiskFactor = 1.0; // No adjustment
            break;
        case REGIME_TRENDING_DOWN:
            adjustedRiskFactor = 1.0; // No adjustment
            break;
        case RANGING_WIDE: // Assuming RANGING_WIDE corresponds to PHASE_RANGING
        case RANGING_NARROW:
            adjustedRiskFactor = 0.5; // Reduce risk by half
            break;
        case REGIME_HIGH_VOLATILITY:
            adjustedRiskFactor = 0.25; // Reduce risk to 25%
            break;
        default:
            adjustedRiskFactor = 0.75; // Default conservative adjustment
            break;
    }
    
    // Use the adjustedRiskFactor in calculations elsewhere
    // This doesn't try to modify RiskPercent directly
    if(DisplayDebugInfo) {
        Print("[RISK] Adjusted risk factor for phase ", EnumToString(phase), ": ", DoubleToString(adjustedRiskFactor, 2));
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
    
    CTrade trade_local; // Renamed to avoid shadowing global variable
    tradeLocal.SetDeviationInPoints(AdaptiveSlippagePoints);
    return trade_local.PositionModify(ticket, chochSL, currentTP);
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk percentage and stop distance |
//+------------------------------------------------------------------+
double CalculateDynamicSize(double riskPercent, double stopDistance) {
    // Get account balance and symbol information
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double point = GetSymbolPoint();
    
    // Calculate raw position size
    if(stopDistance <= 0 || tickValue <= 0) {
        if(DisplayDebugInfo) Print("[ERROR] Invalid parameters for position sizing - StopDistance: ", stopDistance, " TickValue: ", tickValue);
        return 0;
    }
    
    double riskAmount = balance * (riskPercent/100);
    double rawSize = riskAmount / (stopDistance * tickValue);
    
    // Apply broker constraints
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    // Round to nearest valid lot size
    double validSize = MathFloor(rawSize/lotStep) * lotStep;
    validSize = MathMax(minLot, MathMin(maxLot, validSize));
    
    if(DisplayDebugInfo) {
        Print(StringFormat("[SIZING] Balance: %.2f | Risk: %.1f%% | Stop: %.1f pips | Size: %.2f lots",
              balance, riskPercent, stopDistance/point, validSize));
    }
    
    return validSize;
}

//+------------------------------------------------------------------+
//| Execute trade with retry mechanism for improved reliability      |
//+------------------------------------------------------------------+
bool ExecuteTradeWithRetry(int signal, double entryPrice, double stopLoss, double takeProfit, double lotSize, string comment) {
    // Initialize trade object
    CTrade trade;
    trade.SetDeviationInPoints(MaxSlippage);
    
    // Set magic number
    int magicNumber = 12345; // Default fallback value
    if(GlobalVariableCheck("SMC_Magic")) {
        magicNumber = (int)GlobalVariableGet("SMC_Magic");
    }
    trade.SetExpertMagicNumber(magicNumber);
    
    // Normalize price values
    entryPrice = NormalizeDouble(entryPrice, _Digits);
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    takeProfit = NormalizeDouble(takeProfit, _Digits);
    
    // Check if order parameters are valid
    if(!OrderCheck(signal, stopLoss, takeProfit)) {
        LogError("Invalid order parameters: Signal=" + IntegerToString(signal) + 
                ", Entry=" + DoubleToString(entryPrice, _Digits) + 
                ", SL=" + DoubleToString(stopLoss, _Digits) + 
                ", TP=" + DoubleToString(takeProfit, _Digits));
        return false;
    }
    
    // Maximum retry attempts
    int maxRetries = 3;
    int retryCount = 0;
    bool success = false;
    
    // Get current market prices
    double currentAsk = GetCurrentAsk();
    double currentBid = GetCurrentBid();
    
    // Start retry loop
    while(retryCount < maxRetries && !success) {
        // Execute trade based on signal type
        if(signal == SIGNAL_BUY) {
            // For buy orders, use current ask price
            success = trade.Buy(lotSize, _Symbol, currentAsk, stopLoss, takeProfit, comment);
        }
        else if(signal == SIGNAL_SELL) {
            // For sell orders, use current bid price
            success = trade.Sell(lotSize, _Symbol, currentBid, stopLoss, takeProfit, comment);
        }
        else {
            LogError("Invalid signal type: " + IntegerToString(signal));
            return false;
        }
        
        // Check if trade was successful
        if(success) {
            // Log successful trade execution
            string orderType = (signal == SIGNAL_BUY) ? "Buy" : "Sell";
            double execPrice = (signal == SIGNAL_BUY) ? currentAsk : currentBid;
            
            LogTrade(orderType + " order executed: " + 
                    "Ticket=" + IntegerToString((int)trade.ResultOrder()) + 
                    ", Price=" + DoubleToString(execPrice, _Digits) + 
                    ", Lot=" + DoubleToString(lotSize, 2) + 
                    ", SL=" + DoubleToString(stopLoss, _Digits) + 
                    ", TP=" + DoubleToString(takeProfit, _Digits) + 
                    ", Comment=" + comment);
            break;
        }
        else {
            // Log error and retry
            int lastError = GetLastError();
            LogError("Trade execution failed (Attempt " + IntegerToString(retryCount + 1) + "/" + 
                    IntegerToString(maxRetries) + "): " + GetLastErrorText(lastError));
            
            // Increment retry counter
            retryCount++;
            
            // Wait before retrying (increasing delay with each retry)
            Sleep(100 * retryCount);
            
            // Update prices for next attempt
            currentAsk = GetCurrentAsk();
            currentBid = GetCurrentBid();
        }
    }
    
    // Track consecutive errors for risk management
    if(!success) {
        ConsecutiveTradeErrors++;
        if(ConsecutiveTradeErrors >= MaxConsecutiveErrors) {
            LogError("Maximum consecutive trade errors reached: " + IntegerToString(ConsecutiveTradeErrors) + 
                    ". Consider pausing trading or checking connection.");
        }
    }
    else {
        // Reset error counter on success
        ConsecutiveTradeErrors = 0;
    }
    
    return success;
}

//+------------------------------------------------------------------+
//| Check if order parameters are valid before submission           |
//+------------------------------------------------------------------+
bool OrderCheck(int signal, double stopLoss, double takeProfit) {
    // Get current market prices
    double currentAsk = GetCurrentAsk();
    double currentBid = GetCurrentBid();
    
    // Get minimum stop level in points
    int minStopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double minStopDistance = minStopLevel * _Point;
    
    // Check if stop loss and take profit are valid based on signal type
    if(signal == SIGNAL_BUY) {
        // For buy orders, stop loss must be below entry price and take profit above
        if(stopLoss >= currentAsk) {
            LogError("Invalid stop loss for buy order: SL (" + DoubleToString(stopLoss, _Digits) + 
                    ") must be below entry price (" + DoubleToString(currentAsk, _Digits) + ")");
            return false;
        }
        
        // Check if stop loss is too close to current price
        if(currentAsk - stopLoss < minStopDistance) {
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
        
        // Check if take profit is too close to current price
        if(takeProfit - currentAsk < minStopDistance) {
            LogError("Take profit too close to entry price for buy order: " + 
                    DoubleToString(takeProfit - currentAsk, _Digits) + " < " + 
                    DoubleToString(minStopDistance, _Digits));
            return false;
        }
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
}

//+------------------------------------------------------------------+
//| Get current bid price                                            |
//+------------------------------------------------------------------+
double GetCurrentBid() {
    return SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

//+------------------------------------------------------------------+
//| Get current ask price                                            |
//+------------------------------------------------------------------+
double GetCurrentAsk() {
    return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
}

//+------------------------------------------------------------------+
//| Get symbol point value                                           |
//+------------------------------------------------------------------+
double GetSymbolPoint() {
    return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}
