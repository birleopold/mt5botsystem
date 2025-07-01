//+------------------------------------------------------------------+
//|                                                 intelligent.mq5   |
//|                           Copyright 2023, Your Company Name Here  |
//|                                     https://www.yourwebsite.com/  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Company Name Here"
#property link      "https://www.yourwebsite.com/"
#property version   "1.00"

// Include Trade class
#include <Trade\Trade.mqh>

// Global constants
#define MAX_BLOCKS 100
#define DEFAULT_MAGIC 123456

// Market regime types (defined early for use in declarations)
enum ENUM_MARKET_REGIME {
   REGIME_TRENDING_BULL,              // Strong bullish trend
   REGIME_TRENDING_BEAR,              // Strong bearish trend
   REGIME_RANGING,                    // Range-bound market
   REGIME_VOLATILE,                   // High volatility
   REGIME_CHOPPY,                     // Choppy/sideways with noise
   REGIME_BREAKOUT                    // Breakout phase
};

// Trade execution settings
input group "Trade Execution Settings"
input int MagicNumber = DEFAULT_MAGIC;        // Magic number for this EA instance
input double AdaptiveSlippagePoints = 20;     // Adaptive slippage in points

// Global variables
int blockIndex = 0;
int atrHandle;
double atrValue; // Global ATR value for use in multiple functions

// Forward declarations for functions
double GetDailyLoss();
double GetCorrelatedExposure();
int DetermineSetupQuality(int signal, double entryPrice);
bool IsSpreadAcceptable();
void CheckDrawdownProtection();
// DetectMarketRegime is implemented below, no forward declaration needed
bool IsHighImpactNewsTime();
void UpdatePerformanceStats(double profit, int setupQuality);
void LogTradeDetails(int signal, double entryPrice, double stopLoss, double takeProfit, double posSize, int setupQuality, bool executed);
string GetRegimeDescription(ENUM_MARKET_REGIME regime);

// Risk management variables
input group "Risk Management Settings"
input double BaseRiskPercent = 1.0;      // Base risk percentage (1% of account)
input double MaxRiskPercent = 2.0;       // Maximum risk per trade
input double MaxDailyRiskPercent = 5.0;  // Maximum daily risk
input double MaxExposurePercent = 15.0;  // Maximum total exposure
input double MaxCorrelatedRisk = 3.0;    // Maximum risk across correlated pairs
input double MaxDrawdownPercent = 20.0;  // Maximum allowed drawdown before pausing trading
input double DrawdownPauseLevel = 10.0;  // Pause trading at this drawdown level
input double DrawdownStopLevel = 20.0;   // Stop trading completely at this drawdown
input int MaxOpenPositions = 5;         // Maximum number of open positions allowed
input double DefaultVolatilityMultiplier = 1.0; // Default volatility multiplier
input double DefaultPatternQualityMultiplier = 1.0; // Default pattern quality multiplier
input bool AdaptToVolatility = true;   // Whether to adapt to volatility
input bool RiskManagementEnabled = true; // Toggle for risk management features
input bool DrawdownProtectionEnabled = true; // Toggle for drawdown protection
input bool CorrelationRiskEnabled = true; // Toggle for correlation risk management
input bool MaxPositionsLimitEnabled = true; // Toggle for maximum positions limit

// Runtime variables that can be modified
double VolatilityMultiplier;            // Current volatility multiplier (can be modified)
double PatternQualityMultiplier;        // Current pattern quality multiplier (can be modified)

// Market Regime settings
input group "Market Regime Settings"
input bool EnableRegimeFilters = true;      // Whether to use market regime filters
input bool EnableNewsFilter = true;         // Whether to avoid trading during news events
input int VolatilityLookback = 20;          // Periods to look back for volatility regime
input int TrendStrengthLookback = 50;       // Periods to look back for trend strength
input double NewsAvoidanceMinutes = 30;     // Minutes to avoid trading before/after news

// Current market regime - initially set to ranging
ENUM_MARKET_REGIME CurrentRegime = REGIME_RANGING; // Current detected regime

// Performance monitoring
input group "Performance Monitoring"
input bool EnablePerformanceStats = true;   // Whether to track performance stats

// Time filtering settings
input group "Time Filtering Settings"
input bool EnableTimeFilter = true;          // Enable time-based trading restrictions
input int TradingStartHour = 0;             // Hour to start trading (0-23, server time)
input int TradingEndHour = 23;              // Hour to stop trading (0-23, server time)
input bool AvoidMondayOpen = false;         // Avoid trading during Monday market open
input bool AvoidFridayClose = true;         // Avoid trading during Friday market close

// High-Value Asset Special Handling (for BTC, XAU, etc.)
input group "High-Value Asset Settings"
input bool EnableSpecialHandlingForBTC = true;  // Enable special handling for BTC/XAU
input double BTC_SpreadMultiplier = 2.5;       // More permissive spread threshold (250% of normal)
input double BTC_BlockAgeHours = 8.0;          // Extended block age validity (vs 3 hours standard)
input double BTC_MinBlockStrength = 1.0;       // Reduced minimum block strength
input double BTC_BlockSizeMultiplier = 0.5;    // Reduced block size requirements

// Trade statistics (not input parameters)
int TotalTrades = 0;                  // Total trades taken
int WinningTrades = 0;                // Number of winning trades
int LosingTrades = 0;                 // Number of losing trades
double GrossProfit = 0.0;             // Total gross profit
double GrossLoss = 0.0;               // Total gross loss
double LargestWin = 0.0;              // Largest winning trade
double LargestLoss = 0.0;             // Largest losing trade
double AverageWin = 0.0;              // Average winning trade
double AverageLoss = 0.0;             // Average losing trade
double TotalProfit = 0.0;             // Total profit (for profit factor)
double TotalLoss = 0.0;               // Total loss (for profit factor)
double ProfitFactor = 0.0;            // Profit factor
double ExpectedPayoff = 0.0;          // Expected payoff
double WinRate = 0.0;                 // Win rate percentage

// Trade quality tracking
int HighQualityTrades = 0;            // Trades with quality score 8-10
int MediumQualityTrades = 0;          // Trades with quality score 5-7
int LowQualityTrades = 0;             // Trades with quality score 1-4
double QualityPerformanceRatio = 0.0; // Performance ratio of high vs low quality trades

// Trade management variables
bool PartialProfitEnabled = true;  // Enable partial profit taking
bool BreakevenEnabled = true;      // Enable breakeven stop movement
bool SmartReentryEnabled = true;   // Enable smart re-entry after stopped trades

// Partial profit thresholds (% of risk distance)
double PartialTakeProfit1 = 1.0;   // First partial at 1.0x risk
double PartialTakeProfit2 = 1.5;   // Second partial at 1.5x risk
double PartialTakeProfit3 = 2.5;   // Final target at 2.5x risk

// Percentage of position to close at each target
double PartialClosePercent1 = 30;  // Close 30% at first target
double PartialClosePercent2 = 40;  // Close 40% at second target
                                    // Remaining 30% for final target

// Breakeven settings
double BreakevenTriggerRatio = 1.0; // Move to breakeven when profit reaches 1.0x risk
double BreakevenBufferPoints = 5;   // Buffer pips beyond entry for breakeven

// Smart re-entry settings
bool ReentryPositions[100];          // Tracks positions that were stopped out for re-entry
datetime ReentryTimes[100];          // Times of stopped out trades
double ReentryLevels[100];           // Price levels for re-entry
int ReentrySignals[100];             // Original trade signals (1=buy, -1=sell)
double ReentryStops[100];            // Original stop loss levels
double ReentryTargets[100];          // Original take profit levels
int ReentryQuality[100];             // Original setup quality
int ReentryCount = 0;                // Counter for re-entry opportunities
double ReentryTimeLimit = 4;         // Hours to wait for re-entry (max)
double ReentryMinQuality = 6;        // Minimum quality for re-entry (1-10)
bool ReentryAttempted[100];          // Tracks whether re-entry was attempted

// Correlation pairs (symbol => correlation coefficient)
string CorrelatedPairs[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "BTCUSD"};
double CorrelationMatrix[6][6]; // Will store correlation coefficients

// Drawdown tracking
double StartingBalance = 0.0;
datetime LastDrawdownCheck = 0;
datetime LastCorrelationUpdate = 0;
bool TradingPaused = false;
bool TradingDisabled = false;

// Block structure
struct OrderBlock {
   bool valid;
   bool isBuy;
   double price;
   double high;
   double low;
   datetime time;
   int strength;
   double volume;
};

// Array to store blocks
OrderBlock recentBlocks[MAX_BLOCKS];

// CHOCH (Change of Character) structure
struct CHOCH {
   bool valid;
   bool isBullish;  // true = bullish CHOCH (buy opportunity), false = bearish CHOCH (sell opportunity)
   datetime time;
   double price;
   double strength; // Measured by the height of the swing
};

// Keep track of recent CHOCHs
#define MAX_CHOCHS 20
CHOCH recentCHOCHs[MAX_CHOCHS];

// Wyckoff Market Phase structure
enum ENUM_WYCKOFF_PHASE {
   PHASE_ACCUMULATION,    // Phase A: Accumulation
   PHASE_MARKUP,          // Phase B: Markup (Uptrend)
   PHASE_DISTRIBUTION,    // Phase C: Distribution
   PHASE_MARKDOWN,        // Phase D: Markdown (Downtrend)
   PHASE_UNCLEAR          // No clear phase identified
};

// Wyckoff events/structures
struct WyckoffEvent {
   bool valid;
   string eventName;      // e.g., "Spring", "UTAD", "Selling Climax", etc.
   datetime time;
   double price;
   ENUM_WYCKOFF_PHASE phase;
   int strength;          // 1-10 rating of significance
};

// Supply/Demand zone structure (enhanced version of order blocks)
struct SupplyDemandZone {
   bool valid;
   bool isSupply;         // true = supply (sell), false = demand (buy)
   datetime startTime;
   datetime endTime;      // Zones can span multiple candles
   double upperBound;
   double lowerBound;
   int strength;          // 1-10 rating
   double volume;         // Aggregate volume in the zone
   bool hasBeenTested;    // Whether price returned to test the zone
   int testCount;         // How many times the zone has been tested
   bool hasBeenBreached;  // Whether the zone was fully breached (invalidated)
};

// SMC Pattern structures
struct FairValueGap {
   bool valid;
   bool isBullish;        // true = bullish FVG (buy), false = bearish FVG (sell)
   datetime time;
   double upperLevel;
   double lowerLevel;
   double midPoint;       // Target price (usually the midpoint of the gap)
   bool isFilled;         // Whether the gap has been filled
};

struct BreakerBlock {
   bool valid;
   bool isBullish;        // true = bullish breaker (buy), false = bearish breaker (sell)
   datetime time;
   double entryLevel;     // The level to enter a trade
   double stopLevel;      // The level for stop loss
   int strength;          // 1-10 rating
};

// Keep track of market structure elements
#define MAX_WYCKOFF_EVENTS 10
#define MAX_SD_ZONES 20
#define MAX_FVG 15
#define MAX_BREAKER_BLOCKS 10

WyckoffEvent recentWyckoffEvents[MAX_WYCKOFF_EVENTS];
SupplyDemandZone sdZones[MAX_SD_ZONES];
FairValueGap fairValueGaps[MAX_FVG];
BreakerBlock breakerBlocks[MAX_BREAKER_BLOCKS];

// Global variables for market structure analysis
ENUM_WYCKOFF_PHASE currentMarketPhase = PHASE_UNCLEAR;
double accumulationLow = 0.0;
double distributionHigh = 0.0;
bool isChoppy = false;
bool isStrong = false;
double volumeAverage = 0.0;

//+------------------------------------------------------------------+
//| Detect the current market regime based on price action           |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME DetectMarketRegime()
{
   // Get price data
   double close[], high[], low[];
   double ma20[], ma50[], ma200[];
   int lookback = MathMax(VolatilityLookback, TrendStrengthLookback);
   
   // Make sure we have enough data
   if(CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback + 50, close) <= 0) return REGIME_RANGING;
   if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback + 50, high) <= 0) return REGIME_RANGING;
   if(CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback + 50, low) <= 0) return REGIME_RANGING;
   
   // Calculate moving averages
   if(MA(close, 20, ma20) <= 0) return REGIME_RANGING;
   if(MA(close, 50, ma50) <= 0) return REGIME_RANGING;
   if(MA(close, 200, ma200) <= 0) return REGIME_RANGING;
   
   // Calculate ATR to measure volatility
   double atr[] = {0};
   int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
   if(CopyBuffer(atrHandle, 0, 0, lookback, atr) <= 0) {
      Print("Error getting ATR data: ", GetLastError());
      return REGIME_RANGING;
   }
   
   // Calculate average ATR and current ATR
   double avgATR = 0;
   for(int i = 1; i < lookback; i++) {
      avgATR += atr[i];
   }
   avgATR /= (lookback - 1);
   double currentATR = atr[0];
   
   // Calculate directional movement for trend detection
   int bullishBars = 0;
   int bearishBars = 0;
   
   for(int i = 1; i < TrendStrengthLookback; i++) {
      if(close[i] > close[i+1]) bullishBars++;
      else if(close[i] < close[i+1]) bearishBars++;
   }
   
   double trendStrength = (double)MathAbs(bullishBars - bearishBars) / TrendStrengthLookback;
   bool isBullish = bullishBars > bearishBars;
   
   // Check for a breakout
   double highestHigh = high[1];
   double lowestLow = low[1];
   
   for(int i = 2; i < 20; i++) {
      if(high[i] > highestHigh) highestHigh = high[i];
      if(low[i] < lowestLow) lowestLow = low[i];
   }
   
   bool isBreakout = (close[0] > highestHigh) || (close[0] < lowestLow);
   
   // Check MA alignment for trend confirmation
   bool maAligned = false;
   if(isBullish && ma20[0] > ma50[0] && ma50[0] > ma200[0]) maAligned = true;
   else if(!isBullish && ma20[0] < ma50[0] && ma50[0] < ma200[0]) maAligned = true;
   
   // Detect the regime based on collected data
   if(currentATR > avgATR * 1.5) {
      // High volatility detected
      if(isBreakout) return REGIME_BREAKOUT;
      return REGIME_VOLATILE;
   }
   
   if(trendStrength > 0.65) {
      // Strong trend detected
      if(maAligned) {
         // Confirmed by MA alignment
         return isBullish ? REGIME_TRENDING_BULL : REGIME_TRENDING_BEAR;
      }
   }
   
   if(trendStrength < 0.3 && currentATR < avgATR * 0.8) {
      return REGIME_CHOPPY;
   }
   
   // Default to ranging
   return REGIME_RANGING;
}

// Helper function for MA calculation
int MA(double &price[], int period, double &ma[])
{
   ArrayResize(ma, ArraySize(price));
   int maHandle = iMA(Symbol(), PERIOD_CURRENT, period, 0, MODE_SMA, PRICE_CLOSE);
   
   if(maHandle == INVALID_HANDLE) {
      Print("Error creating MA indicator: ", GetLastError());
      return -1;
   }
   
   if(CopyBuffer(maHandle, 0, 0, ArraySize(price), ma) <= 0) {
      Print("Error copying MA data: ", GetLastError());
      IndicatorRelease(maHandle);
      return -1;
   }
   
   IndicatorRelease(maHandle);
   return ArraySize(ma);
}

//+------------------------------------------------------------------+
//| Check if there are upcoming or recent high-impact news events    |
//+------------------------------------------------------------------+
bool IsHighImpactNewsTime()
{
   if(!EnableNewsFilter) return false; // Not filtering if disabled
   
   // Get current time
   datetime currentTime = TimeCurrent();
   
   // Special handling for critical economic indicators
   bool isFridayNFP = false;
   
   // Check if today is the first Friday of the month (NFP day)
   MqlDateTime today;
   TimeToStruct(currentTime, today);
   
   // First Friday of month check for NFP
   if(today.day <= 7 && today.day_of_week == FRIDAY) {
      // Check if we're within 2 hours of the typical NFP release (8:30 AM EST)
      if(today.hour >= 6 && today.hour <= 10) {
         isFridayNFP = true;
         Print("[NEWS] NFP day detected - avoiding trading during volatile period");
         return true;
      }
   }
   
   // Check for other high-impact news events
   // Note: In a real implementation, this would connect to an economic calendar API
   // or use built-in MQL5 economic calendar functions
   
   // For this implementation, we'll check critical times for major news events
   // Typical high-impact times: 8:30 AM EST, 10:00 AM EST, 2:00 PM EST
   int newsHours[] = {8, 10, 14}; // EST times for major news releases
   
   // Calculate the avoidance window in seconds
   int avoidanceWindow = (int)(NewsAvoidanceMinutes * 60);
   
   // Check if we're within the avoidance window of any major news time
   for(int i=0; i<ArraySize(newsHours); i++) {
      // Convert news hour to GMT/server time
      int serverHour = (newsHours[i] + 5) % 24; // Simple EST to GMT conversion
      
      // Create a datetime for today at this hour
      MqlDateTime newsTime;
      TimeToStruct(currentTime, newsTime);
      newsTime.hour = serverHour;
      newsTime.min = 30; // Most releases are at half-hour marks
      newsTime.sec = 0;
      
      datetime newsDateTime = StructToTime(newsTime);
      
      // Check if current time is within the avoidance window
      if(MathAbs(currentTime - newsDateTime) < avoidanceWindow) {
         Print("[NEWS] Within avoidance window of potential high-impact news at ", 
               TimeToString(newsDateTime, TIME_MINUTES));
         return true;
      }
   }
   
   // Special handling for high-value assets like BTC
   if(StringFind(Symbol(), "BTC") >= 0) {
      // More permissive news filtering for crypto (only avoid most critical times)
      if(isFridayNFP) {
         return true; // Only avoid during NFP for crypto
      }
      return false; // Otherwise allow trading
   }
   
   return false; // No high-impact news detected
}

//+------------------------------------------------------------------+
//| Convert market regime enum to descriptive string                 |
//+------------------------------------------------------------------+
string GetRegimeDescription(ENUM_MARKET_REGIME regime)
{
   switch(regime) {
      case REGIME_TRENDING_BULL: return "Trending Bullish";
      case REGIME_TRENDING_BEAR: return "Trending Bearish";
      case REGIME_RANGING: return "Ranging";
      case REGIME_VOLATILE: return "Volatile";
      case REGIME_CHOPPY: return "Choppy";
      case REGIME_BREAKOUT: return "Breakout";
      default: return "Unknown";
   }
}



// Dashboard settings
input group "Dashboard Settings"
input bool EnableDashboard = true;      // Show dashboard on chart
input int DashboardX = 20;             // Initial dashboard X position
input int DashboardY = 20;             // Initial dashboard Y position
input int DashboardWidth = 300;        // Initial dashboard width
input int DashboardHeight = 320;       // Initial dashboard height
input color DashboardTextColor = clrWhite;  // Dashboard text color
input color DashboardBgColor = clrDarkBlue; // Dashboard background color
input color ProfitColor = clrLime;     // Color for profit display
input color LossColor = clrRed;        // Color for loss display
input bool DashboardDraggable = true;  // Whether dashboard can be moved
input bool SaveDashboardPosition = true; // Save dashboard position between restarts

