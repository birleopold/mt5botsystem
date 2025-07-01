//+------------------------------------------------------------------+
//| SMC Scalper Hybrid - Smart Money Concepts with Advanced Scalping |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Leo Software"
#property link      "https://www.example.com"
#property version   "1.0"
#property strict

// Include required files
#include <Trade/Trade.mqh>
#include <Math/Stat/Normal.mqh>

// Core Constants and Definitions
#define MAX_BLOCKS 20
#define MAX_GRABS 10
#define MAX_FVGS 10
#define MAX_BOS 15
#define MAX_CHOCH 10
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

// --- INPUTS AND PARAMETERS ---
// Trading Timeframes
input ENUM_TIMEFRAMES AnalysisTimeframe = PERIOD_H1;  // Main analysis timeframe
input ENUM_TIMEFRAMES ScanningTimeframe = PERIOD_M15; // Scanning timeframe
input ENUM_TIMEFRAMES ExecutionTimeframe = PERIOD_M5; // Execution timeframe

// Risk Management
input int TradingStartHour = 0;
input int TradingEndHour = 23;
input int MaxTrades = 2;               // Maximum concurrent trades
input double RiskPercent = 0.1;        // Risk per trade as % of balance
input double SL_Pips = 10.0;           // Initial stop loss in pips
input double TP_Pips = 30.0;           // Initial take profit in pips
input int SignalCooldownSeconds = 60;  // Seconds between trade signals
input int MinBlockStrength = 1;        // Minimum order block strength for valid signal
input bool RequireTrendConfirmation = false; // Require trend confirmation for trades
input int MaxConsecutiveLosses = 3;    // Stop trading after this many consecutive losses

// Advanced Scalping Parameters
input bool EnableFastExecution = true;  // Enable fast execution mode
input bool EnableAdaptiveRisk = true;   // Enable adaptive position sizing
input bool EnableAggressiveTrailing = true; // Use aggressive trailing stops
input double TrailingActivationPct = 0.5; // When to activate trailing (% of TP reached)
input double TrailingStopMultiplier = 0.5; // Trailing stop multiplier of ATR
input double EnhancedRR = 2.0; // Enhanced risk:reward ratio after trailing activation
input bool EnableMarketRegimeFiltering = true; // Filter trades based on market regime
input bool EnableNewsFilter = false;   // Enable news events filter

// Smart Money Concepts Advanced Features
input group "Advanced SMC Features"
input bool EnableBOS = true;           // Enable Break of Structure detection
input bool EnableCHoCH = true;         // Enable Change of Character detection
input double BOSStrengthMultiplier = 1.2; // Multiplier for BOS strength calculation
input double CHoCHStrengthThreshold = 0.7; // Minimum strength for valid CHoCH
input bool UseBOSForEntries = true;   // Use BOS for trade entries
input bool UseCHoCHForEntries = true; // Use CHoCH for trade entries
input bool UseBOSForExits = true;     // Use BOS for early exits
input bool UseCHoCHForExits = true;   // Use CHoCH for early exits

// Performance Tracking
input bool DisplayDebugInfo = true;    // Display debug info in comments
input bool LogPerformanceStats = true; // Log detailed performance statistics

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
int regimeWins[];
int regimeLosses[];
double regimeProfit[];
double regimeAccuracy[];
double predictionResults[];
int predictionCount = 0;

// SMC Structures
struct LiquidityGrab { datetime time; double high; double low; bool bullish; bool active; double strength; };
struct FairValueGap { datetime startTime; datetime endTime; double high; double low; bool bullish; bool active; };
struct OrderBlock { datetime blockTime; double priceLevel; double highPrice; double lowPrice; bool bullish; bool valid; int strength; bool hasLiquidityGrab; bool hasSDConfirm; bool hasImbalance; bool hasFVG; };
struct SwingPoint {
    int barIndex;
    double price;
    int score;
    datetime time;
    bool high; // true if high swing point, false if low swing point
};

// Break of Structure structure
struct BOSEvent {
    datetime time;
    double price;
    bool bullish; // true for bullish BOS (break of lows), false for bearish BOS (break of highs)
    double strength; // Strength of the break (1.0 = normal, >1.0 = strong)
    bool active; // Whether this BOS is still active/valid
    bool confirmed; // Whether the BOS has been confirmed by a retest
};

// Change of Character structure
struct CHoCHEvent {
    datetime time;
    double price;
    bool bullish; // true for bullish CHoCH (higher low), false for bearish CHoCH (lower high)
    double strength; // Strength of the change (0-2.0)
    double prevSwing; // Price level of the previous swing that was changed
    bool active; // Whether this CHoCH is still active/valid
};

LiquidityGrab recentGrabs[MAX_GRABS];
FairValueGap recentFVGs[MAX_FVGS];
OrderBlock recentBlocks[MAX_BLOCKS];
BOSEvent bosEvents[MAX_BOS];
CHoCHEvent chochEvents[MAX_CHOCH];

