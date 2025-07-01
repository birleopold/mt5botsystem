//+------------------------------------------------------------------+
//|                      MeanReversionBBVolumeEA.mq5                 |
//|        BB+Volume Mean Reversion with Robust Risk Controls        |
//+------------------------------------------------------------------+
#property version   "1.11"
#property strict

//+------------------------------------------------------------------+
//| Best Practice Headers                                             |
//+------------------------------------------------------------------+
// 1. Always set both SL and TP on every trade.
// 2. Add robust trailing stop logic and alerts.
// 3. Add full error handling and logging for all trade actions.
// 4. Add risk management and position expiration logic.
// 5. Clean and robust structure.

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int    InpBBPeriod       = 20;        // Bollinger Bands period
input double InpBBDeviation    = 2.0;       // BB standard deviations
input int    InpVolumePeriod   = 20;        // Volume MA period
input int    InpATRPeriod      = 14;        // ATR period
input double InpATRMultiplier  = 2.0;       // ATR multiplier for stops
input uint   InpSlippage       = 3;         // Slippage in points
input uint   InpDuration       = 1440;      // Position duration in minutes
input double InpRiskPerTrade   = 1.0;       // Risk % per trade
input long   InpMagicNumber    = 234567;    // Unique EA identifier

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int    ExtBBHandle    = INVALID_HANDLE;
int    ExtATRHandle   = INVALID_HANDLE;
double ExtBBUpper[], ExtBBLower[], ExtATR[];
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Smart Money Concepts (SMC) Structures                            |
//+------------------------------------------------------------------+
// Structure for swing points
struct SwingPoint {
   datetime time;      // Time of the swing point
   double   price;     // Price level of the swing point
   bool     isHigh;    // true for swing high, false for swing low
   int      strength;  // Strength/significance of the swing (1-10)
};

// Structure for Break of Structure (BOS) events
struct BosEvent {
   datetime time;      // Time of the BOS event
   double   price;     // Price at which BOS occurred
   bool     isBullish; // true for bullish BOS, false for bearish
   double   strength;  // Strength/significance of the break (1-10)
   int      swingIdx;  // Index of the broken swing point
};

// Structure for Change of Character (CHoCH) events
struct ChochEvent {
   datetime time;      // Time of the CHoCH event
   double   price;     // Price at which CHoCH occurred
   bool     isBullish; // true for bullish CHoCH, false for bearish
   double   strength;  // Strength/significance of the change (1-10)
   int      bosIdx;    // Index of the related BOS event
};

// Arrays to store SMC events
SwingPoint swingPoints[100];  // Store last 100 swing points
BosEvent bosEvents[50];       // Store last 50 BOS events
ChochEvent chochEvents[50];   // Store last 50 CHoCH events

// Counters for the arrays
int swingPointCount = 0;
int bosEventCount = 0;
int chochEventCount = 0;

// Visual indicators for chart
bool showSmcVisualization = true;  // Option to show/hide SMC markings on chart

//+------------------------------------------------------------------+
//| Expert Initialization Function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set expert magic number
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   //--- Set deviation in points
   ExtTrade.SetDeviationInPoints(InpSlippage);
   //--- Set type of filling
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   //--- Initialize symbol info
   if(!ExtSymbolInfo.Name(_Symbol)) {
      Print("[ERROR] Symbol info init failed");
      return INIT_FAILED;
   }
   //--- Initialize indicators
   ExtBBHandle = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   ExtATRHandle = iATR(_Symbol, _Period, InpATRPeriod);
   //--- Check for invalid handles
   if(ExtBBHandle == INVALID_HANDLE || ExtATRHandle == INVALID_HANDLE) {
      Print("[ERROR] Indicator init failed");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(ExtBBHandle != INVALID_HANDLE) IndicatorRelease(ExtBBHandle);
   if(ExtATRHandle != INVALID_HANDLE) IndicatorRelease(ExtATRHandle);
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Static variables
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, _Period, 0);
   //--- Check for new bar
   if(lastBar == curBar) return;
   lastBar = curBar;
   
   //--- Refresh indicators
   if(!RefreshIndicators()) return;
   
   //--- Run SMC detection functions on new bar
   DetectSwingPoints();
   DetectBreakOfStructure();
   DetectChangeOfCharacter();
   
   //--- Check for existing positions
   if(ExtPositionInfo.Select(_Symbol)) {
      //--- Check for early exit based on SMC events
      CheckSmcExitConditions();
      //--- Manage trailing stop with SMC enhancements
      ManageTrailingStop();
      //--- Check position expiration
      CheckPositionExpiration();
      return;
   }
   
   //--- Get enhanced trade signal with SMC
   int signal = TradeSignal();
   
   //--- Execute trade
   if(signal == 1) {
      Print("[SMC] Enhanced Mean Reversion BUY signal");
      ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
   } else if(signal == -1) {
      Print("[SMC] Enhanced Mean Reversion SELL signal");
      ExecuteTrade(ORDER_TYPE_SELL, ExtATR[1]);
   }
}

