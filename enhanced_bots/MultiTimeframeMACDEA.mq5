//+------------------------------------------------------------------+
//|                     MultiTimeframeMACDEA.mq5                     |
//|                              AI Cascade                          |
//|            Multi-Timeframe MACD Crossover Strategy               |
//+------------------------------------------------------------------+
#property copyright "AI Cascade"
#property link      ""
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Signal Constants
#define SIGNAL_BUY    1
#define SIGNAL_NOT    0
#define SIGNAL_SELL  -1

//--- Input Parameters
// [Indicator Parameters]
input int    InpFastEMA       = 12;       // Fast EMA period
input int    InpSlowEMA       = 26;       // Slow EMA period
input int    InpSignalSMA     = 9;        // Signal SMA period
input ENUM_TIMEFRAMES InpHigherTF = PERIOD_H1; // Higher timeframe

// [Trade Parameters]
input uint   InpSlippage      = 3;        // Slippage in points
input uint   InpDuration      = 1440;     // Position duration in minutes
input double InpATRMultiplier = 2.0;      // ATR multiplier for stops
input int    InpATRPeriod     = 14;       // ATR period

// [Money Management]
input double InpRiskPerTrade  = 1.0;      // Risk % per trade

// [Expert ID]
input long   InpMagicNumber   = 456789;   // Unique EA identifier

//--- Global Variables
int    ExtMACDHandle    = INVALID_HANDLE;
int    ExtATRHandle     = INVALID_HANDLE;
int    ExtSignal        = SIGNAL_NOT;
string ExtSignalInfo    = "";
bool   ExtNewBar        = false;

//--- Smart Money Concepts (SMC) Structures

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

//--- Indicator Buffers
double ExtMACDMain[], ExtMACDSignal[], ExtATR[];

//--- Service Objects
CTrade       ExtTrade;
CSymbolInfo  ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parameter validation
   if(InpFastEMA < 2 || InpFastEMA > 100)
     {
      Print("[ERROR] FastEMA must be between 2 and 100");
      return INIT_FAILED;
     }
   if(InpSlowEMA < 2 || InpSlowEMA > 200)
     {
      Print("[ERROR] SlowEMA must be between 2 and 200");
      return INIT_FAILED;
     }
   if(InpSignalSMA < 1 || InpSignalSMA > 100)
     {
      Print("[ERROR] SignalSMA must be between 1 and 100");
      return INIT_FAILED;
     }
   if(InpRiskPerTrade <= 0 || InpRiskPerTrade > 100)
     {
      Print("[ERROR] RiskPerTrade must be between 0 and 100");
      return INIT_FAILED;
     }
   if(InpATRMultiplier <= 0)
     {
      Print("[ERROR] ATRMultiplier must be positive");
      return INIT_FAILED;
     }

   //--- Initialize trading objects
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippage);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   
   if(!ExtSymbolInfo.Name(_Symbol))
     {
      Print("Failed to initialize symbol info");
      return INIT_FAILED;
     }

   //--- Initialize indicators
   ExtMACDHandle = iMACD(_Symbol, _Period, InpFastEMA, InpSlowEMA, InpSignalSMA, PRICE_CLOSE);
   ExtATRHandle = iATR(_Symbol, _Period, InpATRPeriod);
   
   if(ExtMACDHandle == INVALID_HANDLE || ExtATRHandle == INVALID_HANDLE)
     {
      Print("Indicator initialization failed");
      return INIT_FAILED;
     }
     
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(ExtMACDHandle != INVALID_HANDLE)
      IndicatorRelease(ExtMACDHandle);
   if(ExtATRHandle != INVALID_HANDLE)
      IndicatorRelease(ExtATRHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBarTime = 0;
   datetime currentTime = iTime(_Symbol, _Period, 0);
   
   //--- Check for new bar
   if(lastBarTime == currentTime)
      return;
   lastBarTime = currentTime;
   ExtNewBar = true;

   //--- Refresh indicator data
   if(!RefreshIndicators())
      return;
      
   //--- Run SMC detection on new bar
   DetectSwingPoints();
   DetectBreakOfStructure();
   DetectChangeOfCharacter();
      
   //--- Check trading conditions with SMC enhancement
   CheckTradingConditions();
}

