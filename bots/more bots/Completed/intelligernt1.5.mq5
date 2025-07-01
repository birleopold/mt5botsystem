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

// Global variables
int MagicNumber = DEFAULT_MAGIC;
double AdaptiveSlippagePoints = 20;
int blockIndex = 0;
int atrHandle;

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
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA initialized successfully with Advanced Market Structure Analysis");
   
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
   DetectSupplyDemandZones();
   DetectFairValueGaps();
   DetectBreakerBlocks();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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
   double totalVolume = 0;
   for(int i=0; i<copied; i++) {
      totalVolume += rates[i].tick_volume;
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
//| Calculate position size based on risk percentage                  |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double stopLoss, double riskPercent=1.0)
{
   Print("[SIZE] Calculating position size for entry: ", entryPrice, " stop: ", stopLoss);
   
   // Get account balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Calculate risk amount
   double riskAmount = balance * (riskPercent / 100.0);
   
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
//| Execute a trade with enhanced error handling                      |
//+------------------------------------------------------------------+
bool ExecuteTradeWithSignal(int signal)
{
   Print("[TRADE] Processing signal: ", signal);
   
   // Validate signal
   if(signal == 0) {
      Print("[TRADE] Invalid signal (0)");
      return false;
   }
   
   // Get current market prices
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Determine entry price
   double entryPrice = (signal > 0) ? ask : bid;
   
   // Calculate optimal stop loss
   double stopLoss = CalculateOptimalStopLoss(signal, entryPrice);
   
   // Calculate take profit with RR ratio
   double riskDistance = MathAbs(entryPrice - stopLoss);
   double rrRatio = 1.5; // Risk:Reward ratio
   double takeProfit = (signal > 0) ? 
                      entryPrice + (riskDistance * rrRatio) : 
                      entryPrice - (riskDistance * rrRatio);
   
   // Normalize take profit
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   takeProfit = NormalizeDouble(takeProfit, digits);
   
   // Calculate position size based on risk
   double lotSize = CalculatePositionSize(entryPrice, stopLoss, 1.0); // 1% risk
   
   // Execute the trade with retry logic
   bool result = RetryTrade(signal, entryPrice, stopLoss, takeProfit, lotSize, 3);
   
   if(result) {
      Print("[TRADE] Successfully executed trade");
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
   int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   double atr = 0.001; // Default value
   
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0) {
      atr = atrBuffer[0];
   } else {
      Print("[FILTER] Failed to get ATR for spread check");
   }
   
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
   Print("[BLOCK] Starting advanced block detection for ", Symbol());
   
   // Reset old block data
   for(int i=0; i<ArraySize(recentBlocks); i++) {
      recentBlocks[i].valid = false;
   }
   
   // Get latest price data - more bars for better pattern recognition
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
   int atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
   ArraySetAsSeries(atrBuffer, true);
   bool atrValid = CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0;
   double atr = atrValid ? atrBuffer[0] : 0.001;
   
   // Calculate volume profile for filtering (more permissive for crypto)
   double totalVolume = 0;
   double maxVolume = 0;
   for(int i=0; i<MathMin(50, copied); i++) {
      totalVolume += rates[i].tick_volume;
      if(rates[i].tick_volume > maxVolume) maxVolume = rates[i].tick_volume;
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
         if(simpleReversal) score += 1.0;
         if(strongReversal) score += 0.5;
         if(volumeSpike) score += 1.5;
         if(isNearSwingLow) score += 2.0;
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
}

//+------------------------------------------------------------------+
//| Retry trade execution with error handling                         |
//+------------------------------------------------------------------+
bool RetryTrade(int signal, double price, double sl, double tp, double size, int maxRetries=3)
{
   CTrade tradeMgr;
   tradeMgr.SetDeviationInPoints(AdaptiveSlippagePoints);
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
   
   // Get ATR for size reference
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
         rates[i].tick_volume > volumeAverage * 1.2) {
         
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
   DetectSupplyDemandZones();
   DetectFairValueGaps();
   DetectBreakerBlocks();
   LogMarketPhase();
   
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
            ExecuteTradeWithSignal(1); // Buy signal
         }
      }
      
      // Process best sell block
      if(bestSellBlockIndex >= 0) {
         double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double blockPrice = recentBlocks[bestSellBlockIndex].price;
         
         // If price is near the block (within 5 points)
         if(MathAbs(currentPrice - blockPrice) < 5 * _Point) {
            Print("[TICK] Price near SELL block, executing trade");
            ExecuteTradeWithSignal(-1); // Sell signal
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
//| Manage existing trades                                           |
//+------------------------------------------------------------------+
void ManageOpenTrade()
{
   // Placeholder for trade management
}