//+------------------------------------------------------------------+
//| Refresh Indicators Function                                       |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   //--- Refresh Bollinger Bands
   if(CopyBuffer(ExtBBHandle, 0, 0, 2, ExtBBUpper) <= 0) { Print("[ERROR] BB Upper buffer"); return false; }
   if(CopyBuffer(ExtBBHandle, 1, 0, 2, ExtBBLower) <= 0) { Print("[ERROR] BB Lower buffer"); return false; }
   //--- Refresh ATR
   if(CopyBuffer(ExtATRHandle, 0, 0, 2, ExtATR) <= 0) { Print("[ERROR] ATR buffer"); return false; }
   return true;
}

//+------------------------------------------------------------------+
//| Trade Signal Function                                             |
//+------------------------------------------------------------------+
int TradeSignal()
{
   //--- Get basic price data
   double close = iClose(_Symbol, _Period, 1);
   datetime currentTime = iTime(_Symbol, _Period, 1);
   
   //--- Get basic mean reversion signal using Bollinger Bands
   int basicSignal = 0;
   if(close < ExtBBLower[1]) basicSignal = 1;  // Basic buy signal
   if(close > ExtBBUpper[1]) basicSignal = -1; // Basic sell signal
   
   //--- Check for recent SMC events that could enhance or invalidate the signal
   datetime recentTime = iTime(_Symbol, _Period, 5); // Look at events from last 5 bars
   bool recentBullishBOS = false;
   bool recentBearishBOS = false;
   bool recentBullishCHoCH = false;
   bool recentBearishCHoCH = false;
   double bullishStrength = 0;
   double bearishStrength = 0;
   
   // Find recent SMC events and calculate their combined strength
   for(int i=0; i<bosEventCount; i++) {
      if(bosEvents[i].time >= recentTime) {
         if(bosEvents[i].isBullish) {
            recentBullishBOS = true;
            bullishStrength += bosEvents[i].strength;
         } else {
            recentBearishBOS = true;
            bearishStrength += bosEvents[i].strength;
         }
      }
   }
   
   for(int i=0; i<chochEventCount; i++) {
      if(chochEvents[i].time >= recentTime) {
         if(chochEvents[i].isBullish) {
            recentBullishCHoCH = true;
            bullishStrength += chochEvents[i].strength * 1.5; // CHoCH gets higher weight
         } else {
            recentBearishCHoCH = true;
            bearishStrength += chochEvents[i].strength * 1.5; // CHoCH gets higher weight
         }
      }
   }
   
   //--- Enhanced Mean Reversion with SMC Logic
   
   // Case 1: Mean reversion BUY signal (price below lower BB) with bearish SMC
   // This is a good confirmation for a mean reversion long
   if(basicSignal == 1 && (recentBearishBOS || recentBearishCHoCH)) {
      // The market has moved down heavily and hit oversold conditions
      // This is perfect for a mean reversion BUY
      Print("[SMC] Strong BUY signal - Mean reversion with bearish SMC confirmation");
      return 1;
   }
   
   // Case 2: Mean reversion SELL signal (price above upper BB) with bullish SMC
   // This is a good confirmation for a mean reversion short
   if(basicSignal == -1 && (recentBullishBOS || recentBullishCHoCH)) {
      // The market has moved up heavily and hit overbought conditions
      // This is perfect for a mean reversion SELL
      Print("[SMC] Strong SELL signal - Mean reversion with bullish SMC confirmation");
      return -1;
   }
   
   // Case 3: Mean reversion signal but opposing SMC is very strong
   // This could indicate a strong trend that will overcome mean reversion
   if(basicSignal == 1 && bearishStrength > 8.0) {
      // Very strong bearish momentum might keep pushing price lower
      Print("[SMC] Rejecting mean reversion BUY due to extremely strong bearish momentum");
      return 0; // Reject the buy signal
   }
   
   if(basicSignal == -1 && bullishStrength > 8.0) {
      // Very strong bullish momentum might keep pushing price higher
      Print("[SMC] Rejecting mean reversion SELL due to extremely strong bullish momentum");
      return 0; // Reject the sell signal
   }
   
   // Case 4: Check for swing failure patterns that enhance mean reversion
   // A failed breakout that returns back inside the bands quickly is a strong signal
   double prevClose = iClose(_Symbol, _Period, 2);
   
   if(basicSignal == 1 && prevClose < ExtBBLower[1]) {
      // Price was below lower band and is still there - stronger mean reversion signal
      Print("[SMC] Enhanced BUY signal - Continued oversold condition");
      return 1;
   }
   
   if(basicSignal == -1 && prevClose > ExtBBUpper[1]) {
      // Price was above upper band and is still there - stronger mean reversion signal
      Print("[SMC] Enhanced SELL signal - Continued overbought condition");
      return -1;
   }
   
   // Return the basic signal if no special cases apply
   return basicSignal;
}

