//+------------------------------------------------------------------+
//|                 ScalpingAutoTrailExpert_v2 with SMC Hybrid     |
//|        Copyright 2025, Leo Software                           |
//|       Enhanced: SMC Structure-based Trading with ML Regime     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Leo Software"
#property link      "https://www.example.com"
#property version   "3.00"
#property strict

// Include required files
#include <Trade/Trade.mqh>
#include <Math/Stat/Normal.mqh>

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

// --- INPUTS AND PARAMETERS ---
// Original parameters
input double   RiskPercentage = 1.0;       // Risk percentage per trade
input int      InitialStopLoss = 50;       // Initial Stop Loss (pips)
input int      InitialTakeProfit = 100;    // Initial Take Profit (pips)
input int      TrailingStop = 30;          // Trailing Stop Distance (pips)
input int      TrailingStep = 20;          // Trailing Step (pips)
input int      FastMAPeriod = 5;           // Fast MA Period
input int      SlowMAPeriod = 20;          // Slow MA Period
input int      MagicNumber = 12345;        // EA Magic Number

// SMC Enhancement Parameters
input group "===== SMC FEATURES ====="
input bool     EnableSMCFeatures = true;    // Enable SMC advanced features
input bool     EnableMarketRegimeFiltering = true; // Filter trades based on market regime
input bool     EnableOptimalStopLoss = true;   // Use swing-based optimal stop loss
input bool     EnableDynamicTakeProfit = true; // Use dynamic take profit calculation
input bool     EnableAdvancedTrailing = true;  // Use advanced trailing methods
input int      LookbackBars = 100;            // Bars to look back for structures
input int      MinBlockStrength = 1;         // Minimum order block strength for valid signal
input double   SL_ATR_Mult = 1.5;            // ATR multiplier for stop loss
input double   BaseRiskReward = 2.0;         // Base risk:reward ratio
input double   TrailingActivationPct = 0.5;  // When to activate trailing (% of TP reached)
input double   TrailingStopMultiplier = 0.5; // Trailing stop multiplier of ATR
input int      MaxConsecutiveLosses = 3;     // Stop trading after this many consecutive losses
input bool     DisplayDebugInfo = true;      // Display debug info in comments

// Original global variables
int fastMAHandle, slowMAHandle;
double minLot, maxLot;
double profitTrailStart = 0.5; // 50% of TP, start profit trailing
input int ProfitTrailBuffer = 20; // pips, the buffer for trailing profit

// SMC Structures
struct LiquidityGrab { datetime time; double high; double low; bool bullish; bool active; };
struct FairValueGap { datetime startTime; datetime endTime; double high; double low; bool bullish; bool active; };
struct OrderBlock { datetime blockTime; double priceLevel; double highPrice; double lowPrice; bool bullish; bool valid; int strength; };
struct SwingPoint { int barIndex; double price; int score; datetime time; };

// SMC Global Variables
LiquidityGrab recentGrabs[MAX_GRABS];
FairValueGap recentFVGs[MAX_FVGS];
OrderBlock recentBlocks[MAX_BLOCKS];
CTrade trade;

// Trading Status Variables
bool emergencyMode = false;
datetime lastTradeTime = 0;
datetime lastSignalTime = 0;
bool trailingActive = false;
double trailingLevel = 0;
double trailingTP = 0;
int consecutiveLosses = 0;
int currentRegime = -1;
int regimeBarCount = 0;
int lastRegime = -1;
double regimeProfit[REGIME_COUNT];
double regimeAccuracy[REGIME_COUNT];

// Performance tracking
int winStreak = 0;
int lossStreak = 0;
double tradeProfits[METRIC_WINDOW];
double tradeReturns[METRIC_WINDOW];
int regimeWins[REGIME_COUNT];
int regimeLosses[REGIME_COUNT];

// Utility: Get pip size for the symbol
// Returns number of points per pip (e.g., 10 for 5-digit, 1 for 4-digit)
double GetPipSize() {
   double pip = 0.0;
   if(_Digits == 3 || _Digits == 5)
      pip = 10 * _Point;
   else
      pip = 1 * _Point;
   return pip;
}

// Utility: ATR filter for volatility
bool ATRFilter(int period, double minATR)
{
   int handle = iATR(_Symbol, _Period, period);
   double atr[];
   if(CopyBuffer(handle, 0, 0, 1, atr) == 1)
   {
      IndicatorRelease(handle);
      return atr[0] >= minATR;
   }
   IndicatorRelease(handle);
   return false;
}

//+------------------------------------------------------------------+
//| Helper functions for market regime detection                      |
//+------------------------------------------------------------------+

// Get ATR value for specified symbol and timeframe
double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift) {
    int handle = iATR(symbol, timeframe, period);
    double buffer[];
    if(CopyBuffer(handle, 0, shift, 1, buffer) > 0) {
        double result = buffer[0];
        IndicatorRelease(handle);
        return result;
    }
    IndicatorRelease(handle);
    return SymbolInfoDouble(symbol, SYMBOL_POINT) * 10; // Fallback value
}

