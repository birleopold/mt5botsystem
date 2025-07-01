//+------------------------------------------------------------------+
//|                      ScalpingAutoTrail with SMC Hybrid         |
//|                        Copyright 2025, Leo Software            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Leo Software"
#property link      "https://www.example.com"
#property version   "2.00"
#property strict

#include <Math/Stat/Normal.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/Trade.mqh>

// Core Constants and Definitions
#define MAX_BLOCKS 20
#define MAX_GRABS 10
#define MAX_FVGS 10
#define METRIC_WINDOW 100

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
#define REGIME_COUNT 9

// SMC structure definitions
struct SwingPoint {
    int barIndex;
    double price;
    datetime time;
    int score; // Quality score for the swing
    bool isValid;
};

struct LiquidityGrab {
    datetime time;
    double price;
    bool isBullish;  // true for bullish (buying) liquidity grab, false for bearish
    bool isExpired;  // whether this liquidity has been used up
    double score;    // quality score
};

struct FairValueGap {
    datetime time;
    double lowPrice;
    double highPrice;
    double midPrice;
    bool isBullish;  // true for bullish (buyers in control), false for bearish
    bool isFilled;   // whether this gap has been filled
    double score;    // quality score
};

struct OrderBlock {
    datetime blockTime;
    double startPrice;
    double endPrice;
    double volume;
    bool isValid;    // order block validity
    double score;    // quality score
};

// Input parameters
// --- Risk Management ---
input double   RiskPercent = 1.0;          // Risk percentage per trade
input bool     FixedLot = false;           // Use fixed lot size instead of % risk
input double   LotSize = 0.01;             // Fixed lot size (if FixedLot=true)
input int      InitialStopLoss = 50;       // Initial Stop Loss (pips)
input int      InitialTakeProfit = 100;    // Initial Take Profit (pips)
input int      Slippage = 10;             // Allowed slippage in points
input double TrailingStop = 50;      // Trailing Stop in pips
input double TrailingStep = 10;      // Minimum pips to move trailing stop
input double ActivationDistance = 20; // Minimum profit in pips to activate trailing
input double BreakEvenPips = 15;     // Pips in profit to move stop to break even
input double BreakEvenBuffer = 2;    // Buffer pips above/below entry after break even
input double TrailingATRMultiplier = 2.0; // Multiplier for ATR-based trailing

// SMC Strategy Parameters
input group "===== SMC FEATURES ====="
input bool EnableOptimalStopLoss = true;     // Use swing-point based optimal stop loss
input bool EnableDynamicTakeProfit = true;   // Use dynamic take profit calculation
input bool EnableAdvancedTrailing = true;    // Use advanced structure-based trailing
input bool EnableMarketRegimeFiltering = true; // Filter trades based on market regime

// SMC Structure Filtering
input group "===== SMC STRUCTURE FILTERING ====="
input bool EnableOrderBlockFiltering = true;  // Filter entries using order blocks
input bool StrictOrderBlockFiltering = false; // Strict mode (only enter with valid OB)
input bool EnableLiquidityGrabFiltering = true; // Filter entries using liquidity grabs
input bool StrictLiquidityGrabFiltering = false; // Strict mode for liquidity grabs
input bool EnableFVGFiltering = true;         // Filter entries using fair value gaps
input bool StrictFVGFiltering = false;        // Strict mode for fair value gaps
input int LookbackBars = 300;                // Bars to look back for structures

// Risk Management
input group "===== RISK MANAGEMENT ====="
input double SL_ATR_Mult = 1.5;              // ATR multiplier for stop loss
input double BaseRiskReward = 2.0;           // Base risk:reward ratio
input double MinRiskReward = 1.5;            // Minimum risk:reward allowed
input double MaxRiskReward = 4.0;            // Maximum risk:reward allowed
input int      SlowMAPeriod = 20;          // Slow MA Period
input int      MagicNumber = 12345;        // EA Magic Number
input int      MaxConsecutiveLosses = 3;   // Stop trading after this many consecutive losses

// --- Additional Parameters ---
input bool     EnableAggressiveTrailing = true;   // Use aggressive trailing stops
input double   TrailingActivationPct = 0.5;      // When to activate trailing (% of TP reached)
input double   TrailingStopMultiplier = 0.5;     // Trailing stop multiplier of ATR
input int      MinBlockStrength = 1;             // Minimum order block strength for valid signal
input bool     DisplayDebugInfo = true;          // Display debug info on chart
input int      FastMAPeriod = 5;                // Fast MA Period - added to fix compilation error

// Note: Other SMC parameters now defined in the main parameter section above

// Global variables
int fastMAHandle, slowMAHandle;
double minLot, maxLot;

// --- SMC Global Variables ---
LiquidityGrab liquidityGrabs[MAX_GRABS];
int liquidityGrabCount = 0;

FairValueGap fairValueGaps[MAX_FVGS];
int fvgCount = 0;

OrderBlock bullishOB;
OrderBlock bearishOB;

SwingPoint qualitySwingPoints[20];
int swingPointCount = 0;

double FVGMinSize = 0.5;

// --- Trade Statistics ---
int totalTrades = 0, winTrades = 0, lossTrades = 0;
int consecutiveLosses = 0;
double totalProfit = 0.0;

// --- Market Regime Statistics ---
int regimeWins[REGIME_COUNT];
int regimeLosses[REGIME_COUNT];

// --- Trading variables ---
MqlTradeRequest request;  // Trade request structure
MqlTradeResult result;    // Trade result structure
CPositionInfo tradePositionInfo; // Position information object
double prevStopLoss = 0;  // Previous stop loss level
double prevPrice = 0;     // Previous entry price
bool emergencyMode = false; // Emergency mode after consecutive losses
int currentRegime = -1;    // Current market regime
double regimeProfit[REGIME_COUNT];
double regimeAccuracy[REGIME_COUNT];
int lastRegime = -1;