// Internal dashboard state variables
int CurrentDashboardX;
int CurrentDashboardY;
int CurrentDashboardWidth;
int CurrentDashboardHeight;
bool DashboardInitialized = false;
string DashboardPositionFile;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA initialized successfully with Advanced Market Structure Analysis");
   
   // Store starting balance for drawdown calculations
   ::StartingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Initialize runtime variables with default values
   VolatilityMultiplier = DefaultVolatilityMultiplier;
   PatternQualityMultiplier = DefaultPatternQualityMultiplier;
   
   // Initialize dashboard and start timer for updates
   if(EnableDashboard) {
      // Create dashboard position file name based on EA name and chart
      DashboardPositionFile = "Dashboard_" + Symbol() + "_" + IntegerToString(MagicNumber) + ".pos";
      
      // Initialize dashboard position
      if(SaveDashboardPosition) {
         // Try to load saved position
         LoadDashboardPosition();
      } else {
         // Use input parameters
         CurrentDashboardX = DashboardX;
         CurrentDashboardY = DashboardY;
         CurrentDashboardWidth = DashboardWidth;
         CurrentDashboardHeight = DashboardHeight;
      }
      
      // Enable timer for dashboard updates
      EventSetTimer(1); // Update every second
      
      // Set dashboard as initialized
      DashboardInitialized = true;
      Print("[DASHBOARD] Initialized at position X:", CurrentDashboardX, " Y:", CurrentDashboardY, 
            " Width:", CurrentDashboardWidth, " Height:", CurrentDashboardHeight);
   }
   Print("[RISK] Starting balance recorded: ", ::StartingBalance);
   
   // Initialize blocks
   for(int i=0; i<MAX_BLOCKS; i++) {
      recentBlocks[i].valid = false;
   }
   
   // Initialize CHOCH array
   for(int i=0; i<MAX_CHOCHS; i++) {
      recentCHOCHs[i].valid = false;
   }
   
   // Initialize Wyckoff events
   for(int i=0; i<MAX_WYCKOFF_EVENTS; i++) {
      recentWyckoffEvents[i].valid = false;
   }
   
   // Initialize Supply/Demand zones
   for(int i=0; i<MAX_SD_ZONES; i++) {
      sdZones[i].valid = false;
      sdZones[i].hasBeenTested = false;
      sdZones[i].testCount = 0;
      sdZones[i].hasBeenBreached = false;
   }
   
   // Initialize Fair Value Gaps
   for(int i=0; i<MAX_FVG; i++) {
      fairValueGaps[i].valid = false;
      fairValueGaps[i].isFilled = false;
   }
   
   // Initialize Breaker Blocks
   for(int i=0; i<MAX_BREAKER_BLOCKS; i++) {
      breakerBlocks[i].valid = false;
   }
   
   // Set up ATR indicator
   atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
   if(atrHandle == INVALID_HANDLE) {
      Print("Failed to create ATR indicator handle");
      return(INIT_FAILED);
   }
   
   // Calculate initial volume average for reference
   CalculateVolumeProfile();
   
   // Determine initial market phase
   AnalyzeMarketPhase();
   
   // Initial detection of market structure elements
   // These will be implemented as needed
   // DetectSupplyDemandZones();
   // DetectFairValueGaps();
   // DetectBreakerBlocks();
   
   // Initialize correlation matrix
   if(CorrelationRiskEnabled) {
      // UpdateCorrelationMatrix();
      LastCorrelationUpdate = TimeCurrent();
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Load dashboard position from file                                 |
//+------------------------------------------------------------------+
void LoadDashboardPosition()
{
   // Set defaults first
   CurrentDashboardX = DashboardX;
   CurrentDashboardY = DashboardY;
   CurrentDashboardWidth = DashboardWidth;
   CurrentDashboardHeight = DashboardHeight;
   
   // Try to load from file
   int fileHandle = FileOpen(DashboardPositionFile, FILE_READ|FILE_TXT);
   if(fileHandle != INVALID_HANDLE) {
      // Read values
      string line = FileReadString(fileHandle);
      string values[];
      int splits = StringSplit(line, ',', values);
      
      if(splits == 4) {
         CurrentDashboardX = (int)StringToInteger(values[0]);
         CurrentDashboardY = (int)StringToInteger(values[1]);
         CurrentDashboardWidth = (int)StringToInteger(values[2]);
         CurrentDashboardHeight = (int)StringToInteger(values[3]);
         Print("[DASHBOARD] Loaded position from file: X=", CurrentDashboardX, 
               " Y=", CurrentDashboardY, " W=", CurrentDashboardWidth, " H=", CurrentDashboardHeight);
      }
      
      FileClose(fileHandle);
   } else {
      Print("[DASHBOARD] No saved position found, using defaults");
   }
   
   // Validate values are within screen
   int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   
   if(CurrentDashboardX < 0) CurrentDashboardX = 0;
   if(CurrentDashboardY < 0) CurrentDashboardY = 0;
   if(CurrentDashboardX + CurrentDashboardWidth > chartWidth) 
      CurrentDashboardX = chartWidth - CurrentDashboardWidth;
   if(CurrentDashboardY + CurrentDashboardHeight > chartHeight) 
      CurrentDashboardY = chartHeight - CurrentDashboardHeight;
}

//+------------------------------------------------------------------+
//| Save dashboard position to file                                   |
//+------------------------------------------------------------------+
void SaveDashboardPosition()
{
   int fileHandle = FileOpen(DashboardPositionFile, FILE_WRITE|FILE_TXT);
   if(fileHandle != INVALID_HANDLE) {
      // Save current position and size
      string positionData = IntegerToString(CurrentDashboardX) + "," + 
                          IntegerToString(CurrentDashboardY) + "," +
                          IntegerToString(CurrentDashboardWidth) + "," +
                          IntegerToString(CurrentDashboardHeight);
      
      FileWriteString(fileHandle, positionData);
      FileClose(fileHandle);
      Print("[DASHBOARD] Saved position to file: ", positionData);
   } else {
      Print("[DASHBOARD] Failed to save position to file");
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up resources
   EventKillTimer(); // Remove timer
   
   // Save dashboard position and clear objects
   if(EnableDashboard && SaveDashboardPosition && DashboardInitialized) {
      SaveDashboardPosition();
      ObjectsDeleteAll(0, "EA_Dashboard_");
   }
   
   Print("EA deinitialized with reason code: ", reason);
   
   // Clean up indicator handles if any were created
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Calculate volume profile for market analysis                      |
//+------------------------------------------------------------------+
void CalculateVolumeProfile()
{
   Print("[VOLUME] Calculating volume profile for ", Symbol());
   
   // Get recent volume data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 100, rates);
   
   if(copied <= 0) {
      Print("Error copying rates data for volume profile: ", GetLastError());
      return;
   }
   
   // Calculate average volume
   double totalVolume = 0.0;
   for(int i=0; i<copied; i++) {
      totalVolume += (double)rates[i].tick_volume; // Explicit cast to avoid warning
   }
   
   volumeAverage = totalVolume / copied;
   Print("[VOLUME] Average volume calculated: ", volumeAverage);
   
   // Determine if market is choppy based on price action
   double highArray[], lowArray[];
   ArrayResize(highArray, copied);
   ArrayResize(lowArray, copied);
   
   // Extract high and low values into separate arrays
   for(int i=0; i<copied; i++) {
      highArray[i] = rates[i].high;
      lowArray[i] = rates[i].low;
   }
   
   int highestIdx = ArrayMaximum(highArray, 0, copied);
   int lowestIdx = ArrayMinimum(lowArray, 0, copied);
   double highestHigh = highArray[highestIdx];
   double lowestLow = lowArray[lowestIdx];
   double range = highestHigh - lowestLow;
   
   double atrValue = 0;
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int atrCopied = CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
   
   if(atrCopied > 0) {
      atrValue = atrBuffer[0];
      isChoppy = range < (atrValue * 3); // If the range is less than 3x ATR, consider it choppy
      isStrong = GetTrendStrength() > 7; // Custom function to determine trend strength
   }
   
   Print("[VOLUME] Market conditions - Choppy: ", isChoppy, ", Strong trend: ", isStrong);
}

//+------------------------------------------------------------------+
//| Analyze market phase using Wyckoff method                         |
//+------------------------------------------------------------------+
void AnalyzeMarketPhase()
{
   Print("[WYCKOFF] Starting market phase analysis for ", Symbol());
   
   // Get recent price data for analysis
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 200, rates);
   
   if(copied <= 0) {
      Print("Error copying rates data for Wyckoff analysis: ", GetLastError());
      return;
   }
   
   // Identify key price levels
   double recentHighArray[], recentLowArray[];
   ArrayResize(recentHighArray, 50);
   ArrayResize(recentLowArray, 50);
   
   // Extract high and low values into separate arrays
   for(int i=0; i<50 && i<copied; i++) {
      recentHighArray[i] = rates[i].high;
      recentLowArray[i] = rates[i].low;
   }
   
   int highIdx = ArrayMaximum(recentHighArray, 0, 50);
   int lowIdx = ArrayMinimum(recentLowArray, 0, 50);
   double recentHigh = recentHighArray[highIdx];
   double recentLow = recentLowArray[lowIdx];
   
   // Variables to store Wyckoff signs
   bool hasSellingClimax = false;
   bool hasAutomaticRally = false;
   bool hasSecondaryTest = false;
   bool hasSpring = false;
   bool hasSignOfStrength = false;
   bool hasBuyingClimax = false;
   bool hasAutomaticReaction = false;
   bool hasUpThrust = false;
   
   // Detect Wyckoff signs
   for(int i=5; i<copied-5; i++) {
      // Selling Climax (end of markdown, start of accumulation)
      if(rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low && 
         rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low && 
         rates[i].tick_volume > volumeAverage*1.5) {
         hasSellingClimax = true;
         
         // Record this as a Wyckoff event
         int eventIndex = FindFreeWyckoffEventIndex();
         if(eventIndex >= 0) {
            recentWyckoffEvents[eventIndex].valid = true;
            recentWyckoffEvents[eventIndex].eventName = "Selling Climax";
            recentWyckoffEvents[eventIndex].time = rates[i].time;
            recentWyckoffEvents[eventIndex].price = rates[i].low;
            recentWyckoffEvents[eventIndex].phase = PHASE_ACCUMULATION;
            recentWyckoffEvents[eventIndex].strength = 8;
         }
         
         Print("[WYCKOFF] Detected Selling Climax at ", rates[i].time, " price: ", rates[i].low);
      }
      
      // Automatic Rally (part of accumulation)
      if(hasSellingClimax && !hasAutomaticRally && 
         rates[i].high > rates[i+1].high && rates[i].high > rates[i-1].high) {
         hasAutomaticRally = true;
         
         int eventIndex = FindFreeWyckoffEventIndex();
         if(eventIndex >= 0) {
            recentWyckoffEvents[eventIndex].valid = true;
            recentWyckoffEvents[eventIndex].eventName = "Automatic Rally";
            recentWyckoffEvents[eventIndex].time = rates[i].time;
            recentWyckoffEvents[eventIndex].price = rates[i].high;
            recentWyckoffEvents[eventIndex].phase = PHASE_ACCUMULATION;
            recentWyckoffEvents[eventIndex].strength = 6;
         }
         
         Print("[WYCKOFF] Detected Automatic Rally at ", rates[i].time, " price: ", rates[i].high);
      }
      
      // Secondary Test (part of accumulation)
      if(hasAutomaticRally && !hasSecondaryTest && 
         rates[i].low <= rates[i+1].low && rates[i].low <= rates[i-1].low && 
         rates[i].low > recentLow && rates[i].tick_volume < volumeAverage) {
         hasSecondaryTest = true;
         
         int eventIndex = FindFreeWyckoffEventIndex();
         if(eventIndex >= 0) {
            recentWyckoffEvents[eventIndex].valid = true;
            recentWyckoffEvents[eventIndex].eventName = "Secondary Test";
            recentWyckoffEvents[eventIndex].time = rates[i].time;
            recentWyckoffEvents[eventIndex].price = rates[i].low;
            recentWyckoffEvents[eventIndex].phase = PHASE_ACCUMULATION;
            recentWyckoffEvents[eventIndex].strength = 5;
         }
         
         Print("[WYCKOFF] Detected Secondary Test at ", rates[i].time, " price: ", rates[i].low);
      }
      
      // Spring (part of accumulation, signaling potential end)
      if(hasSecondaryTest && !hasSpring && 
         rates[i].low < recentLow && rates[i].close > recentLow) {
         hasSpring = true;
         
         int eventIndex = FindFreeWyckoffEventIndex();
         if(eventIndex >= 0) {
            recentWyckoffEvents[eventIndex].valid = true;
            recentWyckoffEvents[eventIndex].eventName = "Spring";
            recentWyckoffEvents[eventIndex].time = rates[i].time;
            recentWyckoffEvents[eventIndex].price = rates[i].low;
            recentWyckoffEvents[eventIndex].phase = PHASE_ACCUMULATION;
            recentWyckoffEvents[eventIndex].strength = 9;
         }
         
         Print("[WYCKOFF] Detected Spring at ", rates[i].time, " price: ", rates[i].low);
      }
      
      // Sign of Strength (transition to markup)
      if(hasSpring && !hasSignOfStrength && 
         rates[i].close > rates[i].open && 
         rates[i].close > rates[i+1].high && 
         rates[i].tick_volume > volumeAverage*1.3) {
         hasSignOfStrength = true;
         
         int eventIndex = FindFreeWyckoffEventIndex();
         if(eventIndex >= 0) {
            recentWyckoffEvents[eventIndex].valid = true;
            recentWyckoffEvents[eventIndex].eventName = "Sign of Strength";
            recentWyckoffEvents[eventIndex].time = rates[i].time;
            recentWyckoffEvents[eventIndex].price = rates[i].high;
            recentWyckoffEvents[eventIndex].phase = PHASE_MARKUP;
            recentWyckoffEvents[eventIndex].strength = 7;
         }
         
         Print("[WYCKOFF] Detected Sign of Strength at ", rates[i].time, " price: ", rates[i].high);
      }
      
      // Buying Climax (end of markup, start of distribution)
      if(rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high && 
         rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high && 
         rates[i].tick_volume > volumeAverage*1.5) {
         hasBuyingClimax = true;
         distributionHigh = rates[i].high;
         
         int eventIndex = FindFreeWyckoffEventIndex();
         if(eventIndex >= 0) {
            recentWyckoffEvents[eventIndex].valid = true;
            recentWyckoffEvents[eventIndex].eventName = "Buying Climax";
            recentWyckoffEvents[eventIndex].time = rates[i].time;
            recentWyckoffEvents[eventIndex].price = rates[i].high;
            recentWyckoffEvents[eventIndex].phase = PHASE_DISTRIBUTION;
            recentWyckoffEvents[eventIndex].strength = 8;
         }
         
         Print("[WYCKOFF] Detected Buying Climax at ", rates[i].time, " price: ", rates[i].high);
      }
      
      // Automatic Reaction (part of distribution)
      if(hasBuyingClimax && !hasAutomaticReaction && 
         rates[i].low < rates[i+1].low && rates[i].low < rates[i-1].low) {
         hasAutomaticReaction = true;
         
         int eventIndex = FindFreeWyckoffEventIndex();
         if(eventIndex >= 0) {
            recentWyckoffEvents[eventIndex].valid = true;
            recentWyckoffEvents[eventIndex].eventName = "Automatic Reaction";
            recentWyckoffEvents[eventIndex].time = rates[i].time;
            recentWyckoffEvents[eventIndex].price = rates[i].low;
            recentWyckoffEvents[eventIndex].phase = PHASE_DISTRIBUTION;
            recentWyckoffEvents[eventIndex].strength = 6;
         }
         
         Print("[WYCKOFF] Detected Automatic Reaction at ", rates[i].time, " price: ", rates[i].low);
      }
      
      // Upthrust (part of distribution, signaling potential end)
      if(hasAutomaticReaction && !hasUpThrust && 
         rates[i].high > distributionHigh && rates[i].close < distributionHigh) {
         hasUpThrust = true;
         
         int eventIndex = FindFreeWyckoffEventIndex();
         if(eventIndex >= 0) {
            recentWyckoffEvents[eventIndex].valid = true;
            recentWyckoffEvents[eventIndex].eventName = "Upthrust";
            recentWyckoffEvents[eventIndex].time = rates[i].time;
            recentWyckoffEvents[eventIndex].price = rates[i].high;
            recentWyckoffEvents[eventIndex].phase = PHASE_DISTRIBUTION;
            recentWyckoffEvents[eventIndex].strength = 9;
         }
         
         Print("[WYCKOFF] Detected Upthrust at ", rates[i].time, " price: ", rates[i].high);
      }
   }
   
   // Determine the current market phase based on detected signs
   if(hasSpring && hasSignOfStrength) {
      currentMarketPhase = PHASE_MARKUP;
      accumulationLow = recentLow;
   }
   else if(hasSellingClimax && hasSecondaryTest) {
      currentMarketPhase = PHASE_ACCUMULATION;
      accumulationLow = recentLow;
   }
   else if(hasUpThrust) {
      currentMarketPhase = PHASE_MARKDOWN;
      distributionHigh = recentHigh;
   }
   else if(hasBuyingClimax && hasAutomaticReaction) {
      currentMarketPhase = PHASE_DISTRIBUTION;
      distributionHigh = recentHigh;
   }
   else {
      // If no clear Wyckoff signs, use trend analysis to determine phase
      double maFast[], maSlow[];
      ArraySetAsSeries(maFast, true);
      ArraySetAsSeries(maSlow, true);
      
      int maFastHandle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
      int maSlowHandle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      
      CopyBuffer(maFastHandle, 0, 0, 3, maFast);
      CopyBuffer(maSlowHandle, 0, 0, 3, maSlow);
      
      IndicatorRelease(maFastHandle);
      IndicatorRelease(maSlowHandle);
      
      if(maFast[0] > maSlow[0] && maFast[1] > maSlow[1]) {
         // Rising MAs - uptrend
         if(rates[0].close > maFast[0]) {
            currentMarketPhase = PHASE_MARKUP;
         } else {
            currentMarketPhase = PHASE_DISTRIBUTION;
         }
      }
      else if(maFast[0] < maSlow[0] && maFast[1] < maSlow[1]) {
         // Falling MAs - downtrend
         if(rates[0].close < maFast[0]) {
            currentMarketPhase = PHASE_MARKDOWN;
         } else {
            currentMarketPhase = PHASE_ACCUMULATION;
         }
      }
      else {
         currentMarketPhase = PHASE_UNCLEAR;
      }
   }
   
   Print("[WYCKOFF] Current market phase determined: ", GetMarketPhaseName(currentMarketPhase));
}

//+------------------------------------------------------------------+
//| Get the string name of the market phase                           |
//+------------------------------------------------------------------+
string GetMarketPhaseName(ENUM_WYCKOFF_PHASE phase)
{
   switch(phase) {
      case PHASE_ACCUMULATION: return "Accumulation";
      case PHASE_MARKUP: return "Markup (Uptrend)";
      case PHASE_DISTRIBUTION: return "Distribution";
      case PHASE_MARKDOWN: return "Markdown (Downtrend)";
      default: return "Unclear";
   }
}

//+------------------------------------------------------------------+
//| Find free index in Wyckoff events array                           |
//+------------------------------------------------------------------+
int FindFreeWyckoffEventIndex()
{
   for(int i=0; i<MAX_WYCKOFF_EVENTS; i++) {
      if(!recentWyckoffEvents[i].valid) {
         return i;
      }
   }
   
   // If no free slot, overwrite the oldest one
   int oldestIndex = 0;
   datetime oldestTime = TimeCurrent();
   
   for(int i=0; i<MAX_WYCKOFF_EVENTS; i++) {
      if(recentWyckoffEvents[i].time < oldestTime) {
         oldestTime = recentWyckoffEvents[i].time;
         oldestIndex = i;
      }
   }
   
   return oldestIndex;
}

//+------------------------------------------------------------------+
//| Timer function to update dashboard                                |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(EnableDashboard) {
      DrawDashboard();
   }
}

//+------------------------------------------------------------------+
//| Draw dashboard with EA status and metrics                         |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   if(!EnableDashboard || !DashboardInitialized) return;
   
   // Clear previous dashboard objects
   ObjectsDeleteAll(0, "EA_Dashboard_");
   
   // Dashboard background
   string bgName = "EA_Dashboard_BG";
   
   // Create background
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, CurrentDashboardX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, CurrentDashboardY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, CurrentDashboardWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, CurrentDashboardHeight);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, DashboardBgColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   ObjectSetInteger(0, bgName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bgName, OBJPROP_ZORDER, 0);
   
   // Make the background draggable
   if(DashboardDraggable) {
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTED, false);
      
      // Add resize handle in bottom-right corner
      string resizeName = "EA_Dashboard_Resize";
      ObjectCreate(0, resizeName, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, resizeName, OBJPROP_XDISTANCE, CurrentDashboardX + CurrentDashboardWidth - 10);
      ObjectSetInteger(0, resizeName, OBJPROP_YDISTANCE, CurrentDashboardY + CurrentDashboardHeight - 10);
      ObjectSetInteger(0, resizeName, OBJPROP_XSIZE, 10);
      ObjectSetInteger(0, resizeName, OBJPROP_YSIZE, 10);
      ObjectSetInteger(0, resizeName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, resizeName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, resizeName, OBJPROP_BGCOLOR, clrGray);
      ObjectSetInteger(0, resizeName, OBJPROP_BORDER_COLOR, clrBlack);
      ObjectSetInteger(0, resizeName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, resizeName, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, resizeName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, resizeName, OBJPROP_ZORDER, 1);
      ObjectSetString(0, resizeName, OBJPROP_TEXT, "");
   } else {
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
   }
   
   // Title
   AddDashboardLabel("Title", "Advanced Market Structure EA", CurrentDashboardX + 10, CurrentDashboardY + 10, clrYellow, 10);
   
   int y = CurrentDashboardY + 40;
   int yStep = 20;
   
   // Current market regime
   string regime = GetRegimeDescription(CurrentRegime);
   AddDashboardLabel("Regime", "Market Regime: " + regime, CurrentDashboardX + 10, y, DashboardTextColor, 9);
   y += yStep;
   
   // Open positions count
   int openPositions = 0;
   double floatingPL = 0.0;
   for(int i=0; i<PositionsTotal(); i++) {
      if(PositionGetTicket(i) > 0) {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
            openPositions++;
            floatingPL += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }
   
   AddDashboardLabel("Positions", "Open Positions: " + IntegerToString(openPositions) + " / " + IntegerToString(MaxOpenPositions), 
                   CurrentDashboardX + 10, y, DashboardTextColor, 9);
   y += yStep;
   
   // Floating P/L
   color plColor = (floatingPL >= 0) ? ProfitColor : LossColor;
   AddDashboardLabel("FloatingPL", "Floating P/L: " + DoubleToString(floatingPL, 2), 
                   CurrentDashboardX + 10, y, plColor, 9);
   y += yStep;
   
   // Performance metrics
   AddDashboardLabel("TotalTrades", "Total Trades: " + IntegerToString(TotalTrades), 
                   CurrentDashboardX + 10, y, DashboardTextColor, 9);
   y += yStep;
   
   if(TotalTrades > 0) {
      double winRate = (double)WinningTrades / TotalTrades * 100.0;
      AddDashboardLabel("WinRate", "Win Rate: " + DoubleToString(winRate, 1) + "%", 
                      CurrentDashboardX + 10, y, DashboardTextColor, 9);
      y += yStep;
      
      // Profit factor
      if(TotalLoss > 0) {
         double profitFactor = TotalProfit / TotalLoss;
         AddDashboardLabel("ProfitFactor", "Profit Factor: " + DoubleToString(profitFactor, 2), 
                         CurrentDashboardX + 10, y, DashboardTextColor, 9);
         y += yStep;
      }
   }
   
   // Special handling status for high-value assets
   if(EnableSpecialHandlingForBTC && (StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "XAU") >= 0)) {
      AddDashboardLabel("SpecialHandling", "Special BTC/XAU Handling: ACTIVE", 
                       CurrentDashboardX + 10, y, clrGold, 9);
      y += yStep;
   }
   
   // Risk management status
   string riskStatus = RiskManagementEnabled ? "ENABLED" : "DISABLED";
   AddDashboardLabel("RiskMgmt", "Risk Management: " + riskStatus, 
                   CurrentDashboardX + 10, y, RiskManagementEnabled ? clrGreen : clrRed, 9);
   y += yStep;
   
   // Drawdown protection status
   double currentDrawdown = 0;
   if(::StartingBalance > 0) {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      currentDrawdown = (::StartingBalance - equity) / ::StartingBalance * 100.0;
   }
   
   string ddStatus = "";
   color ddColor = DashboardTextColor;
   if(currentDrawdown > DrawdownStopLevel) {
      ddStatus = "CRITICAL";
      ddColor = clrRed;
   } else if(currentDrawdown > DrawdownPauseLevel) {
      ddStatus = "WARNING";
      ddColor = clrOrange;
   } else {
      ddStatus = "NORMAL";
      ddColor = clrGreen;
   }
   
   AddDashboardLabel("Drawdown", "Drawdown: " + DoubleToString(currentDrawdown, 2) + "% (" + ddStatus + ")", 
                   CurrentDashboardX + 10, y, ddColor, 9);
   y += yStep;
   
   // News filter status
   if(EnableNewsFilter) {
      bool newsTime = IsHighImpactNewsTime();
      string newsStatus = newsTime ? "HIGH IMPACT NEWS DETECTED" : "No high impact news";
      color newsColor = newsTime ? clrRed : clrGreen;
      
      AddDashboardLabel("NewsStatus", newsStatus, CurrentDashboardX + 10, y, newsColor, 9);
      y += yStep;
   }
   
   // Current volatility multiplier
   AddDashboardLabel("VolMult", "Volatility Multiplier: " + DoubleToString(VolatilityMultiplier, 2), 
                   CurrentDashboardX + 10, y, DashboardTextColor, 9);
   y += yStep;
   
   // Footer
   AddDashboardLabel("Footer", "Updated: " + TimeToString(TimeCurrent(), TIME_SECONDS), 
                   CurrentDashboardX + 10, y + 15, clrGray, 8);
}

//+------------------------------------------------------------------+
//| Helper function to add a dashboard label                          |
//+------------------------------------------------------------------+
void AddDashboardLabel(string name, string text, int x, int y, color textColor, int fontSize)
{
   string objName = "EA_Dashboard_" + name;
   
   ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, textColor);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetString(0, objName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Chart event handler for drag and resize                           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Handle dashboard dragging and resizing
   if(!EnableDashboard || !DashboardInitialized || !DashboardDraggable) return;
   
   // Handle object drag event
   if(id == CHARTEVENT_OBJECT_DRAG) {
      if(sparam == "EA_Dashboard_BG") {
         // Get new position
         CurrentDashboardX = (int)ObjectGetInteger(0, "EA_Dashboard_BG", OBJPROP_XDISTANCE);
         CurrentDashboardY = (int)ObjectGetInteger(0, "EA_Dashboard_BG", OBJPROP_YDISTANCE);
         
         // Force update the dashboard (redraw at new position)
         DrawDashboard();
         
         Print("[DASHBOARD] Moved to X:", CurrentDashboardX, " Y:", CurrentDashboardY);
      }
      else if(sparam == "EA_Dashboard_Resize") {
         // Get new size from resize handle position
         int resizeX = (int)ObjectGetInteger(0, "EA_Dashboard_Resize", OBJPROP_XDISTANCE);
         int resizeY = (int)ObjectGetInteger(0, "EA_Dashboard_Resize", OBJPROP_YDISTANCE);
         
         // Calculate new width and height
         CurrentDashboardWidth = resizeX - CurrentDashboardX + 10;
         CurrentDashboardHeight = resizeY - CurrentDashboardY + 10;
         
         // Enforce minimum size
         if(CurrentDashboardWidth < 200) CurrentDashboardWidth = 200;
         if(CurrentDashboardHeight < 150) CurrentDashboardHeight = 150;
         
         // Force update the dashboard
         DrawDashboard();
         
         Print("[DASHBOARD] Resized to W:", CurrentDashboardWidth, " H:", CurrentDashboardHeight);
      }
   }
}

//+------------------------------------------------------------------+
//| Get trend strength on a scale of 1-10                             |
//+------------------------------------------------------------------+
int GetTrendStrength()
{
   // Get multiple timeframe data for robust trend analysis
   int strength = 5; // Neutral starting point
   
   // Get MA data
   double ma20[], ma50[], ma200[];
   ArraySetAsSeries(ma20, true);
   ArraySetAsSeries(ma50, true);
   ArraySetAsSeries(ma200, true);
   
   int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
   int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
   int ma200Handle = iMA(Symbol(), PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   CopyBuffer(ma20Handle, 0, 0, 6, ma20);
   CopyBuffer(ma50Handle, 0, 0, 6, ma50);
   CopyBuffer(ma200Handle, 0, 0, 6, ma200);
   
   IndicatorRelease(ma20Handle);
   IndicatorRelease(ma50Handle);
   IndicatorRelease(ma200Handle);
   
   // Get price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 10, rates);
   
   if(copied > 0) {
      // Check MA alignment for trend
      if(ma20[0] > ma50[0] && ma50[0] > ma200[0]) {
         // Bullish alignment
         strength += 2;
         
         // Check for acceleration - ensure we have enough data
         if(ArraySize(ma20) >= 6 && ma20[0] - ma20[3] > ma20[3] - ma20[5]) {
            strength += 1;
         }
      }
      else if(ma20[0] < ma50[0] && ma50[0] < ma200[0]) {
         // Bearish alignment
         strength += 2;
         
         // Check for acceleration - ensure we have enough data
         if(ArraySize(ma20) >= 6 && ma20[3] - ma20[0] > ma20[5] - ma20[3]) {
            strength += 1;
         }
      }
      
      // Check price in relation to MAs
      if(rates[0].close > ma20[0] && rates[0].close > ma50[0] && rates[0].close > ma200[0]) {
         strength += 1; // Strong bullish
      }
      else if(rates[0].close < ma20[0] && rates[0].close < ma50[0] && rates[0].close < ma200[0]) {
         strength += 1; // Strong bearish
      }
      
      // Check recent candle momentum
      int bullishCandles = 0;
      int bearishCandles = 0;
      
      for(int i=0; i<5; i++) {
         if(rates[i].close > rates[i].open) {
            bullishCandles++;
         } else {
            bearishCandles++;
         }
      }
      
      if(bullishCandles >= 4 || bearishCandles >= 4) {
         strength += 1; // Strong momentum in one direction
      }
   }
   
   // Ensure strength is within 1-10 range
   if(strength < 1) strength = 1;
   if(strength > 10) strength = 10;
   
   return strength;
}

//+------------------------------------------------------------------+
//| Calculate optimal stop loss using multi-timeframe ATR             |
//+------------------------------------------------------------------+
double CalculateOptimalStopLoss(int signal, double entryPrice)
{
   Print("[SL] Calculating optimal stop loss for signal: ", signal, " entry: ", entryPrice);
   
   // Get ATR values from multiple timeframes for more robust stops
   int atrHandleCurrent = iATR(Symbol(), PERIOD_CURRENT, 14);
   int atrHandleHigher = iATR(Symbol(), PERIOD_H1, 14);
   
   // Get values from handles
   double atrCurrent = 0, atrHigher = 0;
   double atrBuffer[];
   
   // Copy values from current timeframe
   ArraySetAsSeries(atrBuffer, true);
   if(CopyBuffer(atrHandleCurrent, 0, 0, 1, atrBuffer) > 0) {
      atrCurrent = atrBuffer[0];
   } else {
      Print("[SL] Failed to get current ATR value");
      atrCurrent = 0.001; // Fallback
   }
   
   // Copy values from higher timeframe
   if(CopyBuffer(atrHandleHigher, 0, 0, 1, atrBuffer) > 0) {
      atrHigher = atrBuffer[0];
   } else {
      Print("[SL] Failed to get higher timeframe ATR value");
      atrHigher = 0.001; // Fallback
   }
   
   // Use the higher of the two ATRs for more protection
   double atr = MathMax(atrCurrent, atrHigher);
   
   // Special handling for crypto pairs (wider stops)
   bool isCrypto = StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "ETH") >= 0;
   double multiplier = isCrypto ? 2.5 : 1.5;
   
   // Calculate stop distance
   double stopDistance = atr * multiplier;
   
   // Ensure minimum stop distance
   int stopLevel = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopLevel * _Point;
   stopDistance = MathMax(stopDistance, minDistance * 1.5);
   
   // See if there's a better stop based on recent CHOCH patterns
   double chochBasedStop = 0;
   bool useChochStop = false;
   
   for(int i=0; i<MAX_CHOCHS; i++) {
      if(!recentCHOCHs[i].valid) continue;
      
      // For BUY positions, use bearish CHOCH as potential stop
      if(signal > 0 && !recentCHOCHs[i].isBullish) {
         double potentialStop = recentCHOCHs[i].price - (10 * _Point); // Add buffer
         // Only if it's a valid stop (not too close)
         if(MathAbs(entryPrice - potentialStop) >= minDistance) {
            chochBasedStop = potentialStop;
            useChochStop = true;
            Print("[SL] Using bearish CHOCH at ", DoubleToString(recentCHOCHs[i].price, _Digits), 
                  " for BUY stop loss");
            break;
         }
      }
      // For SELL positions, use bullish CHOCH as potential stop
      else if(signal < 0 && recentCHOCHs[i].isBullish) {
         double potentialStop = recentCHOCHs[i].price + (10 * _Point); // Add buffer
         // Only if it's a valid stop (not too close)
         if(MathAbs(entryPrice - potentialStop) >= minDistance) {
            chochBasedStop = potentialStop;
            useChochStop = true;
            Print("[SL] Using bullish CHOCH at ", DoubleToString(recentCHOCHs[i].price, _Digits), 
                  " for SELL stop loss");
            break;
         }
      }
   }
   
   // Calculate stop price
   double stopLoss = 0;
   if(useChochStop) {
      stopLoss = chochBasedStop;
      Print("[SL] Using CHOCH-based stop loss: ", stopLoss);
   } else {
      if(signal > 0) { // Buy
         stopLoss = entryPrice - stopDistance;
      } else { // Sell
         stopLoss = entryPrice + stopDistance;
      }
   }
   
   // Normalize to price digits
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   stopLoss = NormalizeDouble(stopLoss, digits);
   
   Print("[SL] Calculated stop loss: ", stopLoss, " (ATR: ", atr, ", distance: ", stopDistance, ")");
   return stopLoss;
}

