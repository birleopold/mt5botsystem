//+------------------------------------------------------------------+
//|                 ScalpingAutoTrailExpert_v3.mq5                  |
//|         Smart Money Concepts & Advanced Trailing Strategy       |
//|     Integrated: Market Structure, Liquidity, & Hybrid Trailing  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "3.50"
#property strict

// Core SMC Constants and Definitions
#define MAX_BLOCKS 20
#define MAX_GRABS 10
#define MAX_FVGS 10
#define METRIC_WINDOW 100
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

// SMC structure definitions
struct LiquidityGrab { 
   datetime time; 
   double high; 
   double low; 
   bool bullish; 
   bool active; 
   double score; // quality score
};

struct FairValueGap { 
   double high;         // Upper boundary
   double low;          // Lower boundary
   datetime time;       // Time when detected
   bool bullish;        // True if bullish (gap up), false if bearish (gap down)
   bool filled;         // Whether price has revisited and filled the gap
   double significance; // Measure of significance (size relative to ATR)
   bool active;         // Whether the FVG is still relevant
};

struct OrderBlock { 
   double high;         // Upper boundary
   double low;          // Lower boundary
   datetime time;       // Time when created
   datetime expiry;     // Time when it expires
   bool bullish;        // True if bullish (buy block), false if bearish (sell block)
   bool tested;         // Whether price has tested this order block
   double strength;     // Strength of the order block based on volume and price action
   bool active;         // Whether it's still an active order block
};
OrderBlock orderBlocks[];
int obCount = 0;

struct BreakOfStructure {
   double price;        // Price level where the break occurred
   datetime time;       // Time when the break occurred
   bool bullish;        // True if bullish (breaking highs), false if bearish (breaking lows)
   int swingIndex;      // Index of the broken swing point
   double strength;     // Strength of the break (momentum)
   bool confirmed;      // Whether the break has been confirmed by subsequent price action
   bool active;         // Whether it's still an active BOS
   int barIndex;        // Bar index where the break occurred
};
BreakOfStructure bosEvents[];
int bosCount = 0;

struct ChangeOfCharacter {
   double price;        // Price level where CHoCH occurred
   datetime time;       // Time when the CHoCH occurred
   bool bullish;        // True if bullish (higher low), false if bearish (lower high)
   double prevSwing;    // Previous swing level
   double strength;     // Strength/significance of the CHoCH
   bool active;         // Whether it's still active
   int barIndex;        // Bar index where CHoCH occurred
};
ChangeOfCharacter chochEvents[];
int chochCount = 0;

struct SwingPoint {
   int barIndex;
   double price;
   int score;
   datetime time;
};

// General Settings
input group "===== RISK & POSITION SIZING ====="
input double   RiskPercentage = 1.0;       // Risk percentage per trade
input int      InitialStopLoss = 50;       // Initial Stop Loss (pips)
input int      InitialTakeProfit = 100;    // Initial Take Profit (pips)
input int      MagicNumber = 12345;        // EA Magic Number

// Trailing Stop Settings
input group "===== TRAILING STOP SETTINGS ====="
input int      TrailingStop = 30;          // Trailing Stop Distance (pips)
input int      TrailingStep = 20;          // Trailing Step (pips)
input int      ProfitTrailBuffer = 20;     // Profit trail buffer (pips)
input double   ProfitTrailStart = 0.5;     // Start profit trail at X% of TP (0.5 = 50%)
input bool     NoProfitTrailLoss = true;   // Never close at loss due to profit trail
input bool     UseDynamicBuffer = false;   // Use dynamic buffer (ATR based)
input double   DynamicBufferATRMultiplier = 1.0; // ATR multiplier for dynamic buffer

// Signal Generation Settings
input group "===== SIGNAL SETTINGS ====="
input int      FastMAPeriod = 5;           // Fast MA Period
input int      SlowMAPeriod = 20;          // Slow MA Period

// Smart Money Concepts Settings
input group "Smart Money Concepts Settings"
input bool     EnableSMC = true;           // Enable Smart Money Concepts (SMC) features
input bool     UseMarketRegime = true;     // Filter trades based on market regime
input bool     UseOptimalStopLoss = true;  // Calculate stop loss based on market structure
input bool     UseAdvancedTrailing = true; // Use structure-based trailing stop

// SMC Visualization Settings
input group "SMC Visualization Settings"
input bool     ShowSwingPoints = true;     // Show swing points on chart
input bool     ShowLiquidityGrabs = true;  // Show liquidity grabs on chart
input bool     ShowFairValueGaps = true;   // Show fair value gaps on chart
input bool     ShowOrderBlocks = true;     // Show order blocks on chart
input bool     ShowBOS = true;             // Show Break of Structure events
input bool     ShowCHoCH = true;           // Show Change of Character events
input color    BullishColor = clrGreen;    // Color for bullish structures
input color    BearishColor = clrRed;      // Color for bearish structures
input int      VisualizationDays = 5;      // Days to keep structures visible (0=all)

// Display Settings
input bool     DisplayInfo = true;        // Show info on chart

// SMC Feature Settings
input int      LookbackBars = 100;        // Bars to analyze for SMC structures
input double   RegimeAtrPeriod = 14;      // ATR period for regime detection
input double   RegimeVolThreshold = 1.5;   // Volatility threshold multiplier

// Original indicator handles
int fastMAHandle, slowMAHandle, atrHandle;
double minLot, maxLot;

// SMC Global Variables
LiquidityGrab liquidityGrabs[MAX_GRABS];
FairValueGap fairValueGaps[MAX_FVGS];
OrderBlock orderBlocks[MAX_BLOCKS];
SwingPoint swingPoints[20];

// Liquidity grab and FVG counts
int grabCount = 0;
int fvgCount = 0;
int blockCount = 0;
int swingCount = 0;

// Market regime tracking
int currentRegime = -1;
int previousRegime = -1;

// Performance tracking
double regimeProfit[REGIME_COUNT];
double regimeAccuracy[REGIME_COUNT];
int regimeWins[REGIME_COUNT];
int regimeLosses[REGIME_COUNT];

// Position management
bool emergencyMode = false;
bool trailingActive = false;
datetime lastTradeTime = 0;
datetime lastSignalTime = 0;
int consecutiveLosses = 0;

// Track max profit for enhanced trailing
static double maxProfit[2] = {0, 0}; // [0]=buy, [1]=sell

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