//+------------------------------------------------------------------+
//| Refresh indicator data                                           |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   //--- Refresh MACD
   if(CopyBuffer(ExtMACDHandle, 0, 0, 2, ExtMACDMain) <= 0)
     {
      Print("[ERROR] Failed to copy MACD Main buffer");
      return false;
     }
   if(CopyBuffer(ExtMACDHandle, 1, 0, 2, ExtMACDSignal) <= 0)
     {
      Print("[ERROR] Failed to copy MACD Signal buffer");
      return false;
     }
     
   //--- Refresh ATR
   if(CopyBuffer(ExtATRHandle, 0, 0, 2, ExtATR) <= 0)
     {
      Print("[ERROR] Failed to copy ATR buffer");
      return false;
     }
     
   return true;
}

//+------------------------------------------------------------------+
//| Check higher timeframe MACD signal                               |
//+------------------------------------------------------------------+
bool HigherTFMACDSignal()
{
   double macd_htf[], signal_htf[];
   int handleHTF = iMACD(_Symbol, InpHigherTF, InpFastEMA, InpSlowEMA, InpSignalSMA, PRICE_CLOSE);
   bool result = false;
   
   if(CopyBuffer(handleHTF, 0, 0, 2, macd_htf) > 0 && CopyBuffer(handleHTF, 1, 0, 2, signal_htf) > 0)
     {
      result = macd_htf[1] > signal_htf[1];
     }
     
   IndicatorRelease(handleHTF);
   return result;
}

//+------------------------------------------------------------------+
//| Check trading conditions                                         |
//+------------------------------------------------------------------+
void CheckTradingConditions()
{
   //--- Check for existing positions
   if(ExtPositionInfo.Select(_Symbol))
     {
      Print("[INFO] Existing position detected. No new trades.");
      CheckPositionExpiration();
      CheckSmcExitConditions();
      return;
     }
   
   //--- Look for recent SMC events (last 5 bars)
   bool recentBullishBOS = false;
   bool recentBearishBOS = false;
   bool recentBullishCHoCH = false;
   bool recentBearishCHoCH = false;
   double smcBullStrength = 0;
   double smcBearStrength = 0;
   
   datetime recentTime = iTime(_Symbol, _Period, 5); // Events in the last 5 bars
   
   //--- Check for recent BOS events
   for(int i=0; i<bosEventCount; i++) {
      if(bosEvents[i].time >= recentTime) {
         if(bosEvents[i].isBullish) {
            recentBullishBOS = true;
            smcBullStrength += bosEvents[i].strength;
         } else {
            recentBearishBOS = true;
            smcBearStrength += bosEvents[i].strength;
         }
      }
   }
   
   //--- Check for recent CHoCH events (these are more significant)
   for(int i=0; i<chochEventCount; i++) {
      if(chochEvents[i].time >= recentTime) {
         if(chochEvents[i].isBullish) {
            recentBullishCHoCH = true;
            smcBullStrength += chochEvents[i].strength * 1.5; // CHoCH gets 1.5x weight
         } else {
            recentBearishCHoCH = true;
            smcBearStrength += chochEvents[i].strength * 1.5; // CHoCH gets 1.5x weight
         }
      }
   }
   
   //--- Check buy conditions (MACD crossover + higher TF confirmation + SMC support)
   if(ExtMACDMain[1] > ExtMACDSignal[1] && HigherTFMACDSignal())
     {
      //--- Strengthen buy signal if we have bullish SMC events
      if(recentBullishBOS || recentBullishCHoCH) {
         ExtSignal = SIGNAL_BUY;
         ExtSignalInfo = "MACD Crossover Buy + SMC Confirmation";
         ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
      }
      //--- Standard buy signal (no SMC confirmation)
      else if(smcBearStrength < 3.0) { // Only take standard signal if no strong opposing SMC
         ExtSignal = SIGNAL_BUY;
         ExtSignalInfo = "MACD Crossover Buy";
         ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
      }
      else {
         ExtSignal = SIGNAL_NOT;
         ExtSignalInfo = "MACD Buy rejected by SMC";
      }
     }
   //--- Check sell conditions (MACD crossunder + higher TF confirmation + SMC support)
   else if(ExtMACDMain[1] < ExtMACDSignal[1] && !HigherTFMACDSignal())
     {
      //--- Strengthen sell signal if we have bearish SMC events
      if(recentBearishBOS || recentBearishCHoCH) {
         ExtSignal = SIGNAL_SELL;
         ExtSignalInfo = "MACD Crossover Sell + SMC Confirmation";
         ExecuteTrade(ORDER_TYPE_SELL, ExtATR[1]);
      }
      //--- Standard sell signal (no SMC confirmation)
      else if(smcBullStrength < 3.0) { // Only take standard signal if no strong opposing SMC
         ExtSignal = SIGNAL_SELL;
         ExtSignalInfo = "MACD Crossover Sell";
         ExecuteTrade(ORDER_TYPE_SELL, ExtATR[1]);
      }
      else {
         ExtSignal = SIGNAL_NOT;
         ExtSignalInfo = "MACD Sell rejected by SMC";
      }
     }
   //--- Check for SMC-only signals when MACD is not giving a clear signal
   else if(recentBullishCHoCH && smcBullStrength > 6.0)
     {
      ExtSignal = SIGNAL_BUY;
      ExtSignalInfo = "SMC-only Buy Signal";
      ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
     }
   else if(recentBearishCHoCH && smcBearStrength > 6.0)
     {
      ExtSignal = SIGNAL_SELL;
      ExtSignalInfo = "SMC-only Sell Signal";
      ExecuteTrade(ORDER_TYPE_SELL, ExtATR[1]);
     }
   else
     {
      ExtSignal = SIGNAL_NOT;
      ExtSignalInfo = "No trading signal";
     }
}

