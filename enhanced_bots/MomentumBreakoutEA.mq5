//+------------------------------------------------------------------+
//|                   MomentumBreakoutEA.mq5                        |
//|   Donchian Channel Breakout with Robust Risk Management         |
//+------------------------------------------------------------------+
#property version   "1.11"
#property strict

//+------------------------------------------------------------------+
//| Best Practice Headers                                             |
//+------------------------------------------------------------------+
// 1. Always use meaningful variable names
// 2. Use comments to explain complex logic
// 3. Use functions to organize code
// 4. Use error handling and logging
// 5. Use risk management and position expiration logic

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int    InpDonchianPeriod  = 20;       // Donchian Channel period
input int    InpATRPeriod       = 14;       // ATR period
input double InpATRMultiplier   = 2.0;      // ATR multiplier for stops
input uint   InpSlippage        = 3;        // Slippage in points
input uint   InpDuration        = 1440;     // Position duration in minutes
input double InpRiskPerTrade    = 1.0;      // Risk % per trade
input long   InpMagicNumber     = 345678;   // Unique EA identifier

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int    ExtDonchianUpperHandle = INVALID_HANDLE;
int    ExtDonchianLowerHandle = INVALID_HANDLE;
int    ExtATRHandle           = INVALID_HANDLE;
double ExtDonchianUpper[], ExtDonchianLower[], ExtATR[];
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Smart Money Concepts (SMC) Structures                            |
//+------------------------------------------------------------------+

// Structure for swing points 
struct SwingPoint {
   datetime time;       // Time of the swing point
   double   price;      // Price level of the swing point
   bool     isHigh;     // true for swing high, false for swing low
   int      strength;   // Strength of the swing point (1-10)
};

// Structure for Break of Structure (BOS) events
struct BOSEvent {
   datetime time;       // Time when BOS occurred
   double   price;      // Price level where BOS occurred
   bool     isBullish;  // true for bullish BOS, false for bearish BOS
   double   strength;   // Strength/significance of the BOS (1.0-10.0)
   int      swingIndex; // Index of the swing point that was broken
};

// Structure for Change of Character (CHoCH) events
struct CHoCHEvent {
   datetime time;       // Time when CHoCH occurred
   double   price;      // Price level where CHoCH occurred
   bool     isBullish;  // true for bullish CHoCH, false for bearish CHoCH
   double   strength;   // Strength/significance of the CHoCH (1.0-10.0)
   int      bosIndex;   // Index of the related BOS event
};

// Arrays to store SMC events
SwingPoint swingPoints[100];   // Store up to 100 swing points
BOSEvent   bosEvents[50];      // Store up to 50 BOS events
CHoCHEvent chochEvents[50];    // Store up to 50 CHoCH events

// Counters for each type of event
int swingPointCount = 0;       // Count of swing points
int bosEventCount = 0;         // Count of BOS events
int chochEventCount = 0;       // Count of CHoCH events

//+------------------------------------------------------------------+
//| Expert Initialization Function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set expert magic number
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   // Set deviation in points
   ExtTrade.SetDeviationInPoints(InpSlippage);
   // Set type filling
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Initialize symbol info
   if(!ExtSymbolInfo.Name(_Symbol)) {
      Print("[ERROR] Symbol info init failed");
      return INIT_FAILED;
   }
   
   // Initialize indicators
   ExtDonchianUpperHandle = iHighest(_Symbol, _Period, MODE_HIGH, InpDonchianPeriod);
   ExtDonchianLowerHandle = iLowest(_Symbol, _Period, MODE_LOW, InpDonchianPeriod);
   ExtATRHandle = iATR(_Symbol, _Period, InpATRPeriod);
   
   // Check if indicators are initialized
   if(ExtDonchianUpperHandle == INVALID_HANDLE || ExtDonchianLowerHandle == INVALID_HANDLE || ExtATRHandle == INVALID_HANDLE) {
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
   // Release indicator handles
   if(ExtDonchianUpperHandle != INVALID_HANDLE) IndicatorRelease(ExtDonchianUpperHandle);
   if(ExtDonchianLowerHandle != INVALID_HANDLE) IndicatorRelease(ExtDonchianLowerHandle);
   if(ExtATRHandle != INVALID_HANDLE) IndicatorRelease(ExtATRHandle);
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(lastBar == curBar) return;
   lastBar = curBar;
   
   // Refresh indicators
   if(!RefreshIndicators()) return;
   
   // Run SMC detection functions on new bar
   DetectSwingPoints();
   DetectBreakOfStructure();
   DetectChangeOfCharacter();
   
   // Check if position exists
   if(ExtPositionInfo.Select(_Symbol)) {
      // Manage trailing stop with SMC enhancement
      ManageTrailingStop();
      // Check for early exit based on SMC
      CheckSmcExitConditions();
      // Check position expiration
      CheckPositionExpiration();
      return;
   }
   
   // Get enhanced trade signal with SMC
   int signal = TradeSignal();
   if(signal == 1) {
      // Execute buy trade
      ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
   } else if(signal == -1) {
      // Execute sell trade
      ExecuteTrade(ORDER_TYPE_SELL, ExtATR[1]);
   }
}