double GetDynamicBuffer() {
   if(!UseDynamicBuffer) return ProfitTrailBuffer;
   int atrHandle = iATR(_Symbol, _Period, 14);
   double atr[];
   double pip = GetPipSize();
   double buffer = ProfitTrailBuffer;
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) == 1) {
      buffer = MathMax(ProfitTrailBuffer, atr[0] * DynamicBufferATRMultiplier / pip);
   }
   IndicatorRelease(atrHandle);
   return buffer;
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

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize standard indicators
   fastMAHandle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   slowMAHandle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, (int)RegimeAtrPeriod);
   
   // Check if indicators initialized correctly
   if(fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE || 
      atrHandle == INVALID_HANDLE) {
      Print("ERROR: Failed to initialize indicators");
      return(INIT_FAILED);
   }
   
   // Get lot size constraints
   minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   // Initialize SMC structures if enabled
   if(EnableSMC) {
      // Reset SMC structure counts
      grabCount = 0;
      fvgCount = 0;
      blockCount = 0;
      swingCount = 0;
      
      // Reset performance tracking arrays
      ArrayInitialize(regimeWins, 0);
      ArrayInitialize(regimeLosses, 0);
      ArrayInitialize(regimeProfit, 0.0);
      ArrayInitialize(regimeAccuracy, 0.0);
      
      // Reset trading status variables
      emergencyMode = false;
      trailingActive = false;
      lastTradeTime = 0;
      lastSignalTime = 0;
      consecutiveLosses = 0;
      
      // Initialize market regime
      if(UseMarketRegime) {
         currentRegime = DetectMarketRegime();
         previousRegime = currentRegime;
         Print("Initial market regime: ", RegimeToString(currentRegime));
         
         // Initial SMC structure detection
         DetectLiquidityGrabs();
         DetectFairValueGaps();
         IdentifySwingPoints();
      }
   }
   
   // Display initialization message
   if(DisplayInfo) {
      string initMsg = "ScalpingAutoTrailExpert_v3 with SMC initialized";
      if(EnableSMC) initMsg += " with SMC features enabled";
      Print(initMsg);
      Comment(initMsg);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Detect market regime based on price patterns and volatility       |
//+------------------------------------------------------------------+
int DetectMarketRegime() {
    // Get price data for multiple timeframes
    double close0 = iClose(_Symbol, _Period, 0);
    double close1 = iClose(_Symbol, _Period, 1);
    double close3 = iClose(_Symbol, _Period, 3);
    double close5 = iClose(_Symbol, _Period, 5);
    double close10 = iClose(_Symbol, _Period, 10);
    
    // Get high/low data
    double high0 = iHigh(_Symbol, _Period, 0);
    double high1 = iHigh(_Symbol, _Period, 1);
    double high3 = iHigh(_Symbol, _Period, 3);
    double low0 = iLow(_Symbol, _Period, 0);
    double low1 = iLow(_Symbol, _Period, 1);
    double low3 = iLow(_Symbol, _Period, 3);
    
    // Calculate multiple moving averages for trend detection
    double ma3 = 0, ma5 = 0, ma10 = 0, ma20 = 0;
    for(int i=0; i<3; i++) ma3 += iClose(_Symbol, _Period, i);
    for(int i=0; i<5; i++) ma5 += iClose(_Symbol, _Period, i);
    for(int i=0; i<10; i++) ma10 += iClose(_Symbol, _Period, i);
    for(int i=0; i<20; i++) ma20 += iClose(_Symbol, _Period, i);
    ma3 /= 3;
    ma5 /= 5;
    ma10 /= 10;
    ma20 /= 20;
    
    // Calculate volatility metrics
    double atr = 0;
    double atrBuffer[];
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
        atr = atrBuffer[0];
    } else {
        // Fallback calculation
        double sum = 0;
        for(int i=0; i<10; i++) {
            sum += MathAbs(iHigh(_Symbol, _Period, i) - iLow(_Symbol, _Period, i));
        }
        atr = sum / 10;
    }
    
    double avgRange = 0;
    for(int i=0; i<5; i++) {
        avgRange += MathAbs(iHigh(_Symbol, _Period, i) - iLow(_Symbol, _Period, i));
    }
    avgRange /= 5;
    
    // Calculate price range over different periods
    double range3 = MathMax(high0, high1) - MathMin(low0, low1);
    double range10 = 0;
    double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, 10, 0));
    double lowestLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, 10, 0));
    range10 = highestHigh - lowestLow;
    
    // Calculate momentum and direction changes
    double momentum3 = close0 - close3;
    double momentum5 = close0 - close5;
    double momentum10 = close0 - close10;
    
    // Count direction changes (choppiness)
    int directionChanges = 0;
    for(int i=1; i<5; i++) {
        if((iClose(_Symbol, _Period, i) > iClose(_Symbol, _Period, i+1) && 
            iClose(_Symbol, _Period, i-1) < iClose(_Symbol, _Period, i)) ||
           (iClose(_Symbol, _Period, i) < iClose(_Symbol, _Period, i+1) && 
            iClose(_Symbol, _Period, i-1) > iClose(_Symbol, _Period, i))) {
            directionChanges++;
        }
    }
    
    // Calculate Bollinger Band width for range detection
    double bbUpper = 0, bbLower = 0, bbWidth = 0;
    int bbHandle = iBands(_Symbol, _Period, 20, 2.0, 0, PRICE_CLOSE);
    if(bbHandle != INVALID_HANDLE) {
        double bbBuffer[];
        if(CopyBuffer(bbHandle, 1, 0, 1, bbBuffer) > 0) bbUpper = bbBuffer[0]; // Upper band
        if(CopyBuffer(bbHandle, 2, 0, 1, bbBuffer) > 0) bbLower = bbBuffer[0]; // Lower band
        bbWidth = (bbUpper - bbLower) / ma20;
        IndicatorRelease(bbHandle);
    }
    
    // Check for breakouts
    bool breakoutUp = close0 > bbUpper && close1 <= bbUpper;
    bool breakoutDown = close0 < bbLower && close1 >= bbLower;
    bool insideBands = close0 > bbLower && close0 < bbUpper;
    
    // Check for reversals
    bool potentialReversal = (momentum3 * momentum10 < 0) && MathAbs(momentum3) > atr * 0.3;
    
    // Detect market conditions
    bool isVolatile = atr > avgRange * 1.2;
    bool isVeryVolatile = atr > avgRange * RegimeVolThreshold;
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
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(fastMAHandle);
   IndicatorRelease(slowMAHandle);
   IndicatorRelease(atrHandle);
   
   // Output performance statistics if using SMC
   if(EnableSMC && UseMarketRegime) {
      Print("===== SMC Performance Statistics =====");
      double totalProfit = 0;
      int totalWins = 0, totalLosses = 0;
      
      for(int i=0; i<REGIME_COUNT; i++) {
         int trades = regimeWins[i] + regimeLosses[i];
         if(trades > 0) {
            double winRate = (trades > 0) ? 100.0 * regimeWins[i] / trades : 0;
            Print("Regime: ", RegimeToString(i), 
                  ", Trades: ", trades, 
                  ", Win rate: ", DoubleToString(winRate, 1), "%",
                  ", Profit: ", DoubleToString(regimeProfit[i], 2));
            
            totalProfit += regimeProfit[i];
            totalWins += regimeWins[i];
            totalLosses += regimeLosses[i];
         }
      }
      
      double overallWinRate = (totalWins + totalLosses > 0) ? 100.0 * totalWins / (totalWins + totalLosses) : 0;
      Print("Total trades: ", totalWins + totalLosses,
            ", Overall win rate: ", DoubleToString(overallWinRate, 1), "%",
            ", Total profit: ", DoubleToString(totalProfit, 2));
   }
}

//+------------------------------------------------------------------+
//| Detect liquidity grabs in recent price action                     |
//+------------------------------------------------------------------+
int DetectLiquidityGrabs(string symbol = NULL, int maxCount = 5, bool clearOld = true) {
   if(!EnableSMC) return 0;
   if(symbol == NULL) symbol = _Symbol;
   
   // Reset grab count if requested
   if(clearOld) grabCount = 0;
   
   // Get historical price data
   int lookback = LookbackBars;
   double high[], low[], close[], open[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);
   
   if(CopyHigh(symbol, _Period, 0, lookback, high) <= 0) return 0;
   if(CopyLow(symbol, _Period, 0, lookback, low) <= 0) return 0;
   if(CopyClose(symbol, _Period, 0, lookback, close) <= 0) return 0;
   if(CopyOpen(symbol, _Period, 0, lookback, open) <= 0) return 0;
   
   // Calculate average true range for comparison
   double atrValue = 0;
   double atrBuffer[];
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
      atrValue = atrBuffer[0];
   } else {
      // Fallback calculation
      double sum = 0;
      for(int i=0; i<10; i++) {
         double tr = MathMax(high[i] - low[i], MathMax(MathAbs(high[i] - close[i+1]), MathAbs(low[i] - close[i+1])));
         sum += tr;
      }
      atrValue = sum / 10;
   }
   
   // Find swing highs/lows to detect sweeps
   int foundGrabs = 0;
   
   // Look for bullish liquidity grabs (price sweeps below support)
   for(int i=5; i<lookback-5 && foundGrabs < maxCount; i++) {
      // Look for a prior low that gets swept
      bool isMinimum = true;
      for(int j=i-2; j<=i+2; j++) {
         if(j != i && low[j] < low[i]) {
            isMinimum = false;
            break;
         }
      }
      
      if(isMinimum) {
         // Check if price swept this low then reversed up
         for(int j=1; j<5; j++) {
            if(low[j] < low[i] && close[j] > low[i] && open[j] > close[j] && 
               close[j-1] > low[i] && close[j-1] - low[j] > atrValue * 0.3) {
               // Valid grab found
               if(grabCount < MAX_GRABS) {
                  MqlDateTime time;
                  datetime barTime = iTime(symbol, _Period, j);
                  TimeToStruct(barTime, time);
                  
                  liquidityGrabs[grabCount].time = barTime;
                  liquidityGrabs[grabCount].high = high[j];
                  liquidityGrabs[grabCount].low = low[j];
                  liquidityGrabs[grabCount].bullish = true;
                  liquidityGrabs[grabCount].active = true;
                  liquidityGrabs[grabCount].score = (close[j-1] - low[j]) / atrValue; // Normalized score
                  
                  grabCount++;
                  foundGrabs++;
                  break;
               }
            }
         }
      }
   }
   
   // Look for bearish liquidity grabs (price sweeps above resistance)
   for(int i=5; i<lookback-5 && foundGrabs < maxCount; i++) {
      // Look for a prior high that gets swept
      bool isMaximum = true;
      for(int j=i-2; j<=i+2; j++) {
         if(j != i && high[j] > high[i]) {
            isMaximum = false;
            break;
         }
      }
      
      if(isMaximum) {
         // Check if price swept this high then reversed down
         for(int j=1; j<5; j++) {
            if(high[j] > high[i] && close[j] < high[i] && open[j] < close[j] && 
               close[j-1] < high[i] && high[j] - close[j-1] > atrValue * 0.3) {
               // Valid grab found
               if(grabCount < MAX_GRABS) {
                  MqlDateTime time;
                  datetime barTime = iTime(symbol, _Period, j);
                  TimeToStruct(barTime, time);
                  
                  liquidityGrabs[grabCount].time = barTime;
                  liquidityGrabs[grabCount].high = high[j];
                  liquidityGrabs[grabCount].low = low[j];
                  liquidityGrabs[grabCount].bullish = false;
                  liquidityGrabs[grabCount].active = true;
                  liquidityGrabs[grabCount].score = (high[j] - close[j-1]) / atrValue; // Normalized score
                  
                  grabCount++;
                  foundGrabs++;
                  break;
               }
            }
         }
      }
   }
   
   return foundGrabs;
}