//+------------------------------------------------------------------+
//| Execute Trade Function                                            |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   //--- Refresh symbol info
   ExtSymbolInfo.RefreshRates();
   //--- Calculate price
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   //--- Calculate stop loss
   double sl = (type == ORDER_TYPE_BUY) ? price - InpATRMultiplier * atrValue : price + InpATRMultiplier * atrValue;
   //--- Calculate take profit
   double tp = (type == ORDER_TYPE_BUY) ? price + InpATRMultiplier * atrValue : price - InpATRMultiplier * atrValue;
   //--- Calculate lot size
   double lot = CalculateLot(atrValue);
   //--- Open position
   if(!ExtTrade.PositionOpen(_Symbol, type, lot, price, sl, tp, "MeanRev")) {
      Print("[ERROR] Trade open failed: ", ExtTrade.ResultRetcodeDescription());
      Alert("[ERROR] Trade open failed: ", ExtTrade.ResultRetcodeDescription());
   } else {
      Print("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
      Alert("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size Function                                       |
//+------------------------------------------------------------------+
double CalculateLot(double atrValue)
{
   //--- Calculate risk
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   //--- Calculate lot size
   double lot = risk / (atrValue * 10 * _Point);
   //--- Check lot size limits
   lot = MathMax(lot, ExtSymbolInfo.LotsMin());
   lot = MathMin(lot, ExtSymbolInfo.LotsMax());
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop Function                                     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   //--- Get ATR value
   double atr = ExtATR[1];
   //--- Refresh symbol info
   ExtSymbolInfo.RefreshRates();
   //--- Get current price
   double price = (ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
   //--- Get old stop loss
   double oldSL = ExtPositionInfo.StopLoss();
   
   //--- Adjust ATR multiplier based on SMC events
   double multiplier = InpATRMultiplier;
   
   // SMC-enhanced trailing logic for mean reversion strategy
   // For mean reversion, we tighten stops faster on reversion to mean
   datetime recentTime = iTime(_Symbol, _Period, 3); // Last 3 bars
   
   // For mean reversion long positions
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) {
      // Get current Bollinger Band positions
      double middleBand = (ExtBBUpper[1] + ExtBBLower[1]) / 2;
      
      // When price approaches middle band, tighten stop (mean reversion target)
      if(price > middleBand * 0.98) { // Within 2% of middle band
         multiplier = InpATRMultiplier * 0.7; // Tighten stop by 30%
         Print("[SMC] Tightening buy stop - Price approaching mean reversion target");
      }
      
      // If we have confirming SMC events for our long position, we can loosen stops
      for(int i=0; i<bosEventCount; i++) {
         if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
            // Bullish BOS suggests potential for extended move
            if(price < middleBand) { // Only if still below mean
               multiplier = InpATRMultiplier * 1.2; // Give more room
               Print("[SMC] Loosening buy stop due to bullish BOS before target reached");
            }
            break;
         }
      }
   }
   // For mean reversion short positions
   else if(ExtPositionInfo.PositionType() == POSITION_TYPE_SELL) {
      // Get current Bollinger Band positions
      double middleBand = (ExtBBUpper[1] + ExtBBLower[1]) / 2;
      
      // When price approaches middle band, tighten stop (mean reversion target)
      if(price < middleBand * 1.02) { // Within 2% of middle band
         multiplier = InpATRMultiplier * 0.7; // Tighten stop by 30%
         Print("[SMC] Tightening sell stop - Price approaching mean reversion target");
      }
      
      // If we have confirming SMC events for our short position, we can loosen stops
      for(int i=0; i<bosEventCount; i++) {
         if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
            // Bearish BOS suggests potential for extended move
            if(price > middleBand) { // Only if still above mean
               multiplier = InpATRMultiplier * 1.2; // Give more room
               Print("[SMC] Loosening sell stop due to bearish BOS before target reached");
            }
            break;
         }
      }
   }
   
   //--- Calculate new stop loss with adjusted multiplier
   double newSL;
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY)
      newSL = price - multiplier * atr;
   else
      newSL = price + multiplier * atr;
      
   //--- Check if new stop loss is better
   if((ExtPositionInfo.PositionType() == POSITION_TYPE_BUY && newSL > oldSL) || (ExtPositionInfo.PositionType() == POSITION_TYPE_SELL && newSL < oldSL)) {
      //--- Modify position
      if(!ExtTrade.PositionModify(_Symbol, newSL, ExtPositionInfo.TakeProfit())) {
         Print("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
         Alert("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
      } else {
         Print("[INFO] SMC trailing stop updated with multiplier: ", DoubleToString(multiplier, 2));
         Alert("[INFO] SMC trailing stop updated with multiplier: ", DoubleToString(multiplier, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Check for early exit based on SMC events - Mean Reversion        |
//+------------------------------------------------------------------+
void CheckSmcExitConditions()
{
   // Early exit logic specifically designed for mean reversion strategy
   bool shouldExit = false;
   string exitReason = "";
   datetime recentTime = iTime(_Symbol, _Period, 3); // Last 3 bars
   
   // Get current price and Bollinger Band values
   ExtSymbolInfo.RefreshRates();
   double price = (ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
   double middleBand = (ExtBBUpper[1] + ExtBBLower[1]) / 2;
   
   //--- For mean reversion BUY positions
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) {
      // Case 1: Exit when price hits target (middle band) with strong momentum
      if(price >= middleBand) {
         // Check if we have strong bearish SMC events at the target
         for(int i=0; i<bosEventCount; i++) {
            if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime && bosEvents[i].strength >= 6.0) {
               shouldExit = true;
               exitReason = "Target reached with bearish reversal signal";
               break;
            }
         }
         
         // Also check CHoCH events which are stronger
         if(!shouldExit) {
            for(int i=0; i<chochEventCount; i++) {
               if(!chochEvents[i].isBullish && chochEvents[i].time >= recentTime) {
                  shouldExit = true;
                  exitReason = "Target reached with bearish CHoCH signal";
                  break;
               }
            }
         }
      }
      
      // Case 2: Exit if we see extremely strong bearish SMC events anywhere
      if(!shouldExit) {
         for(int i=0; i<bosEventCount; i++) {
            if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime && bosEvents[i].strength >= 8.0) {
               shouldExit = true;
               exitReason = "Strong bearish BOS signal against position";
               break;
            }
         }
      }
      
      // Case 3: Failed mean reversion - price keeps making new lows
      double lowestLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, 5, 0));
      if(lowestLow < ExtBBLower[1] * 0.99) {
         // Price making new lows outside the band - mean reversion failing
         shouldExit = true;
         exitReason = "Failed mean reversion - new lows beyond band";
      }
   }
   //--- For mean reversion SELL positions
   else if(ExtPositionInfo.PositionType() == POSITION_TYPE_SELL) {
      // Case 1: Exit when price hits target (middle band) with strong momentum
      if(price <= middleBand) {
         // Check if we have strong bullish SMC events at the target
         for(int i=0; i<bosEventCount; i++) {
            if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime && bosEvents[i].strength >= 6.0) {
               shouldExit = true;
               exitReason = "Target reached with bullish reversal signal";
               break;
            }
         }
         
         // Also check CHoCH events which are stronger
         if(!shouldExit) {
            for(int i=0; i<chochEventCount; i++) {
               if(chochEvents[i].isBullish && chochEvents[i].time >= recentTime) {
                  shouldExit = true;
                  exitReason = "Target reached with bullish CHoCH signal";
                  break;
               }
            }
         }
      }
      
      // Case 2: Exit if we see extremely strong bullish SMC events anywhere
      if(!shouldExit) {
         for(int i=0; i<bosEventCount; i++) {
            if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime && bosEvents[i].strength >= 8.0) {
               shouldExit = true;
               exitReason = "Strong bullish BOS signal against position";
               break;
            }
         }
      }
      
      // Case 3: Failed mean reversion - price keeps making new highs
      double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, 5, 0));
      if(highestHigh > ExtBBUpper[1] * 1.01) {
         // Price making new highs outside the band - mean reversion failing
         shouldExit = true;
         exitReason = "Failed mean reversion - new highs beyond band";
      }
   }
   
   //--- Execute early exit if conditions met
   if(shouldExit) {
      double positionProfit = ExtPositionInfo.Profit();
      
      if(ExtTrade.PositionClose(_Symbol)) {
         Print("[SMC] Early exit triggered: ", exitReason, ". Profit: ", DoubleToString(positionProfit, 2));
         Alert("[SMC] Early exit triggered: ", exitReason, ". Profit: ", DoubleToString(positionProfit, 2));
      } else {
         Print("[ERROR] Failed to execute early exit despite signal");
         Alert("[ERROR] Failed to execute early exit despite signal");
      }
   }
}