// Get Bollinger Bands values
double GetBands(string symbol, ENUM_TIMEFRAMES timeframe, int period, double deviation, int shift, ENUM_APPLIED_PRICE applied_price, int band, int bar) {
    int handle = iBands(symbol, timeframe, period, deviation, 0, applied_price);
    double buffer[];
    if(CopyBuffer(handle, band, bar, 1, buffer) > 0) {
        double bandValue = buffer[0];
        IndicatorRelease(handle);
        return bandValue;
    }
    IndicatorRelease(handle);
    return 0;
}

//+------------------------------------------------------------------+
//| Detect market regime based on price patterns and volatility       |
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
    else if(isVeryVolatile) {
        regime = HIGH_VOLATILITY;
    }
    else if(isTrendingUp) {
        regime = TRENDING_UP;
    }
    else if(isTrendingDown) {
        regime = TRENDING_DOWN;
    }
    
    return regime;
}

//+------------------------------------------------------------------+
//| Convert regime code to string description                         |
//+------------------------------------------------------------------+
string RegimeToString(int regime) {
    switch(regime) {
        case TRENDING_UP:      return "Trending Up";
        case TRENDING_DOWN:    return "Trending Down";
        case HIGH_VOLATILITY:  return "High Volatility";
        case LOW_VOLATILITY:   return "Low Volatility";
        case RANGING_NARROW:   return "Ranging Narrow";
        case RANGING_WIDE:     return "Ranging Wide";
        case BREAKOUT:         return "Breakout";
        case REVERSAL:         return "Reversal";
        case CHOPPY:           return "Choppy";
        default:               return "Unknown";
    }
}

int OnInit()
{
   // Initialize MA handles
   fastMAHandle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   slowMAHandle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   
   if(fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }
   
   // Get lot size limits
   minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   // Initialize CTrade object
   trade.SetDeviationInPoints(10); // 1 pip deviation
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Reset SMC arrays
   ArrayInitialize(regimeWins, 0);
   ArrayInitialize(regimeLosses, 0);
   ArrayInitialize(regimeProfit, 0.0);
   ArrayInitialize(regimeAccuracy, 0.0);
   ArrayInitialize(tradeProfits, 0.0);
   ArrayInitialize(tradeReturns, 0.0);
   
   // Reset trading status variables
   emergencyMode = false;
   lastTradeTime = 0;
   lastSignalTime = 0;
   trailingActive = false;
   trailingLevel = 0;
   trailingTP = 0;
   consecutiveLosses = 0;
   winStreak = 0;
   lossStreak = 0;
   
   // Detect initial market regime
   if(EnableMarketRegimeFiltering) {
      currentRegime = FastRegimeDetection(_Symbol);
      Print("Initial market regime: ", RegimeToString(currentRegime));
   }
   
   Print("[Init] ScalpingAutoTrailExpert_v2 with SMC Hybrid initialized successfully");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(fastMAHandle);
   IndicatorRelease(slowMAHandle);
}