//+------------------------------------------------------------------+
//| Detect fair value gaps in recent price action                     |
//+------------------------------------------------------------------+
int DetectFairValueGaps(string symbol = NULL, int maxCount = 5, bool clearOld = true) {
   if(!EnableSMC) return 0;
   if(symbol == NULL) symbol = _Symbol;
   
   // Reset FVG count if requested
   if(clearOld) fvgCount = 0;
   
   // Get historical price data
   int lookback = LookbackBars;
   double high[], low[], close[], open[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);
   
   if(CopyHigh(symbol, _Period, 0, lookback, high) <= 0) return 0;
   if(CopyLow(symbol, _Period, 0, lookback, low) <= 0) return 0;
   if(CopyClose(symbol, _Period, 0, lookback, close) <= 0) return 0;
   if(CopyOpen(symbol, _Period, 0, lookback, open) <= 0) return 0;
   
   // Get ATR for significance filtering
   double atrValue = 0;
   double atrBuffer[];
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
      atrValue = atrBuffer[0];
   } else {
      // Fallback calculation
      double sum = 0;
      for(int i=0; i<10; i++) {
         double tr = MathMax(high[i] - low[i], MathMax(MathAbs(high[i] - close[i+1]), MathAbs(low[i] - close[i+1])));
         sum += tr;
      }
      atrValue = sum / 10;
   }
   
   // Identify fair value gaps
   int foundFVGs = 0;
   
   // Bullish FVG: low[i] > high[i+2]
   for(int i=1; i<lookback-3 && foundFVGs < maxCount; i++) {
      if(low[i] > high[i+2]) { 
         // We have a bullish FVG
         double gapSize = low[i] - high[i+2];
         
         // Only count significant gaps
         if(gapSize > atrValue * 0.3) {
            if(fvgCount < MAX_FVGS) {
               fairValueGaps[fvgCount].startTime = iTime(symbol, _Period, i+2);
               fairValueGaps[fvgCount].endTime = iTime(symbol, _Period, i);
               fairValueGaps[fvgCount].high = low[i];
               fairValueGaps[fvgCount].low = high[i+2];
               fairValueGaps[fvgCount].bullish = true;
               fairValueGaps[fvgCount].active = IsGapStillValid(symbol, low[i], high[i+2], true);
               fairValueGaps[fvgCount].score = gapSize / atrValue; // Normalized score
               
               fvgCount++;
               foundFVGs++;
            }
         }
      }
   }
   
   // Bearish FVG: high[i] < low[i+2]
   for(int i=1; i<lookback-3 && foundFVGs < maxCount; i++) {
      if(high[i] < low[i+2]) { 
         // We have a bearish FVG
         double gapSize = low[i+2] - high[i];
         
         // Only count significant gaps
         if(gapSize > atrValue * 0.3) {
            if(fvgCount < MAX_FVGS) {
               fairValueGaps[fvgCount].startTime = iTime(symbol, _Period, i+2);
               fairValueGaps[fvgCount].endTime = iTime(symbol, _Period, i);
               fairValueGaps[fvgCount].high = low[i+2];
               fairValueGaps[fvgCount].low = high[i];
               fairValueGaps[fvgCount].bullish = false;
               fairValueGaps[fvgCount].active = IsGapStillValid(symbol, high[i], low[i+2], false);
               fairValueGaps[fvgCount].score = gapSize / atrValue; // Normalized score
               
               fvgCount++;
               foundFVGs++;
            }
         }
      }
   }
   
   return foundFVGs;
}