//+------------------------------------------------------------------+
//| Check Position Expiration Function                                |
//+------------------------------------------------------------------+
void CheckPositionExpiration()
{
   //--- Check if position expiration is enabled
   if(InpDuration <= 0) return;
   //--- Get position time
   datetime positionTime = (datetime)ExtPositionInfo.Time();
   //--- Check if position has expired
   if(TimeCurrent() - positionTime >= InpDuration * 60) {
      //--- Close position
      if(ExtTrade.PositionClose(_Symbol)) {
         Print("[INFO] Position closed due to duration expiration");
         Alert("[INFO] Position closed due to duration expiration");
      } else {
         Print("[ERROR] Failed to close expired position");
         Alert("[ERROR] Failed to close expired position");
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Swing Points Function - SMC Enhancement                    |
//+------------------------------------------------------------------+
void DetectSwingPoints()
{
   // Look back several bars to detect swing points
   const int lookback = 20;
   
   // Arrays for price data
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   // Get high and low prices
   if(CopyHigh(_Symbol, _Period, 0, lookback + 4, high) <= 0) return;
   if(CopyLow(_Symbol, _Period, 0, lookback + 4, low) <= 0) return;
   
   // Detect swing high
   for(int i = 2; i < lookback - 2; i++) {
      // Swing high condition: middle bar higher than surrounding bars
      if(high[i] > high[i-1] && high[i] > high[i-2] && 
         high[i] > high[i+1] && high[i] > high[i+2]) {
         
         // Check if we already have this swing point (avoid duplicates)
         bool isDuplicate = false;
         for(int j = 0; j < swingPointCount; j++) {
            if(MathAbs(swingPoints[j].price - high[i]) < 10 * _Point) {
               isDuplicate = true;
               break;
            }
         }
         
         if(!isDuplicate) {
            // Make space in array if needed
            if(swingPointCount >= ArraySize(swingPoints)) {
               // Shift array to remove oldest
               for(int j = 0; j < ArraySize(swingPoints) - 1; j++) {
                  swingPoints[j] = swingPoints[j+1];
               }
               swingPointCount--;
            }
            
            // Calculate strength (1-10 scale) based on surrounding bars
            double leftDelta = high[i] - MathMax(high[i-1], high[i-2]);
            double rightDelta = high[i] - MathMax(high[i+1], high[i+2]);
            int strength = (int)MathMin(10, MathMax(1, (leftDelta + rightDelta) / (20 * _Point)));
            
            // Add new swing high
            swingPoints[swingPointCount].time = iTime(_Symbol, _Period, i);
            swingPoints[swingPointCount].price = high[i];
            swingPoints[swingPointCount].isHigh = true;
            swingPoints[swingPointCount].strength = strength;
            swingPointCount++;
            
            if(showSmcVisualization) {
               // Optional visualization code for chart
               string objName = "SwingHigh_" + IntegerToString((long)iTime(_Symbol, _Period, i));
               ObjectCreate(0, objName, OBJ_ARROW_DOWN, 0, iTime(_Symbol, _Period, i), high[i] + 15 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            }
         }
      }
      
      // Swing low condition: middle bar lower than surrounding bars
      if(low[i] < low[i-1] && low[i] < low[i-2] && 
         low[i] < low[i+1] && low[i] < low[i+2]) {
         
         // Check if we already have this swing point (avoid duplicates)
         bool isDuplicate = false;
         for(int j = 0; j < swingPointCount; j++) {
            if(MathAbs(swingPoints[j].price - low[i]) < 10 * _Point) {
               isDuplicate = true;
               break;
            }
         }
         
         if(!isDuplicate) {
            // Make space in array if needed
            if(swingPointCount >= ArraySize(swingPoints)) {
               // Shift array to remove oldest
               for(int j = 0; j < ArraySize(swingPoints) - 1; j++) {
                  swingPoints[j] = swingPoints[j+1];
               }
               swingPointCount--;
            }
            
            // Calculate strength (1-10 scale) based on surrounding bars
            double leftDelta = MathMin(low[i-1], low[i-2]) - low[i];
            double rightDelta = MathMin(low[i+1], low[i+2]) - low[i];
            int strength = (int)MathMin(10, MathMax(1, (leftDelta + rightDelta) / (20 * _Point)));
            
            // Add new swing low
            swingPoints[swingPointCount].time = iTime(_Symbol, _Period, i);
            swingPoints[swingPointCount].price = low[i];
            swingPoints[swingPointCount].isHigh = false;
            swingPoints[swingPointCount].strength = strength;
            swingPointCount++;
            
            if(showSmcVisualization) {
               // Optional visualization code for chart
               string objName = "SwingLow_" + IntegerToString((long)iTime(_Symbol, _Period, i));
               ObjectCreate(0, objName, OBJ_ARROW_UP, 0, iTime(_Symbol, _Period, i), low[i] - 15 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrGreen);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Break of Structure (BOS) Function - SMC Enhancement       |
//+------------------------------------------------------------------+
void DetectBreakOfStructure()
{
   // Need at least a few swing points to detect BOS
   if(swingPointCount < 3) return;
   
   // Get current price data
   double close = iClose(_Symbol, _Period, 1);
   datetime currentTime = iTime(_Symbol, _Period, 1);
   
   // Look for breaks of swing points
   for(int i = 0; i < swingPointCount; i++) {
      // Only consider recent swing points (within last 50 bars)
      if(currentTime - swingPoints[i].time > 50 * PeriodSeconds(_Period)) continue;
      
      // Check for bullish BOS (price breaks above a swing high)
      if(swingPoints[i].isHigh && close > swingPoints[i].price) {
         // Verify this is a new BOS
         bool isNewBOS = true;
         for(int j = 0; j < bosEventCount; j++) {
            if(bosEvents[j].swingIdx == i || MathAbs(bosEvents[j].price - swingPoints[i].price) < 5 * _Point) {
               isNewBOS = false;
               break;
            }
         }
         
         if(isNewBOS) {
            // Make space in array if needed
            if(bosEventCount >= ArraySize(bosEvents)) {
               // Shift array to remove oldest
               for(int j = 0; j < ArraySize(bosEvents) - 1; j++) {
                  bosEvents[j] = bosEvents[j+1];
               }
               bosEventCount--;
            }
            
            // Calculate break strength
            double breakDistance = close - swingPoints[i].price;
            double strength = MathMin(10.0, MathMax(1.0, breakDistance / (10 * _Point)));
            
            // Add the BOS event
            bosEvents[bosEventCount].time = currentTime;
            bosEvents[bosEventCount].price = close;
            bosEvents[bosEventCount].isBullish = true;
            bosEvents[bosEventCount].strength = strength;
            bosEvents[bosEventCount].swingIdx = i;
            bosEventCount++;
            
            Print("[SMC] Bullish BOS detected at price ", close, " strength: ", DoubleToString(strength, 1));
            
            if(showSmcVisualization) {
               // Visual marker for bullish BOS
               string objName = "BullBOS_" + IntegerToString((long)currentTime);
               ObjectCreate(0, objName, OBJ_ARROW, 0, currentTime, close - 25 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 233); // Up arrow
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrBlue);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            }
         }
      }
      
      // Check for bearish BOS (price breaks below a swing low)
      if(!swingPoints[i].isHigh && close < swingPoints[i].price) {
         // Verify this is a new BOS
         bool isNewBOS = true;
         for(int j = 0; j < bosEventCount; j++) {
            if(bosEvents[j].swingIdx == i || MathAbs(bosEvents[j].price - swingPoints[i].price) < 5 * _Point) {
               isNewBOS = false;
               break;
            }
         }
         
         if(isNewBOS) {
            // Make space in array if needed
            if(bosEventCount >= ArraySize(bosEvents)) {
               // Shift array to remove oldest
               for(int j = 0; j < ArraySize(bosEvents) - 1; j++) {
                  bosEvents[j] = bosEvents[j+1];
               }
               bosEventCount--;
            }
            
            // Calculate break strength
            double breakDistance = swingPoints[i].price - close;
            double strength = MathMin(10.0, MathMax(1.0, breakDistance / (10 * _Point)));
            
            // Add the BOS event
            bosEvents[bosEventCount].time = currentTime;
            bosEvents[bosEventCount].price = close;
            bosEvents[bosEventCount].isBullish = false;
            bosEvents[bosEventCount].strength = strength;
            bosEvents[bosEventCount].swingIdx = i;
            bosEventCount++;
            
            Print("[SMC] Bearish BOS detected at price ", close, " strength: ", DoubleToString(strength, 1));
            
            if(showSmcVisualization) {
               // Visual marker for bearish BOS
               string objName = "BearBOS_" + IntegerToString((long)currentTime);
               ObjectCreate(0, objName, OBJ_ARROW, 0, currentTime, close + 25 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 234); // Down arrow
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrMagenta);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Change of Character (CHoCH) Function - SMC Enhancement    |
//+------------------------------------------------------------------+
void DetectChangeOfCharacter()
{
   // Need BOS events to detect CHoCH
   if(bosEventCount < 1 || swingPointCount < 3) return;
   
   // Get current price information
   double close = iClose(_Symbol, _Period, 1);
   datetime currentTime = iTime(_Symbol, _Period, 1);
   
   // Check for CHoCH by analyzing recent BOS events
   for(int i = 0; i < bosEventCount; i++) {
      // Only consider recent BOS events (within last 30 bars)
      if(currentTime - bosEvents[i].time > 30 * PeriodSeconds(_Period)) continue;
      
      // Check for bullish CHoCH (price makes higher low after bullish BOS)
      if(bosEvents[i].isBullish) {
         // Find a recent swing low that occurred after this BOS
         for(int j = 0; j < swingPointCount; j++) {
            if(!swingPoints[j].isHigh && // Must be a swing low
               swingPoints[j].time > bosEvents[i].time && // Must be after BOS
               close > swingPoints[j].price && // Current price must be above this swing low
               swingPoints[j].price > swingPoints[bosEvents[i].swingIdx].price) { // Must be higher than broken level
               
               // Verify this is a new CHoCH
               bool isNewCHoCH = true;
               for(int k = 0; k < chochEventCount; k++) {
                  if(chochEvents[k].bosIdx == i) {
                     isNewCHoCH = false;
                     break;
                  }
               }
               
               if(isNewCHoCH) {
                  // Make space in array if needed
                  if(chochEventCount >= ArraySize(chochEvents)) {
                     // Shift array to remove oldest
                     for(int k = 0; k < ArraySize(chochEvents) - 1; k++) {
                        chochEvents[k] = chochEvents[k+1];
                     }
                     chochEventCount--;
                  }
                  
                  // Calculate CHoCH strength based on the BOS strength and price movement
                  double priceRange = close - swingPoints[j].price;
                  double strength = MathMin(10.0, bosEvents[i].strength * 0.8 + priceRange / (15 * _Point));
                  
                  // Add the CHoCH event
                  chochEvents[chochEventCount].time = currentTime;
                  chochEvents[chochEventCount].price = close;
                  chochEvents[chochEventCount].isBullish = true;
                  chochEvents[chochEventCount].strength = strength;
                  chochEvents[chochEventCount].bosIdx = i;
                  chochEventCount++;
                  
                  Print("[SMC] Bullish CHoCH detected at price ", close, " strength: ", DoubleToString(strength, 1));
                  
                  if(showSmcVisualization) {
                     // Visual marker for bullish CHoCH
                     string objName = "BullCHoCH_" + IntegerToString((long)currentTime);
                     ObjectCreate(0, objName, OBJ_TEXT, 0, currentTime, close - 35 * _Point);
                     ObjectSetString(0, objName, OBJPROP_TEXT, "CHoCH");
                     ObjectSetInteger(0, objName, OBJPROP_COLOR, clrBlue);
                     ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
                  }
                  break;
               }
            }
         }
      }
      
      // Check for bearish CHoCH (price makes lower high after bearish BOS)
      if(!bosEvents[i].isBullish) {
         // Find a recent swing high that occurred after this BOS
         for(int j = 0; j < swingPointCount; j++) {
            if(swingPoints[j].isHigh && // Must be a swing high
               swingPoints[j].time > bosEvents[i].time && // Must be after BOS
               close < swingPoints[j].price && // Current price must be below this swing high
               swingPoints[j].price < swingPoints[bosEvents[i].swingIdx].price) { // Must be lower than broken level
               
               // Verify this is a new CHoCH
               bool isNewCHoCH = true;
               for(int k = 0; k < chochEventCount; k++) {
                  if(chochEvents[k].bosIdx == i) {
                     isNewCHoCH = false;
                     break;
                  }
               }
               
               if(isNewCHoCH) {
                  // Make space in array if needed
                  if(chochEventCount >= ArraySize(chochEvents)) {
                     // Shift array to remove oldest
                     for(int k = 0; k < ArraySize(chochEvents) - 1; k++) {
                        chochEvents[k] = chochEvents[k+1];
                     }
                     chochEventCount--;
                  }
                  
                  // Calculate CHoCH strength based on the BOS strength and price movement
                  double priceRange = swingPoints[j].price - close;
                  double strength = MathMin(10.0, bosEvents[i].strength * 0.8 + priceRange / (15 * _Point));
                  
                  // Add the CHoCH event
                  chochEvents[chochEventCount].time = currentTime;
                  chochEvents[chochEventCount].price = close;
                  chochEvents[chochEventCount].isBullish = false;
                  chochEvents[chochEventCount].strength = strength;
                  chochEvents[chochEventCount].bosIdx = i;
                  chochEventCount++;
                  
                  Print("[SMC] Bearish CHoCH detected at price ", close, " strength: ", DoubleToString(strength, 1));
                  
                  if(showSmcVisualization) {
                     // Visual marker for bearish CHoCH
                     string objName = "BearCHoCH_" + IntegerToString((long)currentTime);
                     ObjectCreate(0, objName, OBJ_TEXT, 0, currentTime, close + 35 * _Point);
                     ObjectSetString(0, objName, OBJPROP_TEXT, "CHoCH");
                     ObjectSetInteger(0, objName, OBJPROP_COLOR, clrMagenta);
                     ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
                  }
                  break;
               }
            }
         }
      }
   }
}