//+------------------------------------------------------------------+
//| Execute trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   ExtSymbolInfo.RefreshRates();
   
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? price - InpATRMultiplier * atrValue : price + InpATRMultiplier * atrValue;
   double lot = CalculateLot(atrValue);
   
   if(!ExtTrade.PositionOpen(_Symbol, type, lot, price, sl, 0, ExtSignalInfo))
     {
      Print("[ERROR] Trade failed: ", ExtTrade.ResultRetcodeDescription());
     }
   else
     {
      Print("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
     }
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculateLot(double atrValue)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   double lot = risk / (atrValue * 10 * _Point);
   lot = MathMax(lot, ExtSymbolInfo.LotsMin());
   lot = MathMin(lot, ExtSymbolInfo.LotsMax());
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Check position expiration                                        |
//+------------------------------------------------------------------+
void CheckPositionExpiration()
{
   if(InpDuration <= 0) return;
   
   datetime positionTime = (datetime)ExtPositionInfo.Time();
   if(TimeCurrent() - positionTime >= InpDuration * 60)
     {
      if(ExtTrade.PositionClose(_Symbol))
         Print("[INFO] Position closed due to duration expiration");
      else
         Print("[ERROR] Failed to close expired position");
     }
}

//+------------------------------------------------------------------+
//| Check for early exit based on SMC events                         |
//+------------------------------------------------------------------+
void CheckSmcExitConditions()
{
   //--- Check for opposing SMC events that might warrant an early exit
   bool hasOpposingSignal = false;
   datetime recentTime = iTime(_Symbol, _Period, 3); // Look for very recent opposing signals
   string exitReason = "";
   
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) {
      //--- Check for bearish signals that oppose our long position
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
      //--- Check for bullish signals that oppose our short position
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
   
   //--- Close position early if strong opposing signal detected
   if(hasOpposingSignal) {
      // Get position profit before closing
      double positionProfit = ExtPositionInfo.Profit();
      
      if(ExtTrade.PositionClose(_Symbol)) {
         Print("[SMC] Position closed early due to ", exitReason, ". Profit: ", DoubleToString(positionProfit, 2));
      } else {
         Print("[ERROR] Failed to close position despite SMC exit signal");
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