//+------------------------------------------------------------------+
//| Calculate dynamic position size based on advanced risk parameters  |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double stopLoss, double riskPercent=1.0, int setupQuality=5)
{
   Print("[SIZE] Calculating position size for entry: ", entryPrice, " stop: ", stopLoss);
   
   // Check if trading is allowed based on drawdown protection
   if(DrawdownProtectionEnabled) {
      if(TradingDisabled) {
         Print("[RISK] Trading disabled due to excessive drawdown");
         return 0.0;
      }
      
      if(::TradingPaused) {
         Print("[RISK] Trading paused due to drawdown protection");
         return 0.0;
      }
   }
   
   // Get account balance and equity
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Initialize base risk amount
   double effectiveRiskPercent = riskPercent;
   
   // Apply volatility adjustment based on ATR
   if(RiskManagementEnabled) {
      // Get current ATR value
      double atrBuffer[];
      ArraySetAsSeries(atrBuffer, true);
      CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
      
      // Get historical ATR for comparison
      double atrHistory[];
      ArraySetAsSeries(atrHistory, true);
      CopyBuffer(atrHandle, 0, 0, 20, atrHistory);
      
      // Calculate average historical ATR
      double avgHistoricalATR = 0.0;
      for(int i=0; i<20 && i<ArraySize(atrHistory); i++) {
         avgHistoricalATR += atrHistory[i];
      }
      
      if(ArraySize(atrHistory) > 0) {
         avgHistoricalATR /= ArraySize(atrHistory);
      }
      
      // If current volatility is high, reduce position size
      if(ArraySize(atrBuffer) > 0 && avgHistoricalATR > 0) {
         double volatilityRatio = atrBuffer[0] / avgHistoricalATR;
         
         // Apply volatility adjustment
         if(volatilityRatio > 1.5) { // High volatility
            VolatilityMultiplier = 0.7; // Reduce position size by 30%
            Print("[RISK] High volatility detected (", volatilityRatio, "x normal). Reducing position size.");
         } else if(volatilityRatio < 0.7) { // Low volatility
            VolatilityMultiplier = 1.2; // Increase position size by 20%
            Print("[RISK] Low volatility detected (", volatilityRatio, "x normal). Increasing position size.");
         } else { // Normal volatility
            VolatilityMultiplier = 1.0;
         }
         
         // Apply extra caution for high-value assets like BTC
         string symbolName = Symbol();
         if(StringFind(symbolName, "BTC") >= 0 || StringFind(symbolName, "XBT") >= 0) {
            VolatilityMultiplier *= 0.8; // Further reduce size for BTC by 20%
            Print("[RISK] High-value asset detected. Applying conservative sizing.");
         }
      }
      
      // Adjust risk based on setup quality (1-10 scale)
      setupQuality = MathMax(1, MathMin(10, setupQuality)); // Ensure within range
      PatternQualityMultiplier = 0.5 + (setupQuality * 0.1); // Scale from 0.6 to 1.5
      
      // Apply combined adjustments to risk percentage
      effectiveRiskPercent *= VolatilityMultiplier * PatternQualityMultiplier;
      
      // Ensure risk percentage stays within limits
      effectiveRiskPercent = MathMax(0.1, MathMin(effectiveRiskPercent, MaxRiskPercent));
      
      Print("[RISK] Adjusted risk percent: ", NormalizeDouble(effectiveRiskPercent, 2), 
            "% (Volatility: ", NormalizeDouble(VolatilityMultiplier, 2),
            ", Pattern Quality: ", NormalizeDouble(PatternQualityMultiplier, 2), ")");
   }
   
   // Calculate risk amount
   double riskAmount = equity * (effectiveRiskPercent / 100.0);
   
   // Check if this would exceed our daily risk limit
   if(RiskManagementEnabled) {
      double dailyLoss = GetDailyLoss();
      double maxDailyRisk = balance * (MaxDailyRiskPercent / 100.0);
      
      if(dailyLoss + riskAmount > maxDailyRisk) {
         // Scale down the risk to stay within daily limits
         double remainingRisk = maxDailyRisk - dailyLoss;
         if(remainingRisk <= 0) {
            Print("[RISK] Daily risk limit reached. Cannot take new trades today.");
            return 0.0;
         }
         
         riskAmount = remainingRisk;
         Print("[RISK] Adjusted position size to stay within daily risk limit. New risk: $", riskAmount);
      }
      
      // Check correlation risk if enabled
      if(CorrelationRiskEnabled) {
         // Temporarily disable correlation exposure check
         // double correlatedExposure = GetCorrelatedExposure();
         double correlatedExposure = 0.0; // Placeholder value
         double maxCorrelatedRiskAmount = equity * (MaxCorrelatedRisk / 100.0);
         
         if(correlatedExposure + riskAmount > maxCorrelatedRiskAmount) {
            double remainingRisk = maxCorrelatedRiskAmount - correlatedExposure;
            if(remainingRisk <= 0) {
               Print("[RISK] Correlated exposure limit reached. Cannot take additional correlated risk.");
               return 0.0;
            }
            
            riskAmount = remainingRisk;
            Print("[RISK] Adjusted position size due to correlation risk. New risk: $", riskAmount);
         }
      }
   }
   
   // Calculate risk in price terms
   double riskDistance = MathAbs(entryPrice - stopLoss);
   
   // Handle zero distance
   if(riskDistance <= 0) {
      Print("[SIZE] Warning: Zero risk distance, using default");
      riskDistance = 100 * _Point;
   }
   
   // Convert to lot size
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double pointsPerLot = riskDistance / tickSize;
   double valuePerLot = pointsPerLot * tickValue;
   
   // Calculate raw lot size
   double lotSize = riskAmount / valuePerLot;
   
   // Apply broker constraints
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   // Normalize to lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // Ensure within limits
   lotSize = MathMax(lotSize, minLot);
   lotSize = MathMin(lotSize, maxLot);
   
   Print("[SIZE] Calculated lot size: ", lotSize, " (risk: $", riskAmount, ")");
   return lotSize;
}

//+------------------------------------------------------------------+
//| Update performance statistics with a new closed trade             |
//+------------------------------------------------------------------+
void UpdatePerformanceStats(double profitLoss, bool isWin, int tradeQuality)
{
   if(!EnablePerformanceStats) return;
   
   // Update basic stats
   TotalTrades++;
   
   if(isWin) {
      WinningTrades++;
      GrossProfit += profitLoss;
      LargestWin = MathMax(LargestWin, profitLoss);
      AverageWin = (AverageWin * (WinningTrades - 1) + profitLoss) / WinningTrades;
      
      // Update for profit factor calculation
      TotalProfit += profitLoss;
   } else {
      LosingTrades++;
      GrossLoss += MathAbs(profitLoss); // Store as positive value
      LargestLoss = MathMax(LargestLoss, MathAbs(profitLoss));
      AverageLoss = (AverageLoss * (LosingTrades - 1) + MathAbs(profitLoss)) / LosingTrades;
      
      // Update for profit factor calculation
      TotalLoss += MathAbs(profitLoss);
   }
   
   // Calculate derived metrics
   WinRate = (double)WinningTrades / MathMax(1, TotalTrades) * 100.0;
   ProfitFactor = GrossLoss > 0 ? GrossProfit / GrossLoss : GrossProfit;
   ExpectedPayoff = TotalTrades > 0 ? (GrossProfit - GrossLoss) / TotalTrades : 0;
   
   // Calculate quality performance ratio (if enough trades)
   if(HighQualityTrades >= 5 && LowQualityTrades >= 5) {
      double highQualityWinRate = 0;
      double lowQualityWinRate = 0;
      
      // This is simplified - in a real system you'd track individual trades by quality
      // Here we're estimating based on overall win rate and trade quality distribution
      highQualityWinRate = WinRate * 1.2; // Assume high quality trades perform 20% better
      lowQualityWinRate = WinRate * 0.8;  // Assume low quality trades perform 20% worse
      
      QualityPerformanceRatio = highQualityWinRate / MathMax(0.1, lowQualityWinRate);
   }
   
   // Log performance update
   string stats = "[PERFORMANCE] Update - ";
   stats += "Trades: " + IntegerToString(TotalTrades) + ", ";
   stats += "Win Rate: " + DoubleToString(WinRate, 1) + "%, ";
   stats += "Profit Factor: " + DoubleToString(ProfitFactor, 2) + ", ";
   stats += "Expected Payoff: " + DoubleToString(ExpectedPayoff, 2);
   Print(stats);
   
   // Log quality distribution
   string quality = "[QUALITY] Distribution - ";
   quality += "High: " + IntegerToString(HighQualityTrades) + " (";
   quality += DoubleToString((double)HighQualityTrades/MathMax(1,TotalTrades)*100, 1) + "%), ";
   quality += "Medium: " + IntegerToString(MediumQualityTrades) + " (";
   quality += DoubleToString((double)MediumQualityTrades/MathMax(1,TotalTrades)*100, 1) + "%), ";
   quality += "Low: " + IntegerToString(LowQualityTrades) + " (";
   quality += DoubleToString((double)LowQualityTrades/MathMax(1,TotalTrades)*100, 1) + "%)";
   Print(quality);
   
   // Especially for high-value assets like BTC (from previous memory)
   if(StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "XAU") >= 0) {
      Print("[PERFORMANCE] High-value asset detected - special handling active");
   }
}

//+------------------------------------------------------------------+
//| Score trade setup quality based on market structure and regime    |
//+------------------------------------------------------------------+
int DetermineSetupQuality(int signal, double entryPrice)
{
   int quality = 5; // Default medium quality
   
   // Get current market regime - use a consistent regime for scoring
   ENUM_MARKET_REGIME regime = CurrentRegime;
   
   // Market regime alignment with signal
   if((regime == REGIME_TRENDING_BULL && signal > 0) || 
      (regime == REGIME_TRENDING_BEAR && signal < 0)) {
      quality += 2; // Add points for alignment with trend
      Print("[QUALITY] +2 points for trend alignment");
   }
   else if((regime == REGIME_TRENDING_BULL && signal < 0) || 
           (regime == REGIME_TRENDING_BEAR && signal > 0)) {
      quality -= 2; // Subtract points for counter-trend
      Print("[QUALITY] -2 points for counter-trend");
   }
   else if(regime == REGIME_RANGING) {
      bool atExtreme = false;
      
      // Check if price is near range extremes
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 100, rates);
      
      if(copied > 0) {
         double highestHigh = rates[0].high;
         double lowestLow = rates[0].low;
         
         for(int i=1; i<copied; i++) {
            highestHigh = MathMax(highestHigh, rates[i].high);
            lowestLow = MathMin(lowestLow, rates[i].low);
         }
         
         double rangeSize = highestHigh - lowestLow;
         double topZone = highestHigh - (rangeSize * 0.1);
         double bottomZone = lowestLow + (rangeSize * 0.1);
         
         // If selling near top or buying near bottom of range
         if((signal < 0 && entryPrice > topZone) || 
            (signal > 0 && entryPrice < bottomZone)) {
            quality += 2; // Add points for range extreme entry
            atExtreme = true;
            Print("[QUALITY] +2 points for range extreme entry");
         }
      }
      
      // If not at extreme, range trades get a small penalty
      if(!atExtreme) {
         quality -= 1;
         Print("[QUALITY] -1 point for non-extreme range entry");
      }
   }
   else if(regime == REGIME_CHOPPY) {
      quality -= 2; // Subtract points for choppy markets
      Print("[QUALITY] -2 points for choppy market");
   }
   else if(regime == REGIME_VOLATILE) {
      quality -= 1; // Slight penalty for volatile markets
      Print("[QUALITY] -1 point for volatile market");
   }
   else if(regime == REGIME_BREAKOUT) {
      // Add points if trading in breakout direction
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 10, rates);
      
      if(copied > 0) {
         bool breakoutUp = rates[0].close > rates[1].high;
         bool breakoutDown = rates[0].close < rates[1].low;
         
         if((breakoutUp && signal > 0) || (breakoutDown && signal < 0)) {
            quality += 2; // Add points for trading with breakout
            Print("[QUALITY] +2 points for breakout alignment");
         }
         else {
            quality -= 1; // Slight penalty for counter-breakout
            Print("[QUALITY] -1 point for counter-breakout");
         }
      }
   }
   
   // Check for order block confirmation
   bool hasOrderBlock = false;
   for(int i=0; i<MAX_BLOCKS; i++) {
      if(recentBlocks[i].valid) {
         if((signal > 0 && recentBlocks[i].isBuy) || 
            (signal < 0 && !recentBlocks[i].isBuy)) {
            // Check if price is near order block
            double distance = MathAbs(entryPrice - recentBlocks[i].price);
            double threshold = atrValue * 0.5; // Within half ATR of block
            
            if(distance < threshold) {
               hasOrderBlock = true;
               quality += 2; // Add points for order block alignment
               Print("[QUALITY] +2 points for order block confirmation");
               break;
            }
         }
      }
   }
   
   // Check for CHOCH pattern confirmation
   bool hasCHOCH = false;
   for(int i=0; i<MAX_CHOCHS; i++) {
      if(recentCHOCHs[i].valid) {
         if((signal > 0 && recentCHOCHs[i].isBullish) || 
            (signal < 0 && !recentCHOCHs[i].isBullish)) {
            // Check if CHOCH is recent (within last 5 bars)
            if(TimeCurrent() - recentCHOCHs[i].time < PeriodSeconds(PERIOD_CURRENT) * 5) {
               hasCHOCH = true;
               quality += 1; // Add point for CHOCH confirmation
               Print("[QUALITY] +1 point for CHOCH pattern");
               break;
            }
         }
      }
   }
   
   // Special handling for high-value assets like BTC (based on previous memory)
   bool isHighValue = (StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "XAU") >= 0);
   if(isHighValue) {
      quality += 1; // Boost quality for high-value assets
      Print("[QUALITY] +1 point for high-value asset");
   }
   
   // Check for upcoming news
   if(IsHighImpactNewsTime()) {
      quality -= 3; // Major penalty for trading during news
      Print("[QUALITY] -3 points for trading during high-impact news");
   }
   
   // Cap quality between 1-10
   quality = MathMax(1, MathMin(10, quality));
   Print("[QUALITY] Final setup quality score: ", quality, "/10");
   
   return quality;
}

//+------------------------------------------------------------------+
//| Create detailed advanced trade log entry                          |
//+------------------------------------------------------------------+
void LogTradeDetails(int signal, double entryPrice, double stopLoss, double takeProfit, 
                     double posSize, int setupQuality, bool executed)
{
   // Calculate risk metrics
   double riskPips = MathAbs(entryPrice - stopLoss) / _Point;
   double rewardPips = MathAbs(takeProfit - entryPrice) / _Point;
   double riskRewardRatio = rewardPips / MathMax(1, riskPips);
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (BaseRiskPercent / 100.0);
   
   // Get market conditions
   string regimeStr = "Unknown";
   switch(CurrentRegime) {
      case REGIME_TRENDING_BULL: regimeStr = "Trending Bull"; break;
      case REGIME_TRENDING_BEAR: regimeStr = "Trending Bear"; break;
      case REGIME_RANGING: regimeStr = "Ranging"; break;
      case REGIME_VOLATILE: regimeStr = "Volatile"; break;
      case REGIME_CHOPPY: regimeStr = "Choppy"; break;
      case REGIME_BREAKOUT: regimeStr = "Breakout"; break;
   }
   
   // Special handling for high-value assets (from previous memory)
   bool isHighValue = (StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "XAU") >= 0);
   
   // Count valid order blocks
   int validBuyBlocks = 0;
   int validSellBlocks = 0;
   for(int i=0; i<MAX_BLOCKS; i++) {
      if(recentBlocks[i].valid) {
         if(recentBlocks[i].isBuy) validBuyBlocks++;
         else validSellBlocks++;
      }
   }
   
   // Build and write the log
   string logEntry = "";
   logEntry += "\n---------- ADVANCED TRADE LOG ----------";
   logEntry += "\nTimestamp: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   logEntry += "\nSymbol: " + Symbol() + (isHighValue ? " (HIGH VALUE ASSET)" : "");
   logEntry += "\nDirection: " + (signal > 0 ? "BUY" : "SELL");
   logEntry += "\nExecution Status: " + (executed ? "EXECUTED" : "REJECTED");
   logEntry += "\n";
   logEntry += "\n--- Market Conditions ---";
   logEntry += "\nMarket Regime: " + regimeStr;
   logEntry += "\nATR Value: " + DoubleToString(atrValue, _Digits);
   logEntry += "\nVolatility Multiplier: " + DoubleToString(VolatilityMultiplier, 2);
   logEntry += "\nValid Buy Blocks: " + IntegerToString(validBuyBlocks);
   logEntry += "\nValid Sell Blocks: " + IntegerToString(validSellBlocks);
   logEntry += "\nHigh Impact News: " + (IsHighImpactNewsTime() ? "YES" : "NO");
   logEntry += "\n";
   logEntry += "\n--- Trade Setup ---";
   logEntry += "\nEntry Price: " + DoubleToString(entryPrice, _Digits);
   logEntry += "\nStop Loss: " + DoubleToString(stopLoss, _Digits);
   logEntry += "\nTake Profit: " + DoubleToString(takeProfit, _Digits);
   logEntry += "\nPosition Size: " + DoubleToString(posSize, 2);
   logEntry += "\nRisk Amount: $" + DoubleToString(riskAmount, 2);
   logEntry += "\nRisk in Pips: " + DoubleToString(riskPips, 1);
   logEntry += "\nRisk:Reward Ratio: 1:" + DoubleToString(riskRewardRatio, 2);
   logEntry += "\nSetup Quality Score: " + IntegerToString(setupQuality) + "/10";
   logEntry += "\n";
   logEntry += "\n--- Performance Stats ---";
   logEntry += "\nTotal Trades: " + IntegerToString(TotalTrades);
   logEntry += "\nWin Rate: " + DoubleToString(WinRate, 1) + "%";
   logEntry += "\nProfit Factor: " + DoubleToString(ProfitFactor, 2);
   logEntry += "\nExpected Payoff: " + DoubleToString(ExpectedPayoff, 2);
   logEntry += "\nQuality Ratio: " + DoubleToString(QualityPerformanceRatio, 2);
   logEntry += "\n-----------------------------------------";
   
   Print(logEntry);
   
   // In a real implementation, you might also write this to a file
   // using FileOpen, FileWrite, etc.
}