//+------------------------------------------------------------------+
//| Check if a fair value gap is still valid (hasn't been filled)     |
//+------------------------------------------------------------------+
bool IsGapStillValid(string symbol, double level1, double level2, bool isBullish) {
   // For bullish gaps, level1 > level2
   // For bearish gaps, level1 < level2
   double upper = isBullish ? level1 : level2;
   double lower = isBullish ? level2 : level1;
   
   // Check the bars since the gap formed
   for(int i=0; i<20; i++) {
      double high = iHigh(symbol, _Period, i);
      double low = iLow(symbol, _Period, i);
      
      // If price has traded through the entire gap, it's no longer valid
      if(high >= upper && low <= lower) {
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Identify swing points for optimal stop placement                  |
//+------------------------------------------------------------------+
int IdentifySwingPoints(int lookback = 20, bool useIntradayLevels = true) {
   if(!EnableSMC) return 0;
   swingCount = 0;
   
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(_Symbol, _Period, 0, lookback, high) <= 0) return 0;
   if(CopyLow(_Symbol, _Period, 0, lookback, low) <= 0) return 0;
   
   // Identify swing highs
   for(int i=2; i<lookback-2; i++) {
      // Check if this bar's high is higher than surrounding bars
      if(high[i] > high[i-1] && high[i] > high[i-2] && 
         high[i] > high[i+1] && high[i] > high[i+2]) {
         
         // Calculate strength score (how much higher than neighbors)
         double leftDelta = high[i] - MathMax(high[i-1], high[i-2]);
         double rightDelta = high[i] - MathMax(high[i+1], high[i+2]);
         int strengthScore = (int)MathRound((leftDelta + rightDelta) * 10000); // Higher score = stronger swing
         
         // Add to swing points array
         if(swingCount < 20) {
            swingPoints[swingCount].barIndex = i;
            swingPoints[swingCount].price = high[i];
            swingPoints[swingCount].score = strengthScore;
            swingPoints[swingCount].time = iTime(_Symbol, _Period, i);
            swingCount++;
         }
      }
   }
   
   // Identify swing lows
   for(int i=2; i<lookback-2; i++) {
      // Check if this bar's low is lower than surrounding bars
      if(low[i] < low[i-1] && low[i] < low[i-2] && 
         low[i] < low[i+1] && low[i] < low[i+2]) {
         
         // Calculate strength score (how much lower than neighbors)
         double leftDelta = MathMin(low[i-1], low[i-2]) - low[i];
         double rightDelta = MathMin(low[i+1], low[i+2]) - low[i];
         int strengthScore = (int)MathRound((leftDelta + rightDelta) * 10000); // Higher score = stronger swing
         
         // Add to swing points array
         if(swingCount < 20) {
            swingPoints[swingCount].barIndex = i;
            swingPoints[swingCount].price = low[i];
            swingPoints[swingCount].score = strengthScore;
            swingPoints[swingCount].time = iTime(_Symbol, _Period, i);
            swingCount++;
         }
      }
   }
   
   // Sort swing points by score (strongest first)
   for(int i=0; i<swingCount-1; i++) {
      for(int j=i+1; j<swingCount; j++) {
         if(swingPoints[j].score > swingPoints[i].score) {
            // Swap
            SwingPoint temp = swingPoints[i];
            swingPoints[i] = swingPoints[j];
            swingPoints[j] = temp;
         }
      }
   }
   
   return swingCount;
}

//+------------------------------------------------------------------+
//| Expert tick function with integrated SMC features                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Skip all processing if EA is in emergency mode
   if(emergencyMode && consecutiveLosses >= MaxConsecutiveLosses) {
      if(DisplayInfo) Comment("Emergency mode active. Max consecutive losses reached: ", consecutiveLosses);
      return;
   }
   
   // Get current spread
   double currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Check if spread is acceptable for trading
   if(currentSpread > MaxSpread * GetPipSize()) {
      if(DisplayInfo) Comment("Spread too high: ", DoubleToString(currentSpread / GetPipSize(), 1), " pips");
      return;
   }
   
   // Update indicators and market structures on new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   
   if(currentBarTime != lastBarTime) {
      lastBarTime = currentBarTime;
      
      // Update market regime if SMC features are enabled
      if(EnableSMC && UseMarketRegime) {
         previousRegime = currentRegime;
         currentRegime = (ENUM_MARKET_REGIME)DetectMarketRegime();
         
         if(previousRegime != currentRegime && DisplayInfo) {
            Print("Market regime changed from ", RegimeToString(previousRegime), 
                  " to ", RegimeToString(currentRegime));
         }
      }
      
      // Update all SMC structures if SMC features are enabled
      if(EnableSMC) {
         // First identify swing points which are foundation for other structures
         IdentifySwingPoints();
         
         // Then detect derived structures in correct sequence
         DetectLiquidityGrabs();
         DetectFairValueGaps();
         DetectOrderBlocks();
         DetectBreakOfStructure();   // BOS depends on swing points
         DetectChangeOfCharacter();  // CHoCH depends on BOS
         
         if(DisplayInfo) {
            Print("SMC structures updated: ", 
                 swingCount, " swing points, ", 
                 grabCount, " liquidity grabs, ", 
                 fvgCount, " fair value gaps, ",
                 obCount, " order blocks, ",
                 bosCount, " BOS events, ",
                 chochCount, " CHoCH events");
         }
         
         // Update chart visualizations if enabled
         if(ShowSwingPoints || ShowLiquidityGrabs || ShowFairValueGaps || 
            ShowOrderBlocks || ShowBOS || ShowCHoCH) {
            UpdateSMCVisualizations();
         }
      }
   }
   
   // Check for early exit conditions before position management
   CheckEarlyExitConditions();
   
   // If we have an open position, manage it
   if(PositionsTotal() > 0) {
      // Position management
      CheckForPositionManagement();
      
      // Update trailing stops if enabled
      if(TrailingStop > 0 || (EnableSMC && UseAdvancedTrailing)) {
         TrailPositions();
      }
      
      // Skip entry checks if we already have a position
      return;
   }
   
   // Check if trading is allowed based on time restrictions
   if(!IsTradingTimeAllowed()) {
      return;
   }
   
   // Check for new entry signals
   CheckForEntry();
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
//| Check for entry signals with enhanced SMC filtering                |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   // No entry if we already have a position
   if(PositionsTotal() > 0) return;
   
   // Basic signal generation using Moving Average crossover
   double fastMA[2], slowMA[2];
   if(CopyBuffer(fastMAHandle, 0, 0, 2, fastMA) != 2) return;
   if(CopyBuffer(slowMAHandle, 0, 0, 2, slowMA) != 2) return;
   
   // Higher timeframe trend filter
   int htMAHandle = iMA(_Symbol, PERIOD_H1, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   double htMA[];
   if(CopyBuffer(htMAHandle, 0, 0, 1, htMA) != 1) { IndicatorRelease(htMAHandle); return; }
   double htMAValue = htMA[0];
   IndicatorRelease(htMAHandle);
   
   double htClose[];
   if(CopyClose(_Symbol, PERIOD_H1, 0, 1, htClose) != 1) return;
   double htCloseValue = htClose[0];
   
   // Determine higher timeframe trend bias
   bool trendUp = htCloseValue > htMAValue;
   bool trendDown = htCloseValue < htMAValue;
   
   // Check minimum volatility condition
   bool volatilityOK = ATRFilter(14, RegimeVolThreshold * GetPipSize());
   
   // Basic MA crossover signal with trend filter
   bool baseBuySignal = fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0] && trendUp && volatilityOK;
   bool baseSellSignal = fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0] && trendDown && volatilityOK;
   
   // Final signals after SMC filtering (if enabled)
   bool buySignal = baseBuySignal;
   bool sellSignal = baseSellSignal;
   
   // Apply SMC filter if enabled
   if(EnableSMC) {
      // Apply market regime filter
      if(UseMarketRegime) {
         // Filter buy signals in unfavorable regimes
         if(baseBuySignal && (currentRegime == CHOPPY || 
                              currentRegime == HIGH_VOLATILITY || 
                              currentRegime == TRENDING_DOWN)) {
            buySignal = false; // Reject buy in choppy/volatile/downtrend
            if(DisplayInfo) Print("Buy signal rejected due to ", RegimeToString(currentRegime), " market regime");
         }
         
         // Filter sell signals in unfavorable regimes
         if(baseSellSignal && (currentRegime == CHOPPY || 
                               currentRegime == HIGH_VOLATILITY || 
                               currentRegime == TRENDING_UP)) {
            sellSignal = false; // Reject sell in choppy/volatile/uptrend
            if(DisplayInfo) Print("Sell signal rejected due to ", RegimeToString(currentRegime), " market regime");
         }
      }
      
      // Look for SMC structure confirmation for buy signals
      if(buySignal) {
         bool smcConfirmation = false;
         
         // Check for bullish liquidity grabs
         for(int i=0; i<grabCount; i++) {
            if(liquidityGrabs[i].bullish && liquidityGrabs[i].active) {
               // If a recent bullish liquidity grab exists, confirm the buy signal
               datetime grabTime = liquidityGrabs[i].time;
               if(TimeCurrent() - grabTime < 4 * PeriodSeconds(_Period)) {
                  smcConfirmation = true;
                  if(DisplayInfo) Print("Buy signal confirmed by bullish liquidity grab");
                  break;
               }
            }
         }
         
         // Check for bullish fair value gaps
         if(!smcConfirmation) {
            for(int i=0; i<fvgCount; i++) {
               if(fairValueGaps[i].bullish && fairValueGaps[i].active) {
                  // Check if price is near the bottom of the FVG
                  double currentPrice = iClose(_Symbol, _Period, 0);
                  double atrBuffer[];
                  double atrValue = 0;
                  if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) atrValue = atrBuffer[0];
                  
                  if(MathAbs(currentPrice - fairValueGaps[i].low) < atrValue * 0.5) {
                     smcConfirmation = true;
                     if(DisplayInfo) Print("Buy signal confirmed by bullish fair value gap");
                     break;
                  }
               }
            }
         }
         
         // Check for bullish order blocks
         if(!smcConfirmation) {
            for(int i=0; i<obCount; i++) {
               if(orderBlocks[i].bullish && orderBlocks[i].active) {
                  // Check if price is retesting the order block
                  double currentPrice = iClose(_Symbol, _Period, 0);
                  double previousPrice = iClose(_Symbol, _Period, 1);
                  
                  // If price is inside or just entered the order block
                  if(currentPrice >= orderBlocks[i].low && currentPrice <= orderBlocks[i].high && 
                     (previousPrice < orderBlocks[i].low || previousPrice > orderBlocks[i].high)) {
                     
                     smcConfirmation = true;
                     orderBlocks[i].tested = true; // Mark as tested
                     
                     if(DisplayInfo) Print("Buy signal confirmed by bullish order block retest");
                     break;
                  }
               }
            }
         }
         
         // Check for bullish BOS and CHoCH events
         if(!smcConfirmation) {
            // Look for a recent bullish BOS event
            for(int i=0; i<bosCount; i++) {
               if(bosEvents[i].bullish && bosEvents[i].active && bosEvents[i].confirmed) {
                  // Check if it's a recent BOS event
                  if(TimeCurrent() - bosEvents[i].time < 10 * PeriodSeconds(_Period)) {
                     // Check that price is near or retesting the BOS level
                     double currentPrice = iClose(_Symbol, _Period, 0);
                     double breakLevel = bosEvents[i].price;
                     
                     // Price should be near the break level
                     double atrBuffer[];
                     double atrValue = 0;
                     if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) atrValue = atrBuffer[0];
                     
                     if(MathAbs(currentPrice - breakLevel) < atrValue * 0.5) {
                        smcConfirmation = true;
                        if(DisplayInfo) Print("Buy signal confirmed by bullish Break of Structure");
                        break;
                     }
                  }
               }
            }
            
            // If no BOS confirmation, look for a bullish CHoCH event
            if(!smcConfirmation) {
               for(int i=0; i<chochCount; i++) {
                  if(chochEvents[i].bullish && chochEvents[i].active) {
                     // Check if it's a recent and strong CHoCH event
                     if(TimeCurrent() - chochEvents[i].time < 8 * PeriodSeconds(_Period) && 
                        chochEvents[i].strength > 0.5) {
                        
                        // Confirm we're trading in the direction of the CHoCH
                        double currentPrice = iClose(_Symbol, _Period, 0);
                        
                        if(currentPrice > chochEvents[i].price) {
                           smcConfirmation = true;
                           if(DisplayInfo) Print("Buy signal confirmed by bullish Change of Character");
                           break;
                        }
                     }
                  }
               }
            }
         }
         
         // No SMC confirmation found - only enforce if structures exist
         if(!smcConfirmation && (grabCount > 0 || fvgCount > 0 || obCount > 0)) {
            buySignal = false;
            if(DisplayInfo) Print("Buy signal rejected due to lack of SMC confirmation");
         }
      }
      
      // Look for SMC structure confirmation for sell signals
      if(sellSignal) {
         bool smcConfirmation = false;
         
         // Check for bearish liquidity grabs
         for(int i=0; i<grabCount; i++) {
            if(!liquidityGrabs[i].bullish && liquidityGrabs[i].active) {
               // If a recent bearish liquidity grab exists, confirm the sell signal
               datetime grabTime = liquidityGrabs[i].time;
               if(TimeCurrent() - grabTime < 4 * PeriodSeconds(_Period)) {
                  smcConfirmation = true;
                  if(DisplayInfo) Print("Sell signal confirmed by bearish liquidity grab");
                  break;
               }
            }
         }
         
         // Check for bearish fair value gaps
         if(!smcConfirmation) {
            for(int i=0; i<fvgCount; i++) {
               if(!fairValueGaps[i].bullish && fairValueGaps[i].active) {
                  // Check if price is near the top of the FVG
                  double currentPrice = iClose(_Symbol, _Period, 0);
                  double atrBuffer[];
                  double atrValue = 0;
                  if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) atrValue = atrBuffer[0];
                  
                  if(MathAbs(currentPrice - fairValueGaps[i].high) < atrValue * 0.5) {
                     smcConfirmation = true;
                     if(DisplayInfo) Print("Sell signal confirmed by bearish fair value gap");
                     break;
                  }
               }
            }
         }
         
         // Check for bearish order blocks
         if(!smcConfirmation) {
            for(int i=0; i<obCount; i++) {
               if(!orderBlocks[i].bullish && orderBlocks[i].active) {
                  // Check if price is retesting the order block
                  double currentPrice = iClose(_Symbol, _Period, 0);
                  double previousPrice = iClose(_Symbol, _Period, 1);
                  
                  // If price is inside or just entered the order block
                  if(currentPrice >= orderBlocks[i].low && currentPrice <= orderBlocks[i].high && 
                     (previousPrice < orderBlocks[i].low || previousPrice > orderBlocks[i].high)) {
                     
                     smcConfirmation = true;
                     orderBlocks[i].tested = true; // Mark as tested
                     
                     if(DisplayInfo) Print("Sell signal confirmed by bearish order block retest");
                     break;
                  }
               }
            }
         }
         
         // Check for bearish BOS and CHoCH events
         if(!smcConfirmation) {
            // Look for a recent bearish BOS event
            for(int i=0; i<bosCount; i++) {
               if(!bosEvents[i].bullish && bosEvents[i].active && bosEvents[i].confirmed) {
                  // Check if it's a recent BOS event
                  if(TimeCurrent() - bosEvents[i].time < 10 * PeriodSeconds(_Period)) {
                     // Check that price is near or retesting the BOS level
                     double currentPrice = iClose(_Symbol, _Period, 0);
                     double breakLevel = bosEvents[i].price;
                     
                     // Price should be near the break level
                     double atrBuffer[];
                     double atrValue = 0;
                     if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) atrValue = atrBuffer[0];
                     
                     if(MathAbs(currentPrice - breakLevel) < atrValue * 0.5) {
                        smcConfirmation = true;
                        if(DisplayInfo) Print("Sell signal confirmed by bearish Break of Structure");
                        break;
                     }
                  }
               }
            }
            
            // If no BOS confirmation, look for a bearish CHoCH event
            if(!smcConfirmation) {
               for(int i=0; i<chochCount; i++) {
                  if(!chochEvents[i].bullish && chochEvents[i].active) {
                     // Check if it's a recent and strong CHoCH event
                     if(TimeCurrent() - chochEvents[i].time < 8 * PeriodSeconds(_Period) && 
                        chochEvents[i].strength > 0.5) {
                        
                        // Confirm we're trading in the direction of the CHoCH
                        double currentPrice = iClose(_Symbol, _Period, 0);
                        
                        if(currentPrice < chochEvents[i].price) {
                           smcConfirmation = true;
                           if(DisplayInfo) Print("Sell signal confirmed by bearish Change of Character");
                           break;
                        }
                     }
                  }
               }
            }
         }
         
         // No SMC confirmation found - only enforce if structures exist
         if(!smcConfirmation && (grabCount > 0 || fvgCount > 0 || obCount > 0)) {
            sellSignal = false;
            if(DisplayInfo) Print("Sell signal rejected due to lack of SMC confirmation");
         }
      }
   }
   
   // Execute the trade if we have a confirmed signal
   if(buySignal || sellSignal) {
      // Calculate position size based on risk percentage
      double lotSize = CalculateLotSize(RiskPercentage, InitialStopLoss);
      ENUM_ORDER_TYPE orderType = buySignal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      
      // Log trade details
      Print("Entry: ", (buySignal ? "BUY" : "SELL"), " | Lot: ", lotSize, 
            " | Price: ", SymbolInfoDouble(_Symbol, buySignal ? SYMBOL_ASK : SYMBOL_BID),
            " | Regime: ", RegimeToString(currentRegime));
      
      // Open the position
      OpenPosition(orderType, lotSize);
   }
}

