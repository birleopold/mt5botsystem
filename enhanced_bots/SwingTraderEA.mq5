//+------------------------------------------------------------------+
//|                     SwingTraderEA.mq5                            |
//|            Swing Trading with Robust Risk Management             |
//+------------------------------------------------------------------+
#property version   "1.11"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input int    InpTrendMAPeriod   = 50;     // Trend MA period
input int    InpSignalMAPeriod  = 14;     // Signal MA period
input int    InpATRPeriod       = 14;     // ATR period
input double InpATRMultiplier   = 2.0;    // ATR multiplier for SL
input double InpTPMultiplier    = 3.0;    // ATR multiplier for TP
input double InpRiskPerTrade    = 1.0;    // Risk % per trade
input uint   InpSlippage        = 5;      // Slippage
input uint   InpDuration        = 1440;   // Max trade duration (min)
input long   InpMagicNumber     = 900001; // Magic number

int    ExtTrendMAHandle = INVALID_HANDLE;
int    ExtSignalMAHandle = INVALID_HANDLE;
int    ExtATRHandle = INVALID_HANDLE;
double ExtTrendMA[], ExtSignalMA[], ExtATR[];
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

int OnInit()
{
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippage);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   if(!ExtSymbolInfo.Name(_Symbol)) {
      Print("[ERROR] Symbol info init failed");
      return INIT_FAILED;
   }
   ExtTrendMAHandle = iMA(_Symbol, _Period, InpTrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ExtSignalMAHandle = iMA(_Symbol, _Period, InpSignalMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ExtATRHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(ExtTrendMAHandle == INVALID_HANDLE || ExtSignalMAHandle == INVALID_HANDLE || ExtATRHandle == INVALID_HANDLE) {
      Print("[ERROR] Indicator init failed");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(ExtTrendMAHandle != INVALID_HANDLE) IndicatorRelease(ExtTrendMAHandle);
   if(ExtSignalMAHandle != INVALID_HANDLE) IndicatorRelease(ExtSignalMAHandle);
   if(ExtATRHandle != INVALID_HANDLE) IndicatorRelease(ExtATRHandle);
}

void OnTick()
{
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
   
   if(ExtPositionInfo.Select(_Symbol)) {
      Print("[INFO] Existing position. Managing risk with SMC.");
      // Check for early exit based on SMC
      CheckSmcExitConditions();
      // Manage trailing stop with SMC enhancement
      ManageTrailingStop();
      // Check position expiration
      CheckPositionExpiration();
      return;
   }
   
   // Get enhanced trade signal incorporating SMC
   int signal = TradeSignal();
   if(signal == 1) {
      Print("[INFO] Enhanced Swing Buy Signal with SMC");
      ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
   } else if(signal == -1) {
      Print("[INFO] Enhanced Swing Sell Signal with SMC");
      ExecuteTrade(ORDER_TYPE_SELL, ExtATR[1]);
   }
}

bool RefreshIndicators()
{
   if(CopyBuffer(ExtTrendMAHandle, 0, 0, 2, ExtTrendMA) <= 0) { Print("[ERROR] TrendMA buffer"); return false; }
   if(CopyBuffer(ExtSignalMAHandle, 0, 0, 2, ExtSignalMA) <= 0) { Print("[ERROR] SignalMA buffer"); return false; }
   if(CopyBuffer(ExtATRHandle, 0, 0, 2, ExtATR) <= 0) { Print("[ERROR] ATR buffer"); return false; }
   return true;
}

int TradeSignal()
{
   // Get base signal from MA crossover
   int baseSignal = 0;
   if(ExtTrendMA[1] > ExtSignalMA[1]) baseSignal = 1;
   if(ExtTrendMA[1] < ExtSignalMA[1]) baseSignal = -1;
   
   // Check for recent SMC events
   datetime recentTime = iTime(_Symbol, _Period, 5); // Last 5 bars
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
   
   // Analyze recent CHoCH events (more significant)
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
   
   // Enhanced trading logic with SMC integration
   
   // Case 1: MA crossover with SMC confirmation - strongest signal
   if(baseSignal == 1 && (recentBullishBOS || recentBullishCHoCH)) {
      Print("[SMC] Strong BUY signal - MA crossover with SMC confirmation");
      Alert("[SMC] Strong BUY signal - MA crossover with SMC confirmation");
      return 1;
   }
   
   if(baseSignal == -1 && (recentBearishBOS || recentBearishCHoCH)) {
      Print("[SMC] Strong SELL signal - MA crossover with SMC confirmation");
      Alert("[SMC] Strong SELL signal - MA crossover with SMC confirmation");
      return -1;
   }
   
   // Case 2: MA crossover but opposing SMC - reject the signal
   if(baseSignal == 1 && bearishStrength > 5.0) {
      Print("[SMC] Rejecting MA BUY signal due to strong bearish SMC events");
      Alert("[SMC] Rejecting MA BUY signal due to strong bearish SMC events");
      return 0;
   }
   
   if(baseSignal == -1 && bullishStrength > 5.0) {
      Print("[SMC] Rejecting MA SELL signal due to strong bullish SMC events");
      Alert("[SMC] Rejecting MA SELL signal due to strong bullish SMC events");
      return 0;
   }
   
   // Case 3: No MA signal but strong SMC events
   if(baseSignal == 0 && recentBullishCHoCH && bullishStrength > 7.0) {
      Print("[SMC] SMC-only BUY signal - Strong bullish CHoCH without MA confirmation");
      Alert("[SMC] SMC-only BUY signal - Strong bullish CHoCH without MA confirmation");
      return 1;
   }
   
   if(baseSignal == 0 && recentBearishCHoCH && bearishStrength > 7.0) {
      Print("[SMC] SMC-only SELL signal - Strong bearish CHoCH without MA confirmation");
      Alert("[SMC] SMC-only SELL signal - Strong bearish CHoCH without MA confirmation");
      return -1;
   }
   
   // Case 4: Standard MA signal without strong SMC confirmation/rejection
   return baseSignal;
}

void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   ExtSymbolInfo.RefreshRates();
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? price - InpATRMultiplier * atrValue : price + InpATRMultiplier * atrValue;
   double tp = (type == ORDER_TYPE_BUY) ? price + InpTPMultiplier * atrValue : price - InpTPMultiplier * atrValue;
   double lot = CalculateLot(atrValue);
   if(!ExtTrade.PositionOpen(_Symbol, type, lot, price, sl, tp, "SwingTrade")) {
      Print("[ERROR] Trade open failed: ", ExtTrade.ResultRetcodeDescription());
      Alert("[ERROR] Trade open failed: ", ExtTrade.ResultRetcodeDescription());
   } else {
      Print("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
      Alert("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
   }
}

double CalculateLot(double atrValue)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   double lot = risk / (atrValue * 10 * _Point);
   lot = MathMax(lot, ExtSymbolInfo.LotsMin());
   lot = MathMin(lot, ExtSymbolInfo.LotsMax());
   return NormalizeDouble(lot, 2);
}

void ManageTrailingStop()
{
   double atr = ExtATR[1];
   ExtSymbolInfo.RefreshRates();
   double price = (ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
   double oldSL = ExtPositionInfo.StopLoss();
   
   // Adjust ATR multiplier based on SMC events for more dynamic trailing
   double multiplier = InpATRMultiplier;
   
   // Check for confirming SMC events to tighten trailing stop
   datetime recentTime = iTime(_Symbol, _Period, 3); // Last 3 bars
   
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) {
      // For buy positions, look for bullish SMC events
      for(int i=0; i<bosEventCount; i++) {
         if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
            // Bullish BOS suggests trend strength - tighten stop
            multiplier = InpATRMultiplier * 0.85; // 85% of original
            Print("[SMC] Tightening trailing stop due to bullish BOS");
            break;
         }
      }
      
      // CHoCH events are even more significant
      for(int i=0; i<chochEventCount; i++) {
         if(chochEvents[i].isBullish && chochEvents[i].time >= recentTime) {
            // Bullish CHoCH is stronger confirmation - tighten more
            multiplier = InpATRMultiplier * 0.7; // 70% of original
            Print("[SMC] Tightening trailing stop due to bullish CHoCH");
            break;
         }
      }
   }
   else if(ExtPositionInfo.PositionType() == POSITION_TYPE_SELL) {
      // For sell positions, look for bearish SMC events
      for(int i=0; i<bosEventCount; i++) {
         if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
            // Bearish BOS suggests trend strength - tighten stop
            multiplier = InpATRMultiplier * 0.85; // 85% of original
            Print("[SMC] Tightening trailing stop due to bearish BOS");
            break;
         }
      }
      
      // CHoCH events are even more significant
      for(int i=0; i<chochEventCount; i++) {
         if(!chochEvents[i].isBullish && chochEvents[i].time >= recentTime) {
            // Bearish CHoCH is stronger confirmation - tighten more
            multiplier = InpATRMultiplier * 0.7; // 70% of original
            Print("[SMC] Tightening trailing stop due to bearish CHoCH");
            break;
         }
      }
   }
   
   // Calculate new stop loss with adjusted multiplier
   double newSL;
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY)
      newSL = price - multiplier * atr;
   else
      newSL = price + multiplier * atr;
   
   // Update stop loss if it's better than the current one
   if((ExtPositionInfo.PositionType() == POSITION_TYPE_BUY && newSL > oldSL) || (ExtPositionInfo.PositionType() == POSITION_TYPE_SELL && newSL < oldSL)) {
      if(!ExtTrade.PositionModify(_Symbol, newSL, ExtPositionInfo.TakeProfit())) {
         Print("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
         Alert("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
      } else {
         Print("[INFO] Trailing stop updated with multiplier: ", DoubleToString(multiplier, 2));
         Alert("[INFO] Trailing stop updated with multiplier: ", DoubleToString(multiplier, 2));
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
   datetime recentTime = iTime(_Symbol, _Period, 3); // Check last 3 bars
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

void CheckPositionExpiration()
{
   if(InpDuration <= 0) return;
   datetime positionTime = (datetime)ExtPositionInfo.Time();
   if(TimeCurrent() - positionTime >= InpDuration * 60) {
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