//+------------------------------------------------------------------+
//| Convert regime code to string description                         |
//+------------------------------------------------------------------+
string RegimeToString(int regime)
{
   switch(regime)
   {
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

// --- Trading Status ---
datetime lastTradeTime = 0;
datetime lastSignalTime = 0;
bool trailingActive = false;
double trailingLevel = 0;
double trailingTP = 0;
string lastErrorMessage = "";

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

// Helper function for getting ATR for different symbols and timeframes
double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift) {
    int handle = iATR(symbol, timeframe, period);
    double buffer[];
    if(CopyBuffer(handle, 0, shift, 1, buffer) > 0) {
        double result = buffer[0];
        IndicatorRelease(handle);
        return result;
    }
    IndicatorRelease(handle);
    return SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;
}

// Helper function for getting Bollinger Bands values
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
//| Market Regime Detection from SMC Scalper Hybrid                  |
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
//| Detect liquidity grabs from SMC strategy                       |
//+------------------------------------------------------------------+
void DetectLiquidityGrabs() {
   int lookback = MathMin(LookbackBars, Bars(_Symbol, PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   long volume[];
   
   ArrayResize(high, lookback);
   ArrayResize(low, lookback);
   ArrayResize(open, lookback);
   ArrayResize(close, lookback);
   ArrayResize(time, lookback);
   ArrayResize(volume, lookback);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
   CopyOpen(_Symbol, PERIOD_CURRENT, 0, lookback, open);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, lookback, close);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, lookback, time);
   CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, lookback, volume);
   
   // Reset liquidityGrabs array
   liquidityGrabCount = 0;
   
   // Find liquidity grabs
   for(int i=2; i<lookback-2; i++) {
      // Bullish liquidity grab (sweep below previous low, then reversal)
      if(low[i] < low[i+1] && low[i] < low[i+2] && close[i] > open[i]) {
         LiquidityGrab grab;
         grab.time = time[i];
         grab.price = low[i];
         grab.isBullish = true;
         grab.isExpired = false;
         grab.score = 1.0; // Base score
         
         // Calculate score based on quality factors
         
         // 1. Strength of reversal candle
         double bodySize = MathAbs(close[i] - open[i]);
         double totalSize = high[i] - low[i];
         if(bodySize > totalSize * 0.6) // Strong body
            grab.score += 1.0;
            
         // 2. Volume on reversal candle
         if(volume[i] > volume[i+1] * 1.5) // Volume spike
            grab.score += 1.0;
            
         // 3. Depth of sweep (how much below prior low)
         double sweepDepth = (low[i+1] - low[i]) / low[i+1] * 100;
         if(sweepDepth > 0.1) // Meaningful sweep
            grab.score += 0.5;
            
         // 4. Confirmed by next candle
         if(i > 0 && close[i-1] > open[i-1] && low[i-1] > low[i])
            grab.score += 1.0;
            
         // 5. Market regime alignment
         if(currentRegime == TRENDING_UP || currentRegime == BREAKOUT)
            grab.score += 1.0;
            
         // Check if this grab has expired (price below the low again)
         for(int j=0; j<i; j++) {
            if(low[j] < grab.price) {
               grab.isExpired = true;
               break;
            }
         }
         
         // Only add high-quality grabs
         if(grab.score >= 2.0 && liquidityGrabCount < MAX_GRABS) {
            liquidityGrabs[liquidityGrabCount] = grab;
            liquidityGrabCount++;
         }
      }
      
      // Bearish liquidity grab (sweep above previous high, then reversal)
      if(high[i] > high[i+1] && high[i] > high[i+2] && close[i] < open[i]) {
         LiquidityGrab grab;
         grab.time = time[i];
         grab.price = high[i];
         grab.isBullish = false;
         grab.isExpired = false;
         grab.score = 1.0; // Base score
         
         // Calculate score based on quality factors
         
         // 1. Strength of reversal candle
         double bodySize = MathAbs(close[i] - open[i]);
         double totalSize = high[i] - low[i];
         if(bodySize > totalSize * 0.6) // Strong body
            grab.score += 1.0;
            
         // 2. Volume on reversal candle
         if(volume[i] > volume[i+1] * 1.5) // Volume spike
            grab.score += 1.0;
            
         // 3. Depth of sweep (how much above prior high)
         double sweepDepth = (high[i] - high[i+1]) / high[i+1] * 100;
         if(sweepDepth > 0.1) // Meaningful sweep
            grab.score += 0.5;
            
         // 4. Confirmed by next candle
         if(i > 0 && close[i-1] < open[i-1] && high[i-1] < high[i])
            grab.score += 1.0;
            
         // 5. Market regime alignment
         if(currentRegime == TRENDING_DOWN || currentRegime == BREAKOUT)
            grab.score += 1.0;
            
         // Check if this grab has expired (price above the high again)
         for(int j=0; j<i; j++) {
            if(high[j] > grab.price) {
               grab.isExpired = true;
               break;
            }
         }
         
         // Only add high-quality grabs
         if(grab.score >= 2.0 && liquidityGrabCount < MAX_GRABS) {
            liquidityGrabs[liquidityGrabCount] = grab;
            liquidityGrabCount++;
         }
      }
   }
   
   // Sort grabs by score (highest first)
   if(liquidityGrabCount > 1) {
      for(int i=0; i<liquidityGrabCount-1; i++) {
         for(int j=i+1; j<liquidityGrabCount; j++) {
            if(liquidityGrabs[j].score > liquidityGrabs[i].score) {
               LiquidityGrab temp = liquidityGrabs[i];
               liquidityGrabs[i] = liquidityGrabs[j];
               liquidityGrabs[j] = temp;
            }
         }
      }
   }
   
   if(liquidityGrabCount > 0) {
      Print("Found ", liquidityGrabCount, " liquidity grabs. Top score: ", liquidityGrabs[0].score);
   }
}