//+------------------------------------------------------------------+
//| Calculate optimal stop loss based on swing points                 |
//+------------------------------------------------------------------+
double CalculateOptimalStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice, double defaultSL) {
   // If SMC features or optimal SL is disabled, use default stop loss
   if(!EnableSMC || !UseOptimalStopLoss || swingCount == 0) return defaultSL;
   
   double pip = GetPipSize();
   double atrBuffer[];
   double atrValue = 0;
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) atrValue = atrBuffer[0];
   
   double bestSL = defaultSL;
   double bestScore = 0;
   
   if(orderType == ORDER_TYPE_BUY) {
      // For buy orders, find recent swing lows for stop placement
      for(int i=0; i<swingCount; i++) {
         // Only consider swing points below entry price
         if(swingPoints[i].price < entryPrice) {
            // Calculate distance from entry to swing point
            double distance = entryPrice - swingPoints[i].price;
            
            // Stop loss should be reasonable - not too close or far
            if(distance > atrValue * 0.5 && distance < InitialStopLoss * 1.5 * pip) {
               // Calculate score based on swing strength and distance ratio
               // Prefer stronger swings that are not too far from entry
               double score = swingPoints[i].score * (1.0 - (distance / (InitialStopLoss * 2 * pip)));
               
               if(score > bestScore) {
                  // Place SL slightly below the swing point
                  bestScore = score;
                  bestSL = swingPoints[i].price - 5 * _Point;
               }
            }
         }
      }
   } else { // SELL order
      // For sell orders, find recent swing highs for stop placement
      for(int i=0; i<swingCount; i++) {
         // Only consider swing points above entry price
         if(swingPoints[i].price > entryPrice) {
            // Calculate distance from entry to swing point
            double distance = swingPoints[i].price - entryPrice;
            
            // Stop loss should be reasonable - not too close or far
            if(distance > atrValue * 0.5 && distance < InitialStopLoss * 1.5 * pip) {
               // Calculate score based on swing strength and distance ratio
               double score = swingPoints[i].score * (1.0 - (distance / (InitialStopLoss * 2 * pip)));
               
               if(score > bestScore) {
                  // Place SL slightly above the swing point
                  bestScore = score;
                  bestSL = swingPoints[i].price + 5 * _Point;
               }
            }
         }
      }
   }
   
   // If no suitable swing point found, use default SL
   if(bestScore == 0) {
      bestSL = defaultSL;
   } else {
      if(DisplayInfo) Print("Using optimal structure-based stop loss");
   }
   
   return bestSL;
}