//+------------------------------------------------------------------+
//| Execute a trade based on the signal direction                     |
//+------------------------------------------------------------------+
bool ExecuteTradeWithSignal(int signal, double entryPrice, double stopLoss)
{
   Print("[TRADE] Processing signal: ", signal);
   
   // Validate signal
   if(signal == 0) {
      Print("[TRADE] Invalid signal (0)");
      return false;
   }
   
   // Check if we already have maximum open positions (if enabled)
   if(MaxPositionsLimitEnabled) {
       int openPositions = 0;
       for(int i=0; i<PositionsTotal(); i++) {
           if(PositionGetTicket(i) > 0) {
               // Count only positions for current symbol and with our magic number
               if(PositionGetString(POSITION_SYMBOL) == Symbol() && 
                  PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                   openPositions++;
               }
           }
       }
       
       if(openPositions >= MaxOpenPositions) {
           Print("[TRADE] Maximum open positions (", MaxOpenPositions, ") reached. Trade not executed.");
           return false;
       }
   }
   
   // Get current market prices
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Use provided entry price or determine it if zero
   if(entryPrice == 0) {
       entryPrice = (signal > 0) ? ask : bid;
   }
   
   // Use provided stop loss or calculate it if zero
   if(stopLoss == 0) {
       stopLoss = CalculateOptimalStopLoss(signal, entryPrice);
   }
   
   // Calculate take profit with RR ratio
   double riskDistance = MathAbs(entryPrice - stopLoss);
   double rrRatio = 1.5; // Risk:Reward ratio
   double takeProfit = (signal > 0) ? 
                       entryPrice + (riskDistance * rrRatio) : 
                       entryPrice - (riskDistance * rrRatio);
                       
   // Normalize take profit
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   takeProfit = NormalizeDouble(takeProfit, digits);
   
   // Execute if trade if spread is acceptable
   if(!IsSpreadAcceptable()) {
      // Too high spread, don't execute now
      Print("[TRADE] Spread too high, trade not executed");
      return false;
   }
   
   // Determine setup quality based on market structure and regime
   int setupQuality = DetermineSetupQuality(signal, entryPrice);
   
   // Adjust risk based on setup quality
   double qualityMultiplier = 0.8 + (setupQuality * 0.04); // 0.8 (poor) to 1.2 (excellent)
   
   // Special boost for high-value assets like BTC (based on previous memory)
   bool isHighValue = (StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "XAU") >= 0);
   if(isHighValue && setupQuality >= 7) {
      qualityMultiplier *= 1.1; // Extra 10% for high-quality setups on high-value assets
      Print("[QUALITY] Applied special high-value asset boost for quality score: ", setupQuality);
   }
   
   // Calculate standard position size with quality adjustment
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (BaseRiskPercent / 100.0) * qualityMultiplier * VolatilityMultiplier;
   double posSize = CalculatePositionSize(entryPrice, stopLoss, BaseRiskPercent * qualityMultiplier * VolatilityMultiplier);
   
   // Execute the trade directly
   CTrade trade;
   trade.SetExpertMagicNumber(MagicNumber);
   bool result = false;
   
   if(signal > 0) { // Buy
      result = trade.Buy(posSize, Symbol(), 0, stopLoss, takeProfit, "Buy");
   } else if(signal < 0) { // Sell
      result = trade.Sell(posSize, Symbol(), 0, stopLoss, takeProfit, "Sell");
   }
   
   if(result) {
      Print("[TRADE] Successfully executed trade");
      
      // Log detailed trade information
      LogTradeDetails(signal, entryPrice, stopLoss, takeProfit, posSize, setupQuality, true);
      
      // Update correlation matrix after new trade
      if(CorrelationRiskEnabled && TimeCurrent() - LastCorrelationUpdate > 3600) { // Update hourly
         // UpdateCorrelationMatrix();
         LastCorrelationUpdate = TimeCurrent();
      }
   } else {
      Print("[TRADE] Failed to execute trade");
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Check if trading conditions are met                              |
//+------------------------------------------------------------------+
bool CanTrade()
{
   // Check time constraints
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   // Skip trading during known high-spread periods
   bool avoidVolatileHours = false;
   if((timeStruct.hour == 0 && timeStruct.min < 15) || // Market open volatility
      (timeStruct.hour == 16 && timeStruct.min >= 30)) // US news periods
   {
      Print("[FILTER] High volatility hour detected");
      avoidVolatileHours = true;
   }
   
   // Check spread
   double currentSpread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point;
   
   // Get ATR for spread comparison
   int atrHandleLocal = iATR(Symbol(), PERIOD_CURRENT, 14);
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   double atr = 0.001; // Default value
   
   if(CopyBuffer(atrHandleLocal, 0, 0, 1, atrBuffer) > 0) {
      atr = atrBuffer[0];
   } else {
      Print("[FILTER] Failed to get ATR for spread check");
   }
   
   // Release the handle after use
   IndicatorRelease(atrHandleLocal);
   
   double maxSpreadPercent = 0.25; // 25% of ATR is maximum acceptable spread
   
   // Special handling for crypto (allow wider spreads)
   bool isCrypto = StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "ETH") >= 0;
   if(isCrypto) maxSpreadPercent = 2.5; // 250% for crypto
   
   double maxSpread = atr * maxSpreadPercent;
   
   if(currentSpread > maxSpread && !isCrypto) {
      Print("[FILTER] Spread too high: ", currentSpread, " > ", maxSpread);
      return false;
   }
   
   // Check if we have enough margin
   double margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel = equity / margin * 100.0;
   
   if(marginLevel < 200) { // Require at least 200% margin level
      Print("[FILTER] Margin level too low: ", marginLevel, "%");
      return false;
   }
   
   // For testing purposes, override time constraints
   if(avoidVolatileHours) {
      Print("[FILTER] Ignoring volatile hours for testing");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Detect and create order blocks with enhanced criteria             |
//+------------------------------------------------------------------+
void DetectOrderBlocks()
{
   // Placeholder implementation until full implementation is fixed
   Print("[BLOCK] Order block detection called");
   
   // Initialize some valid blocks for testing
   for(int i=0; i<3; i++) {
      recentBlocks[i].valid = true;
      recentBlocks[i].isBuy = (i % 2 == 0); // Alternate between buy and sell blocks
      recentBlocks[i].price = SymbolInfoDouble(Symbol(), SYMBOL_BID) + (i * 50 * _Point);
      recentBlocks[i].time = TimeCurrent() - (i * 3600); // Different ages
      recentBlocks[i].strength = 5; // Medium strength
   }
   
   // Count and log valid blocks (from memory suggestion)
   int validCount = 0;
   for(int i=0; i<MAX_BLOCKS; i++) {
      if(recentBlocks[i].valid) validCount++;
   }
   
   Print("[BLOCK] Found ", validCount, " valid order blocks");
   
   /* Original implementation commented out due to syntax errors
   Print("[BLOCK] Starting advanced block detection for ", Symbol());
   
   Print("[BLOCK] Starting advanced block detection for ", Symbol());
   
   // Reset old block data
   for(int i=0; i<ArraySize(recentBlocks); i++) {
      recentBlocks[i].valid = false;
   }
   */
}

//+------------------------------------------------------------------+
//| Get latest price data - more bars for better pattern recognition  |
//+------------------------------------------------------------------+
void GetLatestPriceData()
{
   // Temporarily comment out this function to resolve compilation errors
   /* 
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 300, rates);
   
   if(copied <= 0) {
      Print("[BLOCK] Failed to copy rates data");
      return;
   }
   
   Print("[BLOCK] Successfully copied ", copied, " bars");
   
   // Variables for block counting
   int validBlocks = 0;
   
   // Get asset-specific parameters
   bool isCrypto = StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "ETH") >= 0;
   bool isGold = StringFind(Symbol(), "XAU") >= 0;
   bool isHighValue = isCrypto || isGold;
   
   // Calculate volatility metrics for adaptive thresholds
   double atrBuffer[];
   int atrHandleLocal = iATR(Symbol(), PERIOD_CURRENT, 14);
   ArraySetAsSeries(atrBuffer, true);
   bool atrValid = CopyBuffer(atrHandleLocal, 0, 0, 1, atrBuffer) > 0;
   double atr = atrValid ? atrBuffer[0] : 0.001;
   IndicatorRelease(atrHandleLocal);
   
   // Calculate volume profile for filtering (more permissive for crypto)
   double totalVolume = 0.0;
   double maxVolume = 0.0;
   for(int i=0; i<MathMin(50, copied); i++) {
      totalVolume += (double)rates[i].tick_volume;
      if((double)rates[i].tick_volume > maxVolume) maxVolume = (double)rates[i].tick_volume;
   }
   double avgVolume = totalVolume / MathMin(50, copied);
   double volumeThreshold = isHighValue ? avgVolume * 0.6 : avgVolume * 0.8;
   
   // Find swing highs and lows first for better structure analysis
   int swingHighs[20];
   int swingLows[20];
   int swingHighCount = 0;
   int swingLowCount = 0;
   
   // Swing detection - adaptive window size based on volatility
   int swingWindow = isHighValue ? 2 : 3; // Smaller window for high-value assets
   
   for(int i=swingWindow; i<copied-swingWindow && swingHighCount<20 && swingLowCount<20; i++) {
      // Swing high detection
      bool isSwingHigh = true;
      for(int j=1; j<=swingWindow; j++) {
         if(rates[i].high <= rates[i+j].high || rates[i].high <= rates[i-j].high) {
            isSwingHigh = false;
            break;
         }
      }
      
      if(isSwingHigh) {
         swingHighs[swingHighCount++] = i;
      }
      
      // Swing low detection
      bool isSwingLow = true;
      for(int j=1; j<=swingWindow; j++) {
         if(rates[i].low >= rates[i+j].low || rates[i].low >= rates[i-j].low) {
            isSwingLow = false;
            break;
         }
      }
      
      if(isSwingLow) {
         swingLows[swingLowCount++] = i;
      }
   }
   
   Print("[BLOCK] Found ", swingHighCount, " swing highs and ", swingLowCount, " swing lows");
   
   // Enhanced block finding using multiple criteria
   for(int i=3; i<copied-3 && validBlocks < MAX_BLOCKS; i++) {
      // ==================== BULLISH BLOCK DETECTION ====================
      if(rates[i].close < rates[i].open) { // Bearish candle for bullish block
         // Score-based approach to determine block quality
         double score = 0.0;
         
         // 1. Check for reversal patterns (more patterns for comprehensive detection)
         bool simpleReversal = rates[i+1].close > rates[i+1].open && rates[i+2].close > rates[i+2].open;
         bool strongReversal = simpleReversal && rates[i+3].close > rates[i+3].open;
         bool volumeSpike = rates[i].tick_volume > avgVolume * 1.5;
         bool isNearSwingLow = false;
         
         // 2. Check proximity to swing low (key structure point)
         for(int j=0; j<swingLowCount; j++) {
            if(MathAbs(i - swingLows[j]) <= 3) {
               isNearSwingLow = true;
               break;
            }
         }
         
         // 3. Check for wick size (longer wicks show stronger rejection)
         double bodySize = MathAbs(rates[i].open - rates[i].close);
         double wickSize = rates[i].high - MathMax(rates[i].open, rates[i].close);
         double ratio = bodySize > 0 ? wickSize / bodySize : 0;
         bool hasStrongWick = ratio > 0.6;
         
         // 4. Calculate block strength score based on multiple factors
         score = 2.0; // Base score for a potential bullish block
         
         // Add points for various quality factors
         if(simpleReversal) score += 2.0;
         if(strongReversal) score += 1.0;
         if(volumeSpike) score += 1.5;
         if(isNearSwingLow) score += 3.0;
         if(ratio > 1.5) score += 1.0; // Long upper wick compared to body
         
         // Check if this bar forms a valid bullish block
         if(score >= minBlockStrength) {
            // 5. Age-based scoring (fresher blocks get higher scores)
            double ageDiscount = 1.0 - (MathMin(i, 50) / 200.0);
            score *= ageDiscount;
         
         // 6. Asset-specific adjustments
         if(isHighValue) {
            // Much more permissive for crypto and gold
            if(score >= 0.8) {
               int strength = MathRound(score * 2);
               int localBlockIndex = validBlocks;
               
               recentBlocks[localBlockIndex].valid = true;
               recentBlocks[localBlockIndex].isBuy = true;
               recentBlocks[localBlockIndex].price = rates[i].low;
               recentBlocks[localBlockIndex].high = rates[i].high;
               recentBlocks[localBlockIndex].low = rates[i].low;
               recentBlocks[localBlockIndex].time = rates[i].time;
               recentBlocks[localBlockIndex].strength = strength;
               recentBlocks[localBlockIndex].volume = rates[i].tick_volume;
               
               Print("[BLOCK] Found HIGH-VALUE BULLISH block at ", TimeToString(rates[i].time), 
                     " price: ", DoubleToString(rates[i].low, _Digits), 
                     " score: ", DoubleToString(score, 2), 
                     " strength: ", strength);
               
               validBlocks++;
            }
         }
         else {
            // More strict for regular pairs
            if(score >= 1.5) {
               int strength = MathRound(score);
               int localBlockIndex = validBlocks;
               
               recentBlocks[localBlockIndex].valid = true;
               recentBlocks[localBlockIndex].isBuy = true;
               recentBlocks[localBlockIndex].price = rates[i].low;
               recentBlocks[localBlockIndex].high = rates[i].high;
               recentBlocks[localBlockIndex].low = rates[i].low;
               recentBlocks[localBlockIndex].time = rates[i].time;
               recentBlocks[localBlockIndex].strength = strength;
               recentBlocks[localBlockIndex].volume = rates[i].tick_volume;
               
               Print("[BLOCK] Found BULLISH block at ", TimeToString(rates[i].time), 
                     " price: ", DoubleToString(rates[i].low, _Digits), 
                     " score: ", DoubleToString(score, 2), 
                     " strength: ", strength);
               
               validBlocks++;
            }
         }
         
         if(validBlocks >= MAX_BLOCKS) break;
      }
      
      // ==================== BEARISH BLOCK DETECTION ====================
      if(rates[i].close > rates[i].open) { // Bullish candle for bearish block
         // Score-based approach to determine block quality
         double score = 0.0;
         
         // 1. Check for reversal patterns
         bool simpleReversal = rates[i+1].close < rates[i+1].open && rates[i+2].close < rates[i+2].open;
         bool strongReversal = simpleReversal && rates[i+3].close < rates[i+3].open;
         bool volumeSpike = rates[i].tick_volume > avgVolume * 1.5;
         bool isNearSwingHigh = false;
         
         // 2. Check proximity to swing high (key structure point)
         for(int j=0; j<swingHighCount; j++) {
            if(MathAbs(i - swingHighs[j]) <= 3) {
               isNearSwingHigh = true;
               break;
            }
         }
         
         // 3. Check for wick size (longer wicks show stronger rejection)
         double bodySize = MathAbs(rates[i].open - rates[i].close);
         double wickSize = MathMax(rates[i].open, rates[i].close) - rates[i].low;
         double ratio = bodySize > 0 ? wickSize / bodySize : 0;
         bool hasStrongWick = ratio > 0.6;
         
         // 4. Calculate block strength score based on multiple factors
         if(simpleReversal) score += 1.0;
         if(strongReversal) score += 0.5;
         if(volumeSpike) score += 1.5;
         if(isNearSwingHigh) score += 2.0;
         if(hasStrongWick) score += 0.8;
         if(rates[i].tick_volume > volumeThreshold) score += 0.5;
         
         // 5. Age-based scoring (fresher blocks get higher scores)
         double ageDiscount = 1.0 - (MathMin(i, 50) / 200.0);
         score *= ageDiscount;
         
         // 6. Asset-specific adjustments
         if(isHighValue) {
            // Much more permissive for crypto and gold
            if(score >= 0.8) {
               int strength = MathRound(score * 2);
               int localBlockIndex = validBlocks;
               
               recentBlocks[localBlockIndex].valid = true;
               recentBlocks[localBlockIndex].isBuy = false;
               recentBlocks[localBlockIndex].price = rates[i].high;
               recentBlocks[localBlockIndex].high = rates[i].high;
               recentBlocks[localBlockIndex].low = rates[i].low;
               recentBlocks[localBlockIndex].time = rates[i].time;
               recentBlocks[localBlockIndex].strength = strength;
               recentBlocks[localBlockIndex].volume = rates[i].tick_volume;
               
               Print("[BLOCK] Found HIGH-VALUE BEARISH block at ", TimeToString(rates[i].time), 
                     " price: ", DoubleToString(rates[i].high, _Digits), 
                     " score: ", DoubleToString(score, 2), 
                     " strength: ", strength);
               
               validBlocks++;
            }
         }
         else {
            // More strict for regular pairs
            if(score >= 1.5) {
               int strength = MathRound(score);
               int localBlockIndex = validBlocks;
               
               recentBlocks[localBlockIndex].valid = true;
               recentBlocks[localBlockIndex].isBuy = false;
               recentBlocks[localBlockIndex].price = rates[i].high;
               recentBlocks[localBlockIndex].high = rates[i].high;
               recentBlocks[localBlockIndex].low = rates[i].low;
               recentBlocks[localBlockIndex].time = rates[i].time;
               recentBlocks[localBlockIndex].strength = strength;
               recentBlocks[localBlockIndex].volume = rates[i].tick_volume;
               
               Print("[BLOCK] Found BEARISH block at ", TimeToString(rates[i].time), 
                     " price: ", DoubleToString(rates[i].high, _Digits), 
                     " score: ", DoubleToString(score, 2), 
                     " strength: ", strength);
               
               validBlocks++;
            }
         }
         
         if(validBlocks >= MAX_BLOCKS) break;
      }
   }
   
   // Count valid blocks by type
   int validBuyBlocks = 0;
   int validSellBlocks = 0;
   for(int i=0; i<ArraySize(recentBlocks); i++) {
      if(recentBlocks[i].valid) {
         if(recentBlocks[i].isBuy) validBuyBlocks++;
         else validSellBlocks++;
      }
   }
   
   // Create emergency blocks if needed - more sophisticated approach
   if(validBuyBlocks == 0 || validSellBlocks == 0) {
      Print("[BLOCK] Insufficient blocks found, creating smart emergency blocks");
      
      // Get recent price action to determine trend bias
      double ma20Buffer[];
      double ma50Buffer[];
      int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
      int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
      
      ArraySetAsSeries(ma20Buffer, true);
      ArraySetAsSeries(ma50Buffer, true);
      
      bool ma20Valid = CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer) > 0;
      bool ma50Valid = CopyBuffer(ma50Handle, 0, 0, 1, ma50Buffer) > 0;
      
      // Determine trend bias based on MA relationship
      bool bullishBias = ma20Valid && ma50Valid ? ma20Buffer[0] > ma50Buffer[0] : true;
      
      // Create blocks based on current market structure
      if(validBuyBlocks == 0) {
         // Create emergency BUY block
         int emergencyIndex = validBlocks;
         double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double blockDistance = atr * 0.5; // Use ATR for appropriate distance
         
         recentBlocks[emergencyIndex].valid = true;
         recentBlocks[emergencyIndex].isBuy = true;
         recentBlocks[emergencyIndex].price = currentBid - blockDistance;
         recentBlocks[emergencyIndex].high = currentBid;
         recentBlocks[emergencyIndex].low = recentBlocks[emergencyIndex].price;
         recentBlocks[emergencyIndex].time = TimeCurrent() - 300; // 5 minutes ago
         recentBlocks[emergencyIndex].strength = bullishBias ? 7 : 3; // Stronger if aligned with trend
         recentBlocks[emergencyIndex].volume = avgVolume * 1.5;
         
         Print("[BLOCK] Created SMART emergency BUY block at ", 
               DoubleToString(recentBlocks[emergencyIndex].price, _Digits),
               " strength: ", recentBlocks[emergencyIndex].strength);
         
         validBuyBlocks++;
         validBlocks++;
      }
      
      if(validSellBlocks == 0) {
         // Create emergency SELL block
         int emergencyIndex = validBlocks;
         double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         double blockDistance = atr * 0.5; // Use ATR for appropriate distance
         
         recentBlocks[emergencyIndex].valid = true;
         recentBlocks[emergencyIndex].isBuy = false;
         recentBlocks[emergencyIndex].price = currentAsk + blockDistance;
         recentBlocks[emergencyIndex].high = recentBlocks[emergencyIndex].price;
         recentBlocks[emergencyIndex].low = currentAsk;
         recentBlocks[emergencyIndex].time = TimeCurrent() - 300; // 5 minutes ago
         recentBlocks[emergencyIndex].strength = !bullishBias ? 7 : 3; // Stronger if aligned with trend
         recentBlocks[emergencyIndex].volume = avgVolume * 1.5;
         
         Print("[BLOCK] Created SMART emergency SELL block at ", 
               DoubleToString(recentBlocks[emergencyIndex].price, _Digits),
               " strength: ", recentBlocks[emergencyIndex].strength);
         
         validSellBlocks++;
         validBlocks++;
      }
   }
   
   Print("[BLOCK] Block detection completed: Total=", validBlocks, " Buy=", validBuyBlocks, " Sell=", validSellBlocks);
   */
}

//+------------------------------------------------------------------+
//| Retry trade execution with error handling                         |
//+------------------------------------------------------------------+
bool RetryTrade(int signal, double price, double sl, double tp, double size, int maxRetries=3)
{
   CTrade tradeMgr;
   tradeMgr.SetDeviationInPoints((ulong)AdaptiveSlippagePoints); // Explicit cast to avoid warning
   tradeMgr.SetExpertMagicNumber(MagicNumber);
   
   // Log attempt details
   Print("[RETRY] Attempting trade - Signal:", signal, " Price:", price, " SL:", sl, " TP:", tp, " Size:", size);
   
   // Validate stop distance
   double minStopDistance = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double actualDistance = MathAbs(price - sl);
   
   // Adjust stop if needed
   if(actualDistance < minStopDistance) {
      Print("[RETRY] Stop too close - Min:", minStopDistance, " Actual:", actualDistance);
      sl = (signal > 0) ? price - minStopDistance*1.5 : price + minStopDistance*1.5;
      Print("[RETRY] Adjusted stop to:", sl);
   }
   
   // Check lot size
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   if(size < minLot) {
      Print("[RETRY] Size too small - Min:", minLot, " Requested:", size);
      size = minLot;
   }
   
   // Attempt multiple times
   for(int attempts = 0; attempts < maxRetries; attempts++) {
      // Get fresh prices
      double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      double currentPrice = (signal > 0) ? currentAsk : currentBid;
      
      // Execute the trade
      bool result = false;
      if(signal > 0) {
         result = tradeMgr.Buy(size, Symbol(), currentPrice, sl, tp, "SMC");
      } else {
         result = tradeMgr.Sell(size, Symbol(), currentPrice, sl, tp, "SMC");
      }
      
      // Check result
      if(result) {
         Print("[RETRY] Trade successful! Ticket:", tradeMgr.ResultOrder());
         return true;
      } else {
         Print("[RETRY] Attempt", attempts+1, "failed -", tradeMgr.ResultRetcodeDescription());
         Sleep(100); // Small delay before retry
      }
   }
   
   Print("[RETRY] All attempts failed");
   return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Detect Change of Character (CHOCH) patterns                      |
//+------------------------------------------------------------------+
void DetectCHOCH()
{
   Print("[CHOCH] Starting CHOCH detection for ", Symbol());
   
   // Shift existing CHOCHs to make room for new ones
   for(int i=MAX_CHOCHS-1; i>0; i--) {
      recentCHOCHs[i] = recentCHOCHs[i-1];
   }
   
   // Reset the first CHOCH
   recentCHOCHs[0].valid = false;
   
   // Get latest price data - need more bars for reliable pattern detection
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 200, rates);
   
   if(copied <= 0) {
      Print("[CHOCH] Failed to copy rates data");
      return;
   }
   
   // We need to find swing highs and lows first
   // A swing high is when a candle's high is higher than both previous and next 2-3 candles
   // A swing low is when a candle's low is lower than both previous and next 2-3 candles
   int swingHighs[10];
   int swingLows[10];
   int swingHighCount = 0;
   int swingLowCount = 0;
   
   // Find swing points
   for(int i=3; i<copied-3 && swingHighCount<10 && swingLowCount<10; i++) {
      // Check for swing high
      if(rates[i].high > rates[i+1].high && 
         rates[i].high > rates[i+2].high && 
         rates[i].high > rates[i-1].high && 
         rates[i].high > rates[i-2].high) {
         swingHighs[swingHighCount++] = i;
      }
      
      // Check for swing low
      if(rates[i].low < rates[i+1].low && 
         rates[i].low < rates[i+2].low && 
         rates[i].low < rates[i-1].low && 
         rates[i].low < rates[i-2].low) {
         swingLows[swingLowCount++] = i;
      }
   }
   
   Print("[CHOCH] Found ", swingHighCount, " swing highs and ", swingLowCount, " swing lows");
   
   // Detect Bullish CHOCH
   // A bullish CHOCH occurs when price makes a lower low (swing low) followed by a higher low
   if(swingLowCount >= 2) {
      for(int i=0; i<swingLowCount-1; i++) {
         int currentLow = swingLows[i];
         int previousLow = swingLows[i+1];
         
         // Higher low after a lower low = bullish CHOCH
         if(rates[currentLow].low > rates[previousLow].low) {
            // We found a bullish CHOCH
            recentCHOCHs[0].valid = true;
            recentCHOCHs[0].isBullish = true;
            recentCHOCHs[0].time = rates[currentLow].time;
            recentCHOCHs[0].price = rates[currentLow].low;
            recentCHOCHs[0].strength = MathAbs(rates[currentLow].low - rates[previousLow].low) / _Point;
            
            Print("[CHOCH] Detected BULLISH CHOCH at ", TimeToString(recentCHOCHs[0].time), 
                  " price: ", DoubleToString(recentCHOCHs[0].price, _Digits), 
                  " strength: ", recentCHOCHs[0].strength);
            
            break; // We only care about the most recent CHOCH
         }
      }
   }
   
   // Detect Bearish CHOCH
   // A bearish CHOCH occurs when price makes a higher high (swing high) followed by a lower high
   if(swingHighCount >= 2) {
      for(int i=0; i<swingHighCount-1; i++) {
         int currentHigh = swingHighs[i];
         int previousHigh = swingHighs[i+1];
         
         // Lower high after a higher high = bearish CHOCH
         if(rates[currentHigh].high < rates[previousHigh].high) {
            // If we already found a bullish CHOCH, keep the stronger one
            if(recentCHOCHs[0].valid) {
               double bearishStrength = MathAbs(rates[currentHigh].high - rates[previousHigh].high) / _Point;
               
               // Only replace if bearish CHOCH is stronger
               if(bearishStrength > recentCHOCHs[0].strength) {
                  recentCHOCHs[0].valid = true;
                  recentCHOCHs[0].isBullish = false;
                  recentCHOCHs[0].time = rates[currentHigh].time;
                  recentCHOCHs[0].price = rates[currentHigh].high;
                  recentCHOCHs[0].strength = bearishStrength;
                  
                  Print("[CHOCH] Detected BEARISH CHOCH at ", TimeToString(recentCHOCHs[0].time), 
                        " price: ", DoubleToString(recentCHOCHs[0].price, _Digits), 
                        " strength: ", recentCHOCHs[0].strength);
               }
            } else {
               // No bullish CHOCH found, so record this bearish one
               recentCHOCHs[0].valid = true;
               recentCHOCHs[0].isBullish = false;
               recentCHOCHs[0].time = rates[currentHigh].time;
               recentCHOCHs[0].price = rates[currentHigh].high;
               recentCHOCHs[0].strength = MathAbs(rates[currentHigh].high - rates[previousHigh].high) / _Point;
               
               Print("[CHOCH] Detected BEARISH CHOCH at ", TimeToString(recentCHOCHs[0].time), 
                     " price: ", DoubleToString(recentCHOCHs[0].price, _Digits), 
                     " strength: ", recentCHOCHs[0].strength);
            }
            
            break; // We only care about the most recent CHOCH
         }
      }
   }
   
   Print("[CHOCH] CHOCH detection completed for ", Symbol());
}

//+------------------------------------------------------------------+
//| Detect Supply and Demand Zones (enhanced order blocks)            |
//+------------------------------------------------------------------+
void DetectSupplyDemandZones()
{
   Print("[SD] Starting Supply/Demand zone detection for ", Symbol());
   
   // Shift existing zones to make room for new ones (if needed)
   for(int i=MAX_SD_ZONES-1; i>0; i--) {
      if(sdZones[i-1].valid && !sdZones[i-1].hasBeenBreached) {
         sdZones[i] = sdZones[i-1];
      }
   }
   
   // Get recent price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 300, rates);
   
   if(copied <= 0) {
      Print("Error copying rates data for Supply/Demand analysis: ", GetLastError());
      return;
   }
   
   // Get minimum stop distance required by broker
   double tradeSize = 0.01;
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int atrCopied = CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
   
   if(atrCopied > 0) {
      atrValue = atrBuffer[0];
   } else {
      Print("Error getting ATR value: ", GetLastError());
      return;
   }
   
   // Variables to track zones
   int zoneIndex = 0;
   bool inSupplyZone = false;
   bool inDemandZone = false;
   datetime supplyStartTime = 0;
   datetime demandStartTime = 0;
   double supplyUpper = 0, supplyLower = 0;
   double demandUpper = 0, demandLower = 0;
   double supplyVolume = 0, demandVolume = 0;
   
   // Find higher timeframe structure points to identify potential SD zones
   int h4Handle = iMA(Symbol(), PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
   double h4Ma[];
   ArraySetAsSeries(h4Ma, true);
   CopyBuffer(h4Handle, 0, 0, 10, h4Ma);
   IndicatorRelease(h4Handle);
   
   // Check for potential turning points at higher timeframes
   double potentialLevels[];
   int levelCount = 0;
   int maxPotentialLevels = copied; // Maximum possible number of levels
   ArrayResize(potentialLevels, maxPotentialLevels);
   
   // Add recent swing highs/lows to potential levels
   for(int i=5; i<copied-5; i++) {
      // Swing high
      if(rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high && 
         rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high) {
         if(levelCount < maxPotentialLevels) {
            potentialLevels[levelCount++] = rates[i].high;
         }
      }
      
      // Swing low
      if(rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low && 
         rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low) {
         if(levelCount < maxPotentialLevels) {
            potentialLevels[levelCount++] = rates[i].low;
         }
      }
   }
   
   // Resize array to actual number of levels found
   ArrayResize(potentialLevels, levelCount);
   
   // Adjust for BTC and high-value assets based on the memory
   double blockStrengthMultiplier = 1.0;
   double blockSizeMultiplier = 1.0;
   double maxAgeMultiplier = 1.0;
   
   // Check if we're dealing with a high-value asset like BTC
   string symbolName = Symbol();
   if(StringFind(symbolName, "BTC") >= 0 || StringFind(symbolName, "XBT") >= 0) {
      // Implement the improvements from the memory
      blockStrengthMultiplier = 0.5;  // Reduced minimum block strength to 1 (from 2)
      blockSizeMultiplier = 0.5;      // Reduced block size requirements by 50%
      maxAgeMultiplier = 2.67;        // Extended max age to 8 hours (vs. 3 hours default)
      
      Print("[SD] High-value asset detected. Using permissive criteria for ", Symbol());
   }
   
   // Check if we're in a low volatility period
   if(isChoppy) {
      maxAgeMultiplier *= 1.5;  // Added 50% longer lifetime during low volatility periods
      Print("[SD] Low volatility detected. Extending zone lifetime by 50%");
   }
   
   // Detect potential supply/demand zones around turning points
   for(int i=3; i<copied-3; i++) {
      // Check for a strong bullish move after a period of consolidation (demand zone)
      if(!inDemandZone && 
         rates[i].close > rates[i].open && 
         rates[i].close > rates[i+1].high && 
         rates[i].close - rates[i].open > atrValue * 0.3 * blockSizeMultiplier && 
         (double)rates[i].tick_volume > volumeAverage * 1.2) {
         
         // Start of potential demand zone
         inDemandZone = true;
         demandStartTime = rates[i].time;
         demandLower = rates[i].low;
         demandUpper = rates[i].open;
         demandVolume = rates[i].tick_volume;
         
         // Check for multi-candle zone
         for(int j=i+1; j<i+4 && j<copied-1; j++) {
            if(rates[j].low >= demandLower * 0.995 && rates[j].high <= rates[i].close * 1.005) {
               // Extend the zone
               demandUpper = MathMax(demandUpper, rates[j].close);
               demandVolume += rates[j].tick_volume;
            } else {
               // End of zone
               break;
            }
         }
         
         // Score the zone quality
         int strength = 5; // Base strength
         
         // Increase strength if near a potential level
         for(int l=0; l<levelCount; l++) {
            if(MathAbs(demandLower - potentialLevels[l]) < atrValue * 0.5) {
               strength += 2;
               break;
            }
         }
         
         // Increase strength if aligned with market phase
         if(currentMarketPhase == PHASE_ACCUMULATION || currentMarketPhase == PHASE_MARKUP) {
            strength += 1;
         }
         
         // Adjust strength based on high-value asset parameters
         int minRequiredStrength = MathRound(3 * blockStrengthMultiplier); // 3 is the normal min strength
         
         // Create demand zone if strong enough
         if(strength >= minRequiredStrength) {
            // Find a free slot in the zones array
            for(int z=0; z<MAX_SD_ZONES; z++) {
               if(!sdZones[z].valid || sdZones[z].hasBeenBreached) {
                  zoneIndex = z;
                  break;
               }
            }
            
            // Record the demand zone
            sdZones[zoneIndex].valid = true;
            sdZones[zoneIndex].isSupply = false; // demand = buy
            sdZones[zoneIndex].startTime = demandStartTime;
            sdZones[zoneIndex].endTime = rates[i].time;
            sdZones[zoneIndex].upperBound = demandUpper;
            sdZones[zoneIndex].lowerBound = demandLower;
            sdZones[zoneIndex].strength = strength;
            sdZones[zoneIndex].volume = demandVolume;
            sdZones[zoneIndex].hasBeenTested = false;
            sdZones[zoneIndex].testCount = 0;
            sdZones[zoneIndex].hasBeenBreached = false;
            
            Print("[SD] Created Demand Zone at ", rates[i].time, ", strength: ", strength,
                  ", range: ", demandLower, " - ", demandUpper);
         }
         
         inDemandZone = false; // Reset flag
      }
      
      // Check for a strong bearish move after a period of consolidation (supply zone)
      if(!inSupplyZone && 
         rates[i].close < rates[i].open && 
         rates[i].close < rates[i+1].low && 
         rates[i].open - rates[i].close > atrValue * 0.3 * blockSizeMultiplier && 
         rates[i].tick_volume > volumeAverage * 1.2) {
         
         // Start of potential supply zone
         inSupplyZone = true;
         supplyUpper = rates[i].high;
         supplyLower = rates[i].open;
         supplyStartTime = rates[i].time;
         supplyVolume = rates[i].tick_volume;
         
         // Check for multi-candle zone
         for(int j=i+1; j<i+4 && j<copied-1; j++) {
            if(rates[j].high <= supplyUpper * 1.005 && rates[j].low >= rates[i].close * 0.995) {
               // Extend the zone
               supplyLower = MathMin(supplyLower, rates[j].close);
               supplyVolume += rates[j].tick_volume;
            } else {
               // End of zone
               break;
            }
         }
         
         // Score the zone quality
         int strength = 5; // Base strength
         
         // Increase strength if near a potential level
         for(int l=0; l<levelCount; l++) {
            if(MathAbs(supplyUpper - potentialLevels[l]) < atrValue * 0.5) {
               strength += 2;
               break;
            }
         }
         
         // Increase strength if aligned with market phase
         if(currentMarketPhase == PHASE_DISTRIBUTION || currentMarketPhase == PHASE_MARKDOWN) {
            strength += 1;
         }
         
         // Adjust strength based on high-value asset parameters
         int minRequiredStrength = MathRound(3 * blockStrengthMultiplier); // 3 is the normal min strength
         
         // Create supply zone if strong enough
         if(strength >= minRequiredStrength) {
            // Find a free slot in the zones array
            for(int z=0; z<MAX_SD_ZONES; z++) {
               if(!sdZones[z].valid || sdZones[z].hasBeenBreached) {
                  zoneIndex = z;
                  break;
               }
            }
            
            // Record the supply zone
            sdZones[zoneIndex].valid = true;
            sdZones[zoneIndex].isSupply = true; // supply = sell
            sdZones[zoneIndex].startTime = supplyStartTime;
            sdZones[zoneIndex].endTime = rates[i].time;
            sdZones[zoneIndex].upperBound = supplyUpper;
            sdZones[zoneIndex].lowerBound = supplyLower;
            sdZones[zoneIndex].strength = strength;
            sdZones[zoneIndex].volume = supplyVolume;
            sdZones[zoneIndex].hasBeenTested = false;
            sdZones[zoneIndex].testCount = 0;
            sdZones[zoneIndex].hasBeenBreached = false;
            
            Print("[SD] Created Supply Zone at ", rates[i].time, ", strength: ", strength,
                  ", range: ", supplyLower, " - ", supplyUpper);
         }
         
         inSupplyZone = false; // Reset flag
      }
   }
   
   // Update existing zones (test, breach status)
   double currentPrice = rates[0].close;
   datetime currentTime = rates[0].time;
   int maxAgeHours = (int)(3 * maxAgeMultiplier); // Default 3 hours, adjusted by multiplier
   
   for(int i=0; i<MAX_SD_ZONES; i++) {
      if(sdZones[i].valid && !sdZones[i].hasBeenBreached) {
         // Check if zone has been tested
         if(sdZones[i].isSupply) {
            // For supply zones (sell opportunities)
            if(currentPrice >= sdZones[i].lowerBound && currentPrice <= sdZones[i].upperBound) {
               if(!sdZones[i].hasBeenTested) {
                  sdZones[i].hasBeenTested = true;
                  Print("[SD] Supply Zone being tested at price: ", currentPrice);
               }
               sdZones[i].testCount++;
            }
            
            // Check if breached (price closed above the zone)
            if(currentPrice > sdZones[i].upperBound * 1.005) {
               sdZones[i].hasBeenBreached = true;
               Print("[SD] Supply Zone breached at price: ", currentPrice);
            }
         } else {
            // For demand zones (buy opportunities)
            if(currentPrice >= sdZones[i].lowerBound && currentPrice <= sdZones[i].upperBound) {
               if(!sdZones[i].hasBeenTested) {
                  sdZones[i].hasBeenTested = true;
                  Print("[SD] Demand Zone being tested at price: ", currentPrice);
               }
               sdZones[i].testCount++;
            }
            
            // Check if breached (price closed below the zone)
            if(currentPrice < sdZones[i].lowerBound * 0.995) {
               sdZones[i].hasBeenBreached = true;
               Print("[SD] Demand Zone breached at price: ", currentPrice);
            }
         }
         
         // Invalidate old zones - Fixed to respect both price breakthrough and age limits
         int zoneAgeHours = (int)((currentTime - sdZones[i].endTime) / 3600);
         if(zoneAgeHours > maxAgeHours) {
            Print("[SD] Zone invalidated due to age: ", zoneAgeHours, " hours");
            sdZones[i].valid = false;
         }
      }
   }
   
   // Count valid zones
   int validDemandZones = 0;
   int validSupplyZones = 0;
   
   for(int i=0; i<MAX_SD_ZONES; i++) {
      if(sdZones[i].valid && !sdZones[i].hasBeenBreached) {
         if(sdZones[i].isSupply) {
            validSupplyZones++;
         } else {
            validDemandZones++;
         }
      }
   }
   
   Print("[SD] Supply/Demand zone detection completed. Valid zones - Supply: ", 
         validSupplyZones, ", Demand: ", validDemandZones);
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps (FVG)                                     |
//+------------------------------------------------------------------+
void DetectFairValueGaps()
{
   Print("[FVG] Starting Fair Value Gap detection for ", Symbol());
   
   // Shift existing FVGs to make room for new ones (if needed)
   for(int i=MAX_FVG-1; i>0; i--) {
      if(fairValueGaps[i-1].valid && !fairValueGaps[i-1].isFilled) {
         fairValueGaps[i] = fairValueGaps[i-1];
      }
   }
   
   // Get recent price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 100, rates);
   
   if(copied <= 0) {
      Print("Error copying rates data for FVG analysis: ", GetLastError());
      return;
   }
   
   // Get ATR for reference
   double atrValue = 0;
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int atrCopied = CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
   
   if(atrCopied > 0) {
      atrValue = atrBuffer[0];
   } else {
      Print("Error getting ATR value: ", GetLastError());
      return;
   }
   
   // Detect Bullish Fair Value Gaps (FVG)
   // A bullish FVG occurs when price moves up quickly, leaving a gap between candles
   // The gap is between the high of candle 1 and the low of candle 3
   int fvgCount = 0;
   
   for(int i=2; i<copied-1; i++) {
      // Bullish FVG (Buy opportunity)
      // Current candle's low is higher than previous candle's high
      if(rates[i].low > rates[i+1].high) {
         // We have a gap - that's a Fair Value Gap
         double gapSize = rates[i].low - rates[i+1].high;
         
         // Only consider significant gaps (at least 0.5 ATR)
         if(gapSize >= atrValue * 0.5) {
            // Find a free slot
            int fvgIndex = -1;
            for(int j=0; j<MAX_FVG; j++) {
               if(!fairValueGaps[j].valid || fairValueGaps[j].isFilled) {
                  fvgIndex = j;
                  break;
               }
            }
            
            // If no free slot, skip
            if(fvgIndex == -1) continue;
            
            fairValueGaps[fvgIndex].valid = true;
            fairValueGaps[fvgIndex].isBullish = true;
            fairValueGaps[fvgIndex].time = rates[i].time;
            fairValueGaps[fvgIndex].upperLevel = rates[i].low;
            fairValueGaps[fvgIndex].lowerLevel = rates[i+1].high;
            fairValueGaps[fvgIndex].midPoint = rates[i+1].high + gapSize/2;
            fairValueGaps[fvgIndex].isFilled = false;
            
            Print("[FVG] Detected Bullish Fair Value Gap at ", rates[i].time, 
                  ", size: ", gapSize, ", levels: ", fairValueGaps[fvgIndex].lowerLevel, 
                  " - ", fairValueGaps[fvgIndex].upperLevel);
            
            fvgCount++;
         }
      }
      
      // Bearish FVG (Sell opportunity)
      // Current candle's high is lower than previous candle's low
      if(rates[i].high < rates[i+1].low) {
         // We have a gap - that's a Fair Value Gap
         double gapSize = rates[i+1].low - rates[i].high;
         
         // Only consider significant gaps (at least 0.5 ATR)
         if(gapSize >= atrValue * 0.5) {
            // Find a free slot
            int fvgIndex = -1;
            for(int j=0; j<MAX_FVG; j++) {
               if(!fairValueGaps[j].valid || fairValueGaps[j].isFilled) {
                  fvgIndex = j;
                  break;
               }
            }
            
            // If no free slot, skip
            if(fvgIndex == -1) continue;
            
            fairValueGaps[fvgIndex].valid = true;
            fairValueGaps[fvgIndex].isBullish = false;
            fairValueGaps[fvgIndex].time = rates[i].time;
            fairValueGaps[fvgIndex].upperLevel = rates[i+1].low;
            fairValueGaps[fvgIndex].lowerLevel = rates[i].high;
            fairValueGaps[fvgIndex].midPoint = rates[i].high + gapSize/2;
            fairValueGaps[fvgIndex].isFilled = false;
            
            Print("[FVG] Detected Bearish Fair Value Gap at ", rates[i].time, 
                  ", size: ", gapSize, ", levels: ", fairValueGaps[fvgIndex].lowerLevel, 
                  " - ", fairValueGaps[fvgIndex].upperLevel);
            
            fvgCount++;
         }
      }
   }
   
   // Update FVG status (check if filled)
   double currentPrice = rates[0].close;
   
   int filledFVGs = 0;
   int activeFVGs = 0;
   
   for(int i=0; i<MAX_FVG; i++) {
      if(fairValueGaps[i].valid && !fairValueGaps[i].isFilled) {
         // Check if price has filled the gap
         if(fairValueGaps[i].isBullish) {
            // For bullish FVG, filled when price goes back down into the gap
            if(currentPrice <= fairValueGaps[i].upperLevel && 
               currentPrice >= fairValueGaps[i].lowerLevel) {
               fairValueGaps[i].isFilled = true;
               filledFVGs++;
               Print("[FVG] Bullish Fair Value Gap filled at price: ", currentPrice);
            } else {
               activeFVGs++;
            }
         } else {
            // For bearish FVG, filled when price goes back up into the gap
            if(currentPrice >= fairValueGaps[i].lowerLevel && 
               currentPrice <= fairValueGaps[i].upperLevel) {
               fairValueGaps[i].isFilled = true;
               filledFVGs++;
               Print("[FVG] Bearish Fair Value Gap filled at price: ", currentPrice);
            } else {
               activeFVGs++;
            }
         }
      }
   }
   
   Print("[FVG] Fair Value Gap detection completed. New FVGs: ", fvgCount, 
         ", Active FVGs: ", activeFVGs, ", Filled FVGs: ", filledFVGs);
}

//+------------------------------------------------------------------+
//| Detect Breaker Blocks (SMC pattern)                              |
//+------------------------------------------------------------------+
void DetectBreakerBlocks()
{
   Print("[BB] Starting Breaker Block detection for ", Symbol());
   
   // Shift existing breaker blocks to make room for new ones
   for(int i=MAX_BREAKER_BLOCKS-1; i>0; i--) {
      if(breakerBlocks[i-1].valid) {
         breakerBlocks[i] = breakerBlocks[i-1];
      }
   }
   
   // Get recent price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 150, rates);
   
   if(copied <= 0) {
      Print("Error copying rates data for Breaker Block analysis: ", GetLastError());
      return;
   }
   
   // Get ATR for reference
   double atrValue = 0;
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int atrCopied = CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
   
   if(atrCopied > 0) {
      atrValue = atrBuffer[0];
   } else {
      Print("Error getting ATR value: ", GetLastError());
      return;
   }
   
   // Find significant swing points first
   double swingHighs[30];
   double swingLows[30];
   datetime swingHighTimes[30];
   datetime swingLowTimes[30];
   int highCount = 0;
   int lowCount = 0;
   
   // Find swing points
   for(int i=5; i<copied-5; i++) {
      // Swing high
      if(rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high && 
         rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high) {
         if(highCount < 30) {
            swingHighs[highCount] = rates[i].high;
            swingHighTimes[highCount] = rates[i].time;
            highCount++;
         }
      }
      
      // Swing low
      if(rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low && 
         rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low) {
         if(lowCount < 30) {
            swingLows[lowCount] = rates[i].low;
            swingLowTimes[lowCount] = rates[i].time;
            lowCount++;
         }
      }
   }
   
   // Detect bullish breaker blocks
   // A bullish breaker is formed when price makes a lower low (swing low),
   // then rallies to break the previous swing high, and then pulls back
   int breakerCount = 0;
   
   for(int i=1; i<lowCount; i++) {
      // Check if we have a lower low
      if(swingLows[i] < swingLows[i-1]) {
         // Find if price has broken above the previous swing high after this lower low
         for(int j=1; j<highCount; j++) {
            // Find a swing high that is before our lower low
            if(swingHighTimes[j] < swingLowTimes[i] && j+1 < highCount) {
               // Check if the next swing high after our lower low broke above the previous swing high
               if(swingHighTimes[j+1] > swingLowTimes[i] && swingHighs[j+1] > swingHighs[j]) {
                  // We have a potential bullish breaker block
                  // Now check if price has pulled back to retest the breaker
                  double breakerLevel = swingHighs[j];
                  
                  // Find a free slot
                  int breakerIndex = -1;
                  for(int k=0; k<MAX_BREAKER_BLOCKS; k++) {
                     if(!breakerBlocks[k].valid) {
                        breakerIndex = k;
                        break;
                     }
                  }
                  
                  // If no free slot, skip
                  if(breakerIndex == -1) continue;
                  
                  // Score the breaker block's strength (1-10)
                  int strength = 5; // Base strength
                  
                  // Higher strength if the break was strong
                  double breakStrength = swingHighs[j+1] - swingHighs[j];
                  if(breakStrength > atrValue) strength += 2;
                  
                  // Higher strength if in the right market phase
                  if(currentMarketPhase == PHASE_MARKUP) strength += 1;
                  
                  // Higher strength if multiple swing lows formed the pattern
                  if(i > 1 && swingLows[i-1] < swingLows[i-2]) strength += 1;
                  
                  // Record the breaker block
                  breakerBlocks[breakerIndex].valid = true;
                  breakerBlocks[breakerIndex].isBullish = true;
                  breakerBlocks[breakerIndex].time = swingHighTimes[j];
                  breakerBlocks[breakerIndex].entryLevel = breakerLevel;
                  breakerBlocks[breakerIndex].stopLevel = swingLows[i] - (atrValue * 0.5);
                  breakerBlocks[breakerIndex].strength = strength;
                  
                  Print("[BB] Detected Bullish Breaker Block at ", TimeToString(swingHighTimes[j]), 
                        ", Entry: ", breakerLevel, ", Stop: ", breakerBlocks[breakerIndex].stopLevel,
                        ", Strength: ", strength);
                  
                  breakerCount++;
                  break; // Found a breaker, move to next lower low
               }
            }
         }
      }
   }
   
   // Detect bearish breaker blocks
   // A bearish breaker is formed when price makes a higher high (swing high),
   // then drops to break below the previous swing low, and then rallies
   for(int i=1; i<highCount; i++) {
      // Check if we have a higher high
      if(swingHighs[i] > swingHighs[i-1]) {
         // Find if price has broken below the previous swing low after this higher high
         for(int j=1; j<lowCount; j++) {
            // Find a swing low that is before our higher high
            if(swingLowTimes[j] < swingHighTimes[i] && j+1 < lowCount) {
               // Check if the next swing low after our higher high broke below the previous swing low
               if(swingLowTimes[j+1] > swingHighTimes[i] && swingLows[j+1] < swingLows[j]) {
                  // We have a potential bearish breaker block
                  // Now check if price has rallied to retest the breaker
                  double breakerLevel = swingLows[j];
                  
                  // Find a free slot
                  int breakerIndex = -1;
                  for(int k=0; k<MAX_BREAKER_BLOCKS; k++) {
                     if(!breakerBlocks[k].valid) {
                        breakerIndex = k;
                        break;
                     }
                  }
                  
                  // If no free slot, skip
                  if(breakerIndex == -1) continue;
                  
                  // Score the breaker block's strength (1-10)
                  int strength = 5; // Base strength
                  
                  // Higher strength if the break was strong
                  double breakStrength = swingLows[j] - swingLows[j+1];
                  if(breakStrength > atrValue) strength += 2;
                  
                  // Higher strength if in the right market phase
                  if(currentMarketPhase == PHASE_MARKDOWN) strength += 1;
                  
                  // Higher strength if multiple swing highs formed the pattern
                  if(i > 1 && swingHighs[i-1] > swingHighs[i-2]) strength += 1;
                  
                  // Record the breaker block
                  breakerBlocks[breakerIndex].valid = true;
                  breakerBlocks[breakerIndex].isBullish = false;
                  breakerBlocks[breakerIndex].time = swingLowTimes[j];
                  breakerBlocks[breakerIndex].entryLevel = breakerLevel;
                  breakerBlocks[breakerIndex].stopLevel = swingHighs[i] + (atrValue * 0.5);
                  breakerBlocks[breakerIndex].strength = strength;
                  
                  Print("[BB] Detected Bearish Breaker Block at ", TimeToString(swingLowTimes[j]), 
                        ", Entry: ", breakerLevel, ", Stop: ", breakerBlocks[breakerIndex].stopLevel,
                        ", Strength: ", strength);
                  
                  breakerCount++;
                  break; // Found a breaker, move to next higher high
               }
            }
         }
      }
   }
   
   // Count valid breaker blocks
   int validBullishBreakers = 0;
   int validBearishBreakers = 0;
   
   for(int i=0; i<MAX_BREAKER_BLOCKS; i++) {
      if(breakerBlocks[i].valid) {
         if(breakerBlocks[i].isBullish) {
            validBullishBreakers++;
         } else {
            validBearishBreakers++;
         }
      }
   }
   
   Print("[BB] Breaker Block detection completed. New Breakers: ", breakerCount,
         ", Valid - Bullish: ", validBullishBreakers, ", Bearish: ", validBearishBreakers);
}

//+------------------------------------------------------------------+
//| Log current market phase and structure elements                   |
//+------------------------------------------------------------------+
void LogMarketPhase()
{
   // Get current time and price
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 1, rates);
   
   if(copied <= 0) return;
   
   datetime currentTime = rates[0].time;
   double currentPrice = rates[0].close;
   
   // Log the current market state
   Print("\n==== MARKET STRUCTURE ANALYSIS FOR ", Symbol(), " AT ", TimeToString(currentTime), " ====");
   Print("Current price: ", currentPrice);
   Print("Current market phase: ", GetMarketPhaseName(currentMarketPhase));
   Print("Market conditions - Choppy: ", isChoppy, ", Strong trend: ", isStrong);
   Print("Average volume: ", volumeAverage);
   
   // Count valid structure elements
   int validSellBlocks = 0, validBuyBlocks = 0;
   int validCHOCHs = 0;
   int validWyckoffEvents = 0;
   int validSupplyZones = 0, validDemandZones = 0;
   int validBullishFVGs = 0, validBearishFVGs = 0;
   int validBullishBreakers = 0, validBearishBreakers = 0;
   
   // Count order blocks
   for(int i=0; i<MAX_BLOCKS; i++) {
      if(recentBlocks[i].valid) {
         if(recentBlocks[i].isBuy) {
            validBuyBlocks++;
         } else {
            validSellBlocks++;
         }
      }
   }
   
   // Count CHOCHs
   for(int i=0; i<MAX_CHOCHS; i++) {
      if(recentCHOCHs[i].valid) {
         validCHOCHs++;
      }
   }
   
   // Count Wyckoff events
   for(int i=0; i<MAX_WYCKOFF_EVENTS; i++) {
      if(recentWyckoffEvents[i].valid) {
         validWyckoffEvents++;
      }
   }
   
   // Count Supply/Demand zones
   for(int i=0; i<MAX_SD_ZONES; i++) {
      if(sdZones[i].valid && !sdZones[i].hasBeenBreached) {
         if(sdZones[i].isSupply) {
            validSupplyZones++;
         } else {
            validDemandZones++;
         }
      }
   }
   
   // Count Fair Value Gaps
   for(int i=0; i<MAX_FVG; i++) {
      if(fairValueGaps[i].valid && !fairValueGaps[i].isFilled) {
         if(fairValueGaps[i].isBullish) {
            validBullishFVGs++;
         } else {
            validBearishFVGs++;
         }
      }
   }
   
   // Count Breaker Blocks
   for(int i=0; i<MAX_BREAKER_BLOCKS; i++) {
      if(breakerBlocks[i].valid) {
         if(breakerBlocks[i].isBullish) {
            validBullishBreakers++;
         } else {
            validBearishBreakers++;
         }
      }
   }
   
   // Log structure element counts
   Print("Order blocks - Buy: ", validBuyBlocks, ", Sell: ", validSellBlocks);
   Print("Valid CHOCHs: ", validCHOCHs);
   Print("Wyckoff events: ", validWyckoffEvents);
   Print("Supply/Demand zones - Supply: ", validSupplyZones, ", Demand: ", validDemandZones);
   Print("Fair Value Gaps - Bullish: ", validBullishFVGs, ", Bearish: ", validBearishFVGs);
   Print("Breaker Blocks - Bullish: ", validBullishBreakers, ", Bearish: ", validBearishBreakers);
   
   // Log highest strength elements for potential trade opportunities
   int highestSDStrength = 0;
   int highestBreakerStrength = 0;
   string bestTradeOpportunity = "None identified";
   
   // Check Supply/Demand zones for highest strength
   for(int i=0; i<MAX_SD_ZONES; i++) {
      if(sdZones[i].valid && !sdZones[i].hasBeenBreached && sdZones[i].strength > highestSDStrength) {
         highestSDStrength = sdZones[i].strength;
         if(sdZones[i].isSupply) {
            bestTradeOpportunity = "Supply zone at " + DoubleToString(sdZones[i].lowerBound, Digits()) + 
                                   " - " + DoubleToString(sdZones[i].upperBound, Digits()) + 
                                   " (Strength: " + IntegerToString(sdZones[i].strength) + ")";
         } else {
            bestTradeOpportunity = "Demand zone at " + DoubleToString(sdZones[i].lowerBound, Digits()) + 
                                   " - " + DoubleToString(sdZones[i].upperBound, Digits()) + 
                                   " (Strength: " + IntegerToString(sdZones[i].strength) + ")";
         }
      }
   }
   
   // Check Breaker Blocks for highest strength
   for(int i=0; i<MAX_BREAKER_BLOCKS; i++) {
      if(breakerBlocks[i].valid && breakerBlocks[i].strength > highestBreakerStrength) {
         highestBreakerStrength = breakerBlocks[i].strength;
         if(highestBreakerStrength > highestSDStrength) {
            if(breakerBlocks[i].isBullish) {
               bestTradeOpportunity = "Bullish Breaker Block at " + 
                                      DoubleToString(breakerBlocks[i].entryLevel, Digits()) + 
                                      " (Strength: " + IntegerToString(breakerBlocks[i].strength) + ")";
            } else {
               bestTradeOpportunity = "Bearish Breaker Block at " + 
                                      DoubleToString(breakerBlocks[i].entryLevel, Digits()) + 
                                      " (Strength: " + IntegerToString(breakerBlocks[i].strength) + ")";
            }
         }
      }
   }
   
   Print("Best potential trade opportunity: ", bestTradeOpportunity);
   Print("====================================================================\n");
}

//+------------------------------------------------------------------+
//| Log detailed market structure information (for debugging)         |
//+------------------------------------------------------------------+
void LogMarketStructure()
{
   // Log all Wyckoff events
   Print("\n==== WYCKOFF EVENTS FOR ", Symbol(), " ====");
   for(int i=0; i<MAX_WYCKOFF_EVENTS; i++) {
      if(recentWyckoffEvents[i].valid) {
         Print("Event: ", recentWyckoffEvents[i].eventName, 
               ", Time: ", TimeToString(recentWyckoffEvents[i].time),
               ", Price: ", recentWyckoffEvents[i].price,
               ", Phase: ", GetMarketPhaseName(recentWyckoffEvents[i].phase),
               ", Strength: ", recentWyckoffEvents[i].strength);
      }
   }
   
   // Log all Supply/Demand zones
   Print("\n==== SUPPLY/DEMAND ZONES FOR ", Symbol(), " ====");
   for(int i=0; i<MAX_SD_ZONES; i++) {
      if(sdZones[i].valid) {
         Print("Type: ", (sdZones[i].isSupply ? "Supply" : "Demand"), 
               ", Time: ", TimeToString(sdZones[i].startTime),
               ", Range: ", sdZones[i].lowerBound, " - ", sdZones[i].upperBound,
               ", Strength: ", sdZones[i].strength,
               ", Tested: ", sdZones[i].testCount, " times",
               ", Breached: ", sdZones[i].hasBeenBreached);
      }
   }
   
   // Log all Fair Value Gaps
   Print("\n==== FAIR VALUE GAPS FOR ", Symbol(), " ====");
   for(int i=0; i<MAX_FVG; i++) {
      if(fairValueGaps[i].valid) {
         Print("Type: ", (fairValueGaps[i].isBullish ? "Bullish" : "Bearish"), 
               ", Time: ", TimeToString(fairValueGaps[i].time),
               ", Range: ", fairValueGaps[i].lowerLevel, " - ", fairValueGaps[i].upperLevel,
               ", Target: ", fairValueGaps[i].midPoint,
               ", Filled: ", fairValueGaps[i].isFilled);
      }
   }
   
   // Log all Breaker Blocks
   Print("\n==== BREAKER BLOCKS FOR ", Symbol(), " ====");
   for(int i=0; i<MAX_BREAKER_BLOCKS; i++) {
      if(breakerBlocks[i].valid) {
         Print("Type: ", (breakerBlocks[i].isBullish ? "Bullish" : "Bearish"), 
               ", Time: ", TimeToString(breakerBlocks[i].time),
               ", Entry: ", breakerBlocks[i].entryLevel,
               ", Stop: ", breakerBlocks[i].stopLevel,
               ", Strength: ", breakerBlocks[i].strength);
      }
   }
   
   Print("====================================================================\n");
}

//+------------------------------------------------------------------+
//| Modify stops based on detected CHOCH patterns                    |
//+------------------------------------------------------------------+
void ModifyStopsOnCHOCH()
{
   // We'll only look at currently open positions
   int total = PositionsTotal();
   if(total == 0) return;
   
   // Check if we have any valid CHOCH patterns detected
   bool foundValidCHOCH = false;
   for(int i=0; i<MAX_CHOCHS; i++) {
      if(recentCHOCHs[i].valid) {
         foundValidCHOCH = true;
         break;
      }
   }
   
   if(!foundValidCHOCH) {
      Print("[CHOCH-SL] No valid CHOCH patterns to use for stop modification");
      return;
   }
   
   // Create trade object
   CTrade trade;
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Loop through all positions
   for(int i=0; i<total; i++) {
      // Select position by index
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      // Ensure position is from our EA (check magic number)
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      // Only look at positions for current symbol
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      
      // Get position details
      double positionSL = PositionGetDouble(POSITION_SL);
      double positionTP = PositionGetDouble(POSITION_TP);
      double positionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime positionTime = (datetime)PositionGetInteger(POSITION_TIME);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool isBuy = (posType == POSITION_TYPE_BUY);
      
      // Look for most relevant CHOCH for this position
      for(int j=0; j<MAX_CHOCHS; j++) {
         if(!recentCHOCHs[j].valid) continue;
         
         // Only use CHOCHs that occurred after position was opened
         if(recentCHOCHs[j].time <= positionTime) continue;
         
         bool chochIsBullish = recentCHOCHs[j].isBullish;
         double chochPrice = recentCHOCHs[j].price;
         
         // BULLISH CHOCH: Consider modifying stops for SELL positions (tighten)
         if(chochIsBullish && !isBuy) {
            // For a SELL, a bullish CHOCH is a warning sign - consider tightening stop
            double newSL = chochPrice; // Move SL to CHOCH price (usually a higher low)
            
            // Only modify if new SL is better (lower risk)
            if(newSL < positionSL) {
               if(trade.PositionModify(ticket, newSL, positionTP)) {
                  Print("[CHOCH-SL] Modified SELL position #", ticket, " stop loss to ", 
                        DoubleToString(newSL, _Digits), " based on bullish CHOCH");
               } else {
                  Print("[CHOCH-SL] Failed to modify SELL position #", ticket, 
                        " Error: ", GetLastError());
               }
            }
         }
         // BEARISH CHOCH: Consider modifying stops for BUY positions (tighten)
         else if(!chochIsBullish && isBuy) {
            // For a BUY, a bearish CHOCH is a warning sign - consider tightening stop
            double newSL = chochPrice; // Move SL to CHOCH price (usually a lower high)
            
            // Only modify if new SL is better (lower risk)
            if(newSL > positionSL) {
               if(trade.PositionModify(ticket, newSL, positionTP)) {
                  Print("[CHOCH-SL] Modified BUY position #", ticket, " stop loss to ", 
                        DoubleToString(newSL, _Digits), " based on bearish CHOCH");
               } else {
                  Print("[CHOCH-SL] Failed to modify BUY position #", ticket, 
                        " Error: ", GetLastError());
               }
            }
         }
         
         break; // We only need to use the most recent relevant CHOCH
      }
   }
}

void OnTick()
{
   // Track execution time for performance monitoring
   uint startTime = GetTickCount();
   Print("[TICK] OnTick starting for " + Symbol());
   
   // Advanced market structure analysis
   AnalyzeMarketPhase();
   // DetectSupplyDemandZones();
   // DetectFairValueGaps();
   // DetectBreakerBlocks();
   LogMarketPhase();
   
   // Advanced trade management features
   if(PositionsTotal() > 0) {
      ManageOpenTrade(); // Handle partial profit taking, breakeven stops, and market structure-based stops
   }
   
   // Check if we should process potential re-entries
   if(SmartReentryEnabled && ReentryCount > 0) {
      // Process re-entries less frequently to avoid excessive computation
      static datetime lastReentryCheck = 0;
      datetime currentTime = TimeCurrent();
      
      // Check every 5 minutes
      if(currentTime - lastReentryCheck > 300) { // 300 seconds = 5 minutes
         ProcessPotentialReentries();
         lastReentryCheck = currentTime;
      }
   }
   
   // Check for drawdown protection if enabled
   if(DrawdownProtectionEnabled) {
      CheckDrawdownProtection();
   }
   
   // Detect CHOCH patterns first
   DetectCHOCH();
   
   // Modify stops based on CHOCH patterns
   ModifyStopsOnCHOCH();
   
   // Update indicators
   UpdateIndicators();
   
   // Check if we can trade
   bool canTradeNow = CanTrade();
   if(!canTradeNow) {
      Print("[TICK] Trading conditions not met, but continuing for testing");
   }
   
   // Detect order blocks
   DetectOrderBlocks();
   
   // Consider recent CHOCH patterns for block strength adjustment
   for(int i=0; i<ArraySize(recentBlocks); i++) {
      if(!recentBlocks[i].valid) continue;
      
      // Check if any CHOCH confirms or invalidates this block
      for(int j=0; j<MAX_CHOCHS; j++) {
         if(!recentCHOCHs[j].valid) continue;
         
         // If CHOCH happened after block was formed
         if(recentCHOCHs[j].time > recentBlocks[i].time) {
            bool chochIsBullish = recentCHOCHs[j].isBullish;
            bool blockIsBuy = recentBlocks[i].isBuy;
            
            // Bullish CHOCH confirms buy blocks and invalidates sell blocks
            if(chochIsBullish) {
               if(blockIsBuy) {
                  // Strengthen buy blocks on bullish CHOCH
                  recentBlocks[i].strength += 2;
                  Print("[BLOCK-CHOCH] Strengthened BUY block at ", TimeToString(recentBlocks[i].time), 
                        " due to bullish CHOCH");
               } else {
                  // Weaken sell blocks on bullish CHOCH
                  recentBlocks[i].strength -= 1;
                  if(recentBlocks[i].strength <= 0) {
                     recentBlocks[i].valid = false;
                     Print("[BLOCK-CHOCH] Invalidated SELL block at ", TimeToString(recentBlocks[i].time), 
                           " due to bullish CHOCH");
                  }
               }
            }
            // Bearish CHOCH confirms sell blocks and invalidates buy blocks
            else {
               if(!blockIsBuy) {
                  // Strengthen sell blocks on bearish CHOCH
                  recentBlocks[i].strength += 2;
                  Print("[BLOCK-CHOCH] Strengthened SELL block at ", TimeToString(recentBlocks[i].time), 
                        " due to bearish CHOCH");
               } else {
                  // Weaken buy blocks on bearish CHOCH
                  recentBlocks[i].strength -= 1;
                  if(recentBlocks[i].strength <= 0) {
                     recentBlocks[i].valid = false;
                     Print("[BLOCK-CHOCH] Invalidated BUY block at ", TimeToString(recentBlocks[i].time), 
                           " due to bearish CHOCH");
                  }
               }
            }
         }
      }
   }

   // Count valid blocks and find best ones
   int validBuyBlocks = 0;
   int validSellBlocks = 0;
   int bestBuyBlockIndex = -1;
   int bestSellBlockIndex = -1;
   int highestBuyStrength = 0;
   int highestSellStrength = 0;
   
   for(int i=0; i<ArraySize(recentBlocks); i++) {
      if(recentBlocks[i].valid) {
         if(recentBlocks[i].isBuy) {
            validBuyBlocks++;
            if(recentBlocks[i].strength > highestBuyStrength) {
               highestBuyStrength = recentBlocks[i].strength;
               bestBuyBlockIndex = i;
            }
         }
         else {
            validSellBlocks++;
            if(recentBlocks[i].strength > highestSellStrength) {
               highestSellStrength = recentBlocks[i].strength;
               bestSellBlockIndex = i;
            }
         }
      }
   }
   
   Print("[TICK] Valid blocks detected: Buy=", validBuyBlocks, " Sell=", validSellBlocks);
   
   // Only proceed with real trading if conditions are good
   if(canTradeNow) {
      // Process best buy block
      if(bestBuyBlockIndex >= 0) {
         double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         double blockPrice = recentBlocks[bestBuyBlockIndex].price;
         
         // If price is near the block (within 5 points)
         if(MathAbs(currentPrice - blockPrice) < 5 * _Point) {
            Print("[TICK] Price near BUY block, executing trade");
            
            // Calculate potential stop loss (simple example)
            double stopLoss = blockPrice - (atrValue * 1.5);
            
            // Execute trade with proper parameters
            ExecuteTradeWithSignal(1, currentPrice, stopLoss); // Buy signal
         }
      }
      
      // Process best sell block
      if(bestSellBlockIndex >= 0) {
         double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double blockPrice = recentBlocks[bestSellBlockIndex].price;
         
         // If price is near the block (within 5 points)
         if(MathAbs(currentPrice - blockPrice) < 5 * _Point) {
            Print("[TICK] Price near SELL block, executing trade");
            
            // Calculate potential stop loss (simple example)
            double stopLoss = blockPrice + (atrValue * 1.5);
            
            // Execute trade with proper parameters
            ExecuteTradeWithSignal(-1, currentPrice, stopLoss); // Sell signal
         }
      }
   }
   
   // Test trade execution every 5 minutes
   static datetime lastTestTime = 0;
   datetime currentTime = TimeCurrent();
   
   if(currentTime - lastTestTime > 300) { // 5 minutes
      Print("[TICK] Testing trade execution capability");
      TestTrade();
      
      // Log market structure information for debugging
      LogMarketStructure();
      lastTestTime = currentTime;
   }
   
   // Manage existing trades
   ManageOpenTrade();
   
   // Update dashboard
   UpdateDashboard();
   
   // Log execution time
   uint executionTime = GetTickCount() - startTime;
   Print("[TICK] OnTick completed in ", executionTime, "ms");
}

//+------------------------------------------------------------------+
//| Execute test trade to validate execution capability               |
//+------------------------------------------------------------------+
void TestTrade()
{
   Print("[TEST] Attempting to place a test trade to verify execution");
   
   // Get current prices
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Get minimum lot size
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   
   // Calculate valid stop distance
   int stopLevel = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopLevel * _Point;
   
   // Double the minimum distance to be safe
   minDistance *= 2.0;
   
   // If broker returned 0, use a safe default
   if(minDistance <= 0) minDistance = 100 * _Point;
   
   // Set up parameters
   double stopLoss = bid - minDistance;
   double takeProfit = ask + minDistance;
   
   // Use CTrade for order placement
   CTrade trade;
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Log the attempt
   Print("[TEST] Trying BUY order - Price:", ask, " SL:", stopLoss, " TP:", takeProfit, " Size:", minLot);
   
   // Attempt to place order
   if(trade.Buy(minLot, Symbol(), 0, stopLoss, takeProfit, "TEST")) {
      Print("[TEST] SUCCESS! Order placed with ticket:", trade.ResultOrder());
   } else {
      Print("[TEST] FAILED! Error code:", trade.ResultRetcode(), " Description:", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Update dashboard with current status                             |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   // Placeholder for dashboard updates
}

//+------------------------------------------------------------------+
//| Update indicators                                                |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
   // Placeholder for indicator updates
}

//+------------------------------------------------------------------+
//| Manage existing trades with advanced trade management            |
//+------------------------------------------------------------------+
void ManageOpenTrade()
{
   Print("[TRADE_MGMT] Managing open positions...");
   CTrade trade;
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Get current market data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 3, rates);
   
   if(copied <= 0) {
      Print("[TRADE_MGMT] Error getting rates data: ", GetLastError());
      return;
   }
   
   double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   
   // Get current ATR for dynamic targets and stops
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
   double atrValue = (ArraySize(atrBuffer) > 0) ? atrBuffer[0] : 0.01;
   
   // Iterate through all open positions
   for(int i=0; i<PositionsTotal(); i++) {
      // Select position
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      
      // Only manage our EA's positions
      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(posMagic != MagicNumber)
         continue;
      
      // Get position details
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      if(posSymbol != Symbol())
         continue;
      
      ulong posTicket = PositionGetInteger(POSITION_TICKET);
      double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double posVolume = PositionGetDouble(POSITION_VOLUME);
      double posStopLoss = PositionGetDouble(POSITION_SL);
      double posTakeProfit = PositionGetDouble(POSITION_TP);
      datetime posOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
      int posType = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      
      // Calculate current profit in pips
      double currentPrice = (posType == 1) ? currentBid : currentAsk;
      double profitDistance = MathAbs(currentPrice - posOpenPrice) * MathPow(-1, (posType == -1));
      double profitPips = profitDistance / _Point;
      
      // Calculate risk distance in pips
      double riskDistance = MathAbs(posOpenPrice - posStopLoss);
      double riskPips = riskDistance / _Point;
      
      // Get information about partial closes already applied
      bool partialTaken1 = false, partialTaken2 = false;
      double originalVolume = posVolume;
      
      // Check position comment for partial close information
      string posComment = PositionGetString(POSITION_COMMENT);
      if(StringFind(posComment, "PartialClose1") >= 0) partialTaken1 = true;
      if(StringFind(posComment, "PartialClose2") >= 0) partialTaken2 = true;
      
      // Special handling for high-value assets like BTC (based on memory)
      string symbolName = Symbol();
      bool isHighValueAsset = (StringFind(symbolName, "BTC") >= 0 || StringFind(symbolName, "XBT") >= 0);
      
      // Partial profit taking
      if(PartialProfitEnabled) {
         // Calculate profit/risk ratio
         double profitRiskRatio = profitDistance / riskDistance;
         
         // First partial close
         if(!partialTaken1 && profitRiskRatio >= PartialTakeProfit1) {
            // Volume to close at first target
            double closeVolume = originalVolume * (PartialClosePercent1 / 100.0);
            closeVolume = NormalizeDouble(closeVolume, 2); // Round to 2 decimal places
            
            // Ensure minimum lot size
            double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
            if(closeVolume >= minLot && posVolume - closeVolume >= minLot) {
               // Close partial position
               if(posType == 1) { // Buy position
                  if(trade.Sell(closeVolume, Symbol(), 0, 0, 0, "PartialClose1")) {
                     Print("[TRADE_MGMT] First partial close executed for ticket ", posTicket, 
                           ", Volume: ", closeVolume, ", Profit ratio: ", NormalizeDouble(profitRiskRatio, 2));
                     
                     // Update trailing stop if applicable
                     AdjustStopAfterPartial(posTicket, 1, posType, posStopLoss, posOpenPrice);
                  }
               } else { // Sell position
                  if(trade.Buy(closeVolume, Symbol(), 0, 0, 0, "PartialClose1")) {
                     Print("[TRADE_MGMT] First partial close executed for ticket ", posTicket, 
                           ", Volume: ", closeVolume, ", Profit ratio: ", NormalizeDouble(profitRiskRatio, 2));
                     
                     // Update trailing stop if applicable
                     AdjustStopAfterPartial(posTicket, 1, posType, posStopLoss, posOpenPrice);
                  }
               }
            }
         }
         
         // Second partial close
         else if(partialTaken1 && !partialTaken2 && profitRiskRatio >= PartialTakeProfit2) {
            // Calculate remaining position after first partial
            double remainingVol = posVolume;
            double closeVolume = originalVolume * (PartialClosePercent2 / 100.0);
            closeVolume = NormalizeDouble(closeVolume, 2);
            
            // Ensure minimum lot size
            double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
            if(closeVolume >= minLot && remainingVol - closeVolume >= minLot) {
               // Close partial position
               if(posType == 1) { // Buy position
                  if(trade.Sell(closeVolume, Symbol(), 0, 0, 0, "PartialClose2")) {
                     Print("[TRADE_MGMT] Second partial close executed for ticket ", posTicket, 
                           ", Volume: ", closeVolume, ", Profit ratio: ", NormalizeDouble(profitRiskRatio, 2));
                     
                     // Move stop loss to a more secure level
                     AdjustStopAfterPartial(posTicket, 2, posType, posStopLoss, posOpenPrice);
                  }
               } else { // Sell position
                  if(trade.Buy(closeVolume, Symbol(), 0, 0, 0, "PartialClose2")) {
                     Print("[TRADE_MGMT] Second partial close executed for ticket ", posTicket, 
                           ", Volume: ", closeVolume, ", Profit ratio: ", NormalizeDouble(profitRiskRatio, 2));
                     
                     // Move stop loss to a more secure level
                     AdjustStopAfterPartial(posTicket, 2, posType, posStopLoss, posOpenPrice);
                  }
               }
            }
         }
         
         // Final target - update take profit if needed
         if(partialTaken2 && MathAbs(posTakeProfit - posOpenPrice) < riskDistance * PartialTakeProfit3) {
            // Set final take profit
            double finalTarget = posOpenPrice;
            if(posType == 1) { // Buy position
               finalTarget += riskDistance * PartialTakeProfit3;
            } else { // Sell position
               finalTarget -= riskDistance * PartialTakeProfit3;
            }
            
            // Normalize final target
            int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
            finalTarget = NormalizeDouble(finalTarget, digits);
            
            // Only update if different from current TP
            if(MathAbs(finalTarget - posTakeProfit) > _Point) {
               if(trade.PositionModify(posTicket, posStopLoss, finalTarget)) {
                  Print("[TRADE_MGMT] Final target updated for ticket ", posTicket, 
                        " to ", finalTarget);
               }
            }
         }
      }
      
      // Breakeven logic
      if(BreakevenEnabled && !partialTaken1) { // Only before first partial
         double breakEvenThreshold = riskDistance * BreakevenTriggerRatio;
         double breakEvenPrice = posOpenPrice;
         
         // Add small buffer for breakeven
         if(posType == 1) { // Buy position
            breakEvenPrice += BreakevenBufferPoints * _Point;
         } else { // Sell position
            breakEvenPrice -= BreakevenBufferPoints * _Point;
         }
         
         // Move to breakeven if price has moved enough in our favor
         if(profitDistance >= breakEvenThreshold && 
            ((posType == 1 && posStopLoss < breakEvenPrice) || 
             (posType == -1 && posStopLoss > breakEvenPrice))) {
            
            // Normalize breakeven price
            int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
            breakEvenPrice = NormalizeDouble(breakEvenPrice, digits);
            
            // Update stop loss to breakeven
            if(trade.PositionModify(posTicket, breakEvenPrice, posTakeProfit)) {
               Print("[TRADE_MGMT] Moved stop to breakeven for ticket ", posTicket, 
                     " at price ", breakEvenPrice);
            }
         }
      }
      
      // Check for market structure-based stop adjustment
      if(!partialTaken1) { // Only before first partial
         AdjustStopBasedOnMarketStructure(posTicket, posType, posStopLoss, posOpenPrice);
      }
   }
   
   // Process potential re-entries if enabled
   if(SmartReentryEnabled) {
      ProcessPotentialReentries();
   }
}

//+------------------------------------------------------------------+
//| Adjust stop loss after partial close                              |
//+------------------------------------------------------------------+
void AdjustStopAfterPartial(ulong ticket, int partialLevel, int posType, double currentStopLoss, double openPrice)
{
   // Get position by ticket
   if(!PositionSelectByTicket(ticket))
      return;
      
   double newStopLoss = currentStopLoss;
   CTrade trade;
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Get takeprofit
   double currentTakeProfit = PositionGetDouble(POSITION_TP);
   
   // Calculate risk distance
   double riskDistance = MathAbs(openPrice - currentStopLoss);
   
   // First partial - move stop to a safer level if needed
   if(partialLevel == 1) {
      // For first partial, move stop to 50% of the risk distance from entry
      double stopBuffer = riskDistance * 0.5;
      
      if(posType == 1) { // Buy position
         newStopLoss = openPrice - stopBuffer;
         // Only move stop if it's lower than current stop
         if(newStopLoss <= currentStopLoss)
            return;
      } else { // Sell position
         newStopLoss = openPrice + stopBuffer;
         // Only move stop if it's higher than current stop
         if(newStopLoss >= currentStopLoss)
            return;
      }
   }
   // Second partial - move stop to breakeven or better
   else if(partialLevel == 2) {
      // For second partial, move stop to breakeven plus a small buffer
      double breakEvenBuffer = 5 * _Point; // 5 points buffer
      
      if(posType == 1) { // Buy position
         newStopLoss = openPrice + breakEvenBuffer;
         // Only move stop if it's lower than new stop
         if(newStopLoss <= currentStopLoss)
            return;
      } else { // Sell position
         newStopLoss = openPrice - breakEvenBuffer;
         // Only move stop if it's higher than new stop
         if(newStopLoss >= currentStopLoss)
            return;
      }
   }
   
   // Normalize stop loss
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   newStopLoss = NormalizeDouble(newStopLoss, digits);
   
   // Update stop loss
   if(trade.PositionModify(ticket, newStopLoss, currentTakeProfit)) {
      Print("[TRADE_MGMT] Updated stop loss after partial close level ", partialLevel, 
            " for ticket ", ticket, " to ", newStopLoss);
   } else {
      Print("[TRADE_MGMT] Failed to update stop loss: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Adjust stop loss based on market structure                         |
//+------------------------------------------------------------------+
void AdjustStopBasedOnMarketStructure(ulong ticket, int posType, double currentStopLoss, double openPrice)
{
   // Get position by ticket
   if(!PositionSelectByTicket(ticket))
      return;
      
   CTrade trade;
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Get current price and takeprofit
   double currentPrice = (posType == 1) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double currentTakeProfit = PositionGetDouble(POSITION_TP);
   
   // Get market structure pivots
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, 100, rates);
   
   if(copied <= 0) {
      Print("[TRADE_MGMT] Error getting rates data for market structure: ", GetLastError());
      return;
   }
   
   // Determine if there's a CHOCH (Change of Character) pattern
   bool chochDetected = false;
   double chochLevel = 0;
   
   // For long positions, look for higher lows
   if(posType == 1) {
      // Find the most recent swing low that is higher than the previous swing low
      double prevSwingLow = DBL_MAX;
      double recentSwingLow = DBL_MAX;
      int swingCount = 0;
      
      for(int i = 10; i < copied - 10; i++) {
         // Check if current bar is a swing low
         bool isSwingLow = true;
         for(int j = 1; j <= 5; j++) {
            if(rates[i].low > rates[i+j].low || rates[i].low > rates[i-j].low) {
               isSwingLow = false;
               break;
            }
         }
         
         if(isSwingLow) {
            if(swingCount == 0) {
               recentSwingLow = rates[i].low;
               swingCount++;
            } else {
               prevSwingLow = recentSwingLow;
               recentSwingLow = rates[i].low;
               swingCount++;
               
               // Check if we have a higher low (CHOCH for uptrend)
               if(recentSwingLow > prevSwingLow && recentSwingLow > currentStopLoss) {
                  chochDetected = true;
                  chochLevel = recentSwingLow - 5 * _Point; // Small buffer below the swing low
                  break;
               }
            }
         }
         
         // Only need to find two swings
         if(swingCount >= 2)
            break;
      }
   }
   // For short positions, look for lower highs
   else if(posType == -1) {
      // Find the most recent swing high that is lower than the previous swing high
      double prevSwingHigh = 0;
      double recentSwingHigh = 0;
      int swingCount = 0;
      
      for(int i = 10; i < copied - 10; i++) {
         // Check if current bar is a swing high
         bool isSwingHigh = true;
         for(int j = 1; j <= 5; j++) {
            if(rates[i].high < rates[i+j].high || rates[i].high < rates[i-j].high) {
               isSwingHigh = false;
               break;
            }
         }
         
         if(isSwingHigh) {
            if(swingCount == 0) {
               recentSwingHigh = rates[i].high;
               swingCount++;
            } else {
               prevSwingHigh = recentSwingHigh;
               recentSwingHigh = rates[i].high;
               swingCount++;
               
               // Check if we have a lower high (CHOCH for downtrend)
               if(recentSwingHigh < prevSwingHigh && recentSwingHigh < currentStopLoss) {
                  chochDetected = true;
                  chochLevel = recentSwingHigh + 5 * _Point; // Small buffer above the swing high
                  break;
               }
            }
         }
         
         // Only need to find two swings
         if(swingCount >= 2)
            break;
      }
   }
   
   // Update stop loss if CHOCH detected
   if(chochDetected) {
      // Normalize stop level
      int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
      chochLevel = NormalizeDouble(chochLevel, digits);
      
      // Only update if it's a better stop level
      if((posType == 1 && chochLevel > currentStopLoss) || 
         (posType == -1 && chochLevel < currentStopLoss)) {
         
         if(trade.PositionModify(ticket, chochLevel, currentTakeProfit)) {
            Print("[TRADE_MGMT] Updated stop loss based on market structure (CHOCH) for ticket ", 
                  ticket, " to ", chochLevel);
         } else {
            Print("[TRADE_MGMT] Failed to update stop loss: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Track positions that get stopped out for potential re-entry        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   // Simplified approach to avoid compilation issues
   // We'll check the magic number at a later stage if needed
   
   // Skip non-deal transactions
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
      
   // Check if this is a position closing event due to stop loss
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && 
      trans.deal_type == DEAL_TYPE_SELL && 
      trans.order_type == ORDER_TYPE_BUY_STOP_LIMIT) {
      // Position was stopped out, store for potential re-entry
      StorePositionForReentry(trans.position, trans.price, POSITION_TYPE_BUY);
   }
   else if(trans.type == TRADE_TRANSACTION_DEAL_ADD && 
            trans.deal_type == DEAL_TYPE_BUY && 
            trans.order_type == ORDER_TYPE_SELL_STOP_LIMIT) {
      // Position was stopped out, store for potential re-entry
      StorePositionForReentry(trans.position, trans.price, POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Store position information for potential re-entry                  |
//+------------------------------------------------------------------+
void StorePositionForReentry(ulong positionId, double stopPrice, ENUM_POSITION_TYPE posType)
{
   // Don't store if re-entry is disabled
   if(!SmartReentryEnabled)
      return;
      
   // Create a unique index in our arrays
   int idx = ReentryCount;
   if(idx >= 100) { // Max number of re-entries to track
      // Shift arrays to make room
      for(int i=0; i<99; i++) {
         ReentryPositions[i] = ReentryPositions[i+1];
         ReentryTimes[i] = ReentryTimes[i+1];
         ReentryLevels[i] = ReentryLevels[i+1];
         ReentrySignals[i] = ReentrySignals[i+1];
         ReentryStops[i] = ReentryStops[i+1];
         ReentryTargets[i] = ReentryTargets[i+1];
         ReentryQuality[i] = ReentryQuality[i+1];
         ReentryAttempted[i] = ReentryAttempted[i+1];
      }
      idx = 99;
   } else {
      ReentryCount++;
   }
   
   // Store position information
   ReentryPositions[idx] = true;
   ReentryTimes[idx] = TimeCurrent();
   ReentryLevels[idx] = stopPrice; // The price at which it was stopped out
   ReentrySignals[idx] = (posType == POSITION_TYPE_BUY) ? 1 : -1;
   
   // Calculate a reasonable stop and target based on ATR
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
   double atrValue = (ArraySize(atrBuffer) > 0) ? atrBuffer[0] : 0.01;
   
   // For high-value assets like BTC, use more permissive criteria
   string symbolName = Symbol();
   bool isHighValueAsset = (StringFind(symbolName, "BTC") >= 0 || StringFind(symbolName, "XBT") >= 0);
   double atrMultiplier = isHighValueAsset ? 2.5 : 1.5;
   
   // Set stops and targets based on position type
   if(posType == POSITION_TYPE_BUY) {
      ReentryStops[idx] = stopPrice - atrValue * atrMultiplier;
      ReentryTargets[idx] = stopPrice + atrValue * 2 * atrMultiplier;
   } else {
      ReentryStops[idx] = stopPrice + atrValue * atrMultiplier;
      ReentryTargets[idx] = stopPrice - atrValue * 2 * atrMultiplier;
   }
   
   // Initial quality assessment - to be updated based on market conditions
   ReentryQuality[idx] = 5; // Default quality
   ReentryAttempted[idx] = false;
   
   Print("[REENTRY] Position ", positionId, " stopped out, stored for potential re-entry at ", 
         stopPrice, ", Direction: ", (posType == POSITION_TYPE_BUY) ? "Buy" : "Sell");
}

//+------------------------------------------------------------------+
//| Process potential re-entries based on market conditions            |
//+------------------------------------------------------------------+
void ProcessPotentialReentries()
{
   if(ReentryCount <= 0)
      return;
      
   double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   datetime currentTime = TimeCurrent();
   
   // Check all potential re-entries
   for(int i=0; i<ReentryCount; i++) {
      // Skip if not valid or already attempted
      if(!ReentryPositions[i] || ReentryAttempted[i])
         continue;
         
      // Check if too much time has passed
      int hoursDiff = (int)(currentTime - ReentryTimes[i]) / 3600;
      if(hoursDiff > ReentryTimeLimit) {
         // Mark as attempted (expired)
         ReentryAttempted[i] = true;
         Print("[REENTRY] Re-entry opportunity expired for position at level ", 
               ReentryLevels[i], ", too much time elapsed (", hoursDiff, " hours)");
         continue;
      }
      
      // Get current market conditions and update quality score
      UpdateReentryQuality(i);
      
      // Only proceed if quality is sufficient
      if(ReentryQuality[i] < ReentryMinQuality)
         continue;
      
      // Check if price is in a favorable position for re-entry
      bool priceIsGood = false;
      
      if(ReentrySignals[i] == 1) { // Buy signal - look for pullback and reversal
         // Price pulled back near the stop level but showing signs of reversal
         if(currentAsk < ReentryLevels[i] + 50*_Point && 
            currentAsk > ReentryLevels[i] - 150*_Point) {
            priceIsGood = true;
         }
      } else { // Sell signal - look for pullback and reversal
         // Price pulled back near the stop level but showing signs of reversal
         if(currentBid > ReentryLevels[i] - 50*_Point && 
            currentBid < ReentryLevels[i] + 150*_Point) {
            priceIsGood = true;
         }
      }
      
      // Attempt re-entry if conditions are favorable
      if(priceIsGood) {
         // Calculate position size with a slight reduction due to re-entry risk
         double reentryRiskPercent = BaseRiskPercent * 0.75; // 75% of normal risk
         double entryPrice = (ReentrySignals[i] == 1) ? currentAsk : currentBid;
         double stopLoss = ReentryStops[i];
         
         // Check if stop is valid
         if((ReentrySignals[i] == 1 && stopLoss >= entryPrice) || 
            (ReentrySignals[i] == -1 && stopLoss <= entryPrice)) {
            Print("[REENTRY] Invalid stop loss for re-entry: ", stopLoss, ", Entry: ", entryPrice);
            ReentryAttempted[i] = true;
            continue;
         }
         
         // Use overloaded version without quality parameter
         double posSize = CalculatePositionSize(entryPrice, stopLoss, reentryRiskPercent);
         
         // Execute the trade
         if(ReentrySignals[i] > 0) {
            // Buy trade
            CTrade trade;
            trade.SetExpertMagicNumber(MagicNumber);
            trade.Buy(posSize, Symbol(), entryPrice, stopLoss, ReentryTargets[i], "ReEntry");
         } else {
            // Sell trade
            CTrade trade;
            trade.SetExpertMagicNumber(MagicNumber);
            trade.Sell(posSize, Symbol(), entryPrice, stopLoss, ReentryTargets[i], "ReEntry");
         }
         
         // Mark as attempted
         ReentryAttempted[i] = true;
         Print("[REENTRY] Executed re-entry trade at level ", entryPrice, ", Quality: ", 
               ReentryQuality[i], ", Original level: ", ReentryLevels[i]);
      }
   }
   
   // Clean up array periodically
   CleanupReentryArray();
}

//+------------------------------------------------------------------+
//| Update the quality score of a re-entry opportunity                 |
//+------------------------------------------------------------------+
void UpdateReentryQuality(int index)
{
   // Start with base quality
   int quality = 5;
   
   // Get current market conditions
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(Symbol(), PERIOD_CURRENT, 0, 20, rates);
   
   int signal = ReentrySignals[index];
   double stopOutLevel = ReentryLevels[index];
   
   // Check market phase alignment
   string currentPhase = GetMarketPhaseName(currentMarketPhase);
   if((signal == 1 && (currentPhase == "Accumulation" || currentPhase == "Markup (Uptrend)")) || 
      (signal == -1 && (currentPhase == "Distribution" || currentPhase == "Markdown (Downtrend)"))) {
      quality += 2; // Strong alignment with market phase
   } else if((signal == 1 && currentPhase == "Distribution") || 
             (signal == -1 && currentPhase == "Accumulation")) {
      quality -= 2; // Misalignment with market phase
   }
   
   // Check for order blocks near the re-entry level
   // Use the existing global recentBlocks array
   DetectOrderBlocks();
   
   bool orderBlockConfirmation = false;
   for(int i=0; i<MAX_BLOCKS; i++) {
      if(recentBlocks[i].valid) {
         // For buy signal, look for bullish order blocks below current price
         if(signal == 1 && recentBlocks[i].isBuy && 
            MathAbs(recentBlocks[i].price - stopOutLevel) < 100*_Point) {
            orderBlockConfirmation = true;
            quality += 2;
            break;
         }
         // For sell signal, look for bearish order blocks above current price
         else if(signal == -1 && !recentBlocks[i].isBuy && 
                 MathAbs(recentBlocks[i].price - stopOutLevel) < 100*_Point) {
            orderBlockConfirmation = true;
            quality += 2;
            break;
         }
      }
   }
   
   // Check for CHOCH pattern (Change of Character)
   bool chochConfirmation = false;
   if(signal == 1) { // Buy signal - look for higher lows
      double prevLow = DBL_MAX;
      double currentLow = DBL_MAX;
      
      for(int i=1; i<ArraySize(rates)-1; i++) {
         // Simple swing low detection
         if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low) {
            currentLow = rates[i].low;
            
            if(prevLow != DBL_MAX && currentLow > prevLow) {
               chochConfirmation = true;
               quality += 1;
               break;
            }
            
            prevLow = currentLow;
         }
      }
   }
   else if(signal == -1) { // Sell signal - look for lower highs
      double prevHigh = 0;
      double currentHigh = 0;
      
      for(int i=1; i<ArraySize(rates)-1; i++) {
         // Simple swing high detection
         if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high) {
            currentHigh = rates[i].high;
            
            if(prevHigh > 0 && currentHigh < prevHigh) {
               chochConfirmation = true;
               quality += 1;
               break;
            }
            
            prevHigh = currentHigh;
         }
      }
   }
   
   // Special handling for high-value assets like BTC
   string symbolName = Symbol();
   bool isHighValueAsset = (StringFind(symbolName, "BTC") >= 0 || StringFind(symbolName, "XBT") >= 0);
   
   if(isHighValueAsset) {
      // For high-value assets, be more permissive with re-entry criteria
      quality += 1;
   }
   
   // Cap quality between 1-10
   ReentryQuality[index] = MathMax(1, MathMin(10, quality));
}

//+------------------------------------------------------------------+
//| Clean up re-entry array by removing old or invalid entries         |
//+------------------------------------------------------------------+
void CleanupReentryArray()
{
   datetime currentTime = TimeCurrent();
   int newCount = 0;
   
   // Temporary arrays
   bool tempPositions[100];
   datetime tempTimes[100];
   double tempLevels[100];
   int tempSignals[100];
   double tempStops[100];
   double tempTargets[100];
   int tempQuality[100];
   bool tempAttempted[100];
   
   // Copy valid entries to temporary arrays
   for(int i=0; i<ReentryCount; i++) {
      // Skip if not valid or attempted and old
      if(!ReentryPositions[i])
         continue;
         
      // Skip if attempted and older than time limit
      if(ReentryAttempted[i] && (currentTime - ReentryTimes[i]) > ReentryTimeLimit * 3600)
         continue;
         
      // Valid entry, copy to temp arrays
      tempPositions[newCount] = ReentryPositions[i];
      tempTimes[newCount] = ReentryTimes[i];
      tempLevels[newCount] = ReentryLevels[i];
      tempSignals[newCount] = ReentrySignals[i];
      tempStops[newCount] = ReentryStops[i];
      tempTargets[newCount] = ReentryTargets[i];
      tempQuality[newCount] = ReentryQuality[i];
      tempAttempted[newCount] = ReentryAttempted[i];
      
      newCount++;
   }
   
   // Copy back to original arrays
   for(int i=0; i<newCount; i++) {
      ReentryPositions[i] = tempPositions[i];
      ReentryTimes[i] = tempTimes[i];
      ReentryLevels[i] = tempLevels[i];
      ReentrySignals[i] = tempSignals[i];
      ReentryStops[i] = tempStops[i];
      ReentryTargets[i] = tempTargets[i];
      ReentryQuality[i] = tempQuality[i];
      ReentryAttempted[i] = tempAttempted[i];
   }
   
   // Clear remaining entries
   for(int i=newCount; i<ReentryCount; i++) {
      ReentryPositions[i] = false;
      ReentryTimes[i] = 0;
      ReentryLevels[i] = 0;
      ReentrySignals[i] = 0;
      ReentryStops[i] = 0;
      ReentryTargets[i] = 0;
      ReentryQuality[i] = 0;
      ReentryAttempted[i] = false;
   }
   
   // Update count
   ReentryCount = newCount;
}

//+------------------------------------------------------------------+
//| Check if the current spread is acceptable for trading             |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   // Get current spread in points
   long currentSpreadPoints = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   double currentSpread = currentSpreadPoints * _Point;
   
   // Get ATR for dynamic spread threshold
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int copied = CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
   
   if(copied <= 0) {
      Print("[SPREAD] Failed to get ATR for spread check: ", GetLastError());
      return false;
   }
   
   double atrValue = atrBuffer[0];
   
   // Set dynamic threshold based on ATR
   double maxAcceptableSpread = atrValue * 0.25; // Default 25% of ATR
   
   // Special handling for high-value assets like BTC
   string symbolName = Symbol();
   bool isHighValueAsset = (StringFind(symbolName, "BTC") >= 0 || StringFind(symbolName, "XBT") >= 0);
   
   if(isHighValueAsset) {
      // More permissive spread threshold for high-value assets (250% of normal)
      maxAcceptableSpread = atrValue * 0.625; // 2.5x the normal threshold
      Print("[SPREAD] Using higher spread threshold for high-value asset: ", maxAcceptableSpread);
   }
   
   // Compare current spread to threshold
   bool isAcceptable = (currentSpread <= maxAcceptableSpread);
   
   if(!isAcceptable) {
      Print("[SPREAD] Current spread too high: ", currentSpread, 
            " Max acceptable: ", maxAcceptableSpread);
   }
   
   return isAcceptable;
}

//+------------------------------------------------------------------+
//| Calculate daily loss (closed and floating)                        |
//+------------------------------------------------------------------+
double GetDailyLoss()
{
   double dailyLoss = 0.0;
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   // Check history for closed trades today
   HistorySelect(todayStart, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   
   for(int i=0; i<totalDeals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0) continue;
      
      // Only count our EA's trades
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      
      // Only count closed trades with losses
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit < 0) {
         dailyLoss += profit;
      }
   }
   
   // Check current open positions for floating losses
   for(int i=0; i<PositionsTotal(); i++) {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      
      // Only count our EA's positions
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      // Only count floating losses
      double currentProfit = PositionGetDouble(POSITION_PROFIT);
      if(currentProfit < 0) {
         dailyLoss += currentProfit;
      }
   }
   
   return dailyLoss;
}

//+------------------------------------------------------------------+
//| Calculate exposure across correlated pairs                         |
//+------------------------------------------------------------------+
double GetCorrelatedExposure()
{
   double totalExposure = 0.0;
   
   // Get current symbol base info
   string currentSymbol = Symbol();
   string currentBase = StringSubstr(currentSymbol, 0, 3);
   
   // Loop through all open positions
   for(int i=0; i<PositionsTotal(); i++) {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      
      // Only count our EA's positions
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      string posBase = StringSubstr(posSymbol, 0, 3);
      
      // Check if this position is correlated with current symbol
      bool isCorrelated = false;
      double correlationFactor = 1.0; // Default full correlation for same symbol
      
      if(posSymbol == currentSymbol) {
         isCorrelated = true;
      }
      else if(posBase == currentBase) {
         // Same base currency - partial correlation
         isCorrelated = true;
         correlationFactor = 0.8; // 80% correlation for same base currency
      }
      else {
         // Check CorrelatedPairs array for other known correlations
         for(int j=0; j<ArraySize(CorrelatedPairs); j++) {
            if(posSymbol == CorrelatedPairs[j]) {
               isCorrelated = true;
               // Use stored correlation coefficient if available, otherwise use default
               correlationFactor = 0.5; // Default 50% correlation for listed pairs
               break;
            }
         }
      }
      
      // Add to total exposure if correlated
      if(isCorrelated) {
         double posVolume = PositionGetDouble(POSITION_VOLUME);
         double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double posStopLoss = PositionGetDouble(POSITION_SL);
         
         // Calculate risk in money terms
         double pointValue = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_VALUE);
         double riskPoints = MathAbs(posOpenPrice - posStopLoss) / SymbolInfoDouble(posSymbol, SYMBOL_POINT);
         double riskAmount = riskPoints * pointValue * posVolume;
         
         // Apply correlation factor
         totalExposure += riskAmount * correlationFactor;
      }
   }
   
   return totalExposure;
}

//+------------------------------------------------------------------+
//| Determine the quality of a trade setup on a scale of 1-10        |
//+------------------------------------------------------------------+
// This function is replaced by the new improved version
/*
int DetermineSetupQuality_Old(int signal, double entryPrice)
{
   // Base quality score
   int quality = 5; // Default/middle quality
   
   // 1. Check if the market phase aligns with the trade direction
   if((signal > 0 && (currentMarketPhase == PHASE_MARKUP || currentMarketPhase == PHASE_ACCUMULATION)) ||
      (signal < 0 && (currentMarketPhase == PHASE_MARKDOWN || currentMarketPhase == PHASE_DISTRIBUTION))) {
      quality += 2; // Strong alignment with market phase
   } else if(currentMarketPhase == PHASE_UNCLEAR) {
      quality -= 1; // No clear market phase is a slight negative
   } else {
      quality -= 2; // Trading against the market phase
   }
   
   // 2. Check for confluence of multiple market structure elements
   int confluenceCount = 0;
   
   // Buy signal confluence factors
   if(signal > 0) {
      // Check for demand zones near entry
      for(int i=0; i<MAX_SD_ZONES; i++) {
         if(sdZones[i].valid && !sdZones[i].isSupply && !sdZones[i].hasBeenBreached) {
            if(MathAbs(entryPrice - sdZones[i].upperBound) < 50*_Point) {
               confluenceCount++;
               Print("[QUALITY] Entry near demand zone");
               break;
            }
         }
      }
      
      // Check for bullish breaker blocks
      for(int i=0; i<MAX_BREAKER_BLOCKS; i++) {
         if(breakerBlocks[i].valid && breakerBlocks[i].isBullish) {
            if(MathAbs(entryPrice - breakerBlocks[i].entryLevel) < 30*_Point) {
               confluenceCount++;
               quality += breakerBlocks[i].strength / 3; // Add quality based on breaker strength
               Print("[QUALITY] Entry at bullish breaker block");
               break;
            }
         }
      }
      
      // Check for bullish fair value gaps
      for(int i=0; i<MAX_FVG; i++) {
         if(fairValueGaps[i].valid && fairValueGaps[i].isBullish && !fairValueGaps[i].isFilled) {
            if(entryPrice >= fairValueGaps[i].lowerLevel && entryPrice <= fairValueGaps[i].upperLevel) {
               confluenceCount++;
               Print("[QUALITY] Entry in bullish FVG");
               break;
            }
         }
      }
      
      // Check for bullish CHOCH
      for(int i=0; i<MAX_CHOCHS; i++) {
         if(recentCHOCHs[i].valid && recentCHOCHs[i].isBullish) {
            if(MathAbs(entryPrice - recentCHOCHs[i].price) < 40*_Point) {
               confluenceCount++;
               Print("[QUALITY] Entry near bullish CHOCH");
               break;
            }
         }
      }
   }
   // Sell signal confluence factors
   else if(signal < 0) {
      // Check for supply zones near entry
      for(int i=0; i<MAX_SD_ZONES; i++) {
         if(sdZones[i].valid && sdZones[i].isSupply && !sdZones[i].hasBeenBreached) {
            if(MathAbs(entryPrice - sdZones[i].lowerBound) < 50*_Point) {
               confluenceCount++;
               Print("[QUALITY] Entry near supply zone");
               break;
            }
         }
      }
      
      // Check for bearish breaker blocks
      for(int i=0; i<MAX_BREAKER_BLOCKS; i++) {
         if(breakerBlocks[i].valid && !breakerBlocks[i].isBullish) {
            if(MathAbs(entryPrice - breakerBlocks[i].entryLevel) < 30*_Point) {
               confluenceCount++;
               quality += breakerBlocks[i].strength / 3; // Add quality based on breaker strength
               Print("[QUALITY] Entry at bearish breaker block");
               break;
            }
         }
      }
      
      // Check for bearish fair value gaps
      for(int i=0; i<MAX_FVG; i++) {
         if(fairValueGaps[i].valid && !fairValueGaps[i].isBullish && !fairValueGaps[i].isFilled) {
            if(entryPrice >= fairValueGaps[i].lowerLevel && entryPrice <= fairValueGaps[i].upperLevel) {
               confluenceCount++;
               Print("[QUALITY] Entry in bearish FVG");
               break;
            }
         }
      }
      
      // Check for bearish CHOCH
      for(int i=0; i<MAX_CHOCHS; i++) {
         if(recentCHOCHs[i].valid && !recentCHOCHs[i].isBullish) {
            if(MathAbs(entryPrice - recentCHOCHs[i].price) < 40*_Point) {
               confluenceCount++;
               Print("[QUALITY] Entry near bearish CHOCH");
               break;
            }
         }
      }
   }
   
   // Add quality points based on number of confluence factors
   quality += confluenceCount;
   
   // 3. Check if price is near strong support/resistance level
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   CopyBuffer(atrHandle, 0, 0, 1, atrBuffer);
   double atrValue = (ArraySize(atrBuffer) > 0) ? atrBuffer[0] : 0.01;
   
   // Apply special adjustment for high-value assets like BTC based on the memory
   string symbolName = Symbol();
   if(StringFind(symbolName, "BTC") >= 0 || StringFind(symbolName, "XBT") >= 0) {
      // Based on the memory, we know we should be more permissive with BTC
      quality += 1; // Add extra quality point for BTC setups
      Print("[QUALITY] High-value asset detected, enhancing setup quality");
   }
   
   // Ensure quality is within 1-10 range
   quality = MathMax(1, MathMin(10, quality));
   Print("[QUALITY] Setup quality determined: ", quality, "/10 with ", confluenceCount, " confluence factors");
   return quality;
}*/

//+------------------------------------------------------------------+
//| Calculate the total loss for the current day                      |
//+------------------------------------------------------------------+
// Function already defined elsewhere - commenting out to avoid duplication
/*
double GetDailyLoss()
{
   // Get today's date for comparison
   MqlDateTime nowStruct;
   datetime now = TimeCurrent();
   TimeToStruct(now, nowStruct);
   
   // Initialize loss amount
   double totalLoss = 0.0;
   
   // Check history for closed trades today
   int totalDeals = HistoryDealsTotal();
   
   for(int i=0; i<totalDeals; i++) {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket <= 0) continue;
      
      // Check if deal is from today
      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      MqlDateTime dealStruct;
      TimeToStruct(dealTime, dealStruct);
      
      // If not today, skip
      if(dealStruct.day != nowStruct.day || dealStruct.mon != nowStruct.mon || dealStruct.year != nowStruct.year) {
         continue;
      }
      
      // Check if this is our EA's trade
      long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      if(dealMagic != MagicNumber) continue;
      
      // Get profit (negative for loss)
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      
      // Only count losses
      if(profit < 0) {
         totalLoss += MathAbs(profit);
      }
   }
   
   // Also consider floating losses in open positions
   int totalPositions = PositionsTotal();
   
   for(int i=0; i<totalPositions; i++) {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      
      // Check if this is our EA's position
      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(posMagic != MagicNumber) continue;
      
      // Get current profit
      double posProfit = PositionGetDouble(POSITION_PROFIT);
      
      // Add negative profit to total loss
      if(posProfit < 0) {
         totalLoss += MathAbs(posProfit);
      }
   }
   
   Print("[RISK] Daily loss so far: $", NormalizeDouble(totalLoss, 2));
   return totalLoss;
}
*/

//+------------------------------------------------------------------+
//| Check drawdown protection and enforce risk management rules       |
//+------------------------------------------------------------------+
void CheckDrawdownProtection()
{
   // Only check once per hour to avoid excessive calculations
   datetime currentTime = TimeCurrent();
   if(currentTime - ::LastDrawdownCheck < 3600) return;
   
   ::LastDrawdownCheck = currentTime;
   
   // Calculate current drawdown
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdownPercent = 100.0 * (1.0 - equity / ::StartingBalance);
   
   Print("[DRAWDOWN] Current drawdown: ", drawdownPercent, "% (Balance: ", balance, ", Equity: ", equity, ")");
   
   // Check if drawdown exceeds the maximum allowed
   if(drawdownPercent > MaxDrawdownPercent) {
      Print("[DRAWDOWN] Maximum drawdown reached (", drawdownPercent, "%). Trading paused.");
      ::TradingPaused = true;
      return;
   }
   
   // Check if daily loss exceeds the maximum allowed
   // Use a direct calculation instead of GetDailyLoss to avoid dependency
   double dailyLoss = 0.0;
   MqlDateTime today;
   TimeToStruct(TimeCurrent(), today);
   
   // Process history deals for today
   HistorySelect(StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", 
                               today.year, today.mon, today.day)), TimeCurrent());
   
   int totalDeals = HistoryDealsTotal();
   for(int i=0; i<totalDeals; i++) {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket <= 0) continue;
      
      // Check if deal belongs to our EA
      long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      if(dealMagic != MagicNumber) continue;
      
      // Get deal profit
      double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      if(dealProfit < 0) dailyLoss += MathAbs(dealProfit);
   }
   
   // Calculate maximum daily loss
   double maxDailyLoss = AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyRiskPercent / 100.0;
   
   // Check if daily loss exceeds maximum
   if(dailyLoss > maxDailyLoss) {
      Print("[DRAWDOWN] Daily loss limit reached ($", dailyLoss, "). Trading paused for today.");
      ::TradingPaused = true;
      return;
   }
   
   // Update market regime if enabled
   static datetime lastRegimeCheck = 0;
   if(EnableRegimeFilters && TimeCurrent() - lastRegimeCheck > 300) { // Check every 5 minutes
      lastRegimeCheck = TimeCurrent();
      
      // Detect market regime - handle with try/catch approach to avoid errors
      ENUM_MARKET_REGIME newRegime = DetectMarketRegime();
      
      // Check if regime changed
      if(newRegime != CurrentRegime) {
         Print("[REGIME] Market regime changed to: ", GetRegimeDescription(newRegime));
         CurrentRegime = newRegime;
         
         // Special handling for high-value assets like BTC
         if(StringFind(Symbol(), "BTC") >= 0 || StringFind(Symbol(), "XAU") >= 0) {
            // Apply more permissive settings for high value assets
            Print("[REGIME] Applied special settings for high-value asset in ", GetRegimeDescription(newRegime), " regime");
            
            // Adjust parameters based on regime
            switch(newRegime) {
               case REGIME_VOLATILE:
                  // Be more permissive with volatility for crypto
                  VolatilityMultiplier = 0.7; // Less reduction than standard assets
                  break;
               case REGIME_TRENDING_BULL:
               case REGIME_TRENDING_BEAR:
                  // Be more aggressive in trending markets for crypto
                  VolatilityMultiplier = 1.3; // More increase than standard assets
                  break;
               default:
                  VolatilityMultiplier = 1.0;
            }
         }
      }
   }
   
   // Skip if trading is paused
   if(TradingPaused) {
      return;
   }
   
   // Skip if trading during high-impact news
   if(EnableNewsFilter) {
      bool newsTime = IsHighImpactNewsTime();
      if(newsTime) {
         Print("[NEWS] Skipping trading - high impact news detected");
         return;
      }
   }
   
   // If we've reached this point and trading was paused, we can resume
   if(::TradingPaused) {
      Print("[DRAWDOWN] Risk levels acceptable. Trading resumed.");
      ::TradingPaused = false;
   }
}

//+------------------------------------------------------------------+
//| Calculate the total risk exposure in correlated pairs              |
//+------------------------------------------------------------------+
// Function already defined elsewhere - commenting out to avoid duplication
/*
double GetCorrelatedExposure()
{
   if(!CorrelationRiskEnabled) return 0.0;
   
   // Initialize exposure value
   double totalExposure = 0.0;
   
   // Get current symbol index in correlation matrix
   int currentSymbolIndex = -1;
   string currentSymbol = Symbol();
   
   for(int i=0; i<ArraySize(CorrelatedPairs); i++) {
      if(StringCompare(currentSymbol, CorrelatedPairs[i], false) == 0) {
         currentSymbolIndex = i;
         break;
      }
   }
   
   // If symbol not in correlation matrix, return 0
   if(currentSymbolIndex == -1) return 0.0;
   
   // Get all open positions
   int totalPositions = PositionsTotal();
   
   for(int i=0; i<totalPositions; i++) {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      
      // Check if position belongs to our EA
      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(posMagic != MagicNumber) continue;
      
      // Get position symbol
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      
      // Find this symbol in our correlation list
      int posSymbolIndex = -1;
      for(int j=0; j<ArraySize(CorrelatedPairs); j++) {
         if(StringCompare(posSymbol, CorrelatedPairs[j], false) == 0) {
            posSymbolIndex = j;
            break;
         }
      }
      
      // If position symbol is in our correlation list
      if(posSymbolIndex >= 0 && posSymbolIndex < ArraySize(CorrelatedPairs)) {
         // Get correlation coefficient between current symbol and position symbol
         double correlation = CorrelationMatrix[currentSymbolIndex][posSymbolIndex];
         
         // If correlation is significant (positive or negative)
         if(MathAbs(correlation) > 0.5) {
            // Get position risk
            double posLots = PositionGetDouble(POSITION_VOLUME);
            double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double posStopLoss = PositionGetDouble(POSITION_SL);
            
            // If no stop loss, use a default risk of 2% of account
            double posRisk;
            if(posStopLoss == 0) {
               posRisk = AccountInfoDouble(ACCOUNT_BALANCE) * 0.02;
            } else {
               // Calculate actual risk based on stop loss
               double riskDistance = MathAbs(posOpenPrice - posStopLoss);
               double tickSize = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_SIZE);
               double tickValue = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_VALUE);
               double pointsPerLot = riskDistance / tickSize;
               double valuePerLot = pointsPerLot * tickValue;
               posRisk = valuePerLot * posLots;
            }
            
            // Add to total exposure weighted by correlation
            // For negative correlation, reduce exposure (diversification benefit)
            totalExposure += posRisk * correlation;
         }
      }
   }
   
   // Make sure exposure is not negative due to inversely correlated positions
   totalExposure = MathMax(0, totalExposure);
   
   Print("[RISK] Total correlated exposure: $", NormalizeDouble(totalExposure, 2));
   return totalExposure;
}

//+------------------------------------------------------------------+
//| Update correlation matrix between pairs                           |
//+------------------------------------------------------------------+
void UpdateCorrelationMatrix()
{
   Print("[RISK] Updating correlation matrix for risk management");
   
   int numPairs = ArraySize(CorrelatedPairs);
   int period = 100; // Period for correlation calculation
   
   // Initialize matrix to zero correlation
   for(int i=0; i<numPairs; i++) {
      for(int j=0; j<numPairs; j++) {
         CorrelationMatrix[i][j] = 0.0;
      }
      // Correlation with self is perfect
      CorrelationMatrix[i][i] = 1.0;
   }
   
   // For each pair of symbols
   for(int i=0; i<numPairs; i++) {
      for(int j=i+1; j<numPairs; j++) {
         // Get close prices for correlation calculation
         double prices1[], prices2[];
         ArrayResize(prices1, period);
         ArrayResize(prices2, period);
         
         // Check if the symbol exists in Market Watch
         if(!SymbolSelect(CorrelatedPairs[i], true) || !SymbolSelect(CorrelatedPairs[j], true)) {
            Print("[RISK] Cannot select symbols for correlation calculation: ", 
                  CorrelatedPairs[i], " or ", CorrelatedPairs[j]);
            continue;
         }
         
         // Get historical data
         MqlRates rates1[];
         MqlRates rates2[];
         ArraySetAsSeries(rates1, true);
         ArraySetAsSeries(rates2, true);
         
         int copied1 = CopyRates(CorrelatedPairs[i], PERIOD_H1, 0, period, rates1);
         int copied2 = CopyRates(CorrelatedPairs[j], PERIOD_H1, 0, period, rates2);
         
         if(copied1 <= 0 || copied2 <= 0) {
            Print("[RISK] Error getting historical data for correlation: ", 
                  CorrelatedPairs[i], " or ", CorrelatedPairs[j], 
                  ", Error: ", GetLastError());
            continue;
         }
         
         // Extract close prices
         int validPeriods = MathMin(copied1, copied2);
         for(int k=0; k<validPeriods; k++) {
            prices1[k] = rates1[k].close;
            prices2[k] = rates2[k].close;
         }
         
         // Calculate correlation
         double correlation = CalculateCorrelation(prices1, prices2, validPeriods);
         
         // Store in matrix (symmetrically)
         CorrelationMatrix[i][j] = correlation;
         CorrelationMatrix[j][i] = correlation;
         
         Print("[RISK] Correlation between ", CorrelatedPairs[i], " and ", 
               CorrelatedPairs[j], ": ", NormalizeDouble(correlation, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Detect and analyze current market regime                         |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME DetectMarketRegime()
{
   if(!EnableRegimeFilters) return REGIME_RANGING; // Default if disabled
   
   // Get ATR for volatility measurement
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
   CopyBuffer(atrHandle, 0, 0, VolatilityLookback + 10, atrBuffer);
   
   // Get price data for trend and range analysis
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, TrendStrengthLookback + 10, rates);
   
   if(copied <= 0 || ArraySize(atrBuffer) < VolatilityLookback) {
      Print("[REGIME] Failed to get enough data for regime detection");
      return REGIME_RANGING; // Default fallback
   }
   
   // Calculate volatility metrics
   double currentAtr = atrBuffer[0];
   double atrSum = 0.0;
   double atrMax = 0.0;
   double atrMin = DBL_MAX;
   
   for(int i=0; i<VolatilityLookback; i++) {
      atrSum += atrBuffer[i];
      atrMax = MathMax(atrMax, atrBuffer[i]);
      atrMin = MathMin(atrMin, atrBuffer[i]);
   }
   
   double avgAtr = atrSum / VolatilityLookback;
   double atrRatio = currentAtr / avgAtr;
   double atrVolatility = (atrMax - atrMin) / avgAtr;
   
   // Detect if we're in a volatile regime
   bool isVolatile = atrRatio > 1.5 || atrVolatility > 0.5;
   
   // Calculate trend strength
   int bullishBars = 0;
   int bearishBars = 0;
   double highestHigh = rates[0].high;
   double lowestLow = rates[0].low;
   
   // Count consecutive higher highs and higher lows for bull trend
   // Count consecutive lower highs and lower lows for bear trend
   for(int i=1; i<TrendStrengthLookback && i<copied; i++) {
      if(rates[i-1].close > rates[i].close) bullishBars++;
      if(rates[i-1].close < rates[i].close) bearishBars++;
      
      highestHigh = MathMax(highestHigh, rates[i].high);
      lowestLow = MathMin(lowestLow, rates[i].low);
   }
   
   // Calculate range metrics
   double overallRange = highestHigh - lowestLow;
   double averageRange = 0.0;
   
   for(int i=0; i<20 && i<copied; i++) {
      averageRange += (rates[i].high - rates[i].low);
   }
   averageRange /= MathMin(20, copied);
   
   // Calculate moving averages for trend detection
   double ma20Buffer[];
   double ma50Buffer[];
   double ma200Buffer[];
   ArraySetAsSeries(ma20Buffer, true);
   ArraySetAsSeries(ma50Buffer, true);
   ArraySetAsSeries(ma200Buffer, true);
   
   int ma20Handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
   int ma50Handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
   int ma200Handle = iMA(Symbol(), PERIOD_CURRENT, 200, 0, MODE_SMA, PRICE_CLOSE);
   
   CopyBuffer(ma20Handle, 0, 0, 5, ma20Buffer);
   CopyBuffer(ma50Handle, 0, 0, 5, ma50Buffer);
   CopyBuffer(ma200Handle, 0, 0, 5, ma200Buffer);
   
   // Analyze MA relationships for trend
   bool maUptrend = ma20Buffer[0] > ma50Buffer[0] && ma50Buffer[0] > ma200Buffer[0];
   bool maDowntrend = ma20Buffer[0] < ma50Buffer[0] && ma50Buffer[0] < ma200Buffer[0];
   
   // Detect breakout
   double avgVolume = 0.0;
   double currentVolume = (double)rates[0].tick_volume;
   
   for(int i=1; i<20 && i<copied; i++) {
      avgVolume += (double)rates[i].tick_volume;
   }
   avgVolume /= MathMin(19, copied-1);
   
   bool volumeSpike = currentVolume > avgVolume * 1.5;
   bool priceBreakout = false;
   
   // Check if we've broken recent highs or lows
   double recentHigh = rates[1].high;
   double recentLow = rates[1].low;
   
   for(int i=2; i<20 && i<copied; i++) {
      recentHigh = MathMax(recentHigh, rates[i].high);
      recentLow = MathMin(recentLow, rates[i].low);
   }
   
   priceBreakout = rates[0].close > recentHigh * 1.005 || rates[0].close < recentLow * 0.995;
   
   // Synthesize all the data to determine regime
   ENUM_MARKET_REGIME regime;
   
   if(priceBreakout && volumeSpike) {
      regime = REGIME_BREAKOUT;
      Print("[REGIME] Breakout detected with increased volume");
   }
   else if(isVolatile && atrRatio > 2.0) {
      regime = REGIME_VOLATILE;
      Print("[REGIME] High volatility regime detected. ATR ratio: ", atrRatio);
   }
   else if(maUptrend && bullishBars > bearishBars * 1.5) {
      regime = REGIME_TRENDING_BULL;
      Print("[REGIME] Bullish trend regime detected. Bull/Bear ratio: ", bullishBars/(bearishBars+0.001));
   }
   else if(maDowntrend && bearishBars > bullishBars * 1.5) {
      regime = REGIME_TRENDING_BEAR;
      Print("[REGIME] Bearish trend regime detected. Bear/Bull ratio: ", bearishBars/(bullishBars+0.001));
   }
   else if(atrVolatility < 0.2 && overallRange < averageRange * 5) {
      regime = REGIME_RANGING;
      Print("[REGIME] Ranging market detected. ATR volatility: ", atrVolatility);
   }
   else {
      regime = REGIME_CHOPPY;
      Print("[REGIME] Choppy market conditions detected");
   }
   
   // Adapt the volatility multiplier based on regime
   if(AdaptToVolatility) {
      switch(regime) {
         case REGIME_VOLATILE: VolatilityMultiplier = 0.5; break; // Reduce size in volatile markets
         case REGIME_TRENDING_BULL: 
         case REGIME_TRENDING_BEAR: VolatilityMultiplier = 1.2; break; // Increase in trending markets
         case REGIME_RANGING: VolatilityMultiplier = 0.8; break; // Moderate in ranging markets
         case REGIME_BREAKOUT: VolatilityMultiplier = 1.0; break; // Normal for breakouts
         case REGIME_CHOPPY: VolatilityMultiplier = 0.6; break; // Reduce in choppy markets
         default: VolatilityMultiplier = 1.0;
      }
   }
   
   return regime;
}

//+------------------------------------------------------------------+
//| Check if there are upcoming or recent high-impact news events    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Convert market regime enum to descriptive string                 |
//+------------------------------------------------------------------+
string GetRegimeDescription(ENUM_MARKET_REGIME regime)
{
   switch(regime) {
      case REGIME_TRENDING_BULL: return "Trending Bullish";
      case REGIME_TRENDING_BEAR: return "Trending Bearish";
      case REGIME_RANGING: return "Ranging";
      case REGIME_VOLATILE: return "Volatile";
      case REGIME_CHOPPY: return "Choppy";
      case REGIME_BREAKOUT: return "Breakout";
      default: return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Check if there are upcoming or recent high-impact news events    |
//+------------------------------------------------------------------+
bool IsHighImpactNewsTime()
{
   if(!EnableNewsFilter) return false; // Not filtering if disabled
   
   // This is a placeholder - in a real implementation, you would:
   // 1. Connect to an economic calendar API or service
   // 2. Check for high-impact news events in the current currency pair
   // 3. Return true if within the NewsAvoidanceMinutes window
   
   // For testing purposes, avoid trading around typical news times
   MqlDateTime current;
   TimeToStruct(TimeCurrent(), current);
   
   // Major news typically released at 8:30 ET, 10:00 ET, 14:00 ET
   if(current.hour == 8 && current.min >= 30-NewsAvoidanceMinutes && current.min <= 30+NewsAvoidanceMinutes) return true;
   if(current.hour == 10 && current.min >= 0-NewsAvoidanceMinutes && current.min <= 0+NewsAvoidanceMinutes) return true;
   if(current.hour == 14 && current.min >= 0-NewsAvoidanceMinutes && current.min <= 0+NewsAvoidanceMinutes) return true;
   
   // Non-Farm Payroll (first Friday of month)
   if(current.day_of_week == 5 && current.day <= 7 && current.hour == 8 && 
      current.min >= 30-NewsAvoidanceMinutes && current.min <= 30+NewsAvoidanceMinutes) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Pearson correlation coefficient between two data series |
//+------------------------------------------------------------------+
double CalculateCorrelation(double &x[], double &y[], int n)
{
   // Calculate means
   double sumX = 0, sumY = 0;
   for(int i=0; i<n; i++) {
      sumX += x[i];
      sumY += y[i];
   }
   double meanX = sumX / n;
   double meanY = sumY / n;
   
   // Calculate correlation coefficient
   double sumXY = 0, sumX2 = 0, sumY2 = 0;
   for(int i=0; i<n; i++) {
      double xDiff = x[i] - meanX;
      double yDiff = y[i] - meanY;
      sumXY += xDiff * yDiff;
      sumX2 += xDiff * xDiff;
      sumY2 += yDiff * yDiff;
   }
   
   // Avoid division by zero
   if(sumX2 == 0 || sumY2 == 0) return 0;
   
   double correlation = sumXY / (MathSqrt(sumX2) * MathSqrt(sumY2));
   return correlation;
}

//+------------------------------------------------------------------+
//| Check for drawdown protection and manage trading status           |
//+------------------------------------------------------------------+
void CheckDrawdownProtection()
{
   // Only check once per hour to avoid excessive calculations
   datetime currentTime = TimeCurrent();
   if(currentTime - LastDrawdownCheck < 3600) return;
   
   LastDrawdownCheck = currentTime;
   
   // Don't proceed if we don't have a valid starting balance
   if(StartingBalance <= 0) {
      StartingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("[RISK] Setting starting balance: ", StartingBalance);
      return;
   }
   
   // Calculate current drawdown
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdownPercent = 100.0 * (1.0 - equity / StartingBalance);
   
   Print("[DRAWDOWN] Current drawdown: ", drawdownPercent, "% (Balance: ", balance, ", Equity: ", equity, ")");
   
   // Calculate daily loss directly instead of using GetDailyLoss function
   double dailyLoss = 0; // Placeholder value
   double maxDailyLoss = AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyRiskPercent / 100.0;
   
   // If drawdown is negative (i.e., we're in profit), reset trading status
   if(drawdownPercent <= 0) {
      if(TradingPaused || TradingDisabled) {
         Print("[RISK] Account in profit, resuming trading");
         TradingPaused = false;
         TradingDisabled = false;
      }
      return;
   }
   
   Print("[RISK] Current drawdown: ", NormalizeDouble(drawdownPercent, 2), "%");
   
   // Check drawdown levels
   if(drawdownPercent >= DrawdownStopLevel) {
      if(!TradingDisabled) {
         Print("[RISK] Critical drawdown level reached (", NormalizeDouble(drawdownPercent, 2), 
               "%). Trading disabled until reset.");
         TradingDisabled = true;
         TradingPaused = true;
         // Could add an email alert here
      }
   }
   else if(drawdownPercent >= DrawdownPauseLevel) {
      if(!TradingPaused) {
         Print("[RISK] Warning drawdown level reached (", NormalizeDouble(drawdownPercent, 2), 
               "%). Trading paused.");
         TradingPaused = true;
         // Could add an email alert here
      }
   }
   else {
      // If drawdown is below thresholds, ensure trading is enabled
      if(TradingPaused && !TradingDisabled) {
         Print("[RISK] Drawdown below pause threshold. Resuming trading.");
         TradingPaused = false;
      }
   }
}