int grabIndex = 0, fvgIndex = 0, blockIndex = 0, bosCount = 0, chochCount = 0;
double FVGMinSize = 0.5;
int LookbackBars = 100;
bool UseLiquidityGrab = true, UseImbalanceFVG = true, UseBOS = true, UseCHoCH = true;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize trade object
    trade.SetDeviationInPoints(10);
    // Initialize arrays
    ArrayResize(atrBuffer, 100);
    ArrayResize(maBuffer, 100);
    ArrayResize(volBuffer, 100);
    // Initialize regime arrays
    ArrayResize(regimeWins, REGIME_COUNT);
    ArrayResize(regimeLosses, REGIME_COUNT);
    ArrayResize(regimeProfit, REGIME_COUNT);
    ArrayResize(regimeAccuracy, REGIME_COUNT);
    // Initialize performance arrays
    ArrayResize(tradeProfits, METRIC_WINDOW);
    ArrayResize(tradeReturns, METRIC_WINDOW);
    ArrayResize(predictionResults, ACCURACY_WINDOW);
    // Reset and initialize values
    for(int i=0; i<REGIME_COUNT; i++) {
        regimeWins[i] = 0;
        regimeLosses[i] = 0;
        regimeProfit[i] = 0.0;
        regimeAccuracy[i] = 0.0;
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
    Print("[Init] SMC Scalper Hybrid V1 initialized successfully");
    return INIT_SUCCEEDED;

    // Initialize trade object
    trade.SetDeviationInPoints(10);

    // Initialize arrays
    ArrayResize(atrBuffer, 100);
    ArrayResize(maBuffer, 100);
    ArrayResize(volBuffer, 100);
    
    // Initialize regime arrays
    ArrayResize(regimeWins, REGIME_COUNT);
    ArrayResize(regimeLosses, REGIME_COUNT);
    ArrayResize(regimeProfit, REGIME_COUNT);
    ArrayResize(regimeAccuracy, REGIME_COUNT);
    
    // Initialize performance arrays
    ArrayResize(tradeProfits, METRIC_WINDOW);
    ArrayResize(tradeReturns, METRIC_WINDOW);
    ArrayResize(predictionResults, ACCURACY_WINDOW);
    
    // Reset and initialize values
    for(int i=0; i<REGIME_COUNT; i++) {
        regimeWins[i] = 0;
        regimeLosses[i] = 0;
        regimeProfit[i] = 0.0;
        regimeAccuracy[i] = 0.0;
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
        Print("[Deinit] SMC Scalper Hybrid V1 terminated. Reason: ", reason);
        Print("[Deinit] Total profit: ", totalProfit);
        Print("[Deinit] Win rate: ", winRate);
        Print("[Deinit] Total trades: ", totalWins + totalLosses);
    }
}



//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
    // Step 1: Run detection and analysis
    DetectLiquidityGrabs();
    DetectFairValueGaps();
    DetectOrderBlocks();
    ValidateSupplyDemandZones();
    
    // Step 1b: Run advanced SMC structure detection
    if(EnableBOS) DetectBreakOfStructure();
    if(EnableCHoCH && bosCount > 0) DetectChangeOfCharacter();
    
    // Step 2: Detect current market regime
    if(EnableMarketRegimeFiltering) {
        currentRegime = FastRegimeDetection(Symbol());
    }
    
    // Step 3: Get trading signal
    int signal = GetTradingSignal();
    
    // Step 4: Check if we should execute a trade
    bool cooldownPassed = (TimeCurrent() - lastSignalTime) >= SignalCooldownSeconds;
    if(signal != 0 && cooldownPassed && !emergencyMode && CanTrade()) {
        if(EnableFastExecution) {
            ExecuteTradeOptimized(signal);
        } else {
            ExecuteTrade(signal);
        }
        
        if(signal != 0) {
            lastSignalTime = TimeCurrent();
        }
    }
    
    // Step 5: Manage open positions
    if(EnableAggressiveTrailing) {
        ManageTrailingStops();
    }
    
    // Step 6: Visualize SMC structures on chart
    VisualizeBosChoch();
    
    // Step 7: Display debug information if enabled
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
                // Update accuracy
                int totalTrades = regimeWins[currentRegime] + regimeLosses[currentRegime];
                if(totalTrades > 0) {
                    regimeAccuracy[currentRegime] = (double)regimeWins[currentRegime] / totalTrades;
                }
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
    double bbUpper = GetBands(symbol, PERIOD_M5, 20, 2.0, 0, PRICE_CLOSE, 1, 0);
    double bbLower = GetBands(symbol, PERIOD_M5, 20, 2.0, 0, PRICE_CLOSE, 2, 0);
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
   int lookback = MathMin(LookbackBars, Bars(Symbol(), PERIOD_CURRENT));
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
         sum += src[i+j];
         count++;
      }
      dst[i] = (count>0) ? sum/count : 0;
   }
}

//+------------------------------------------------------------------+
//| Detect order blocks (from original SMC EA with enhancements)     |
//+------------------------------------------------------------------+
void DetectOrderBlocks() {
   int lookback = MathMin(LookbackBars, Bars(Symbol(), PERIOD_CURRENT));
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
         recentBlocks[blockIndex].blockTime = time[i];
         recentBlocks[blockIndex].priceLevel = swingHigh ? high[i] : low[i];
         recentBlocks[blockIndex].highPrice = high[i];
         recentBlocks[blockIndex].lowPrice = low[i];
         recentBlocks[blockIndex].bullish = swingLow;
         recentBlocks[blockIndex].valid = true;
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
         blockIndex = (blockIndex + 1) % MAX_BLOCKS;
      }
   }
}