//+------------------------------------------------------------------+
//| Open a position with enhanced SMC features                        |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType, double lotSize)
{
   MqlTradeRequest request;
   ZeroMemory(request);
   MqlTradeResult result;
   ZeroMemory(result);
   
   // Get pip size and entry price
   double pip = GetPipSize();
   double entryPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate standard stop loss and take profit
   double standardSL = (orderType == ORDER_TYPE_BUY) ? entryPrice - InitialStopLoss * pip : entryPrice + InitialStopLoss * pip;
   double tp = (orderType == ORDER_TYPE_BUY) ? entryPrice + InitialTakeProfit * pip : entryPrice - InitialTakeProfit * pip;
   
   // Use enhanced stop loss calculation if SMC features are enabled
   double sl = EnableSMC ? CalculateOptimalStopLoss(orderType, entryPrice, standardSL) : standardSL;
   
   // Prepare and execute the trade
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = entryPrice;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 5;
   request.magic = MagicNumber;
   request.type_filling = ORDER_FILLING_FOK;
   
   // Set trailing active flag for SMC enhanced trailing
   if(EnableSMC && UseAdvancedTrailing) {
      trailingActive = true;
   }
   
   // Log trade details
   string details = StringFormat("OrderSend: %s | Price: %.5f | SL: %.5f | TP: %.5f | Lot: %.2f", 
                               (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                               entryPrice, sl, tp, lotSize);
   Print(details);
   
   // Execute trade
   if(!OrderSend(request, result)) {
      Print("OrderSend DEAL failed: ", GetLastError());
      consecutiveLosses++;
      
      // Enable emergency mode if too many consecutive failures
      if(consecutiveLosses >= 3) {
         emergencyMode = true;
         Print("WARNING: Enabling emergency mode after ", consecutiveLosses, " failures");
      }
   } else {
      // Reset counters on successful trade
      lastTradeTime = TimeCurrent();
      
      // Reset emergency mode if it was active
      if(emergencyMode) {
         emergencyMode = false;
         consecutiveLosses = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Find best swing point for trailing stop placement                 |
//+------------------------------------------------------------------+
double FindBestSwingTrailLevel(ENUM_POSITION_TYPE posType, double currentPrice, double openPrice, double currentTrailLevel) {
   if(!EnableSMC || !UseAdvancedTrailing || swingCount == 0) return currentTrailLevel;
   
   double bestTrailLevel = currentTrailLevel;
   double bestScore = 0;
   double atrBuffer[];
   double atrValue = 0;
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) atrValue = atrBuffer[0];
   
   if(posType == POSITION_TYPE_BUY) {
      // For buys, find swing lows between open price and current price for trailing
      for(int i=0; i<swingCount; i++) {
         if(swingPoints[i].price > openPrice && swingPoints[i].price < currentPrice - atrValue * 0.5) {
            // Calculate score based on swing strength and recency
            double score = swingPoints[i].score * (1.0 - (0.05 * swingPoints[i].barIndex));
            
            if(score > bestScore && swingPoints[i].price > bestTrailLevel) {
               bestScore = score;
               bestTrailLevel = swingPoints[i].price;
            }
         }
      }
   } else { // SELL position
      // For sells, find swing highs between open price and current price for trailing
      for(int i=0; i<swingCount; i++) {
         if(swingPoints[i].price < openPrice && swingPoints[i].price > currentPrice + atrValue * 0.5) {
            // Calculate score based on swing strength and recency
            double score = swingPoints[i].score * (1.0 - (0.05 * swingPoints[i].barIndex));
            
            if(score > bestScore && swingPoints[i].price < bestTrailLevel) {
               bestScore = score;
               bestTrailLevel = swingPoints[i].price;
            }
         }
      }
   }
   
   return bestScore > 0 ? bestTrailLevel : currentTrailLevel;
}

//+------------------------------------------------------------------+
//| Enhanced trailing stop function with SMC features                 |
//+------------------------------------------------------------------+
void TrailPositions()
{
   double pip = GetPipSize();
   double buffer = GetDynamicBuffer();
   static double maxProfitPips[2] = {0, 0}; // [0]=buy, [1]=sell
   
   // Get ATR value for adaptive trailing
   double atrBuffer[];
   double atrValue = 0;
   if(EnableSMC && CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
      atrValue = atrBuffer[0];
   }
   
   // Update SMC structures if using advanced trailing
   if(EnableSMC && UseAdvancedTrailing && PositionsTotal() > 0) {
      // Periodically update swing points for better trailing
      IdentifySwingPoints();
   }
   
   // Process each open position
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPips = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / pip : (openPrice - currentPrice) / pip;
         
         // Log position details
         if(DisplayInfo) {
            Print("Trail: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), 
                  " | Open: ", DoubleToString(openPrice, 5), 
                  " | Price: ", DoubleToString(currentPrice, 5), 
                  " | SL: ", DoubleToString(currentSL, 5), 
                  " | Pips: ", DoubleToString(profitPips, 1));
         }
         
         // Only proceed with trailing if in profit beyond trailing step
         if(profitPips >= TrailingStep)
         {
            // Calculate standard trailing stop level
            double standardTrailSL = (posType == POSITION_TYPE_BUY) 
                                    ? currentPrice - TrailingStop * pip
                                    : currentPrice + TrailingStop * pip;
            
            double newSL = standardTrailSL;
            
            // Use enhanced structure-based trailing if enabled
            if(EnableSMC && UseAdvancedTrailing) {
               // Adjust trailing based on current market regime
               double trailMultiplier = 1.0;
               
               if(UseMarketRegime) {
                  switch(currentRegime) {
                     case TRENDING_UP:
                        if(posType == POSITION_TYPE_BUY) trailMultiplier = 0.7; // Looser trail in uptrend for buys
                        break;
                     case TRENDING_DOWN:
                        if(posType == POSITION_TYPE_SELL) trailMultiplier = 0.7; // Looser trail in downtrend for sells
                        break;
                     case HIGH_VOLATILITY:
                     case CHOPPY:
                        trailMultiplier = 1.3; // Tighter trail in volatile conditions
                        break;
                  }
               }
               
               // Calculate adaptive trail level based on ATR
               double adaptiveTrailLevel = (posType == POSITION_TYPE_BUY)
                                      ? currentPrice - (atrValue * trailMultiplier)
                                      : currentPrice + (atrValue * trailMultiplier);
               
               // Find best swing point for enhanced trailing
               double structureBasedTrail = FindBestSwingTrailLevel(posType, currentPrice, openPrice, adaptiveTrailLevel);
               
               // Choose the best trail level among all options
               if(posType == POSITION_TYPE_BUY) {
                  // For buy positions, take the highest SL (closest to current price)
                  newSL = MathMax(standardTrailSL, structureBasedTrail);
                  // Don't move SL backward
                  newSL = MathMax(newSL, currentSL);
               } else {
                  // For sell positions, take the lowest SL (closest to current price)
                  newSL = MathMin(standardTrailSL, structureBasedTrail);
                  // Don't move SL backward
                  newSL = MathMin(newSL, currentSL);
               }
            }
            
            // Only update if we have a better stop loss
            bool updateNeeded = (posType == POSITION_TYPE_BUY && newSL > currentSL) || 
                               (posType == POSITION_TYPE_SELL && newSL < currentSL);
            
            if(updateNeeded) {
               MqlTradeRequest request;
               ZeroMemory(request);
               MqlTradeResult result;
               ZeroMemory(result);
               request.action = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.symbol = _Symbol;
               request.sl = newSL;
               request.tp = currentTP; // Keep the same TP
               request.magic = MagicNumber;
               
               // Execute the SL modification
               if(OrderSend(request, result)) {
                  Print("Trail updated: ", DoubleToString(newSL, 5), 
                       (EnableSMC && UseAdvancedTrailing ? " [SMC Enhanced]" : ""));
               } else {
                  Print("Trail update failed: ", GetLastError());
               }
            }
         }
         
         // Hybrid profit trailing: after X% of TP, trail max profit
         double profitTrailStartPips = InitialTakeProfit * ProfitTrailStart;
         int idx = (posType == POSITION_TYPE_BUY) ? 0 : 1;
         
         if(profitPips >= profitTrailStartPips)
         {
            // Track max profit achieved
            if(profitPips > maxProfitPips[idx])
               maxProfitPips[idx] = profitPips;
               
            // Calculate profit trail level
            double profitTrailLevel = maxProfitPips[idx] - buffer;
            bool allowClose = true;
            
            // Apply options for never closing at a loss
            if(NoProfitTrailLoss && profitTrailLevel < 0)
               profitTrailLevel = 0; // never allow close at loss
               
            if(NoProfitTrailLoss && profitPips < 0)
               allowClose = false;
               
            // Close position if profit has dropped below trailing threshold
            if(profitPips < profitTrailLevel && allowClose)
            {
               Print("Profit trail triggered: Current ", DoubleToString(profitPips, 1), 
                     " pips < Trail level ", DoubleToString(profitTrailLevel, 1), " pips");
                     
               // Execute position close
               MqlTradeRequest request;
               ZeroMemory(request);
               MqlTradeResult result;
               ZeroMemory(result);
               request.action = TRADE_ACTION_DEAL;
               request.position = ticket;
               request.symbol = _Symbol;
               request.volume = PositionGetDouble(POSITION_VOLUME);
               request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
               request.price = currentPrice;
               request.deviation = 5;
               request.magic = MagicNumber;
               
               if(OrderSend(request, result)) {
                  Print("Position closed by profit trail successfully");
                  // Update performance tracking for market regime
                  if(EnableSMC && UseMarketRegime && currentRegime >= 0 && currentRegime < REGIME_COUNT) {
                     if(profitPips > 0) {
                        regimeWins[currentRegime]++;
                        regimeProfit[currentRegime] += profitPips;
                     } else {
                        regimeLosses[currentRegime]++;
                        regimeProfit[currentRegime] += profitPips;
                     }
                  }
                  // Reset max profit tracking for this direction
                  maxProfitPips[idx] = 0;
               } else {
                  Print("Position close failed: ", GetLastError());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions and check for closing conditions             |
//+------------------------------------------------------------------+
void CheckForPositionManagement()
{
   if(PositionsTotal() > 0) {
      // Check spread conditions
      double currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
      if(currentSpread > MaxSpread * GetPipSize() && EmergencyCloseOnSpread) {
         CloseAllPositions("Emergency close - spread too high");
         return;
      }
      
      // Check position expiry if enabled
      if(MaxPositionHoldTime > 0) {
         CheckPositionExpiration();
      }
   }
}

//+------------------------------------------------------------------+
//| Check for early exit based on regime change or other conditions   |
//+------------------------------------------------------------------+
void CheckEarlyExitConditions()
{
   // Skip if no SMC features or no positions
   if(!EnableSMC || PositionsTotal() == 0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         bool shouldClose = false;
         string exitReason = "";
         
         // Check for regime-based exits
         if(UseMarketRegime) {
            // Exit long positions in bearish regimes
            if(posType == POSITION_TYPE_BUY && 
               (currentRegime == TRENDING_DOWN || currentRegime == HIGH_VOLATILITY)) {
               shouldClose = true;
               exitReason = "Market regime changed to " + RegimeToString(currentRegime);
            }
            // Exit short positions in bullish regimes
            else if(posType == POSITION_TYPE_SELL && 
                    (currentRegime == TRENDING_UP || currentRegime == BREAKOUT)) {
               shouldClose = true;
               exitReason = "Market regime changed to " + RegimeToString(currentRegime);
            }
         }
         
         // Check for opposing liquidity grabs (strong reversal signal)
         if(!shouldClose && grabCount > 0) {
            for(int j = 0; j < grabCount; j++) {
               // Only consider recent and active grabs
               if(liquidityGrabs[j].active && 
                  TimeCurrent() - liquidityGrabs[j].time < 5 * PeriodSeconds(_Period)) {
                  
                  // Opposing liquidity grab (bullish grab for sell position or vice versa)
                  if((posType == POSITION_TYPE_SELL && liquidityGrabs[j].bullish) || 
                     (posType == POSITION_TYPE_BUY && !liquidityGrabs[j].bullish)) {
                     
                     // Strong opposing liquidity grab
                     if(liquidityGrabs[j].strength > 1.5) {
                        shouldClose = true;
                        exitReason = "Strong opposing liquidity grab detected";
                        break;
                     }
                  }
               }
            }
         }
         
         // Check for opposing Break of Structure (BOS) events
         if(!shouldClose && bosCount > 0) {
            for(int j = 0; j < bosCount; j++) {
               // Only consider recent, active and confirmed BOS events
               if(bosEvents[j].active && bosEvents[j].confirmed && 
                  TimeCurrent() - bosEvents[j].time < 7 * PeriodSeconds(_Period)) {
                  
                  // Opposing BOS (bullish BOS for sell position or vice versa)
                  if((posType == POSITION_TYPE_SELL && bosEvents[j].bullish) || 
                     (posType == POSITION_TYPE_BUY && !bosEvents[j].bullish)) {
                     
                     // Strong opposing BOS with good momentum
                     if(bosEvents[j].strength > 1.0) {
                        shouldClose = true;
                        exitReason = "Opposing Break of Structure detected";
                        break;
                     }
                  }
               }
            }
         }
         
         // Check for opposing Change of Character (CHoCH) events
         if(!shouldClose && chochCount > 0) {
            for(int j = 0; j < chochCount; j++) {
               // Only consider recent and active CHoCH events
               if(chochEvents[j].active && 
                  TimeCurrent() - chochEvents[j].time < 6 * PeriodSeconds(_Period)) {
                  
                  // Opposing CHoCH (bullish CHoCH for sell position or vice versa)
                  if((posType == POSITION_TYPE_SELL && chochEvents[j].bullish) || 
                     (posType == POSITION_TYPE_BUY && !chochEvents[j].bullish)) {
                     
                     // Significant CHoCH signal
                     if(chochEvents[j].strength > 0.8) {
                        shouldClose = true;
                        exitReason = "Opposing Change of Character detected";
                        break;
                     }
                  }
               }
            }
         }
         
         // Close position if conditions met
         if(shouldClose) {
            double closePrice = (posType == POSITION_TYPE_BUY) ? 
                              SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                              SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                              
            Print("Early exit signal: ", exitReason);
            
            MqlTradeRequest request;
            ZeroMemory(request);
            MqlTradeResult result;
            ZeroMemory(result);
            
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = closePrice;
            request.deviation = 5;
            request.magic = MagicNumber;
            
            if(OrderSend(request, result)) {
               Print("Position closed early: ", exitReason);
               
               // Track regime performance if applicable
               if(UseMarketRegime && exitReason.Find("regime") >= 0) {
                  double profitPips = (posType == POSITION_TYPE_BUY) ? 
                                    (closePrice - PositionGetDouble(POSITION_PRICE_OPEN)) / GetPipSize() : 
                                    (PositionGetDouble(POSITION_PRICE_OPEN) - closePrice) / GetPipSize();
                  
                  if(profitPips > 0) {
                     regimeWins[currentRegime]++;
                  } else {
                     regimeLosses[currentRegime]++;
                  }
                  regimeProfit[currentRegime] += profitPips;
               }
            } else {
               Print("Failed to close position: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for position expiration based on max hold time              |
//+------------------------------------------------------------------+
void CheckPositionExpiration()
{
   if(MaxPositionHoldTime <= 0) return; // Feature disabled
   
   datetime currentTime = TimeCurrent();
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         int secondsHeld = (int)(currentTime - openTime);
         
         // Check if position exceeded maximum hold time
         if(secondsHeld > MaxPositionHoldTime) {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double closePrice = (posType == POSITION_TYPE_BUY) ? 
                               SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                               SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            Print("Position expired - exceeded maximum hold time of ", MaxPositionHoldTime, " seconds");
            
            MqlTradeRequest request;
            ZeroMemory(request);
            MqlTradeResult result;
            ZeroMemory(result);
            
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = closePrice;
            request.deviation = 5;
            request.magic = MagicNumber;
            
            if(!OrderSend(request, result)) {
               Print("Failed to close expired position: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if trading is allowed based on time restrictions           |
//+------------------------------------------------------------------+
bool IsTradingTimeAllowed()
{
   // Skip time checks if filters are disabled
   if(!UseTimeFilter) return true;
   
   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   
   // Check if we're within allowed trading hours
   int currentHour = time.hour;
   
   if(currentHour < StartHour || currentHour >= EndHour) {
      if(DisplayInfo) Comment("Outside trading hours: ", currentHour, ":00");
      return false;
   }
   
   // Check trading days
   if(!AllowWeekends && (time.day_of_week == 0 || time.day_of_week == 6)) {
      if(DisplayInfo) Comment("Weekend trading not allowed");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Close all open positions with a specified reason                  |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double closePrice = (posType == POSITION_TYPE_BUY) ? 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         MqlTradeRequest request;
         ZeroMemory(request);
         MqlTradeResult result;
         ZeroMemory(result);
         
         request.action = TRADE_ACTION_DEAL;
         request.position = ticket;
         request.symbol = _Symbol;
         request.volume = PositionGetDouble(POSITION_VOLUME);
         request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = closePrice;
         request.deviation = 5;
         request.magic = MagicNumber;
         request.comment = reason;
         
         if(!OrderSend(request, result)) {
            Print("Failed to close position: ", GetLastError());
         } else {
            Print("Position closed: ", reason);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Break of Structure (BOS) events                           |
//+------------------------------------------------------------------+
void DetectBreakOfStructure()
{
   if(!EnableSMC || swingCount < 2) return;
   
   // Clear previous BOS events
   ArrayFree(bosEvents);
   bosCount = 0;
   
   // Get price data
   double high[], low[], close[];
   int bars_to_analyze = MathMin(200, iBars(_Symbol, _Period));
   
   if(CopyHigh(_Symbol, _Period, 0, bars_to_analyze, high) != bars_to_analyze) return;
   if(CopyLow(_Symbol, _Period, 0, bars_to_analyze, low) != bars_to_analyze) return;
   if(CopyClose(_Symbol, _Period, 0, bars_to_analyze, close) != bars_to_analyze) return;
   
   // Get ATR for measuring break strength
   double atrBuffer[];
   double atrValue = 0;
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) atrValue = atrBuffer[0];
   if(atrValue == 0) return; // Safety check
   
   // Sort swing points by time (most recent first)
   ArraySort(swingPoints, WHOLE_ARRAY, 0, MODE_DESCEND);
   
   // Look for breaks of swing highs (bearish BOS)
   for(int i = 0; i < bars_to_analyze-3; i++) {
      // Scan swing highs to find if any were broken
      for(int j = 0; j < swingCount; j++) {
         // Only check swing highs for bearish BOS
         if(!swingPoints[j].isHigh) continue;
         
         // Skip swing points that are too recent
         if(swingPoints[j].barIndex <= i) continue;
         
         // Check if price broke below this swing high
         if(low[i] < swingPoints[j].price && high[i+1] > swingPoints[j].price) {
            // Found a bearish break of structure
            
            // Calculate break strength based on momentum
            double breakSize = swingPoints[j].price - low[i];
            double breakStrength = breakSize / atrValue;
            
            // Check if we have a minimum strength break
            if(breakStrength > 0.3) {
               bosCount++;
               ArrayResize(bosEvents, bosCount);
               bosEvents[bosCount-1].price = swingPoints[j].price;
               bosEvents[bosCount-1].time = iTime(_Symbol, _Period, i);
               bosEvents[bosCount-1].bullish = false; // Bearish BOS
               bosEvents[bosCount-1].swingIndex = j;
               bosEvents[bosCount-1].strength = breakStrength;
               bosEvents[bosCount-1].barIndex = i;
               bosEvents[bosCount-1].active = true;
               
               // Check if break is confirmed by subsequent close below the level
               bosEvents[bosCount-1].confirmed = (close[i] < swingPoints[j].price);
               
               // Mark the swing point as broken
               swingPoints[j].broken = true;
               
               break; // Move to next bar
            }
         }
      }
   }
   
   // Look for breaks of swing lows (bullish BOS)
   for(int i = 0; i < bars_to_analyze-3; i++) {
      // Scan swing lows to find if any were broken
      for(int j = 0; j < swingCount; j++) {
         // Only check swing lows for bullish BOS
         if(swingPoints[j].isHigh) continue;
         
         // Skip swing points that are too recent
         if(swingPoints[j].barIndex <= i) continue;
         
         // Check if price broke above this swing low
         if(high[i] > swingPoints[j].price && low[i+1] < swingPoints[j].price) {
            // Found a bullish break of structure
            
            // Calculate break strength based on momentum
            double breakSize = high[i] - swingPoints[j].price;
            double breakStrength = breakSize / atrValue;
            
            // Check if we have a minimum strength break
            if(breakStrength > 0.3) {
               bosCount++;
               ArrayResize(bosEvents, bosCount);
               bosEvents[bosCount-1].price = swingPoints[j].price;
               bosEvents[bosCount-1].time = iTime(_Symbol, _Period, i);
               bosEvents[bosCount-1].bullish = true; // Bullish BOS
               bosEvents[bosCount-1].swingIndex = j;
               bosEvents[bosCount-1].strength = breakStrength;
               bosEvents[bosCount-1].barIndex = i;
               bosEvents[bosCount-1].active = true;
               
               // Check if break is confirmed by subsequent close above the level
               bosEvents[bosCount-1].confirmed = (close[i] > swingPoints[j].price);
               
               // Mark the swing point as broken
               swingPoints[j].broken = true;
               
               break; // Move to next bar
            }
         }
      }
   }
   
   // Deactivate old BOS events
   datetime currentTime = TimeCurrent();
   for(int i = 0; i < bosCount; i++) {
      if(currentTime - bosEvents[i].time > 20 * PeriodSeconds(_Period)) {
         bosEvents[i].active = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Change of Character (CHoCH) events                         |
//+------------------------------------------------------------------+
void DetectChangeOfCharacter()
{
   if(!EnableSMC || bosCount < 2) return; // Need BOS events first
   
   // Clear previous CHoCH events
   ArrayFree(chochEvents);
   chochCount = 0;
   
   // Get price data
   double high[], low[], close[];
   int bars_to_analyze = MathMin(200, iBars(_Symbol, _Period));
   
   if(CopyHigh(_Symbol, _Period, 0, bars_to_analyze, high) != bars_to_analyze) return;
   if(CopyLow(_Symbol, _Period, 0, bars_to_analyze, low) != bars_to_analyze) return;
   if(CopyClose(_Symbol, _Period, 0, bars_to_analyze, close) != bars_to_analyze) return;
   
   // Sort BOS events by time (most recent first)
   //ArraySort(bosEvents, WHOLE_ARRAY, 0, MODE_DESCEND);
   
   // CHoCH occurs when after a BOS event, price fails to continue the break
   // and instead reverses, indicating a change of market character
   
   // Look for bullish CHoCH (higher low after bearish BOS)
   for(int i = 0; i < bosCount; i++) {
      // Only interested in bearish BOS events that are confirmed
      if(bosEvents[i].bullish || !bosEvents[i].confirmed) continue;
      
      // Get the bar index of the BOS event
      int bosBarIndex = bosEvents[i].barIndex;
      
      // Check subsequent price action for a higher low
      for(int j = bosBarIndex-1; j >= 0 && j > bosBarIndex-15; j--) {
         // Look for a higher low (after bearish BOS)
         if(low[j] > low[bosBarIndex] && close[j] > bosEvents[i].price) {
            // Found a bullish CHoCH (higher low)
            chochCount++;
            ArrayResize(chochEvents, chochCount);
            chochEvents[chochCount-1].price = low[j];
            chochEvents[chochCount-1].time = iTime(_Symbol, _Period, j);
            chochEvents[chochCount-1].bullish = true;
            chochEvents[chochCount-1].prevSwing = low[bosBarIndex];
            chochEvents[chochCount-1].barIndex = j;
            chochEvents[chochCount-1].active = true;
            
            // Calculate strength based on the size of the higher low
            chochEvents[chochCount-1].strength = (low[j] - low[bosBarIndex]) / bosEvents[i].strength;
            
            break; // Move to next BOS event
         }
      }
   }
   
   // Look for bearish CHoCH (lower high after bullish BOS)
   for(int i = 0; i < bosCount; i++) {
      // Only interested in bullish BOS events that are confirmed
      if(!bosEvents[i].bullish || !bosEvents[i].confirmed) continue;
      
      // Get the bar index of the BOS event
      int bosBarIndex = bosEvents[i].barIndex;
      
      // Check subsequent price action for a lower high
      for(int j = bosBarIndex-1; j >= 0 && j > bosBarIndex-15; j--) {
         // Look for a lower high (after bullish BOS)
         if(high[j] < high[bosBarIndex] && close[j] < bosEvents[i].price) {
            // Found a bearish CHoCH (lower high)
            chochCount++;
            ArrayResize(chochEvents, chochCount);
            chochEvents[chochCount-1].price = high[j];
            chochEvents[chochCount-1].time = iTime(_Symbol, _Period, j);
            chochEvents[chochCount-1].bullish = false;
            chochEvents[chochCount-1].prevSwing = high[bosBarIndex];
            chochEvents[chochCount-1].barIndex = j;
            chochEvents[chochCount-1].active = true;
            
            // Calculate strength based on the size of the lower high
            chochEvents[chochCount-1].strength = (high[bosBarIndex] - high[j]) / bosEvents[i].strength;
            
            break; // Move to next BOS event
         }
      }
   }
   
   // Deactivate old CHoCH events
   datetime currentTime = TimeCurrent();
   for(int i = 0; i < chochCount; i++) {
      if(currentTime - chochEvents[i].time > 20 * PeriodSeconds(_Period)) {
         chochEvents[i].active = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Update chart visualizations for SMC structures                   |
//+------------------------------------------------------------------+
void UpdateSMCVisualizations()
{
   if(!EnableSMC) return;
   
   // Clear old objects
   ObjectsDeleteAll(0, "SMC_");
   
   // Current time for filtering out old structures
   datetime currentTime = TimeCurrent();
   datetime cutoffTime = (VisualizationDays > 0) ? currentTime - VisualizationDays * 24 * 60 * 60 : 0;
   
   // Draw swing points
   if(ShowSwingPoints && swingCount > 0) {
      for(int i = 0; i < swingCount; i++) {
         // Skip old swing points if filtering is active
         if(VisualizationDays > 0 && swingPoints[i].time < cutoffTime) continue;
         
         // Skip broken swing points
         if(swingPoints[i].broken) continue;
         
         string name = "SMC_SwingPoint_" + IntegerToString(i);
         color pointColor = swingPoints[i].isHigh ? BearishColor : BullishColor;
         
         // Adjust size based on strength
         int size = 5 + (int)(swingPoints[i].score * 3);
         size = MathMin(size, 10);
         
         // Draw the swing point
         ObjectCreate(0, name, OBJ_ARROW, 0, swingPoints[i].time, swingPoints[i].price);
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, swingPoints[i].isHigh ? 119 : 119);
         ObjectSetInteger(0, name, OBJPROP_COLOR, pointColor);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, size);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
   }
   
   // Draw liquidity grabs
   if(ShowLiquidityGrabs && grabCount > 0) {
      for(int i = 0; i < grabCount; i++) {
         // Skip old grabs if filtering is active
         if(VisualizationDays > 0 && liquidityGrabs[i].time < cutoffTime) continue;
         
         // Skip inactive grabs
         if(!liquidityGrabs[i].active) continue;
         
         string name = "SMC_LiquidityGrab_" + IntegerToString(i);
         color grabColor = liquidityGrabs[i].bullish ? BullishColor : BearishColor;
         
         // Draw the liquidity grab arrow
         ObjectCreate(0, name, OBJ_ARROW, 0, liquidityGrabs[i].time, liquidityGrabs[i].price);
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, liquidityGrabs[i].bullish ? 241 : 242);
         ObjectSetInteger(0, name, OBJPROP_COLOR, grabColor);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
         
         // Add label to show strength
         string labelName = "SMC_LiqGrabLabel_" + IntegerToString(i);
         string labelText = "LG: " + DoubleToString(liquidityGrabs[i].strength, 1);
         ObjectCreate(0, labelName, OBJ_TEXT, 0, liquidityGrabs[i].time, 
                     liquidityGrabs[i].bullish ? liquidityGrabs[i].high + 10 * _Point : liquidityGrabs[i].low - 10 * _Point);
         ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, grabColor);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
      }
   }
   
   // Draw fair value gaps
   if(ShowFairValueGaps && fvgCount > 0) {
      for(int i = 0; i < fvgCount; i++) {
         // Skip old FVGs if filtering is active
         if(VisualizationDays > 0 && fairValueGaps[i].time < cutoffTime) continue;
         
         // Skip filled or inactive FVGs
         if(fairValueGaps[i].filled || !fairValueGaps[i].active) continue;
         
         string name = "SMC_FVG_" + IntegerToString(i);
         color fvgColor = fairValueGaps[i].bullish ? BullishColor : BearishColor;
         
         // Draw the fair value gap as a rectangle
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, fairValueGaps[i].time, fairValueGaps[i].high, 
                     currentTime, fairValueGaps[i].low);
         ObjectSetInteger(0, name, OBJPROP_COLOR, fvgColor);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true); // Draw behind price
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         
         // Set transparency based on significance
         int transparency = 95 - (int)(fairValueGaps[i].significance * 20);
         transparency = MathMax(70, transparency); // Keep some transparency
         ObjectSetInteger(0, name, OBJPROP_TRANSPARENCY, transparency);
      }
   }
   
   // Draw order blocks
   if(ShowOrderBlocks && obCount > 0) {
      for(int i = 0; i < obCount; i++) {
         // Skip old order blocks if filtering is active
         if(VisualizationDays > 0 && orderBlocks[i].time < cutoffTime) continue;
         
         // Skip inactive order blocks
         if(!orderBlocks[i].active) continue;
         
         string name = "SMC_OrderBlock_" + IntegerToString(i);
         color obColor = orderBlocks[i].bullish ? BullishColor : BearishColor;
         
         // Adjust alpha based on whether it's been tested
         int transparency = orderBlocks[i].tested ? 90 : 80;
         
         // Draw the order block as a rectangle
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, orderBlocks[i].time, orderBlocks[i].high, 
                     orderBlocks[i].expiry, orderBlocks[i].low);
         ObjectSetInteger(0, name, OBJPROP_COLOR, obColor);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true); // Draw behind price
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_TRANSPARENCY, transparency);
         
         // Add border to highlight important order blocks
         if(orderBlocks[i].strength > 1.0) {
            string borderName = "SMC_OB_Border_" + IntegerToString(i);
            ObjectCreate(0, borderName, OBJ_RECTANGLE, 0, orderBlocks[i].time, orderBlocks[i].high, 
                        orderBlocks[i].expiry, orderBlocks[i].low);
            ObjectSetInteger(0, borderName, OBJPROP_COLOR, obColor);
            ObjectSetInteger(0, borderName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, borderName, OBJPROP_FILL, false);
         }
      }
   }
   
   // Draw Break of Structure (BOS) events
   if(ShowBOS && bosCount > 0) {
      for(int i = 0; i < bosCount; i++) {
         // Skip old BOS events if filtering is active
         if(VisualizationDays > 0 && bosEvents[i].time < cutoffTime) continue;
         
         // Skip inactive BOS events
         if(!bosEvents[i].active) continue;
         
         string name = "SMC_BOS_" + IntegerToString(i);
         color bosColor = bosEvents[i].bullish ? BullishColor : BearishColor;
         
         // Draw the BOS arrow
         ObjectCreate(0, name, OBJ_ARROW, 0, bosEvents[i].time, bosEvents[i].price);
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, bosEvents[i].bullish ? 233 : 234);
         ObjectSetInteger(0, name, OBJPROP_COLOR, bosColor);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, bosEvents[i].confirmed ? 3 : 1);
         
         // Add BOS label
         string labelName = "SMC_BOSLabel_" + IntegerToString(i);
         string labelText = "BOS" + (bosEvents[i].confirmed ? "*" : "");
         ObjectCreate(0, labelName, OBJ_TEXT, 0, bosEvents[i].time, 
                     bosEvents[i].price + (bosEvents[i].bullish ? 10 : -10) * _Point);
         ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, bosColor);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
      }
   }
   
   // Draw Change of Character (CHoCH) events
   if(ShowCHoCH && chochCount > 0) {
      for(int i = 0; i < chochCount; i++) {
         // Skip old CHoCH events if filtering is active
         if(VisualizationDays > 0 && chochEvents[i].time < cutoffTime) continue;
         
         // Skip inactive CHoCH events
         if(!chochEvents[i].active) continue;
         
         string name = "SMC_CHoCH_" + IntegerToString(i);
         color chochColor = chochEvents[i].bullish ? BullishColor : BearishColor;
         
         // Draw the CHoCH symbol
         ObjectCreate(0, name, OBJ_ARROW, 0, chochEvents[i].time, chochEvents[i].price);
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, chochEvents[i].bullish ? 236 : 236);
         ObjectSetInteger(0, name, OBJPROP_COLOR, chochColor);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         
         // Draw line connecting previous swing to CHoCH
         string lineName = "SMC_CHoCH_Line_" + IntegerToString(i);
         ObjectCreate(0, lineName, OBJ_TREND, 0, chochEvents[i].time, chochEvents[i].price,
                    chochEvents[i].time - 4 * PeriodSeconds(_Period), chochEvents[i].prevSwing);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, chochColor);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
         
         // Add CHoCH label
         string labelName = "SMC_CHoCHLabel_" + IntegerToString(i);
         string labelText = "CHoCH " + DoubleToString(chochEvents[i].strength, 1);
         ObjectCreate(0, labelName, OBJ_TEXT, 0, chochEvents[i].time, 
                     chochEvents[i].price + (chochEvents[i].bullish ? 15 : -15) * _Point);
         ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, chochColor);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
      }
   }
   
   // Draw current market regime label
   if(UseMarketRegime) {
      string regimeName = "SMC_CurrentRegime";
      string regimeText = "Regime: " + RegimeToString(currentRegime);
      color regimeColor = White;
      
      // Select color based on regime
      switch(currentRegime) {
         case TRENDING_UP: regimeColor = clrLime; break;
         case TRENDING_DOWN: regimeColor = clrRed; break;
         case CHOPPY: regimeColor = clrOrange; break;
         case HIGH_VOLATILITY: regimeColor = clrMagenta; break;
         case BREAKOUT: regimeColor = clrAqua; break;
         default: regimeColor = clrWhite;
      }
      
      // Create or update regime label
      if(ObjectFind(0, regimeName) < 0) {
         ObjectCreate(0, regimeName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, regimeName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
         ObjectSetInteger(0, regimeName, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, regimeName, OBJPROP_YDISTANCE, 20);
      }
      
      ObjectSetString(0, regimeName, OBJPROP_TEXT, regimeText);
      ObjectSetInteger(0, regimeName, OBJPROP_COLOR, regimeColor);
      ObjectSetInteger(0, regimeName, OBJPROP_FONTSIZE, 12);
      ObjectSetInteger(0, regimeName, OBJPROP_BACK, false);
   }
   
   // Force chart redraw
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