//+------------------------------------------------------------------+
//| Detect fair value gaps from SMC strategy                        |
//+------------------------------------------------------------------+
void DetectFairValueGaps() {
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
   
   // Reset FVG count
   fvgCount = 0;
   
   // Find bullish fair value gaps (low of current bar > high of previous bar)
   for(int i=2; i<lookback-2; i++) {
      if(low[i] > high[i+1]) {
         // Bullish FVG found
         FairValueGap fvg;
         fvg.time = time[i];
         fvg.lowPrice = high[i+1]; // High of bar before gap
         fvg.highPrice = low[i];   // Low of bar after gap
         fvg.midPrice = (fvg.lowPrice + fvg.highPrice) / 2;
         fvg.isBullish = true;
         fvg.isFilled = false;
         
         // Calculate gap size and score
         double gapSize = (fvg.highPrice - fvg.lowPrice) / fvg.lowPrice * 100;
         fvg.score = 1.0; // Base score
         
         // Larger gaps are more significant
         if(gapSize > 0.1) fvg.score += 1;
         if(gapSize > 0.2) fvg.score += 1;
         
         // Check if this gap was created after a liquidity grab (more significant)
         for(int j=0; j<liquidityGrabCount; j++) {
            if(liquidityGrabs[j].isBullish && liquidityGrabs[j].time > time[i+1] && liquidityGrabs[j].time <= time[i]) {
               fvg.score += 2;
               break;
            }
         }
         
         // Check if the gap is still valid (not filled)
         for(int j=0; j<i; j++) {
            if(low[j] <= fvg.lowPrice) {
               fvg.isFilled = true;
               break;
            }
         }
         
         // If the gap is significant and not filled, add it
         if(gapSize >= FVGMinSize && !fvg.isFilled) {
            if(fvgCount < MAX_FVGS) {
               fairValueGaps[fvgCount] = fvg;
               fvgCount++;
            }
         }
      }
      
      // Find bearish fair value gaps (high of current bar < low of previous bar)
      if(high[i] < low[i+1]) {
         // Bearish FVG found
         FairValueGap fvg;
         fvg.time = time[i];
         fvg.highPrice = low[i+1]; // Low of bar before gap
         fvg.lowPrice = high[i];   // High of bar after gap
         fvg.midPrice = (fvg.lowPrice + fvg.highPrice) / 2;
         fvg.isBullish = false;
         fvg.isFilled = false;
         
         // Calculate gap size and score
         double gapSize = (fvg.highPrice - fvg.lowPrice) / fvg.lowPrice * 100;
         fvg.score = 1.0; // Base score
         
         // Larger gaps are more significant
         if(gapSize > 0.1) fvg.score += 1;
         if(gapSize > 0.2) fvg.score += 1;
         
         // Check if this gap was created after a liquidity grab (more significant)
         for(int j=0; j<liquidityGrabCount; j++) {
            if(!liquidityGrabs[j].isBullish && liquidityGrabs[j].time > time[i+1] && liquidityGrabs[j].time <= time[i]) {
               fvg.score += 2;
               break;
            }
         }
         
         // Check if the gap is still valid (not filled)
         for(int j=0; j<i; j++) {
            if(high[j] >= fvg.highPrice) {
               fvg.isFilled = true;
               break;
            }
         }
         
         // If the gap is significant and not filled, add it
         if(gapSize >= FVGMinSize && !fvg.isFilled) {
            if(fvgCount < MAX_FVGS) {
               fairValueGaps[fvgCount] = fvg;
               fvgCount++;
            }
         }
      }
   }
   
   // Sort FVGs by score (highest first)
   if(fvgCount > 1) {
      for(int i=0; i<fvgCount-1; i++) {
         for(int j=i+1; j<fvgCount; j++) {
            if(fairValueGaps[j].score > fairValueGaps[i].score) {
               FairValueGap temp = fairValueGaps[i];
               fairValueGaps[i] = fairValueGaps[j];
               fairValueGaps[j] = temp;
            }
         }
      }
   }
   
   if(fvgCount > 0) {
      Print("Found ", fvgCount, " fair value gaps. Top score: ", fairValueGaps[0].score);
   }
}

//+------------------------------------------------------------------+
//| Detect order blocks for SMC strategy                           |
//+------------------------------------------------------------------+
void DetectOrderBlocks() {
   int lookback = MathMin(LookbackBars, Bars(_Symbol, PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   long volume[];
   
   ArrayResize(high, lookback);
   ArrayResize(low, lookback);
   ArrayResize(open, lookback);
   ArrayResize(close, lookback);
   ArrayResize(time, lookback);
   ArrayResize(volume, lookback);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
   CopyOpen(_Symbol, PERIOD_CURRENT, 0, lookback, open);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, lookback, close);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, lookback, time);
   CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, lookback, volume);
   
   // Reset order blocks
   bullishOB.isValid = false;
   bearishOB.isValid = false;
   
   // Detect bullish order blocks (bearish candle followed by strong bullish move)
   for(int i=3; i<lookback-5; i++) {
      // Look for a bearish candle that preceded a bullish move
      if(close[i] < open[i] && close[i+1] > open[i+1] && close[i+2] > open[i+2]) {
         // Check if price made a significant move up after this candle
         double priceAfter = MathMax(close[i-3], close[i-2]); // Look 2-3 candles ahead
         double priceBefore = close[i];
         double movePercent = (priceAfter - priceBefore) / priceBefore * 100;
         
         // Only consider significant moves (0.3% or greater)
         if(movePercent >= 0.3) {
            OrderBlock candidate;
            candidate.blockTime = time[i];
            candidate.startPrice = high[i];
            candidate.endPrice = low[i];
            candidate.volume = (double)volume[i];
            candidate.isValid = true;
            candidate.score = 1.0;
            
            // Enhance score based on characteristics
            
            // 1. Volume analysis
            if(volume[i] > volume[i+1] * 1.3)
               candidate.score += 0.5;
            
            // 2. Candle body size (strong bearish candle is better)
            double bodySize = MathAbs(open[i] - close[i]);
            double fullSize = high[i] - low[i];
            if(bodySize > fullSize * 0.7)
               candidate.score += 0.5;
            
            // 3. Price hasn't retested the zone
            bool retested = false;
            for(int j=i-1; j>=0; j--) {
               if(low[j] <= high[i] && high[j] >= low[i]) {
                  retested = true;
                  break;
               }
            }
            if(!retested)
               candidate.score += 1.0;
            
            // 4. Market regime context
            if(currentRegime == TRENDING_UP || currentRegime == BREAKOUT)
               candidate.score += 0.5;
            
            // If this is better than our current best bullish order block, replace it
            if(!bullishOB.isValid || candidate.score > bullishOB.score) {
               bullishOB = candidate;
            }
         }
      }
   }
   
   // Detect bearish order blocks (bullish candle followed by strong bearish move)
   for(int i=3; i<lookback-5; i++) {
      // Look for a bullish candle that preceded a bearish move
      if(close[i] > open[i] && close[i+1] < open[i+1] && close[i+2] < open[i+2]) {
         // Check if price made a significant move down after this candle
         double priceAfter = MathMin(close[i-3], close[i-2]); // Look 2-3 candles ahead
         double priceBefore = close[i];
         double movePercent = (priceBefore - priceAfter) / priceBefore * 100;
         
         // Only consider significant moves (0.3% or greater)
         if(movePercent >= 0.3) {
            OrderBlock candidate;
            candidate.blockTime = time[i];
            candidate.startPrice = low[i];
            candidate.endPrice = high[i];
            candidate.volume = (double)volume[i];
            candidate.isValid = true;
            candidate.score = 1.0;
            
            // Enhance score based on characteristics
            
            // 1. Volume analysis
            if(volume[i] > volume[i+1] * 1.3)
               candidate.score += 0.5;
            
            // 2. Candle body size (strong bullish candle is better)
            double bodySize = MathAbs(open[i] - close[i]);
            double fullSize = high[i] - low[i];
            if(bodySize > fullSize * 0.7)
               candidate.score += 0.5;
            
            // 3. Price hasn't retested the zone
            bool retested = false;
            for(int j=i-1; j>=0; j--) {
               if(low[j] <= high[i] && high[j] >= low[i]) {
                  retested = true;
                  break;
               }
            }
            if(!retested)
               candidate.score += 1.0;
            
            // 4. Market regime context
            if(currentRegime == TRENDING_DOWN || currentRegime == BREAKOUT)
               candidate.score += 0.5;
            
            // If this is better than our current best bearish order block, replace it
            if(!bearishOB.isValid || candidate.score > bearishOB.score) {
               bearishOB = candidate;
            }
         }
      }
   }
   
   // Log order block information
   if(bullishOB.isValid) {
      Print("Found bullish order block at ", TimeToString(bullishOB.blockTime), 
            " with score ", DoubleToString(bullishOB.score, 1));
   }
   if(bearishOB.isValid) {
      Print("Found bearish order block at ", TimeToString(bearishOB.blockTime), 
            " with score ", DoubleToString(bearishOB.score, 1));
   }
}