//+------------------------------------------------------------------+
//| Refresh Indicators Function                                       |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   // Copy high and low values
   if(CopyHigh(_Symbol, _Period, 1, InpDonchianPeriod, ExtDonchianUpper) <= 0) { Print("[ERROR] Donchian Upper buffer"); return false; }
   if(CopyLow(_Symbol, _Period, 1, InpDonchianPeriod, ExtDonchianLower) <= 0) { Print("[ERROR] Donchian Lower buffer"); return false; }
   
   // Copy ATR values
   if(CopyBuffer(ExtATRHandle, 0, 0, 2, ExtATR) <= 0) { Print("[ERROR] ATR buffer"); return false; }
   
   return true;
}

//+------------------------------------------------------------------+
//| Trade Signal Function                                             |
//+------------------------------------------------------------------+
int TradeSignal()
{
   // Get close price
   double close = iClose(_Symbol, _Period, 1);
   
   // Check for recent SMC events
   datetime recentTime = iTime(_Symbol, _Period, 5); // Events in the last 5 bars
   bool recentBullishBOS = false;
   bool recentBearishBOS = false;
   bool recentBullishCHoCH = false;
   bool recentBearishCHoCH = false;
   double bullishStrength = 0;
   double bearishStrength = 0;
   
   // Analyze recent BOS events
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
   
   // Analyze recent CHoCH events (these are more significant)
   for(int i=0; i<chochEventCount; i++) {
      if(chochEvents[i].time >= recentTime) {
         if(chochEvents[i].isBullish) {
            recentBullishCHoCH = true;
            bullishStrength += chochEvents[i].strength * 1.5; // CHoCH gets 1.5x weight
         } else {
            recentBearishCHoCH = true;
            bearishStrength += chochEvents[i].strength * 1.5; // CHoCH gets 1.5x weight
         }
      }
   }
   
   // Base signals from Donchian Channel breakout
   int donchianSignal = 0;
   if(close > ExtDonchianUpper[0]) donchianSignal = 1;
   if(close < ExtDonchianLower[0]) donchianSignal = -1;
   
   // Enhanced signal incorporating SMC events
   
   // Case 1: Strong buy signal - Donchian breakout with SMC confirmation
   if(donchianSignal == 1 && (recentBullishBOS || recentBullishCHoCH)) {
      Print("[SMC] Enhanced BUY signal - Donchian breakout with SMC confirmation");
      Alert("[SMC] Enhanced BUY signal - Donchian breakout with SMC confirmation");
      return 1;
   }
   
   // Case 2: Strong sell signal - Donchian breakout with SMC confirmation
   if(donchianSignal == -1 && (recentBearishBOS || recentBearishCHoCH)) {
      Print("[SMC] Enhanced SELL signal - Donchian breakout with SMC confirmation");
      Alert("[SMC] Enhanced SELL signal - Donchian breakout with SMC confirmation");
      return -1;
   }
   
   // Case 3: Conflicting signals - Donchian breakout vs SMC
   if(donchianSignal == 1 && (recentBearishBOS || recentBearishCHoCH) && bearishStrength > 5.0) {
      Print("[SMC] Donchian BUY signal rejected due to strong bearish SMC events");
      Alert("[SMC] Donchian BUY signal rejected due to strong bearish SMC events");
      return 0; // Reject the trade
   }
   
   if(donchianSignal == -1 && (recentBullishBOS || recentBullishCHoCH) && bullishStrength > 5.0) {
      Print("[SMC] Donchian SELL signal rejected due to strong bullish SMC events");
      Alert("[SMC] Donchian SELL signal rejected due to strong bullish SMC events");
      return 0; // Reject the trade
   }
   
   // Case 4: SMC-only signal (when very strong) without Donchian breakout
   if(donchianSignal == 0 && recentBullishCHoCH && bullishStrength > 7.0) {
      Print("[SMC] SMC-only BUY signal - Strong bullish CHoCH");
      Alert("[SMC] SMC-only BUY signal - Strong bullish CHoCH");
      return 1;
   }
   
   if(donchianSignal == 0 && recentBearishCHoCH && bearishStrength > 7.0) {
      Print("[SMC] SMC-only SELL signal - Strong bearish CHoCH");
      Alert("[SMC] SMC-only SELL signal - Strong bearish CHoCH");
      return -1;
   }
   
   // Case 5: Standard Donchian signal without SMC confirmation/rejection
   return donchianSignal;
}