//+------------------------------------------------------------------+
//| DetectBreakOfStructure - Detect significant structure breaks     |
//+------------------------------------------------------------------+
void DetectBreakOfStructure() {
   if(!EnableBOS) return;
   
   // Clear previous BOS events
   bosCount = 0;
   
   int lookback = MathMin(LookbackBars, Bars(Symbol(), PERIOD_CURRENT));
   double high[], low[], close[];
   datetime time[];
   
   // Copy price data
   if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback, high) != lookback) return;
   if(CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback, low) != lookback) return;
   if(CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback, close) != lookback) return;
   if(CopyTime(Symbol(), PERIOD_CURRENT, 0, lookback, time) != lookback) return;
   
   // Arrays to store significant swing points
   double swingHighs[20];
   double swingLows[20];
   datetime swingHighTimes[20];
   datetime swingLowTimes[20];
   int swingHighCount = 0, swingLowCount = 0;
   
   // First identify significant swing points
   for(int i = 2; i < lookback - 2 && swingHighCount < 20 && swingLowCount < 20; i++) {
      // Swing high
      if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i+1] && high[i] > high[i+2]) {
         swingHighs[swingHighCount] = high[i];
         swingHighTimes[swingHighCount] = time[i];
         swingHighCount++;
      }
      
      // Swing low
      if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i+1] && low[i] < low[i+2]) {
         swingLows[swingLowCount] = low[i];
         swingLowTimes[swingLowCount] = time[i];
         swingLowCount++;
      }
   }
   
   // Get ATR value for measuring break strength
   double atr = 0;
   int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
   if(atrHandle != INVALID_HANDLE) {
      double atrBuffer[];
      if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
         atr = atrBuffer[0];
      }
      IndicatorRelease(atrHandle);
   }
   
   // Look for breaks of swing highs (bearish BOS)
   for(int i = 0; i < swingHighCount && bosCount < MAX_BOS; i++) {
      double swingHigh = swingHighs[i];
      datetime swingTime = swingHighTimes[i];
      
      // Look for a break of this swing high
      for(int j = 0; j < lookback; j++) {
         // Skip candles before the swing point
         if(time[j] <= swingTime) continue;
         
         // Check if we have a break of structure (price closes above swing high)
         if(close[j] > swingHigh) {
            // Calculate strength of the break
            double breakStrength = (close[j] - swingHigh) / atr;
            breakStrength = MathMin(breakStrength * BOSStrengthMultiplier, 3.0); // Cap at 3.0
            
            // Add to BOS events
            bosEvents[bosCount].time = time[j];
            bosEvents[bosCount].price = close[j];
            bosEvents[bosCount].bullish = false;
            bosEvents[bosCount].strength = breakStrength;
            bosEvents[bosCount].active = true;
            bosEvents[bosCount].confirmed = false;
            
            // Check if this break has been retested/confirmed
            for(int k = j-1; k >= 0; k--) {
               if(low[k] <= swingHigh && low[k] >= swingHigh - atr*0.5) {
                  bosEvents[bosCount].confirmed = true;
                  break;
               }
            }
            
            bosCount++;
            break; // Move to the next swing high
         }
      }
   }
   
   // Look for breaks of swing lows (bullish BOS)
   for(int i = 0; i < swingLowCount && bosCount < MAX_BOS; i++) {
      double swingLow = swingLows[i];
      datetime swingTime = swingLowTimes[i];
      
      // Look for a break of this swing low
      for(int j = 0; j < lookback; j++) {
         // Skip candles before the swing point
         if(time[j] <= swingTime) continue;
         
         // Check if we have a break of structure (price closes below swing low)
         if(close[j] < swingLow) {
            // Calculate strength of the break
            double breakStrength = (swingLow - close[j]) / atr;
            breakStrength = MathMin(breakStrength * BOSStrengthMultiplier, 3.0); // Cap at 3.0
            
            // Add to BOS events
            bosEvents[bosCount].time = time[j];
            bosEvents[bosCount].price = close[j];
            bosEvents[bosCount].bullish = true;
            bosEvents[bosCount].strength = breakStrength;
            bosEvents[bosCount].active = true;
            bosEvents[bosCount].confirmed = false;
            
            // Check if this break has been retested/confirmed
            for(int k = j-1; k >= 0; k--) {
               if(high[k] >= swingLow && high[k] <= swingLow + atr*0.5) {
                  bosEvents[bosCount].confirmed = true;
                  break;
               }
            }
            
            bosCount++;
            break; // Move to the next swing low
         }
      }
   }
   
   if(DisplayDebugInfo) {
      Print("Detected ", bosCount, " Break of Structure events");
   }
}

//+------------------------------------------------------------------+
//| DetectChangeOfCharacter - Identify changes in market character   |
//+------------------------------------------------------------------+
void DetectChangeOfCharacter() {
   if(!EnableCHoCH || bosCount < 2) return; // Need BOS events first
   
   // Clear previous CHoCH events
   chochCount = 0;
   
   // Get price data
   int lookback = MathMin(LookbackBars, Bars(Symbol(), PERIOD_CURRENT));
   double high[], low[], close[];
   datetime time[];
   
   // Copy price data
   if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback, high) != lookback) return;
   if(CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback, low) != lookback) return;
   if(CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback, close) != lookback) return;
   if(CopyTime(Symbol(), PERIOD_CURRENT, 0, lookback, time) != lookback) return;
   
   // Get ATR value for measuring change strength
   double atr = 0;
   int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
   if(atrHandle != INVALID_HANDLE) {
      double atrBuffer[];
      if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
         atr = atrBuffer[0];
      }
      IndicatorRelease(atrHandle);
   }
   
   // Process BOS events to find CHoCH
   for(int i = 0; i < bosCount && chochCount < MAX_CHOCH; i++) {
      if(!bosEvents[i].active) continue;
      
      // Look for bullish CHoCH (higher low after a bullish BOS)
      if(bosEvents[i].bullish) {
         double bosPrice = bosEvents[i].price;
         datetime bosTime = bosEvents[i].time;
         
         // Find the lowest low after this BOS
         double lowestLow = 999999;
         datetime lowestLowTime = 0;
         int lowestIdx = -1;
         
         for(int j = 0; j < lookback; j++) {
            if(time[j] <= bosTime) continue; // Skip candles before BOS
            
            if(low[j] < lowestLow) {
               lowestLow = low[j];
               lowestLowTime = time[j];
               lowestIdx = j;
            }
         }
         
         // If we found a lowest low that's higher than the BOS price, we have a CHoCH
         if(lowestIdx >= 0 && lowestLow > bosPrice) {
            // Calculate strength of CHoCH (1.0 = strong, 0.0 = weak)
            double changeStrength = (lowestLow - bosPrice) / atr;
            changeStrength = MathMin(changeStrength, 2.0); // Cap at 2.0
            
            // Only record significant CHoCH events
            if(changeStrength >= CHoCHStrengthThreshold) {
               chochEvents[chochCount].time = lowestLowTime;
               chochEvents[chochCount].price = lowestLow;
               chochEvents[chochCount].bullish = true;
               chochEvents[chochCount].strength = changeStrength;
               chochEvents[chochCount].prevSwing = bosPrice;
               chochEvents[chochCount].active = true;
               
               chochCount++;
            }
         }
      }
      // Look for bearish CHoCH (lower high after a bearish BOS)
      else {
         double bosPrice = bosEvents[i].price;
         datetime bosTime = bosEvents[i].time;
         
         // Find the highest high after this BOS
         double highestHigh = -999999;
         datetime highestHighTime = 0;
         int highestIdx = -1;
         
         for(int j = 0; j < lookback; j++) {
            if(time[j] <= bosTime) continue; // Skip candles before BOS
            
            if(high[j] > highestHigh) {
               highestHigh = high[j];
               highestHighTime = time[j];
               highestIdx = j;
            }
         }
         
         // If we found a highest high that's lower than the BOS price, we have a CHoCH
         if(highestIdx >= 0 && highestHigh < bosPrice) {
            // Calculate strength of CHoCH (1.0 = strong, 0.0 = weak)
            double changeStrength = (bosPrice - highestHigh) / atr;
            changeStrength = MathMin(changeStrength, 2.0); // Cap at 2.0
            
            // Only record significant CHoCH events
            if(changeStrength >= CHoCHStrengthThreshold) {
               chochEvents[chochCount].time = highestHighTime;
               chochEvents[chochCount].price = highestHigh;
               chochEvents[chochCount].bullish = false;
               chochEvents[chochCount].strength = changeStrength;
               chochEvents[chochCount].prevSwing = bosPrice;
               chochEvents[chochCount].active = true;
               
               chochCount++;
            }
         }
      }
   }
   
   if(DisplayDebugInfo) {
      Print("Detected ", chochCount, " Change of Character events");
   }
}