//+------------------------------------------------------------------+
//| Function to detect liquidity grabs                              |
//+------------------------------------------------------------------+
void DetectLiquidityGrabs() {
   if(!EnableSMCFeatures) return;
   
   int lookback = MathMin(LookbackBars, Bars(_Symbol, PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   
   ArrayResize(high, lookback);
   ArrayResize(low, lookback);
   ArrayResize(open, lookback);
   ArrayResize(close, lookback);
   ArrayResize(time, lookback);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
   CopyOpen(_Symbol, PERIOD_CURRENT, 0, lookback, open);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, lookback, close);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, lookback, time);
   
   int grabCount = 0;
   
   // Find bullish liquidity grabs (sweep below support and reversal)
   for(int i=2; i<lookback-2; i++) {
      // Sweep below lows, then strong close
      if(low[i] < low[i+1] && low[i] < low[i+2] && close[i] > (high[i] + low[i])/2) {
         // Store bullish liquidity grab
         if(grabCount < MAX_GRABS) {
            recentGrabs[grabCount].time = time[i];
            recentGrabs[grabCount].high = high[i];
            recentGrabs[grabCount].low = low[i];
            recentGrabs[grabCount].bullish = true;
            recentGrabs[grabCount].active = true;
            grabCount++;
         }
      }
      
      // Bearish liquidity grab (sweep above resistance and reversal)
      if(high[i] > high[i+1] && high[i] > high[i+2] && close[i] < (high[i] + low[i])/2) {
         // Store bearish liquidity grab
         if(grabCount < MAX_GRABS) {
            recentGrabs[grabCount].time = time[i];
            recentGrabs[grabCount].high = high[i];
            recentGrabs[grabCount].low = low[i];
            recentGrabs[grabCount].bullish = false;
            recentGrabs[grabCount].active = true;
            grabCount++;
         }
      }
   }
   
   // Disable old grabs
   for(int i=0; i<MAX_GRABS; i++) {
      if(recentGrabs[i].time > 0 && TimeCurrent() - recentGrabs[i].time > 24*60*60) {
         recentGrabs[i].active = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Function to detect fair value gaps                              |
//+------------------------------------------------------------------+
void DetectFairValueGaps() {
   if(!EnableSMCFeatures) return;
   
   int lookback = MathMin(LookbackBars, Bars(_Symbol, PERIOD_CURRENT));
   double high[], low[];
   datetime time[];
   
   ArrayResize(high, lookback);
   ArrayResize(low, lookback);
   ArrayResize(time, lookback);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, lookback, time);
   
   int fvgCount = 0;
   
   // Find fair value gaps
   for(int i=0; i<lookback-2; i++) {
      // Bullish FVG: Current Low > Previous High
      if(low[i] > high[i+1]) {
         if(fvgCount < MAX_FVGS) {
            recentFVGs[fvgCount].startTime = time[i+1];
            recentFVGs[fvgCount].endTime = time[i];
            recentFVGs[fvgCount].high = low[i]; // Top of gap
            recentFVGs[fvgCount].low = high[i+1]; // Bottom of gap
            recentFVGs[fvgCount].bullish = true;
            recentFVGs[fvgCount].active = true;
            fvgCount++;
         }
      }
      
      // Bearish FVG: Current High < Previous Low
      if(high[i] < low[i+1]) {
         if(fvgCount < MAX_FVGS) {
            recentFVGs[fvgCount].startTime = time[i+1];
            recentFVGs[fvgCount].endTime = time[i];
            recentFVGs[fvgCount].high = low[i+1]; // Top of gap
            recentFVGs[fvgCount].low = high[i]; // Bottom of gap
            recentFVGs[fvgCount].bullish = false;
            recentFVGs[fvgCount].active = true;
            fvgCount++;
         }
      }
   }
   
   // Check if any FVG has been filled
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   for(int i=0; i<MAX_FVGS; i++) {
      if(!recentFVGs[i].active) continue;
      
      // For bullish FVGs, check if price went back down into the gap
      if(recentFVGs[i].bullish && currentPrice <= recentFVGs[i].low) {
         recentFVGs[i].active = false;
      }
      
      // For bearish FVGs, check if price went back up into the gap
      if(!recentFVGs[i].bullish && currentPrice >= recentFVGs[i].high) {
         recentFVGs[i].active = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Function to detect order blocks                                 |
//+------------------------------------------------------------------+
void DetectOrderBlocks() {
   if(!EnableSMCFeatures) return;
   
   int lookback = MathMin(LookbackBars, Bars(_Symbol, PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   
   ArrayResize(high, lookback);
   ArrayResize(low, lookback);
   ArrayResize(open, lookback);
   ArrayResize(close, lookback);
   ArrayResize(time, lookback);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
   CopyOpen(_Symbol, PERIOD_CURRENT, 0, lookback, open);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, lookback, close);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, lookback, time);
   
   int blockCount = 0;
   
   // Find bullish order blocks (drop base rally structure)
   for(int i=3; i<lookback-3; i++) {
      // Look for down candle followed by strong up move
      if(close[i] < open[i] && close[i-1] > open[i-1] && close[i-2] > open[i-2]) {
         double moveUp = close[i-2] - close[i];
         if(moveUp > 0) {
            if(blockCount < MAX_BLOCKS) {
               recentBlocks[blockCount].blockTime = time[i];
               recentBlocks[blockCount].priceLevel = (high[i] + low[i]) / 2;
               recentBlocks[blockCount].highPrice = high[i];
               recentBlocks[blockCount].lowPrice = low[i];
               recentBlocks[blockCount].bullish = true;
               recentBlocks[blockCount].valid = true;
               recentBlocks[blockCount].strength = 1;
               blockCount++;
            }
         }
      }
      
      // Find bearish order blocks (rally base drop structure)
      if(close[i] > open[i] && close[i-1] < open[i-1] && close[i-2] < open[i-2]) {
         double moveDown = close[i] - close[i-2];
         if(moveDown > 0) {
            if(blockCount < MAX_BLOCKS) {
               recentBlocks[blockCount].blockTime = time[i];
               recentBlocks[blockCount].priceLevel = (high[i] + low[i]) / 2;
               recentBlocks[blockCount].highPrice = high[i];
               recentBlocks[blockCount].lowPrice = low[i];
               recentBlocks[blockCount].bullish = false;
               recentBlocks[blockCount].valid = true;
               recentBlocks[blockCount].strength = 1;
               blockCount++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Function to find quality swing points for optimal stop loss     |
//+------------------------------------------------------------------+
void FindSwingPoints(bool isBullish, int lookback) {
   if(!EnableOptimalStopLoss) return;
   
   double high[], low[];
   datetime time[];
   
   lookback = MathMin(lookback, Bars(_Symbol, PERIOD_CURRENT));
   
   ArrayResize(high, lookback);
   ArrayResize(low, lookback);
   ArrayResize(time, lookback);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, lookback, time);
   
   // Reset swing point count
   int count = 0;
   
   // Find swing lows for bullish trades
   if(isBullish) {
      for(int i=2; i<lookback-2; i++) {
         if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i+1] && low[i] < low[i+2]) {
            // We found a swing low
            if(count < 20) { // Limit to 20 swing points max
               SwingPoint point;
               point.barIndex = i;
               point.price = low[i];
               point.time = time[i];
               point.score = 1; // Basic score
               
               // Improve score based on depth of swing
               double leftDepth = MathMin(low[i-1] - low[i], low[i-2] - low[i]);
               double rightDepth = MathMin(low[i+1] - low[i], low[i+2] - low[i]);
               
               if(leftDepth > 10 * _Point) point.score++;
               if(rightDepth > 10 * _Point) point.score++;
               
               // Store the swing point
               qualitySwingPoints[count] = point;
               count++;
            }
         }
      }
   }
   // Find swing highs for bearish trades
   else {
      for(int i=2; i<lookback-2; i++) {
         if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i+1] && high[i] > high[i+2]) {
            // We found a swing high
            if(count < 20) { // Limit to 20 swing points max
               SwingPoint point;
               point.barIndex = i;
               point.price = high[i];
               point.time = time[i];
               point.score = 1; // Basic score
               
               // Improve score based on depth of swing
               double leftDepth = MathMin(high[i] - high[i-1], high[i] - high[i-2]);
               double rightDepth = MathMin(high[i] - high[i+1], high[i] - high[i+2]);
               
               if(leftDepth > 10 * _Point) point.score++;
               if(rightDepth > 10 * _Point) point.score++;
               
               // Store the swing point
               qualitySwingPoints[count] = point;
               count++;
            }
         }
      }
   }
   
   // Sort swing points by score (highest first)
   for(int i=0; i<count-1; i++) {
      for(int j=i+1; j<count; j++) {
         if(qualitySwingPoints[j].score > qualitySwingPoints[i].score) {
            SwingPoint temp = qualitySwingPoints[i];
            qualitySwingPoints[i] = qualitySwingPoints[j];
            qualitySwingPoints[j] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for emergency mode (too many consecutive losses)
   if(emergencyMode && consecutiveLosses >= MaxConsecutiveLosses) {
      if(DisplayDebugInfo) Comment("Emergency mode active: ", consecutiveLosses, " consecutive losses");
      return;
   }
   
   // Update market regime detection on new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   if(currentBarTime != lastBarTime) {
      lastBarTime = currentBarTime;
      
      // Detect market structures when SMC features are enabled
      if(EnableSMCFeatures) {
         // Update market regime
         if(EnableMarketRegimeFiltering) {
            int prevRegime = currentRegime;
            currentRegime = FastRegimeDetection(_Symbol);
            
            if(prevRegime != currentRegime) {
               Print("Market regime changed from ", RegimeToString(prevRegime), " to ", RegimeToString(currentRegime));
            }
         }
         
         // Detect SMC structures
         DetectLiquidityGrabs();
         DetectFairValueGaps();
         DetectOrderBlocks();
         
         // Find swing points for optimal stop loss placement
         FindSwingPoints(true, LookbackBars); // Find bullish swing points
         FindSwingPoints(false, LookbackBars); // Find bearish swing points
      }
   }
   
   // Basic functions always run
   CheckForEntry();
   TrailPositions();
   
   // Display debug information if enabled
   if(DisplayDebugInfo) {
      string infoText = "--- Scalping Auto Trail Expert v2 with SMC ---\n";
      infoText += "Market Regime: " + RegimeToString(currentRegime) + "\n";
      infoText += "Consecutive Losses: " + IntegerToString(consecutiveLosses) + "\n";
      infoText += "Emergency Mode: " + (emergencyMode ? "Active" : "Inactive") + "\n";
      
      // Add SMC structure counts
      if(EnableSMCFeatures) {
         int activeGrabs = 0, activeFVGs = 0, activeBlocks = 0;
         
         for(int i=0; i<MAX_GRABS; i++) if(recentGrabs[i].active) activeGrabs++;
         for(int i=0; i<MAX_FVGS; i++) if(recentFVGs[i].active) activeFVGs++;
         for(int i=0; i<MAX_BLOCKS; i++) if(recentBlocks[i].valid) activeBlocks++;
         
         infoText += "Active Liquidity Grabs: " + IntegerToString(activeGrabs) + "\n";
         infoText += "Active Fair Value Gaps: " + IntegerToString(activeFVGs) + "\n";
         infoText += "Active Order Blocks: " + IntegerToString(activeBlocks) + "\n";
      }
      
      Comment(infoText);
   }
}

double CalculateLotSize(double riskPercent, int slPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * riskPercent / 100;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipValue = tickValue * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) / _Point);
   double lotSize = riskAmount / (slPips * pipValue);
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Calculate optimal stop loss based on swing points and market structure |
//+------------------------------------------------------------------+
double CalculateOptimalStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice) {
   if(!EnableOptimalStopLoss || !EnableSMCFeatures) {
      // Fall back to standard stop loss calculation
      double pip = GetPipSize();
      return orderType == ORDER_TYPE_BUY ? 
             entryPrice - InitialStopLoss * pip : 
             entryPrice + InitialStopLoss * pip;
   }
   
   bool isBuy = (orderType == ORDER_TYPE_BUY);
   double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // 1. First try to use recent swing points
   for(int i=0; i<20; i++) {
      if(qualitySwingPoints[i].score <= 0) continue;
      
      // For buys, look for recent swing lows below price
      if(isBuy && qualitySwingPoints[i].price < currentPrice) {
         double distance = currentPrice - qualitySwingPoints[i].price;
         // Check if the distance is reasonable (not too small, not too large)
         if(distance > 10 * _Point && distance < 300 * _Point) {
            // Add a small buffer for safety
            return qualitySwingPoints[i].price - 5 * _Point;
         }
      }
      // For sells, look for recent swing highs above price
      else if(!isBuy && qualitySwingPoints[i].price > currentPrice) {
         double distance = qualitySwingPoints[i].price - currentPrice;
         // Check if the distance is reasonable
         if(distance > 10 * _Point && distance < 300 * _Point) {
            // Add a small buffer for safety
            return qualitySwingPoints[i].price + 5 * _Point;
         }
      }
   }
   
   // 2. If no suitable swing points, try to use order blocks
   for(int i=0; i<MAX_BLOCKS; i++) {
      if(!recentBlocks[i].valid) continue;
      
      if(isBuy && recentBlocks[i].bullish) {
         // For buys, use bottom of bullish order block
         if(recentBlocks[i].lowPrice < currentPrice) {
            return recentBlocks[i].lowPrice - 5 * _Point;
         }
      }
      else if(!isBuy && !recentBlocks[i].bullish) {
         // For sells, use top of bearish order block
         if(recentBlocks[i].highPrice > currentPrice) {
            return recentBlocks[i].highPrice + 5 * _Point;
         }
      }
   }
   
   // 3. If still no suitable levels, use ATR-based stop loss
   double atr = GetATR(_Symbol, PERIOD_CURRENT, 14, 0);
   double atrStop = SL_ATR_Mult * atr;
   
   return isBuy ? currentPrice - atrStop : currentPrice + atrStop;
}

//+------------------------------------------------------------------+
//| Calculate dynamic take profit based on market regime and R:R ratio |
//+------------------------------------------------------------------+
double CalculateDynamicTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss) {
   bool isBuy = (orderType == ORDER_TYPE_BUY);
   double slDistance = MathAbs(entryPrice - stopLoss);
   double baseRR = BaseRiskReward; // Start with base R:R
   
   // Adjust based on market regime if enabled
   if(EnableMarketRegimeFiltering && currentRegime >= 0) {
      switch(currentRegime) {
         case TRENDING_UP:
         case TRENDING_DOWN:
            // Increase target in trending markets
            baseRR *= 1.2;
            break;
         case HIGH_VOLATILITY:
            // Increase target in volatile markets
            baseRR *= 1.5;
            break;
         case RANGING_NARROW:
            // Reduce target in tight ranges
            baseRR *= 0.8;
            break;
         case CHOPPY:
            // Reduce target in choppy markets
            baseRR *= 0.7;
            break;
         case BREAKOUT:
            // Maximize target in breakouts
            baseRR *= 1.8;
            break;
      }
   }
   
   // Calculate TP distance based on adjusted R:R
   double tpDistance = slDistance * baseRR;
   
   // Calculate the final TP level
   return isBuy ? entryPrice + tpDistance : entryPrice - tpDistance;
}

//+------------------------------------------------------------------+
//| Check for entry signals with SMC filtering                       |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   // Skip if we already have a position
   if(PositionsTotal() > 0) return;
   
   // Skip if in emergency mode
   if(emergencyMode) return;
   
   // Get MA values for crossover detection
   double fastMA[2], slowMA[2];
   if(CopyBuffer(fastMAHandle, 0, 0, 2, fastMA) != 2) return;
   if(CopyBuffer(slowMAHandle, 0, 0, 2, slowMA) != 2) return;
   
   // Get higher timeframe trend direction for trend filter
   int htMAHandle = iMA(_Symbol, PERIOD_H1, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   double htMA[];
   if(CopyBuffer(htMAHandle, 0, 0, 1, htMA) != 1) { IndicatorRelease(htMAHandle); return; }
   double htMAValue = htMA[0];
   IndicatorRelease(htMAHandle);
   double htClose[];
   if(CopyClose(_Symbol, PERIOD_H1, 0, 1, htClose) != 1) return;
   double htCloseValue = htClose[0];
   bool trendUp = htCloseValue > htMAValue;
   bool trendDown = htCloseValue < htMAValue;
   
   // Volatility filter
   bool volatilityOK = ATRFilter(14, 1.5 * GetPipSize());
   
   // Basic crossover signals
   bool buySignal = fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0] && trendUp && volatilityOK;
   bool sellSignal = fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0] && trendDown && volatilityOK;
   
   // Apply SMC filtering if enabled
   if(EnableSMCFeatures) {
      // Apply market regime filter if enabled
      if(EnableMarketRegimeFiltering && currentRegime >= 0) {
         // Adjust signals based on market regime
         switch(currentRegime) {
            case TRENDING_UP:
               // In uptrend, only take buy signals
               sellSignal = false;
               break;
            case TRENDING_DOWN:
               // In downtrend, only take sell signals
               buySignal = false;
               break;
            case CHOPPY:
            case RANGING_NARROW:
               // In choppy or narrow ranging markets, require stronger signals
               // Require liquidity grab confirmation
               if(buySignal) {
                  bool hasLiqGrab = false;
                  for(int i=0; i<MAX_GRABS; i++) {
                     if(recentGrabs[i].active && recentGrabs[i].bullish) {
                        hasLiqGrab = true;
                        break;
                     }
                  }
                  buySignal = buySignal && hasLiqGrab;
               }
               if(sellSignal) {
                  bool hasLiqGrab = false;
                  for(int i=0; i<MAX_GRABS; i++) {
                     if(recentGrabs[i].active && !recentGrabs[i].bullish) {
                        hasLiqGrab = true;
                        break;
                     }
                  }
                  sellSignal = sellSignal && hasLiqGrab;
               }
               break;
            case HIGH_VOLATILITY:
               // In high volatility, require order block confirmation
               if(buySignal) {
                  bool hasOB = false;
                  for(int i=0; i<MAX_BLOCKS; i++) {
                     if(recentBlocks[i].valid && recentBlocks[i].bullish) {
                        hasOB = true;
                        break;
                     }
                  }
                  buySignal = buySignal && hasOB;
               }
               if(sellSignal) {
                  bool hasOB = false;
                  for(int i=0; i<MAX_BLOCKS; i++) {
                     if(recentBlocks[i].valid && !recentBlocks[i].bullish) {
                        hasOB = true;
                        break;
                     }
                  }
                  sellSignal = sellSignal && hasOB;
               }
               break;
            case BREAKOUT:
               // In breakout regime, look for fair value gaps
               if(buySignal) {
                  bool hasFVG = false;
                  for(int i=0; i<MAX_FVGS; i++) {
                     if(recentFVGs[i].active && recentFVGs[i].bullish) {
                        hasFVG = true;
                        break;
                     }
                  }
                  buySignal = buySignal && hasFVG;
               }
               if(sellSignal) {
                  bool hasFVG = false;
                  for(int i=0; i<MAX_FVGS; i++) {
                     if(recentFVGs[i].active && !recentFVGs[i].bullish) {
                        hasFVG = true;
                        break;
                     }
                  }
                  sellSignal = sellSignal && hasFVG;
               }
               break;
         }
      }
   }
   
   // Execute trade if we have a valid signal
   if(buySignal || sellSignal)
   {
      ENUM_ORDER_TYPE orderType = buySignal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double entryPrice = orderType == ORDER_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Calculate stop loss - either standard or optimal
      double stopLoss = CalculateOptimalStopLoss(orderType, entryPrice);
      int slPips = (int)(MathAbs(entryPrice - stopLoss) / GetPipSize());
      
      // Calculate position size based on risk
      double lotSize = CalculateLotSize(RiskPercentage, slPips);
      
      // Calculate take profit - either standard or dynamic
      double takeProfit;
      if(EnableDynamicTakeProfit && EnableSMCFeatures) {
         takeProfit = CalculateDynamicTakeProfit(orderType, entryPrice, stopLoss);
      } else {
         double pip = GetPipSize();
         takeProfit = orderType == ORDER_TYPE_BUY ? entryPrice + InitialTakeProfit * pip : entryPrice - InitialTakeProfit * pip;
      }
      
      // Log trade details
      Print("Entry: ", (buySignal ? "BUY" : "SELL"), 
           " | Regime: ", RegimeToString(currentRegime),
           " | Lot: ", lotSize, 
           " | Price: ", entryPrice,
           " | SL: ", stopLoss,
           " | TP: ", takeProfit);
      
      // Open the position
      OpenPositionAdvanced(orderType, lotSize, stopLoss, takeProfit);
   }
}

//+------------------------------------------------------------------+
//| Advanced position opening function with SMC features             |
//+------------------------------------------------------------------+
void OpenPositionAdvanced(ENUM_ORDER_TYPE orderType, double lotSize, double stopLoss, double takeProfit)
{
   // Reset request/result structures
   MqlTradeRequest request;
   ZeroMemory(request);
   MqlTradeResult result;
   ZeroMemory(result);
   
   // Get entry price
   double entryPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Fill trade request
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = entryPrice;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 5;
   request.magic = MagicNumber;
   request.type_filling = ORDER_FILLING_FOK;
   request.comment = "SMCScalper_v2";
   
   // Log trade details
   Print("OrderSend: type=", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", 
         " price=", entryPrice, 
         " sl=", stopLoss, 
         " tp=", takeProfit,
         " volume=", lotSize);
   
   // Submit the order
   if(!OrderSend(request, result))
   {
      Print("OrderSend DEAL failed: ", GetLastError());
      lastTradeTime = 0; // Allow retry
   }
   else
   {
      // Record successful trade
      lastTradeTime = TimeCurrent();
      trailingActive = false;
      trailingLevel = 0;
      trailingTP = 0;
   }
}

//+------------------------------------------------------------------+
//| Advanced trailing stop management with SMC concepts              |
//+------------------------------------------------------------------+
void TrailPositions()
{
   double pip = GetPipSize();
   
   // Process all positions with our magic number
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      // Get position details
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPips = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / pip : (openPrice - currentPrice) / pip;
      double profitPercent = (PositionGetDouble(POSITION_PROFIT) / AccountInfoDouble(ACCOUNT_BALANCE)) * 100;
      bool isBuy = (posType == POSITION_TYPE_BUY);
      
      Print("Trail: ", (isBuy ? "BUY" : "SELL"), " | Open: ", openPrice, " | Price: ", currentPrice, 
            " | SL: ", currentSL, " | TP: ", currentTP, " | ProfitPips: ", profitPips);
      
      // If SMC advanced trailing is enabled and we have enough profit
      if(EnableSMCFeatures && EnableAdvancedTrailing && profitPips >= TrailingStep)
      {
         double newSL = currentSL;
         
         // Phase 1: Break-even move (with small buffer) when in some profit
         if(profitPips >= TrailingStep * 1.5) {
            double breakEvenLevel = isBuy ? openPrice + 5 * pip : openPrice - 5 * pip;
            if((isBuy && (currentSL < openPrice || currentSL == 0)) || 
               (!isBuy && (currentSL > openPrice || currentSL == 0))) {
               // Move to breakeven with a small buffer
               newSL = breakEvenLevel;
               ModifyPositionSLTP(ticket, newSL, currentTP);
               Print("Moving to breakeven+ SL: ", newSL);
               continue; // Skip other trailing for this update
            }
         }
         
         // Phase 2: Adaptive trailing based on market regime and structure
         if(EnableMarketRegimeFiltering && currentRegime >= 0) {
            double atr = GetATR(_Symbol, PERIOD_CURRENT, 14, 0);
            double trailMultiplier = TrailingStopMultiplier; // Default multiplier
            
            // Adjust trail distance based on market regime
            switch(currentRegime) {
               case TRENDING_UP:
               case TRENDING_DOWN:
                  // Looser trail in trending markets
                  trailMultiplier *= 1.5;
                  break;
               case HIGH_VOLATILITY:
                  // Much looser trail in volatile markets
                  trailMultiplier *= 2.0;
                  break;
               case CHOPPY:
               case RANGING_NARROW:
                  // Tighter trail in choppy/ranging markets
                  trailMultiplier *= 0.8;
                  break;
            }
            
            // Calculate ATR-based trail distance
            double trailDistance = atr * trailMultiplier;
            
            // Calculate new stop loss level
            double atrBasedSL = isBuy ? currentPrice - trailDistance : currentPrice + trailDistance;
            
            // Use the ATR-based stop if it's better than current
            if((isBuy && atrBasedSL > currentSL) || (!isBuy && atrBasedSL < currentSL)) {
               newSL = atrBasedSL;
            }
         }
         // If not using market regime or no valid regime, use standard trailing
         else {
            double standardSL = isBuy ? currentPrice - TrailingStop * pip : currentPrice + TrailingStop * pip;
            if((isBuy && standardSL > currentSL) || (!isBuy && standardSL < currentSL)) {
               newSL = standardSL;
            }
         }
         
         // If we have a new SL, update the position
         if(newSL != currentSL) {
            ModifyPositionSLTP(ticket, newSL, currentTP);
            Print("Trail updated to: ", newSL);
         }
      }
      
      // Original profit trailing logic (enhanced)
      double profitTrailStartPips = InitialTakeProfit * profitTrailStart;
      static double maxProfitPips[2] = {0, 0}; // [0]=buy, [1]=sell
      int idx = isBuy ? 0 : 1;
      
      if(profitPips >= profitTrailStartPips)
      {
         if(profitPips > maxProfitPips[idx])
            maxProfitPips[idx] = profitPips;
         
         // Apply customized buffer based on market regime if enabled
         double buffer = ProfitTrailBuffer;
         if(EnableSMCFeatures && EnableMarketRegimeFiltering && currentRegime >= 0) {
            // Adjust buffer based on market regime
            switch(currentRegime) {
               case TRENDING_UP:
               case TRENDING_DOWN:
                  // Wider buffer in trending markets
                  buffer *= 1.3;
                  break;
               case HIGH_VOLATILITY:
                  // Much wider buffer in high volatility
                  buffer *= 2.0;
                  break;
               case CHOPPY:
                  // Tighter buffer in choppy markets
                  buffer *= 0.7;
                  break;
            }
         }
         
         double profitTrailLevel = maxProfitPips[idx] - buffer;
         
         // Advanced protection: Close faster when we see a reversal pattern
         if(EnableSMCFeatures && maxProfitPips[idx] > profitTrailStartPips * 1.5) {
            // Check for opposing liquidity grabs (potential reversal)
            bool recentOpposingGrab = false;
            for(int j=0; j<MAX_GRABS; j++) {
               if(!recentGrabs[j].active) continue;
               
               // For buy positions, check for bearish grabs
               if(isBuy && !recentGrabs[j].bullish && 
                  TimeCurrent() - recentGrabs[j].time < 60*15) { // Within last 15 minutes
                  recentOpposingGrab = true;
                  break;
               }
               // For sell positions, check for bullish grabs
               else if(!isBuy && recentGrabs[j].bullish && 
                       TimeCurrent() - recentGrabs[j].time < 60*15) {
                  recentOpposingGrab = true;
                  break;
               }
            }
            
            // Tighten trail if we see opposing liquidity grabs
            if(recentOpposingGrab) {
               profitTrailLevel = maxProfitPips[idx] - buffer * 0.5; // Tighter buffer
               Print("Tightening profit trail due to opposing liquidity grab");
            }
         }
         
         if(profitPips < profitTrailLevel)
         {
            Print("Profit trail triggered, closing: ", profitPips, " < ", profitTrailLevel);
            ClosePosition(ticket, PositionGetDouble(POSITION_VOLUME));
            maxProfitPips[idx] = 0; // Reset for next trade
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify position stop loss and take profit                         |
//+------------------------------------------------------------------+
bool ModifyPositionSLTP(ulong ticket, double newSL, double newTP)
{
   // First select the position
   if(!PositionSelectByTicket(ticket)) return false;
   
   // Prepare the request
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = newSL;
   request.tp = newTP;
   request.magic = MagicNumber;
   
   // Send the request
   bool success = OrderSend(request, result);
   
   if(!success) {
      Print("ModifyPositionSLTP failed: ", GetLastError());
   }
   
   return success;
}

//+------------------------------------------------------------------+
//| Close a position                                                  |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket, double volume)
{
   // First select the position
   if(!PositionSelectByTicket(ticket)) return false;
   
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double closePrice = posType == POSITION_TYPE_BUY ? 
                       SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                       SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Prepare the request
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = _Symbol;
   request.volume = volume;
   request.type = posType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = closePrice;
   request.deviation = 5;
   request.magic = MagicNumber;
   
   // Send the request
   bool success = OrderSend(request, result);
   
   if(!success) {
      Print("ClosePosition failed: ", GetLastError());
   }
   else {
      // Update trade statistics
      double profit = PositionGetDouble(POSITION_PROFIT);
      
      if(profit > 0) {
         winStreak++;
         lossStreak = 0;
         consecutiveLosses = 0;
      }
      else {
         lossStreak++;
         winStreak = 0;
         consecutiveLosses++;
         
         // Activate emergency mode if too many consecutive losses
         if(consecutiveLosses >= MaxConsecutiveLosses) {
            emergencyMode = true;
            Print("Emergency mode activated: ", consecutiveLosses, " consecutive losses");
         }
      }
      
      // Update regime statistics
      if(EnableMarketRegimeFiltering && currentRegime >= 0) {
         if(profit > 0) regimeWins[currentRegime]++;
         else regimeLosses[currentRegime]++;
         regimeProfit[currentRegime] += profit;
         
         // Calculate regime accuracy
         int totalTrades = regimeWins[currentRegime] + regimeLosses[currentRegime];
         if(totalTrades > 0) {
            regimeAccuracy[currentRegime] = (double)regimeWins[currentRegime] / totalTrades;
         }
      }
   }
   
   return success;
}
//+------------------------------------------------------------------+