//+------------------------------------------------------------------+
//| Execute Trade Function                                            |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   // Refresh symbol info
   ExtSymbolInfo.RefreshRates();
   
   // Calculate price and stop loss
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? price - InpATRMultiplier * atrValue : price + InpATRMultiplier * atrValue;
   double tp = (type == ORDER_TYPE_BUY) ? price + InpATRMultiplier * atrValue : price - InpATRMultiplier * atrValue;
   
   // Calculate lot size
   double lot = CalculateLot(atrValue);
   
   // Open position
   if(!ExtTrade.PositionOpen(_Symbol, type, lot, price, sl, tp, "Breakout")) {
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
   // Calculate risk
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   
   // Calculate lot size
   double lot = risk / (atrValue * 10 * _Point);
   
   // Limit lot size
   lot = MathMax(lot, ExtSymbolInfo.LotsMin());
   lot = MathMin(lot, ExtSymbolInfo.LotsMax());
   
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop Function                                    |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   // Get ATR value
   double atr = ExtATR[1];
   
   // Refresh symbol info
   ExtSymbolInfo.RefreshRates();
   
   // Get current price
   double price = (ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
   
   // Get old stop loss
   double oldSL = ExtPositionInfo.StopLoss();
   
   // Adjust ATR multiplier based on SMC events
   double multiplier = InpATRMultiplier;
   
   // Check for confirming SMC events to tighten trailing stop
   datetime recentTime = iTime(_Symbol, _Period, 3);
   bool hasConfirmingSignal = false;
   
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) {
      // For buy positions, look for bullish SMC events
      for(int i=0; i<bosEventCount; i++) {
         if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
            hasConfirmingSignal = true;
            multiplier = InpATRMultiplier * 0.8; // Tighter trailing (80% of original)
            break;
         }
      }
      
      if(!hasConfirmingSignal) {
         for(int i=0; i<chochEventCount; i++) {
            if(chochEvents[i].isBullish && chochEvents[i].time >= recentTime) {
               hasConfirmingSignal = true;
               multiplier = InpATRMultiplier * 0.7; // Even tighter trailing (70% of original)
               break;
            }
         }
      }
   }
   else if(ExtPositionInfo.PositionType() == POSITION_TYPE_SELL) {
      // For sell positions, look for bearish SMC events
      for(int i=0; i<bosEventCount; i++) {
         if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
            hasConfirmingSignal = true;
            multiplier = InpATRMultiplier * 0.8; // Tighter trailing (80% of original)
            break;
         }
      }
      
      if(!hasConfirmingSignal) {
         for(int i=0; i<chochEventCount; i++) {
            if(!chochEvents[i].isBullish && chochEvents[i].time >= recentTime) {
               hasConfirmingSignal = true;
               multiplier = InpATRMultiplier * 0.7; // Even tighter trailing (70% of original)
               break;
            }
         }
      }
   }
   
   // Calculate new stop loss using adjusted multiplier
   double newSL;
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY)
      newSL = price - multiplier * atr;
   else
      newSL = price + multiplier * atr;
   
   // Check if new stop loss is better
   if((ExtPositionInfo.PositionType() == POSITION_TYPE_BUY && newSL > oldSL) || (ExtPositionInfo.PositionType() == POSITION_TYPE_SELL && newSL < oldSL)) {
      // Modify position
      if(!ExtTrade.PositionModify(_Symbol, newSL, ExtPositionInfo.TakeProfit())) {
         Print("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
         Alert("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
      } else {
         Print("[INFO] Trailing stop updated using multiplier: ", DoubleToString(multiplier, 2));
         Alert("[INFO] Trailing stop updated using multiplier: ", DoubleToString(multiplier, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Check for early exit based on SMC events                         |
//+------------------------------------------------------------------+
void CheckSmcExitConditions()
{
   // Check for opposing SMC events that might warrant an early exit
   bool hasOpposingSignal = false;
   datetime recentTime = iTime(_Symbol, _Period, 3); // Look for very recent opposing signals
   string exitReason = "";
   
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) {
      // Check for bearish signals that oppose our long position
      for(int i=0; i<bosEventCount; i++) {
         if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime && bosEvents[i].strength >= 5.0) {
            hasOpposingSignal = true;
            exitReason = "Strong bearish BOS";
            break;
         }
      }
      
      if(!hasOpposingSignal) {
         for(int i=0; i<chochEventCount; i++) {
            if(!chochEvents[i].isBullish && chochEvents[i].time >= recentTime && chochEvents[i].strength >= 5.0) {
               hasOpposingSignal = true;
               exitReason = "Strong bearish CHoCH";
               break;
            }
         }
      }
   }
   else if(ExtPositionInfo.PositionType() == POSITION_TYPE_SELL) {
      // Check for bullish signals that oppose our short position
      for(int i=0; i<bosEventCount; i++) {
         if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime && bosEvents[i].strength >= 5.0) {
            hasOpposingSignal = true;
            exitReason = "Strong bullish BOS";
            break;
         }
      }
      
      if(!hasOpposingSignal) {
         for(int i=0; i<chochEventCount; i++) {
            if(chochEvents[i].isBullish && chochEvents[i].time >= recentTime && chochEvents[i].strength >= 5.0) {
               hasOpposingSignal = true;
               exitReason = "Strong bullish CHoCH";
               break;
            }
         }
      }
   }
   
   // Close position early if strong opposing signal detected
   if(hasOpposingSignal) {
      // Get position profit before closing
      double positionProfit = ExtPositionInfo.Profit();
      
      if(ExtTrade.PositionClose(_Symbol)) {
         Print("[SMC] Position closed early due to ", exitReason, ". Profit: ", DoubleToString(positionProfit, 2));
         Alert("[SMC] Position closed early due to ", exitReason, ". Profit: ", DoubleToString(positionProfit, 2));
      } else {
         Print("[ERROR] Failed to close position despite SMC exit signal");
         Alert("[ERROR] Failed to close position despite SMC exit signal");
      }
   }
}

//+------------------------------------------------------------------+
//| Check Position Expiration Function                                |
//+------------------------------------------------------------------+
void CheckPositionExpiration()
{
   // Check if position duration is set
   if(InpDuration <= 0) return;
   
   // Get position time
   datetime positionTime = (datetime)ExtPositionInfo.Time();
   
   // Check if position is expired
   if(TimeCurrent() - positionTime >= InpDuration * 60) {
      // Close position
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
//| Smart Money Concepts (SMC) Functions                             |
//+------------------------------------------------------------------+

//--- Function to detect swing points in the price action
void DetectSwingPoints(int lookbackBars = 20)
{
   //--- Get highs and lows
   double highs[], lows[];
   ArrayResize(highs, lookbackBars);
   ArrayResize(lows, lookbackBars);
   
   for(int i=0; i<lookbackBars; i++) {
      highs[i] = iHigh(_Symbol, _Period, i);
      lows[i] = iLow(_Symbol, _Period, i);
   }
   
   //--- Detect swing highs
   for(int i=3; i<lookbackBars-3; i++) {
      //--- Swing high detection
      if(highs[i] > highs[i-1] && highs[i] > highs[i-2] && highs[i] > highs[i+1] && highs[i] > highs[i+2]) {
         //--- Calculate strength based on surrounding bars
         int strength = 1;
         if(highs[i] > highs[i-3]) strength++;
         if(highs[i] > highs[i+3]) strength++;
         
         //--- Add a swing high if we have room in the array
         if(swingPointCount < 100) {
            swingPoints[swingPointCount].time = iTime(_Symbol, _Period, i);
            swingPoints[swingPointCount].price = highs[i];
            swingPoints[swingPointCount].isHigh = true;
            swingPoints[swingPointCount].strength = strength;
            swingPointCount++;
            
            Print("[SMC] New swing high detected at price ", DoubleToString(highs[i], 5));
         }
      }
      
      //--- Swing low detection
      if(lows[i] < lows[i-1] && lows[i] < lows[i-2] && lows[i] < lows[i+1] && lows[i] < lows[i+2]) {
         //--- Calculate strength based on surrounding bars
         int strength = 1;
         if(lows[i] < lows[i-3]) strength++;
         if(lows[i] < lows[i+3]) strength++;
         
         //--- Add a swing low if we have room in the array
         if(swingPointCount < 100) {
            swingPoints[swingPointCount].time = iTime(_Symbol, _Period, i);
            swingPoints[swingPointCount].price = lows[i];
            swingPoints[swingPointCount].isHigh = false;
            swingPoints[swingPointCount].strength = strength;
            swingPointCount++;
            
            Print("[SMC] New swing low detected at price ", DoubleToString(lows[i], 5));
         }
      }
   }
   
   //--- Limit the number of swing points by removing older ones if necessary
   if(swingPointCount > 50) {
      for(int i=0; i<swingPointCount-50; i++) {
         for(int j=0; j<swingPointCount-1; j++) {
            swingPoints[j] = swingPoints[j+1];
         }
         swingPointCount--;
      }
   }
}

//--- Function to detect Break of Structure (BOS) events
void DetectBreakOfStructure()
{
   //--- Need at least a few swing points to detect BOS
   if(swingPointCount < 5) return;
   
   //--- Get current price
   double currentPrice = iClose(_Symbol, _Period, 0);
   datetime currentTime = iTime(_Symbol, _Period, 0);
   
   //--- Look for price breaking above significant swing highs (bullish BOS)
   for(int i=0; i<swingPointCount; i++) {
      if(swingPoints[i].isHigh) {
         if(currentPrice > swingPoints[i].price) {
            //--- Check if this is a new BOS (not already recorded)
            bool isNewBOS = true;
            for(int j=0; j<bosEventCount; j++) {
               if(bosEvents[j].swingIndex == i) {
                  isNewBOS = false;
                  break;
               }
            }
            
            if(isNewBOS && bosEventCount < 50) {
               double bosStrength = swingPoints[i].strength * 1.0;
               
               //--- Calculate additional strength based on volume
               double currentVolume = iVolume(_Symbol, _Period, 0);
               double avgVolume = 0;
               for(int v=1; v<=10; v++) avgVolume += iVolume(_Symbol, _Period, v);
               avgVolume /= 10;
               
               if(currentVolume > avgVolume * 1.5) bosStrength *= 1.5;
               
               //--- Record the BOS event
               bosEvents[bosEventCount].time = currentTime;
               bosEvents[bosEventCount].price = currentPrice;
               bosEvents[bosEventCount].isBullish = true;
               bosEvents[bosEventCount].strength = bosStrength;
               bosEvents[bosEventCount].swingIndex = i;
               bosEventCount++;
               
               Print("[SMC] Bullish BOS detected at price ", DoubleToString(currentPrice, 5), ", strength: ", DoubleToString(bosStrength, 1));
            }
         }
      }
   }
   
   //--- Look for price breaking below significant swing lows (bearish BOS)
   for(int i=0; i<swingPointCount; i++) {
      if(!swingPoints[i].isHigh) {
         if(currentPrice < swingPoints[i].price) {
            //--- Check if this is a new BOS (not already recorded)
            bool isNewBOS = true;
            for(int j=0; j<bosEventCount; j++) {
               if(bosEvents[j].swingIndex == i) {
                  isNewBOS = false;
                  break;
               }
            }
            
            if(isNewBOS && bosEventCount < 50) {
               double bosStrength = swingPoints[i].strength * 1.0;
               
               //--- Calculate additional strength based on volume
               double currentVolume = iVolume(_Symbol, _Period, 0);
               double avgVolume = 0;
               for(int v=1; v<=10; v++) avgVolume += iVolume(_Symbol, _Period, v);
               avgVolume /= 10;
               
               if(currentVolume > avgVolume * 1.5) bosStrength *= 1.5;
               
               //--- Record the BOS event
               bosEvents[bosEventCount].time = currentTime;
               bosEvents[bosEventCount].price = currentPrice;
               bosEvents[bosEventCount].isBullish = false;
               bosEvents[bosEventCount].strength = bosStrength;
               bosEvents[bosEventCount].swingIndex = i;
               bosEventCount++;
               
               Print("[SMC] Bearish BOS detected at price ", DoubleToString(currentPrice, 5), ", strength: ", DoubleToString(bosStrength, 1));
            }
         }
      }
   }
}

//--- Function to detect Change of Character (CHoCH) events
void DetectChangeOfCharacter()
{
   //--- Need BOS events to detect CHoCH
   if(bosEventCount < 3) return;
   
   double currentPrice = iClose(_Symbol, _Period, 0);
   datetime currentTime = iTime(_Symbol, _Period, 0);
   
   //--- For each BOS event, check for a change of character
   for(int i=0; i<bosEventCount; i++) {
      //--- For bullish BOS, look for price coming back to retest and then continuing higher
      if(bosEvents[i].isBullish) {
         //--- Check if price retraced back to BOS level and then moved higher again
         double bosLevel = bosEvents[i].price;
         bool wasBelow = false;
         
         //--- Check if price has retested the BOS level
         for(int j=5; j>0; j--) {
            if(iLow(_Symbol, _Period, j) <= bosLevel) {
               wasBelow = true;
               break;
            }
         }
         
         //--- If it retested and is now moving up, it's a CHoCH
         if(wasBelow && currentPrice > bosLevel) {
            //--- Check if this CHoCH is already recorded
            bool isNewCHoCH = true;
            for(int j=0; j<chochEventCount; j++) {
               if(chochEvents[j].bosIndex == i) {
                  isNewCHoCH = false;
                  break;
               }
            }
            
            if(isNewCHoCH && chochEventCount < 50) {
               double chochStrength = bosEvents[i].strength * 1.2;
               
               //--- Record the CHoCH event
               chochEvents[chochEventCount].time = currentTime;
               chochEvents[chochEventCount].price = currentPrice;
               chochEvents[chochEventCount].isBullish = true;
               chochEvents[chochEventCount].strength = chochStrength;
               chochEvents[chochEventCount].bosIndex = i;
               chochEventCount++;
               
               Print("[SMC] Bullish CHoCH detected at price ", DoubleToString(currentPrice, 5), ", strength: ", DoubleToString(chochStrength, 1));
            }
         }
      }
      //--- For bearish BOS, look for price coming back to retest and then continuing lower
      else {
         //--- Check if price retraced back to BOS level and then moved lower again
         double bosLevel = bosEvents[i].price;
         bool wasAbove = false;
         
         //--- Check if price has retested the BOS level
         for(int j=5; j>0; j--) {
            if(iHigh(_Symbol, _Period, j) >= bosLevel) {
               wasAbove = true;
               break;
            }
         }
         
         //--- If it retested and is now moving down, it's a CHoCH
         if(wasAbove && currentPrice < bosLevel) {
            //--- Check if this CHoCH is already recorded
            bool isNewCHoCH = true;
            for(int j=0; j<chochEventCount; j++) {
               if(chochEvents[j].bosIndex == i) {
                  isNewCHoCH = false;
                  break;
               }
            }
            
            if(isNewCHoCH && chochEventCount < 50) {
               double chochStrength = bosEvents[i].strength * 1.2;
               
               //--- Record the CHoCH event
               chochEvents[chochEventCount].time = currentTime;
               chochEvents[chochEventCount].price = currentPrice;
               chochEvents[chochEventCount].isBullish = false;
               chochEvents[chochEventCount].strength = chochStrength;
               chochEvents[chochEventCount].bosIndex = i;
               chochEventCount++;
               
               Print("[SMC] Bearish CHoCH detected at price ", DoubleToString(currentPrice, 5), ", strength: ", DoubleToString(chochStrength, 1));
            }
         }
      }
   }
}