//+------------------------------------------------------------------+
//| Validate supply and demand zones                                |
//+------------------------------------------------------------------+
void ValidateSupplyDemandZones() {
   double low[], high[];
   CopyLow(Symbol(), PERIOD_CURRENT, 0, 1, low);
   CopyHigh(Symbol(), PERIOD_CURRENT, 0, 1, high);
   for(int i = 0; i < MAX_BLOCKS; i++) {
      if(!recentBlocks[i].valid) continue;
      if(recentBlocks[i].bullish) {
         if(low[0] > recentBlocks[i].lowPrice) recentBlocks[i].hasSDConfirm = true;
      } else {
         if(high[0] < recentBlocks[i].highPrice) recentBlocks[i].hasSDConfirm = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Get trading signal with regime-based filtering                   |
//+------------------------------------------------------------------+
int GetTradingSignal() {
   // Check for emergency mode or too many consecutive losses
   if(emergencyMode || consecutiveLosses >= MaxConsecutiveLosses) {
      Print("[SMC] GetTradingSignal: Too many consecutive losses (", consecutiveLosses, ") or emergency mode. No signal.");
      return 0;
   }
   
   // Add time filter - only trade if enough time has passed since last trade
   if(TimeCurrent() - lastSignalTime < SignalCooldownSeconds) {
      if(DisplayDebugInfo) {
         Print("[SMC] GetTradingSignal: Cooldown period active. Seconds remaining: ", 
               SignalCooldownSeconds - (TimeCurrent() - lastSignalTime));
      }
      return 0;
   }
   
   // Variables to track best trading opportunities
   int bestBlock = -1;
   int bestScore = 0;
   int bestBOSIndex = -1;
   double bestBOSStrength = 0;
   int bestCHoCHIndex = -1;
   double bestCHoCHStrength = 0;
   int signalSource = 0; // 0=none, 1=orderblock, 2=BOS, 3=CHoCH
   
   // 1. Find the best order block
   for(int i = 0; i < MAX_BLOCKS; i++) {
      if(recentBlocks[i].valid && recentBlocks[i].strength >= MinBlockStrength) { 
         if(recentBlocks[i].strength > bestScore || bestBlock == -1) {
            bestScore = recentBlocks[i].strength;
            bestBlock = i;
         }
      }
   }
   
   // 2. Find the best BOS event, if enabled
   if(EnableBOS && UseBOSForEntries) {
      for(int i = 0; i < bosCount; i++) {
         if(bosEvents[i].active && bosEvents[i].confirmed) {
            // Check if it's recent enough (within 8 candles)
            if(TimeCurrent() - bosEvents[i].time < 8 * PeriodSeconds(PERIOD_CURRENT)) {
               if(bosEvents[i].strength > bestBOSStrength) {
                  bestBOSStrength = bosEvents[i].strength;
                  bestBOSIndex = i;
               }
            }
         }
      }
   }
   
   // 3. Find the best CHoCH event, if enabled
   if(EnableCHoCH && UseCHoCHForEntries) {
      for(int i = 0; i < chochCount; i++) {
         if(chochEvents[i].active) {
            // Check if it's recent enough (within 5 candles)
            if(TimeCurrent() - chochEvents[i].time < 5 * PeriodSeconds(PERIOD_CURRENT)) {
               if(chochEvents[i].strength > bestCHoCHStrength) {
                  bestCHoCHStrength = chochEvents[i].strength;
                  bestCHoCHIndex = i;
               }
            }
         }
      }
   }
   
   // Determine if we have a valid signal source and which one to use
   bool hasOrderBlock = (bestBlock != -1);
   bool hasBOS = (bestBOSIndex != -1 && bestBOSStrength >= 1.0);
   bool hasCHoCH = (bestCHoCHIndex != -1 && bestCHoCHStrength >= CHoCHStrengthThreshold);
   
   // If we don't have any valid signal source, exit early
   if(!hasOrderBlock && !hasBOS && !hasCHoCH) {
      if(DisplayDebugInfo) Print("[SMC] No valid SMC structures found. No signal.");
      return 0;
   }
   
   // Determine the best signal source - prioritize higher strength signals
   // Scale the scores to be comparable
   double orderBlockScore = hasOrderBlock ? (double)bestScore / 3.0 : 0;
   
   if(hasBOS && bestBOSStrength > orderBlockScore && bestBOSStrength > bestCHoCHStrength) {
      signalSource = 2; // BOS is best signal
   }
   else if(hasCHoCH && bestCHoCHStrength > orderBlockScore && bestCHoCHStrength > bestBOSStrength * 0.8) {
      signalSource = 3; // CHoCH is best signal
   }
   else if(hasOrderBlock) {
      signalSource = 1; // Order block is best signal
   }
   else {
      if(DisplayDebugInfo) Print("[SMC] No dominant signal source found. No signal.");
      return 0;
   }
   
   // Prepare a description of the signal for debugging
   string signalDesc = "";
   bool signalBullish = false;
   
   // Determine signal direction based on the source
   switch(signalSource) {
      case 1: // Order Block
         signalBullish = recentBlocks[bestBlock].bullish;
         signalDesc = "OrderBlock(" + IntegerToString(bestScore) + ")";
         break;
      case 2: // BOS
         signalBullish = bosEvents[bestBOSIndex].bullish;
         signalDesc = "BOS(" + DoubleToString(bestBOSStrength, 1) + ")";
         break;
      case 3: // CHoCH
         signalBullish = chochEvents[bestCHoCHIndex].bullish;
         signalDesc = "CHoCH(" + DoubleToString(bestCHoCHStrength, 1) + ")";
         break;
   }
   
   // If market regime filtering is enabled, apply regime-specific filters
   if(EnableMarketRegimeFiltering && currentRegime >= 0) {
      double signalStrength = 0;
      
      // Convert the signal strength to a comparable scale
      switch(signalSource) {
         case 1: signalStrength = (double)bestScore / 3.0; break;
         case 2: signalStrength = bestBOSStrength; break;
         case 3: signalStrength = bestCHoCHStrength; break;
      }
      
      // In choppy markets, require stronger confirmation
      if(currentRegime == CHOPPY && signalStrength < 1.5) {
         if(DisplayDebugInfo) Print("[SMC] Regime CHOPPY requires stronger signal. No signal.");
         return 0;
      }
      
      // In high volatility, be more selective
      if(currentRegime == HIGH_VOLATILITY && signalStrength < 1.7) {
         if(DisplayDebugInfo) Print("[SMC] Regime HIGH_VOLATILITY requires stronger signal. No signal.");
         return 0;
      }
      
      // In breakout regimes, prefer to trade in breakout direction
      if(currentRegime == BREAKOUT) {
         // Get short-term trend
         double ma5 = 0, ma20 = 0;
         for(int i=0; i<5; i++) ma5 += iClose(Symbol(), PERIOD_M5, i);
         for(int i=0; i<20; i++) ma20 += iClose(Symbol(), PERIOD_M5, i);
         ma5 /= 5;
         ma20 /= 20;
         
         bool shortTermUp = ma5 > ma20;
         
         // Only allow trades in breakout direction
         if((shortTermUp && !signalBullish) || (!shortTermUp && signalBullish)) {
            // Counter-breakout trades need very high strength
            if(signalStrength < 2.0) {
               if(DisplayDebugInfo) Print("[SMC] Breakout regime - trade direction doesn't match breakout direction. No signal.");
               return 0;
            }
         }
      }
      
      // In trending regimes, prefer to trade in trend direction
      if((currentRegime == TRENDING_UP && !signalBullish) || 
         (currentRegime == TRENDING_DOWN && signalBullish)) {
         // We can still trade counter-trend, but require stronger confirmation
         if(signalStrength < 1.8) {
            if(DisplayDebugInfo) Print("[SMC] Counter-trend trade requires stronger signal. No signal.");
            return 0;
         }
      }
   }
   
   // Skip trend confirmation if not required
   if(!RequireTrendConfirmation) {
      if(signalBullish) {
         if(DisplayDebugInfo) Print("[SMC] Buy signal generated from ", signalDesc);
         return 1;
      } else {
         if(DisplayDebugInfo) Print("[SMC] Sell signal generated from ", signalDesc);
         return -1;
      }
   }
   
   // Traditional trend confirmation using moving averages
   int fastHandle = iMA(Symbol(), AnalysisTimeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
   int slowHandle = iMA(Symbol(), AnalysisTimeframe, 200, 0, MODE_SMA, PRICE_CLOSE);
   double fastMA[], slowMA[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);
   CopyBuffer(fastHandle, 0, 0, 1, fastMA);
   CopyBuffer(slowHandle, 0, 0, 1, slowMA);
   bool trendUp = fastMA[0] > slowMA[0];
   bool trendDown = fastMA[0] < slowMA[0];
   
   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
   
   if(signalBullish && trendUp) {
      if(DisplayDebugInfo) Print("[SMC] Buy signal generated from ", signalDesc, " with trend confirmation");
      return 1;
   }
   if(!signalBullish && trendDown) {
      if(DisplayDebugInfo) Print("[SMC] Sell signal generated from ", signalDesc, " with trend confirmation");
      return -1;
   }
   
   if(DisplayDebugInfo) Print("[SMC] No matching trend confirmation for ", signalDesc, ". No signal.");
   return 0;
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                     |
//+------------------------------------------------------------------+
bool CanTrade() {
   if(emergencyMode) { 
      if(DisplayDebugInfo) Print("[SMC] CanTrade: Emergency mode active"); 
      return false; 
   }
   if(marketClosed || isWeekend) { 
      if(DisplayDebugInfo) Print("[SMC] CanTrade: Market closed or weekend"); 
      return false; 
   }
   
   MqlDateTime timeNow; 
   TimeCurrent(timeNow);
   
   if(timeNow.hour < TradingStartHour || timeNow.hour >= TradingEndHour) { 
      if(DisplayDebugInfo) Print("[SMC] CanTrade: Outside trading hours"); 
      return false; 
   }
   
   if(PositionsTotal() >= MaxTrades) { 
      if(DisplayDebugInfo) Print("[SMC] CanTrade: Max positions reached"); 
      return false; 
   }
   
   if(EnableNewsFilter && IsHighImpactNewsTime()) { 
      if(DisplayDebugInfo) Print("[SMC] CanTrade: News filter active"); 
      return false; 
   }
   
   if(TimeCurrent() - lastTradeTime < 30) { // Reduced from 60 seconds to 30 seconds
      if(DisplayDebugInfo) Print("[SMC] CanTrade: Trade cooldown period"); 
      return false; 
   }
   
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   if(freeMargin < margin * 0.5) { // Reduced from 0.8 to 0.5
      if(DisplayDebugInfo) Print("[SMC] CanTrade: Low margin level"); 
      return false; 
   }
   
   if(DisplayDebugInfo) Print("[SMC] CanTrade: All checks passed");
   return true;
}

//+------------------------------------------------------------------+
//| Dummy news filter function                                       |
//+------------------------------------------------------------------+
bool IsHighImpactNewsTime() { 
   return false; // Placeholder - implement news filter if needed
}

//+------------------------------------------------------------------+
//| Visualize BOS and CHoCH on chart                                |
//+------------------------------------------------------------------+
void VisualizeBosChoch() {
   // Clear previous visuals
   ObjectsDeleteAll(0, "SMC_BOS_");
   ObjectsDeleteAll(0, "SMC_CHOCH_");
   
   // Set maximum lookback time (don't show events older than this)
   datetime cutoffTime = TimeCurrent() - (14 * 24 * 60 * 60); // 14 days
   
   // Visualize BOS events
   if(EnableBOS) {
      for(int i=0; i<bosCount; i++) {
         if(!bosEvents[i].active) continue;
         if(bosEvents[i].time < cutoffTime) continue;
         
         string bosName = "SMC_BOS_" + IntegerToString(i);
         string bosLabelName = "SMC_BOS_LABEL_" + IntegerToString(i);
         color bosColor = bosEvents[i].bullish ? clrGreen : clrRed;
         
         // Draw arrow for BOS event
         ObjectCreate(0, bosName, OBJ_ARROW, 0, bosEvents[i].time, bosEvents[i].price);
         ObjectSetInteger(0, bosName, OBJPROP_ARROWCODE, bosEvents[i].bullish ? 233 : 234); // 233=up, 234=down
         ObjectSetInteger(0, bosName, OBJPROP_COLOR, bosColor);
         ObjectSetInteger(0, bosName, OBJPROP_WIDTH, bosEvents[i].confirmed ? 3 : 2);
         ObjectSetInteger(0, bosName, OBJPROP_BACK, false);
         
         // Add label with BOS strength
         ObjectCreate(0, bosLabelName, OBJ_TEXT, 0, bosEvents[i].time, 
                      bosEvents[i].price + (bosEvents[i].bullish ? 15 : -15) * _Point);
         ObjectSetString(0, bosLabelName, OBJPROP_TEXT, "BOS" + (bosEvents[i].confirmed ? "*" : "") + 
                         " " + DoubleToString(bosEvents[i].strength, 1));
         ObjectSetInteger(0, bosLabelName, OBJPROP_COLOR, bosColor);
         ObjectSetInteger(0, bosLabelName, OBJPROP_FONTSIZE, 8);
      }
   }
   
   // Visualize CHoCH events
   if(EnableCHoCH) {
      for(int i=0; i<chochCount; i++) {
         if(!chochEvents[i].active) continue;
         if(chochEvents[i].time < cutoffTime) continue;
         
         string chochName = "SMC_CHOCH_" + IntegerToString(i);
         string chochLabelName = "SMC_CHOCH_LABEL_" + IntegerToString(i);
         string chochLineName = "SMC_CHOCH_LINE_" + IntegerToString(i);
         color chochColor = chochEvents[i].bullish ? clrGreen : clrRed;
         
         // Draw symbol for CHoCH event
         ObjectCreate(0, chochName, OBJ_ARROW, 0, chochEvents[i].time, chochEvents[i].price);
         ObjectSetInteger(0, chochName, OBJPROP_ARROWCODE, 159); // 159=diamond shape
         ObjectSetInteger(0, chochName, OBJPROP_COLOR, chochColor);
         ObjectSetInteger(0, chochName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, chochName, OBJPROP_BACK, false);
         
         // Draw line connecting to previous price
         ObjectCreate(0, chochLineName, OBJ_TREND, 0, 
                     chochEvents[i].time, chochEvents[i].price,
                     chochEvents[i].time - 8 * PeriodSeconds(PERIOD_CURRENT), chochEvents[i].prevSwing);
         ObjectSetInteger(0, chochLineName, OBJPROP_COLOR, chochColor);
         ObjectSetInteger(0, chochLineName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, chochLineName, OBJPROP_RAY_RIGHT, false);
         
         // Add label with CHoCH strength
         ObjectCreate(0, chochLabelName, OBJ_TEXT, 0, chochEvents[i].time, 
                      chochEvents[i].price + (chochEvents[i].bullish ? 20 : -20) * _Point);
         ObjectSetString(0, chochLabelName, OBJPROP_TEXT, "CHoCH " + DoubleToString(chochEvents[i].strength, 1));
         ObjectSetInteger(0, chochLabelName, OBJPROP_COLOR, chochColor);
         ObjectSetInteger(0, chochLabelName, OBJPROP_FONTSIZE, 8);
      }
   }
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
    
    // Get current price for buy/sell
    double currentPrice = (signal > 0) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
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
    
    // Execute trade
    bool result = false;
    trade.SetDeviationInPoints(10);
    
    if(signal > 0) {
        result = trade.Buy(positionSizeInLots, Symbol(), 0, slPrice, tpPrice, "SMC Buy");
    } else {
        result = trade.Sell(positionSizeInLots, Symbol(), 0, slPrice, tpPrice, "SMC Sell");
    }
    
    if(result) {
        if(DisplayDebugInfo) Print("[SMC] ExecuteTrade: Order placed successfully");
        lastTradeTime = TimeCurrent();
    } else {
        int errorCode = GetLastError();
        Print("[SMC] ExecuteTrade: Order failed! Error: ", errorCode, " - ", ErrorDescription(errorCode));
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Detect multiple swing points and return quality scores           |
//+------------------------------------------------------------------+
void FindQualitySwingPoints(bool isBuy, int lookbackBars, SwingPoint &swingPoints[], int &count) {
    count = 0;
    double high[], low[], close[], open[], volume[];
    long vol[];
    datetime time[];
    
    int bars = MathMin(lookbackBars, Bars(Symbol(), PERIOD_CURRENT) - 5);
    
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
//| Execute trade with advanced stop loss                           |
//+------------------------------------------------------------------+
bool ExecuteTradeOptimized(int signal) {
    if(!CanTrade()) return false;
    
    // Calculate optimal position size using adaptive risk
    double positionSizeInLots;
    double currentPrice = 0;
    
    if(signal > 0) { // Buy
        currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    } else { // Sell
        currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    }
    
    // Get optimal stop loss using our advanced algorithm
    double slPrice = DetermineOptimalStopLoss(signal, currentPrice);
    
    // Safety check - ensure minimum stop distance
    double minStopDistance = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    if(MathAbs(currentPrice - slPrice) < minStopDistance) {
        if(signal > 0) { // Buy
            slPrice = currentPrice - minStopDistance - (5 * _Point);
        } else { // Sell
            slPrice = currentPrice + minStopDistance + (5 * _Point);
        }
    }
    
    // Calculate adaptive take profit
    double tpPrice = CalculateDynamicTakeProfit(signal, currentPrice, slPrice);
    
    // Calculate position size based on risk
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
    double priceDistance = MathAbs(currentPrice - slPrice);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue * _Point / tickSize;
    double pipRisk = priceDistance / _Point;
    
    if(EnableAdaptiveRisk && currentRegime >= 0) {
        // Adjust risk based on market regime and win streak
        double riskMultiplier = 1.0;
        
        // Increase risk slightly in high-win regimes
        int totalRegimeTrades = regimeWins[currentRegime] + regimeLosses[currentRegime];
        if(totalRegimeTrades > 5 && regimeWins[currentRegime] / (double)totalRegimeTrades > 0.65) {
            riskMultiplier *= 1.1;
        }
        
        // Increase risk slightly during win streaks
        if(winStreak >= 2) {
            riskMultiplier *= 1.0 + (MathMin(winStreak, 5) * 0.05);
        }
        
        // Decrease risk during loss streaks
        if(lossStreak >= 1) {
            riskMultiplier *= 1.0 - (MathMin(lossStreak, 3) * 0.15);
        }
        
        riskAmount *= riskMultiplier;
    }
    
    if(pointValue > 0 && pipRisk > 0) {
        positionSizeInLots = NormalizeDouble(riskAmount / (pipRisk * pointValue), 2);
    } else {
        positionSizeInLots = 0.01; // Fallback minimum
    }
    
    // Safety checks
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double stepLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    positionSizeInLots = MathMax(minLot, MathMin(maxLot, positionSizeInLots));
    positionSizeInLots = NormalizeDouble(positionSizeInLots / stepLot, 0) * stepLot;
    
    if(positionSizeInLots <= 0) {
        Print("[SMC] Invalid position size calculated");
        return false;
    }
    
    if(DisplayDebugInfo) {
        Print("[SMC] ExecuteTradeOptimized: Signal=", signal, ", Price=", currentPrice, 
              ", SL=", slPrice, ", TP=", tpPrice, ", Size=", positionSizeInLots);
    }
    
    // Execute the trade
    bool result = false;
    if(signal > 0) { // Buy
        result = trade.Buy(positionSizeInLots, Symbol(), 0, slPrice, tpPrice, "SMC Buy");
    } else { // Sell
        result = trade.Sell(positionSizeInLots, Symbol(), 0, slPrice, tpPrice, "SMC Sell");
    }
    
    if(result) {
        if(DisplayDebugInfo) Print("[SMC] ExecuteTradeOptimized: Order placed successfully");
        lastTradeTime = TimeCurrent();
    } else {
        int errorCode = GetLastError();
        Print("[SMC] ExecuteTradeOptimized: Order placement failed with error ", errorCode);
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
//| Find recent swing points                                         |
//+------------------------------------------------------------------+
int FindRecentSwingPoint(bool isBuy, int startBar = 1, int lookbackBars = 20) {
    int swingPointBar = -1;
    double swingValue = isBuy ? 999999 : -999999;
    
    for(int i = startBar; i < lookbackBars + startBar; i++) {
        if(isBuy) { // For buy orders, find swing low
            double low = iLow(Symbol(), PERIOD_CURRENT, i);
            bool isSwingLow = true;
            
            // Check if this is a swing low (lower than both neighbors)
            for(int j = 1; j <= 2; j++) {
                if(i+j < Bars(Symbol(), PERIOD_CURRENT) && iLow(Symbol(), PERIOD_CURRENT, i+j) <= low) {
                    isSwingLow = false;
                    break;
                }
                if(i-j >= 0 && iLow(Symbol(), PERIOD_CURRENT, i-j) <= low) {
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
            
            // Check if this is a swing high (higher than both neighbors)
            for(int j = 1; j <= 2; j++) {
                if(i+j < Bars(Symbol(), PERIOD_CURRENT) && iHigh(Symbol(), PERIOD_CURRENT, i+j) >= high) {
                    isSwingHigh = false;
                    break;
                }
                if(i-j >= 0 && iHigh(Symbol(), PERIOD_CURRENT, i-j) >= high) {
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
//| Manage trailing stops and dynamic exits                         |
//+------------------------------------------------------------------+
void ManageTrailingStops() {
    if(!EnableAggressiveTrailing) return;
    
    for(int i=0; i<PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(!PositionSelectByTicket(ticket)) continue;
        
        // Skip positions that don't belong to our EA
        string posComment = PositionGetString(POSITION_COMMENT);
        if(posComment != "SMC Buy" && posComment != "SMC Sell") continue;
        
        // Get position details
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        double posVolume = PositionGetDouble(POSITION_VOLUME);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        // Calculate profit in pips
        double pointSize = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        double pips = (currentPrice - openPrice) / pointSize;
        if(posType == POSITION_TYPE_SELL) pips = -pips;
        
        // Check for opposing BOS and CHoCH events first (if enabled)
        bool earlyExit = false;
        string exitReason = "";
        
        // Early exit based on BOS events
        if(EnableBOS && UseBOSForExits) {
            for(int j=0; j<bosCount; j++) {
                if(!bosEvents[j].active || !bosEvents[j].confirmed) continue;
                
                // Only consider recent BOS events (within last 5 bars)
                if(TimeCurrent() - bosEvents[j].time <= 5 * PeriodSeconds(PERIOD_CURRENT)) {
                    // If position is buy and we see bearish BOS with good strength
                    if(posType == POSITION_TYPE_BUY && !bosEvents[j].bullish && bosEvents[j].strength >= 1.5) {
                        earlyExit = true;
                        exitReason = "Opposing bearish Break of Structure detected";
                        break;
                    }
                    // If position is sell and we see bullish BOS with good strength
                    else if(posType == POSITION_TYPE_SELL && bosEvents[j].bullish && bosEvents[j].strength >= 1.5) {
                        earlyExit = true;
                        exitReason = "Opposing bullish Break of Structure detected";
                        break;
                    }
                }
            }
        }
        
        // Early exit based on CHoCH events
        if(!earlyExit && EnableCHoCH && UseCHoCHForExits) {
            for(int j=0; j<chochCount; j++) {
                if(!chochEvents[j].active) continue;
                
                // Only consider recent CHoCH events (within last 3 bars)
                if(TimeCurrent() - chochEvents[j].time <= 3 * PeriodSeconds(PERIOD_CURRENT)) {
                    // If position is buy and we see bearish CHoCH with good strength
                    if(posType == POSITION_TYPE_BUY && !chochEvents[j].bullish && chochEvents[j].strength >= CHoCHStrengthThreshold * 1.2) {
                        earlyExit = true;
                        exitReason = "Opposing bearish Change of Character detected";
                        break;
                    }
                    // If position is sell and we see bullish CHoCH with good strength
                    else if(posType == POSITION_TYPE_SELL && chochEvents[j].bullish && chochEvents[j].strength >= CHoCHStrengthThreshold * 1.2) {
                        earlyExit = true;
                        exitReason = "Opposing bullish Change of Character detected";
                        break;
                    }
                }
            }
        }
        
        // If early exit condition detected, close the position
        if(earlyExit && pips > 0) { // Only consider if in profit
            if(DisplayDebugInfo) Print("[SMC] Early exit: ", exitReason, " for ticket ", ticket);
            trade.PositionClose(ticket);
            continue; // Skip to next position
        }
        
        // Skip trades that are in drawdown
        if(pips <= 0) continue;
        
        // Calculate current profit percentage of target
        double targetPips = MathAbs(tp - openPrice) / pointSize;
        if(targetPips == 0) continue; // Skip if no TP set
        
        double profitPct = pips / targetPips;
        
        // Get ATR for dynamic trailing
        double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
        
        // Enhanced trailing based on ATR and market regime
        if(profitPct >= TrailingActivationPct) {
            double newSL = 0;
            double newTP = tp; // Default to current TP
            
            if(posType == POSITION_TYPE_BUY) {
                // For buy positions, calculate new trailing stop level
                newSL = currentPrice - (atr * TrailingStopMultiplier);
                
                // Only update if new stop loss is higher than current one
                if(newSL > sl && MathAbs(newSL - sl) > 10 * _Point) {
                    // If we've achieved 80% of target and we're in a trending up market, extend TP
                    if(profitPct >= 0.8 && currentRegime == TRENDING_UP) {
                        newTP = tp + (tp - openPrice) * 0.5; // Extend by 50% of original target
                    }
                    
                    if(trade.PositionModify(ticket, newSL, newTP)) {
                        if(DisplayDebugInfo) {
                            Print("[SMC] Trailing stop updated for ticket ", ticket, ": SL=", sl, " -> ", newSL, 
                                  newTP != tp ? ", TP extended" : "");
                        }
                    }
                }
            }
            else if(posType == POSITION_TYPE_SELL) {
                // For sell positions, calculate new trailing stop level
                newSL = currentPrice + (atr * TrailingStopMultiplier);
                
                // Only update if new stop loss is lower than current one
                if(newSL < sl && MathAbs(newSL - sl) > 10 * _Point) {
                    // If we've achieved 80% of target and we're in a trending down market, extend TP
                    if(profitPct >= 0.8 && currentRegime == TRENDING_DOWN) {
                        newTP = tp - (openPrice - tp) * 0.5; // Extend by 50% of original target
                    }
                    
                    if(trade.PositionModify(ticket, newSL, newTP)) {
                        if(DisplayDebugInfo) {
                            Print("[SMC] Trailing stop updated for ticket ", ticket, ": SL=", sl, " -> ", newSL,
                                  newTP != tp ? ", TP extended" : "");
                        }
                    }
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
    
    info += "Blocks: " + IntegerToString(validBlocks) + 
            " (Bullish: " + IntegerToString(bullishBlocks) + 
            ", Bearish: " + IntegerToString(bearishBlocks) + ")\n";
    
    // Add BOS and CHoCH information
    if(EnableBOS) {
        int activeBOS = 0;
        int bullishBOS = 0;
        int bearishBOS = 0;
        int confirmedBOS = 0;
        
        for(int i=0; i<bosCount; i++) {
            if(bosEvents[i].active) {
                activeBOS++;
                if(bosEvents[i].bullish) bullishBOS++;
                else bearishBOS++;
                if(bosEvents[i].confirmed) confirmedBOS++;
            }
        }
        
        info += "BOS Events: " + IntegerToString(activeBOS) + 
                " (Bullish: " + IntegerToString(bullishBOS) + 
                ", Bearish: " + IntegerToString(bearishBOS) + 
                ", Confirmed: " + IntegerToString(confirmedBOS) + ")\n";
    }
    
    if(EnableCHoCH) {
        int activeCHoCH = 0;
        int bullishCHoCH = 0;
        int bearishCHoCH = 0;
        double avgStrength = 0;
        
        for(int i=0; i<chochCount; i++) {
            if(chochEvents[i].active) {
                activeCHoCH++;
                if(chochEvents[i].bullish) bullishCHoCH++;
                else bearishCHoCH++;
                avgStrength += chochEvents[i].strength;
            }
        }
        
        if(activeCHoCH > 0) avgStrength /= activeCHoCH;
        
        info += "CHoCH Events: " + IntegerToString(activeCHoCH) + 
                " (Bullish: " + IntegerToString(bullishCHoCH) + 
                ", Bearish: " + IntegerToString(bearishCHoCH) + 
                ", Avg Strength: " + DoubleToString(avgStrength, 2) + ")\n";        
    }
    
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
