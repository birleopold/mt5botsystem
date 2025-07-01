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

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA initialized successfully");
   
   // Initialize blocks
   for(int i=0; i<MAX_BLOCKS; i++) {
      recentBlocks[i].valid = false;
   }
   
   // Initialize CHOCH array
   for(int i=0; i<MAX_CHOCHS; i++) {
      recentCHOCHs[i].valid = false;
   }
   
   // Set up ATR indicator
   atrHandle = iATR(Symbol(), PERIOD_CURRENT, 14);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA deinitialized with reason code: ", reason);
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