//+------------------------------------------------------------------+
//| Validate order blocks based on current price action              |
//+------------------------------------------------------------------+
void ValidateOrderBlocks() {
   // Get current price
   double currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // Validate bullish order block
   if(bullishOB.isValid) {
      // For bullish blocks, price should not break below the zone
      if(currentPrice < bullishOB.endPrice) {
         bullishOB.isValid = false;
         Print("Bullish order block invalidated at price ", currentPrice);
      }
   }
   
   // Validate bearish order block
   if(bearishOB.isValid) {
      // For bearish blocks, price should not break above the zone
      if(currentPrice > bearishOB.endPrice) {
         bearishOB.isValid = false;
         Print("Bearish order block invalidated at price ", currentPrice);
      }
   }
   
   // Also validate fair value gaps (mark them as filled)
   for(int i=0; i<fvgCount; i++) {
      if(fairValueGaps[i].isFilled) continue;
      
      if(fairValueGaps[i].isBullish) {
         // Bullish FVG is filled if price goes below lower boundary
         if(currentPrice <= fairValueGaps[i].lowPrice) {
            fairValueGaps[i].isFilled = true;
            Print("Bullish FVG filled at price ", currentPrice);
         }
      } else {
         // Bearish FVG is filled if price goes above upper boundary
         if(currentPrice >= fairValueGaps[i].highPrice) {
            fairValueGaps[i].isFilled = true;
            Print("Bearish FVG filled at price ", currentPrice);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize moving average indicators
   fastMAHandle = iMA(_Symbol, PERIOD_CURRENT, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   slowMAHandle = iMA(_Symbol, PERIOD_CURRENT, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   
   if(fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles!");
      return INIT_FAILED;
   }
   
   // Get min/max lot sizes
   minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   // Initialize SMC structures
   liquidityGrabCount = 0;
   fvgCount = 0;
   swingPointCount = 0;
   
   // Initialize OrderBlocks
   bullishOB.isValid = false;
   bearishOB.isValid = false;
   
   // Reset the current market regime
   currentRegime = -1;
   if(EnableMarketRegimeFiltering) {
      // Determine initial market regime
      currentRegime = FastRegimeDetection(_Symbol);
      string regimeStr = RegimeToString(currentRegime);
      Print("Initial market regime: ", regimeStr);
   }
   
   // Initialize trade statistics
   for(int i=0; i<REGIME_COUNT; i++) {
      regimeWins[i] = 0;
      regimeLosses[i] = 0;
      regimeProfit[i] = 0.0;
      regimeAccuracy[i] = 0.0;
   }
   
   // Reset trading status variables
   emergencyMode = false;
   trailingActive = false;
   trailingLevel = 0;
   trailingTP = 0;
   consecutiveLosses = 0;
   lastErrorMessage = "";
   
   // Set current market regime
   if(EnableMarketRegimeFiltering) {
      currentRegime = FastRegimeDetection(_Symbol);
   } else {
      currentRegime = LOW_VOLATILITY; // Default regime
   }
   
   Print("[Init] ScalpingAutoTrail with SMC Hybrid initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(fastMAHandle);
   IndicatorRelease(slowMAHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Skip if emergency mode is active (due to consecutive losses)
   if(emergencyMode) {
      Print("Emergency mode active. Trading paused due to consecutive losses.");
      return;
   }
   
   // Verify we have enough bars for analysis
   if(Bars(_Symbol, PERIOD_CURRENT) < LookbackBars) return;
   
   // Update SMC structures on new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   if(currentBarTime != lastBarTime) {
      lastBarTime = currentBarTime;
      
      // Update market regime if enabled
      if(EnableMarketRegimeFiltering) {
         int prevRegime = currentRegime;
         currentRegime = FastRegimeDetection(_Symbol);
         
         // Log regime change
         if(prevRegime != currentRegime) {
            string prevRegimeStr = RegimeToString(prevRegime);
            string currRegimeStr = RegimeToString(currentRegime);
            Print("Market regime changed from ", prevRegimeStr, 
                  " to ", currRegimeStr);
         }
      }
      
      // Update SMC structures
      if(EnableOrderBlockFiltering) {
         DetectOrderBlocks();
         ValidateOrderBlocks(); // Validate existing order blocks
      }
          
      if(EnableLiquidityGrabFiltering)
         DetectLiquidityGrabs();
         
      if(EnableFVGFiltering)
         DetectFairValueGaps();
         
      // Update swing points for optimal stop loss placement
      if(EnableOptimalStopLoss) {
         SwingPoint tempPoints[];
         FindQualitySwingPoints(true, 100, tempPoints, swingPointCount);
      }
   }
   
   // Manage open positions if we have any
   if(PositionsTotal() > 0) {
      // Use advanced trailing stop management
      TrailPositions();
   }
   // Otherwise look for new entry signals
   else {
      CheckForEntry();
   }
}

//+------------------------------------------------------------------+
//| Find quality swing points for optimal stop loss placement        |
//+------------------------------------------------------------------+
void FindQualitySwingPoints(bool isBuy, int lookbackBars, SwingPoint &swingPoints[], int &count) {
    count = 0;
    double high[], low[], close[], open[], volume[];
    long vol[];
    datetime time[];
    
    int bars = MathMin(lookbackBars, Bars(_Symbol, PERIOD_CURRENT));
    
    ArrayResize(high, bars);
    ArrayResize(low, bars);
    ArrayResize(open, bars);
    ArrayResize(close, bars);
    ArrayResize(volume, bars);
    ArrayResize(time, bars);
    
    CopyHigh(_Symbol, PERIOD_CURRENT, 0, bars, high);
    CopyLow(_Symbol, PERIOD_CURRENT, 0, bars, low);
    CopyOpen(_Symbol, PERIOD_CURRENT, 0, bars, open);
    CopyClose(_Symbol, PERIOD_CURRENT, 0, bars, close);
    CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, bars, vol);
    CopyTime(_Symbol, PERIOD_CURRENT, 0, bars, time);
    
    // Convert to double for calculations
    for(int i=0; i<bars; i++) {
        volume[i] = (double)vol[i];
    }
    
    // Find swing points
    int maxSwings = 20;
    ArrayResize(swingPoints, maxSwings);
    
    // For buy trades we look for swing lows
    if(isBuy) {
        for(int i=2; i<bars-2; i++) {
            // Check if this is a swing low
            if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i+1] && low[i] < low[i+2]) {
                SwingPoint sp;
                sp.barIndex = i;
                sp.price = low[i];
                sp.time = time[i];
                sp.score = 1; // Base score
                
                // Calculate swing score based on various factors
                
                // 1. Volume at the swing point
                if(volume[i] > volume[i-1]*1.5 && volume[i] > volume[i+1]*1.5)
                    sp.score += 2;
                
                // 2. Price rejection after swing (bullish confirmation)
                if(close[i] > (high[i] + low[i])/2 && close[i-1] > open[i-1])
                    sp.score += 2;
                
                // 3. Higher timeframe alignment
                int htf_handle = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
                double htf_ma[];
                if(CopyBuffer(htf_handle, 0, 0, 1, htf_ma) > 0) {
                    if(low[i] > htf_ma[0])
                        sp.score += 3;
                }
                IndicatorRelease(htf_handle);
                
                // 4. Depth of the swing (how much lower than surrounding bars)
                double depthLeft = MathAbs((low[i] - low[i-2])/low[i]*100);
                double depthRight = MathAbs((low[i] - low[i+2])/low[i]*100);
                sp.score += (int)MathFloor((depthLeft + depthRight)/2);
                
                // Only add swings with good scores
                if(sp.score >= 3) {
                    swingPoints[count] = sp;
                    count++;
                    if(count >= maxSwings) break;
                }
            }
        }
    }
    // For sell trades we look for swing highs
    else {
        for(int i=2; i<bars-2; i++) {
            // Check if this is a swing high
            if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i+1] && high[i] > high[i+2]) {
                SwingPoint sp;
                sp.barIndex = i;
                sp.price = high[i];
                sp.time = time[i];
                sp.score = 1; // Base score
                
                // Calculate swing score similar to swing lows
                
                // 1. Volume at the swing point
                if(volume[i] > volume[i-1]*1.5 && volume[i] > volume[i+1]*1.5)
                    sp.score += 2;
                
                // 2. Price rejection after swing (bearish confirmation)
                if(close[i] < (high[i] + low[i])/2 && close[i-1] < open[i-1])
                    sp.score += 2;
                
                // 3. Higher timeframe alignment
                int htf_handle = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
                double htf_ma[];
                if(CopyBuffer(htf_handle, 0, 0, 1, htf_ma) > 0) {
                    if(high[i] < htf_ma[0])
                        sp.score += 3;
                }
                IndicatorRelease(htf_handle);
                
                // 4. Depth of the swing (how much higher than surrounding bars)
                double depthLeft = MathAbs((high[i] - high[i-2])/high[i]*100);
                double depthRight = MathAbs((high[i] - high[i+2])/high[i]*100);
                sp.score += (int)MathFloor((depthLeft + depthRight)/2);
                
                // Only add swings with good scores
                if(sp.score >= 3) {
                    swingPoints[count] = sp;
                    count++;
                    if(count >= maxSwings) break;
                }
            }
        }
    }
    
    // Sort swings by score (descending)
    if(count > 1) {
        for(int i=0; i<count-1; i++) {
            for(int j=i+1; j<count; j++) {
                if(swingPoints[j].score > swingPoints[i].score) {
                    SwingPoint temp = swingPoints[i];
                    swingPoints[i] = swingPoints[j];
                    swingPoints[j] = temp;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Determine optimal stop loss based on swing points                |
//+------------------------------------------------------------------+
double DetermineOptimalStopLoss(int signal, double entryPrice) {
    // Array to store potential swing points
    SwingPoint swingPoints[];
    int swingCount = 0;
    
    // Find relevant swing points
    bool isBuy = (signal == ORDER_TYPE_BUY);
    FindQualitySwingPoints(isBuy, 100, swingPoints, swingCount);
    
    if(swingCount == 0) {
        // Fallback to standard SL calculation if no good swing points found
        double pip = GetPipSize();
        return isBuy ? entryPrice - InitialStopLoss * pip : entryPrice + InitialStopLoss * pip;
    }
    
    // Find the best swing point to use for stop loss
    double optimalStopPrice = 0;
    double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double minDistance = 999999;
    double maxDistance = currentPrice * 0.02; // Max 2% away
    double preferredDistance = GetATR(_Symbol, PERIOD_CURRENT, 14, 0) * SL_ATR_Mult; // Preferred distance based on ATR
    
    for(int i=0; i<swingCount; i++) {
        double distance = isBuy ? MathAbs(currentPrice - swingPoints[i].price) : MathAbs(swingPoints[i].price - currentPrice);
        
        // Skip if too close or too far
        if(distance < preferredDistance * 0.5) continue;
        if(distance > maxDistance) continue;
        
        // Rate the stop loss points
        double fitness = MathAbs(distance - preferredDistance) * (1.0 / (1 + swingPoints[i].score * 0.1));
        
        if(fitness < minDistance || optimalStopPrice == 0) {
            minDistance = fitness;
            optimalStopPrice = swingPoints[i].price;
        }
    }
    
    // If no suitable swing point, fall back to standard SL calculation
    if(optimalStopPrice == 0) {
        double pip = GetPipSize();
        optimalStopPrice = isBuy ? entryPrice - InitialStopLoss * pip : entryPrice + InitialStopLoss * pip;
    }
    
    // Add a small buffer to avoid immediate stop hits
    double buffer = isBuy ? -_Point * 5 : _Point * 5;
    return optimalStopPrice + buffer;
}

//+------------------------------------------------------------------+
//| Calculate dynamic take profit based on market conditions         |
//+------------------------------------------------------------------+
double CalculateDynamicTakeProfit(int signal, double entryPrice, double stopLossPrice) {
    // Calculate base risk in price
    double baseRisk = MathAbs(entryPrice - stopLossPrice);
    
    // Get ATR for volatility measurement
    double atr = GetATR(_Symbol, PERIOD_CURRENT, 14, 0);
    
    // Base RR ratio
    double baseRR = BaseRiskReward;
    
    // Adjust based on market regime
    if(EnableMarketRegimeFiltering && currentRegime >= 0) {
        switch(currentRegime) {
            case TRENDING_UP:
            case TRENDING_DOWN:
                baseRR *= 1.3; // Extend targets in trending markets
                break;
            case HIGH_VOLATILITY:
                baseRR *= 1.5; // Extend targets in high volatility
                break;
            case RANGING_NARROW:
                baseRR *= 0.7; // Reduce targets in tight ranges
                break;
            case CHOPPY:
                baseRR *= 0.8; // Reduce targets in choppy markets
                break;
            case BREAKOUT:
                baseRR *= 1.8; // Maximize targets on breakouts
                break;
        }
    }
    
    // Calculate dynamic reward
    double reward = baseRisk * baseRR;
    
    // Adjust for volatility
    double volatilityFactor = atr / (GetPipSize() * 10); // Normalize ATR
    reward *= (1.0 + (volatilityFactor - 1.0) * 0.5); // Dampened adjustment
    
    // Calculate take profit
    double takeProfit = signal == ORDER_TYPE_BUY ? entryPrice + reward : entryPrice - reward;
    
    // Ensure the risk-reward stays within limits
    double currentRR = reward / baseRisk;
    if(currentRR < MinRiskReward)
        takeProfit = signal == ORDER_TYPE_BUY ? entryPrice + baseRisk * MinRiskReward : entryPrice - baseRisk * MinRiskReward;
    else if(currentRR > MaxRiskReward)
        takeProfit = signal == ORDER_TYPE_BUY ? entryPrice + baseRisk * MaxRiskReward : entryPrice - baseRisk * MaxRiskReward;
    
    return takeProfit;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                            |
//+------------------------------------------------------------------+
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

// Note: RegimeToString function already defined at global scope

//+------------------------------------------------------------------+
//| Check current market regime to adapt trading strategy           |
//+------------------------------------------------------------------+
void CheckMarketRegime()
{
   // Detect the current market regime using price patterns and volatility
   currentRegime = FastRegimeDetection(_Symbol);
   
   // Log regime changes only when they occur
   if(currentRegime != lastRegime) {
      string regimeStr = RegimeToString(currentRegime);
      Print("Market regime changed to: ", regimeStr);
      lastRegime = currentRegime;
   }
}

//+------------------------------------------------------------------+
//| Check for MA crossover signals                                   |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(PositionsTotal() > 0) return; // Only one position at a time

   double fastMA[2], slowMA[2];
   if(CopyBuffer(fastMAHandle, 0, 0, 2, fastMA) != 2) return;
   if(CopyBuffer(slowMAHandle, 0, 0, 2, slowMA) != 2) return;

   // Higher timeframe trend filter (e.g., H1 MA)
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

    // ATR filter (volatility)
    // Get current ATR value for volatility check
    int atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
    double atrValues[];
    bool volatilityOK = false;
    if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) > 0) {
        volatilityOK = atrValues[0] >= 1.5 * GetPipSize(); // min ATR: 1.5 pips
    }
    IndicatorRelease(atrHandle);

    bool buySignal = fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0] && trendUp && volatilityOK;
    bool sellSignal = fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0] && trendDown && volatilityOK;

    if(buySignal || sellSignal)
    {
       double lotSize = CalculateLotSize(RiskPercent, InitialStopLoss);
      ENUM_ORDER_TYPE orderType = buySignal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      Print("Entry: ", (buySignal ? "BUY" : "SELL"), " | Lot: ", lotSize, " | Price: ", SymbolInfoDouble(_Symbol, buySignal ? SYMBOL_ASK : SYMBOL_BID));
      OpenTrade(orderType, true);
   }
}

//+------------------------------------------------------------------+
//| Open trade                                                     |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE orderType, bool addStops = true)
{
   // Reset global request/result structures
   ZeroMemory(request);
   ZeroMemory(result);
   
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Get current market regime if enabled
   if(EnableMarketRegimeFiltering && currentRegime < 0) {
      currentRegime = FastRegimeDetection(_Symbol);
      string regimeDescription = RegimeToString(currentRegime);
      Print("Detected market regime: ", regimeDescription);
   }
   
   double sl = 0, tp = 0;
   if(EnableOptimalStopLoss) {
      sl = DetermineOptimalStopLoss(orderType, price);
   } else {
      double pip = GetPipSize();
      sl = (orderType == ORDER_TYPE_BUY) ? price - InitialStopLoss * pip : price + InitialStopLoss * pip;
   }
   
   // Use dynamic take profit calculation if enabled
   if(EnableDynamicTakeProfit) {
      tp = CalculateDynamicTakeProfit(orderType, price, sl);
   } else {
      double pip = GetPipSize();
      tp = (orderType == ORDER_TYPE_BUY) ? price + BaseRiskReward * InitialStopLoss * pip : price - BaseRiskReward * InitialStopLoss * pip;
   }
   
   // Check for order blocks if enabled
   if(EnableOrderBlockFiltering) {
      bool validOB = false;
      
      // For buy orders, check for bullish order blocks
      if(orderType == ORDER_TYPE_BUY && bullishOB.isValid) {
         // Check if price is near the order block
         double obDistance = MathAbs(price - bullishOB.startPrice) / price * 100;
         if(obDistance < 0.1) {  // Within 0.1% of the OB
            validOB = true;
            // Potentially adjust SL to be below the OB
            if(sl > bullishOB.endPrice) {
               sl = bullishOB.endPrice - _Point * 10; // 10 points below OB
            }
         }
      }
      // For sell orders, check for bearish order blocks
      else if(orderType == ORDER_TYPE_SELL && bearishOB.isValid) {
         double obDistance = MathAbs(price - bearishOB.startPrice) / price * 100;
         if(obDistance < 0.1) {  // Within 0.1% of the OB
            validOB = true;
            // Potentially adjust SL to be above the OB
            if(sl < bearishOB.endPrice) {
               sl = bearishOB.endPrice + _Point * 10; // 10 points above OB
            }
         }
      }
      
      // If order block filtering is on but no valid OB found, skip this trade
      if(StrictOrderBlockFiltering && !validOB) {
         Print("No valid order block found for ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", " trade. Skipping.");
         return false;
      }
   }
   
   // Check for liquidity grabs if enabled
   if(EnableLiquidityGrabFiltering) {
      bool validLG = false;
      
      // For buy orders, check for bullish liquidity grabs
      if(orderType == ORDER_TYPE_BUY) {
         for(int i=0; i<liquidityGrabCount; i++) {
            if(liquidityGrabs[i].isBullish && !liquidityGrabs[i].isExpired) {
               // Check if grab is recent and valid
               if(iTime(_Symbol, PERIOD_CURRENT, 0) - liquidityGrabs[i].time < 60*60) { // Within last hour
                  validLG = true;
                  break;
               }
            }
         }
      }
      // For sell orders, check for bearish liquidity grabs
      else if(orderType == ORDER_TYPE_SELL) {
         for(int i=0; i<liquidityGrabCount; i++) {
            if(!liquidityGrabs[i].isBullish && !liquidityGrabs[i].isExpired) {
               // Check if grab is recent and valid
               if(iTime(_Symbol, PERIOD_CURRENT, 0) - liquidityGrabs[i].time < 60*60) { // Within last hour
                  validLG = true;
                  break;
               }
            }
         }
      }
      
      // If liquidity grab filtering is on but no valid grab found, skip this trade
      if(StrictLiquidityGrabFiltering && !validLG) {
         Print("No valid liquidity grab found for ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", " trade. Skipping.");
         return false;
      }
   }
   
   // Apply fair value gap filtering if enabled
   if(EnableFVGFiltering) {
      bool validFVG = false;
      
      // For buy orders, check for bullish FVGs
      if(orderType == ORDER_TYPE_BUY) {
         for(int i=0; i<fvgCount; i++) {
            if(fairValueGaps[i].isBullish && !fairValueGaps[i].isFilled) {
               // Check if price is near the FVG
               if(price >= fairValueGaps[i].lowPrice && price <= fairValueGaps[i].highPrice) {
                  validFVG = true;
                  // Potentially adjust SL to below the FVG
                  if(sl > fairValueGaps[i].lowPrice) {
                     sl = fairValueGaps[i].lowPrice - _Point * 5;
                  }
                  break;
               }
            }
         }
      }
      // For sell orders, check for bearish FVGs
      else if(orderType == ORDER_TYPE_SELL) {
         for(int i=0; i<fvgCount; i++) {
            if(!fairValueGaps[i].isBullish && !fairValueGaps[i].isFilled) {
               // Check if price is near the FVG
               if(price <= fairValueGaps[i].highPrice && price >= fairValueGaps[i].lowPrice) {
                  validFVG = true;
                  // Potentially adjust SL to above the FVG
                  if(sl < fairValueGaps[i].highPrice) {
                     sl = fairValueGaps[i].highPrice + _Point * 5;
                  }
                  break;
               }
            }
         }
      }
      
      // If FVG filtering is on but no valid FVG found, skip this trade
      if(StrictFVGFiltering && !validFVG) {
         Print("No valid fair value gap found for ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", " trade. Skipping.");
         return false;
      }
   }
   
   // Risk management based on market regime
   double lotSize = FixedLot ? LotSize : CalculateLotSize(RiskPercent, (int)(MathAbs(price - sl) / GetPipSize()));
   
   // Adjust position size based on market regime
   if(EnableMarketRegimeFiltering && currentRegime >= 0) {
      switch(currentRegime) {
         case TRENDING_UP:
         case TRENDING_DOWN:
            // Maintain normal lot size in trending markets
            break;
         case HIGH_VOLATILITY:
            // Reduce lot size in high volatility markets
            lotSize *= 0.7;
            break;
         case RANGING_NARROW:
            // Slightly increase lot size in narrow ranging markets
            lotSize *= 1.1;
            break;
         case CHOPPY:
            // Reduce lot size in choppy markets
            lotSize *= 0.6;
            break;
         case BREAKOUT:
            // Increase lot size on breakouts
            lotSize *= 1.2;
            break;
      }
   }
   
   // Normalize the lot size
   lotSize = NormalizeDouble(MathMax(minLot, MathMin(maxLot, lotSize)), 2);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.price = price;
   request.sl = addStops ? sl : 0;
   request.tp = addStops ? tp : 0;
   request.deviation = Slippage;
   request.type = orderType;
   request.type_filling = ORDER_FILLING_FOK;
   request.comment = "ScalpingAutoTrailExpert";
   
   if(OrderSend(request, result)) {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED) {
         tradePositionInfo.SelectByTicket(result.deal);
         prevStopLoss = result.price;
         prevPrice = result.price;
         Print("Trade opened: ", result.order, ", Price: ", result.price, ", SL: ", request.sl, ", TP: ", request.tp);
         return true;
      }
   }
   
   Print("Failed to open trade: ", GetLastError());
   return false;
}

//+------------------------------------------------------------------+
//| Advanced Trailing stop management with SMC concepts              |
//+------------------------------------------------------------------+
void TrailPositions()
{
   if(EnableAdvancedTrailing)
   {
      ManageTrailingStops();
   }
   else
   {
      // Legacy trailing stop implementation
      double pip = GetPipSize();
      for(int i = PositionsTotal()-1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double profitPips = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / pip : (openPrice - currentPrice) / pip;
            Print("Trail: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), " | Open: ", openPrice, " | Price: ", currentPrice, " | SL: ", currentSL, " | ProfitPips: ", profitPips);
            if(profitPips >= TrailingStep)
            {
               double newSL = (posType == POSITION_TYPE_BUY) ? currentPrice - TrailingStop * pip
                                                             : currentPrice + TrailingStop * pip;
               double newTP = (posType == POSITION_TYPE_BUY) ? currentPrice + InitialTakeProfit * pip
                                                             : currentPrice - InitialTakeProfit * pip;
               // Check if new SL is better than current SL
               if((posType == POSITION_TYPE_BUY && newSL > currentSL) || 
                  (posType == POSITION_TYPE_SELL && newSL < currentSL))
               {
                  // Reset the global trade request/result structures
                  ZeroMemory(request);
                  ZeroMemory(result);
                  request.action = TRADE_ACTION_SLTP;
                  request.position = ticket;
                  request.symbol = _Symbol;
                  request.sl = newSL;
                  request.tp = newTP;
                  request.magic = MagicNumber;
                  Print("Trail OrderSend: ", newSL, " ", newTP);
                  if(!OrderSend(request, result))
                  {
                     Print("OrderSend SLTP failed: ", GetLastError());
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage advanced trailing stops based on market structure         |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   // Process all positions with our magic number
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || (PositionGetInteger(POSITION_MAGIC) != MagicNumber))
         continue;
         
      // Get position details
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool isBuy = (posType == POSITION_TYPE_BUY);
      double pip = GetPipSize();
      
      // Calculate profit in pips and percentage
      double profitPips = isBuy ? ((currentPrice - openPrice) / pip) : ((openPrice - currentPrice) / pip);
      double profitPercent = (PositionGetDouble(POSITION_PROFIT) / AccountInfoDouble(ACCOUNT_BALANCE)) * 100;
      
      // Skip trailing if profit doesn't meet minimum activation
      if(profitPips < TrailingStep)
         continue;
      
      // Advanced trailing based on market structure and profit stage
      double newSL = currentSL;
      
      // Stage 1: Initial breakeven move after minimal profit is reached
      if((profitPips >= BreakEvenPips) && ((isBuy && currentSL < openPrice) || (!isBuy && currentSL > openPrice)))
      {
         // Move to breakeven with small buffer
         newSL = isBuy ? openPrice + BreakEvenBuffer * pip : openPrice - BreakEvenBuffer * pip;
         ModifyTrade(ticket, newSL, currentTP);
         Print("Position moved to breakeven with buffer: ", newSL);
         continue; // Skip other trailing for this update
      }
      
      // Stage 2: Structure-based trailing
      if((profitPips >= TrailingStep) && EnableOptimalStopLoss)
      {
         // Use swing points for advanced trailing
         SwingPoint swingPoints[];
         int swingCount = 0;
         
         // Find quality swing points - we look for opposite direction swings to place stops
         FindQualitySwingPoints(!isBuy, 50, swingPoints, swingCount);
         
         if(swingCount > 0)
         {
             // For buys, find the highest swing low below current price but above current SL
             if(isBuy) {
               double bestSwingPrice = 0;
               
               for(int j = 0; j < swingCount; j++)
               {
                  // Skip swing points above current price or below current SL
                  if((swingPoints[j].price > currentPrice) || (swingPoints[j].price <= currentSL)) {
                     continue;
                  }
                  
                  // If this swing point is higher than our best so far, use it
                  if(swingPoints[j].price > bestSwingPrice) {
                     bestSwingPrice = swingPoints[j].price;
                  }
               }
               
               // If we found a valid swing point, use it for trailing
               if((bestSwingPrice > 0) && (bestSwingPrice > currentSL))
               {
                  newSL = bestSwingPrice - _Point * 5; // Small buffer below swing point
                  Print("Found swing-based SL for BUY position: ", newSL);
               }
            }
            // For sells, find the lowest swing high above current price but below current SL
            else {
               double bestSwingPrice = 0;
               
               for(int j = 0; j < swingCount; j++)
               {
                  // Skip swing points below current price or above current SL
                  if(swingPoints[j].price < currentPrice || (currentSL > 0 && swingPoints[j].price >= currentSL))
                     continue;
                  
                  // If this swing point is lower than our best or we haven't found one yet
                  if(bestSwingPrice == 0 || swingPoints[j].price < bestSwingPrice)
                     bestSwingPrice = swingPoints[j].price;
               }
               
               // If we found a valid swing point, use it for trailing
               if(bestSwingPrice > 0 && (currentSL == 0 || bestSwingPrice < currentSL))
               {
                  newSL = bestSwingPrice + _Point * 5; // Small buffer above swing point
                  Print("Found swing-based SL for SELL position: ", newSL);
               }
            }
         }
      }
      
      // If no structure-based stop was found, use standard trailing
      if(newSL == currentSL)
      {
         // Phase 3: Standard ATR-based trailing for final part
         double atr = GetATR(_Symbol, PERIOD_CURRENT, 14, 0);
         double trailDistance = atr * TrailingATRMultiplier;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            // Only move stop if it's better than current
            if(newSL > currentSL + pip * TrailingStep || currentSL == 0)
            {
               Print("Using ATR-based trailing for BUY: ", newSL);
            }
            else newSL = currentSL; // Keep current SL
         }
         else
         {
            newSL = currentPrice + trailDistance;
            // Only move stop if it's better than current
            if(newSL < currentSL - pip * TrailingStep || currentSL == 0)
            {
               Print("Using ATR-based trailing for SELL: ", newSL);
            }
            else newSL = currentSL; // Keep current SL
         }
      }
      
      // Apply the new stop loss if different from current SL
      if(MathAbs(newSL - currentSL) > _Point && newSL != currentSL)
      {
         ModifyTrade(ticket, newSL, currentTP);
         Print("Advanced trailing stop moved to: ", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Modify existing trade with new stop loss and/or take profit     |
//+------------------------------------------------------------------+
bool ModifyTrade(ulong ticket, double newSL, double newTP)
{
   // Reset the global trade request/result structures
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = newSL;
   request.tp = newTP;
   request.magic = MagicNumber;
   
   if(!OrderSend(request, result))
   {
      Print("OrderSend SLTP failed: ", GetLastError());
      return false;
   }
   return true;
}
//+------------------------------------------------------------------+
