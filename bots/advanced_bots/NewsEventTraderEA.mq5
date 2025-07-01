//+------------------------------------------------------------------+
//|                     NewsEventTraderEA.mq5                        |
//|                              AI Cascade                          |
//|                News-Based Trading with SMC Strategy              |
//+------------------------------------------------------------------+
#property copyright "AI Cascade"
#property link      ""
#property version   "2.0"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Signal Constants
#define NEWS_BUY      1
#define NO_NEWS       0
#define NEWS_SELL    -1

//--- Input Parameters
// [News Parameters]
input string   InpNewsFile      = "C:/MT5Signals/news.csv";  // Path to news CSV file
input int      InpNewsWindow    = 15;                        // Minutes before/after news to trade (window size)
input string   InpImpactLevel   = "high";                    // Minimum impact level to trade (high/medium/low)

// [SMC Parameters]
input bool     UseSmcFeatures   = true;      // Use SMC features
input int      SwingStrength    = 3;         // Strength required for swing points (1-10)
input int      LookbackBars     = 50;        // Lookback period for structure analysis
input double   SmcFilterStrength = 0.7;      // Filter strength for SMC signals (0.1-1.0)

// [Trade Parameters]
input uint     InpSlippage      = 3;                         // Slippage in points
input uint     InpDuration      = 1440;                      // Position duration in minutes
input double   InpATRMultiplier = 2.0;                       // ATR multiplier for stops
input int      InpATRPeriod     = 14;                        // ATR period

// [Money Management]
input double   InpRiskPerTrade  = 1.0;                       // Risk % per trade

// [Expert ID]
input long     InpMagicNumber   = 950001;                    // Unique EA identifier

//--- Global Variables
int    ExtATRHandle     = INVALID_HANDLE;
int    ExtSignal        = NO_NEWS;
string ExtSignalInfo    = "";
bool   ExtNewBar        = false;

//--- SMC Structures
struct SwingPoint {
   datetime time;
   double   price;
   bool     isHigh;
   int      strength;
};

struct BosEvent {
   datetime time;
   double   price;
   bool     isBullish;
   double   strength;
};

struct ChochEvent {
   datetime time;
   double   price;
   bool     isBullish;
   double   strength;
};

//--- SMC Variables
SwingPoint swingPoints[];
BosEvent   bosEvents[];
ChochEvent chochEvents[];
int        swingPointCount = 0;
int        bosEventCount = 0;
int        chochEventCount = 0;
int        maxSwingPoints = 10;
int        maxBosEvents = 5;
int        maxChochEvents = 5;

//--- Indicator Buffers
double ExtATR[];
double High[], Low[], Close[], Open[];

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
   if(InpNewsWindow <= 0)
     {
      Print("[ERROR] NewsWindow must be positive");
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
   ExtATRHandle = iATR(_Symbol, _Period, InpATRPeriod);
   
   if(ExtATRHandle == INVALID_HANDLE)
     {
      Print("Indicator initialization failed");
      return INIT_FAILED;
     }
   
   // Initialize SMC arrays
   if(UseSmcFeatures) {
      ArrayResize(swingPoints, maxSwingPoints);
      ArrayResize(bosEvents, maxBosEvents);
      ArrayResize(chochEvents, maxChochEvents);
   }
     
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
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
   
   // Detect SMC events on new bars if enabled
   if(UseSmcFeatures && ExtNewBar) {
      DetectSwingPoints();
      DetectBreakOfStructure();
      DetectChangeOfCharacter();
   }
      
   //--- Check trading conditions
   CheckTradingConditions();
   
   // Apply SMC-based position management if enabled
   if(UseSmcFeatures && ExtPositionInfo.Select(_Symbol)) {
      ManageTrailingStopWithSmc();
      CheckSmcExitConditions();
   }
}

//+------------------------------------------------------------------+
//| Refresh indicator data                                           |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   //--- Refresh ATR
   if(CopyBuffer(ExtATRHandle, 0, 0, 2, ExtATR) <= 0)
     {
      Print("[ERROR] Failed to copy ATR buffer");
      return false;
     }
   
   // Get price data for SMC analysis
   if(UseSmcFeatures) {
      ArraySetAsSeries(High, true);
      ArraySetAsSeries(Low, true);
      ArraySetAsSeries(Close, true);
      ArraySetAsSeries(Open, true);
      
      if(CopyHigh(_Symbol, _Period, 0, LookbackBars, High) <= 0) return false;
      if(CopyLow(_Symbol, _Period, 0, LookbackBars, Low) <= 0) return false;
      if(CopyClose(_Symbol, _Period, 0, LookbackBars, Close) <= 0) return false;
      if(CopyOpen(_Symbol, _Period, 0, LookbackBars, Open) <= 0) return false;
   }
     
   return true;
}

//+------------------------------------------------------------------+
//| Detect swing points                                             |
//+------------------------------------------------------------------+
void DetectSwingPoints()
{
   swingPointCount = 0;
   
   // Look for swing highs
   for(int i = 2; i < LookbackBars - 2; i++) {
      // Check for swing high
      if(High[i] > High[i-1] && High[i] > High[i-2] && 
         High[i] > High[i+1] && High[i] > High[i+2]) {
         
         // Calculate strength based on nearby bars
         int strength = 2; // Base strength
         for(int j = 3; j < MathMin(10, i); j++) {
            if(High[i] > High[i-j]) strength++;
            if(High[i] > High[i+j] && i+j < LookbackBars) strength++;
         }
         
         if(strength >= SwingStrength) {
            // Add to array if strong enough
            if(swingPointCount < maxSwingPoints) {
               swingPoints[swingPointCount].time = iTime(_Symbol, _Period, i);
               swingPoints[swingPointCount].price = High[i];
               swingPoints[swingPointCount].isHigh = true;
               swingPoints[swingPointCount].strength = strength;
               swingPointCount++;
            }
         }
      }
      
      // Check for swing low
      if(Low[i] < Low[i-1] && Low[i] < Low[i-2] && 
         Low[i] < Low[i+1] && Low[i] < Low[i+2]) {
         
         // Calculate strength based on nearby bars
         int strength = 2; // Base strength
         for(int j = 3; j < MathMin(10, i); j++) {
            if(Low[i] < Low[i-j]) strength++;
            if(Low[i] < Low[i+j] && i+j < LookbackBars) strength++;
         }
         
         if(strength >= SwingStrength) {
            // Add to array if strong enough
            if(swingPointCount < maxSwingPoints) {
               swingPoints[swingPointCount].time = iTime(_Symbol, _Period, i);
               swingPoints[swingPointCount].price = Low[i];
               swingPoints[swingPointCount].isHigh = false;
               swingPoints[swingPointCount].strength = strength;
               swingPointCount++;
            }
         }
      }
   }
   
   // Sort swing points by time (newest first)
   for(int i = 0; i < swingPointCount - 1; i++) {
      for(int j = i + 1; j < swingPointCount; j++) {
         if(swingPoints[i].time < swingPoints[j].time) {
            SwingPoint temp = swingPoints[i];
            swingPoints[i] = swingPoints[j];
            swingPoints[j] = temp;
         }
      }
   }
   
   if(swingPointCount > 0) {
      Print("[SMC] Detected ", swingPointCount, " swing points");
   }
}

//+------------------------------------------------------------------+
//| Detect Break of Structure (BOS)                                 |
//+------------------------------------------------------------------+
void DetectBreakOfStructure()
{
   bosEventCount = 0;
   
   // Need at least 3 swing points to detect BOS
   if(swingPointCount < 3) return;
   
   // Find valid swing high/low sequences for BOS
   for(int i = 0; i < swingPointCount - 2; i++) {
      // Bullish BOS: Lower Low followed by Higher Low
      if(!swingPoints[i].isHigh && !swingPoints[i+1].isHigh && !swingPoints[i+2].isHigh) {
         if(swingPoints[i].price > swingPoints[i+1].price && 
            swingPoints[i].price < swingPoints[i+2].price) {
            
            // Calculate BOS strength
            double strength = (swingPoints[i].price - swingPoints[i+1].price) / (ExtATR[1] * InpATRMultiplier);
            strength = MathMin(strength * 2, 1.0);
            
            // Save BOS event if significant
            if(strength >= SmcFilterStrength && bosEventCount < maxBosEvents) {
               bosEvents[bosEventCount].time = swingPoints[i].time;
               bosEvents[bosEventCount].price = swingPoints[i].price;
               bosEvents[bosEventCount].isBullish = true;
               bosEvents[bosEventCount].strength = strength;
               bosEventCount++;
               Print("[SMC] Detected Bullish BOS with strength ", DoubleToString(strength, 2));
            }
         }
      }
      
      // Bearish BOS: Higher High followed by Lower High
      if(swingPoints[i].isHigh && swingPoints[i+1].isHigh && swingPoints[i+2].isHigh) {
         if(swingPoints[i].price < swingPoints[i+1].price && 
            swingPoints[i].price > swingPoints[i+2].price) {
            
            // Calculate BOS strength
            double strength = (swingPoints[i+1].price - swingPoints[i].price) / (ExtATR[1] * InpATRMultiplier);
            strength = MathMin(strength * 2, 1.0);
            
            // Save BOS event if significant
            if(strength >= SmcFilterStrength && bosEventCount < maxBosEvents) {
               bosEvents[bosEventCount].time = swingPoints[i].time;
               bosEvents[bosEventCount].price = swingPoints[i].price;
               bosEvents[bosEventCount].isBullish = false;
               bosEvents[bosEventCount].strength = strength;
               bosEventCount++;
               Print("[SMC] Detected Bearish BOS with strength ", DoubleToString(strength, 2));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Change of Character (CHoCH)                               |
//+------------------------------------------------------------------+
void DetectChangeOfCharacter()
{
   chochEventCount = 0;
   
   // Need BOS events and swing points to detect CHoCH
   if(bosEventCount < 1 || swingPointCount < 2) return;
   
   datetime currentTime = TimeCurrent();
   datetime recentTime = currentTime - PeriodSeconds(_Period) * 10; // Last 10 bars
   
   for(int i = 0; i < bosEventCount; i++) {
      // Only check recent BOS events
      if(bosEventCount > 0 && bosEvents[i].time >= recentTime) {
         // For bullish BOS, look for price breaking above recent swing high
         if(bosEvents[i].isBullish) {
            // Find most recent swing high before this BOS
            double recentHigh = 0;
            for(int j = 0; j < swingPointCount; j++) {
               if(swingPoints[j].isHigh && swingPoints[j].time < bosEvents[i].time) {
                  recentHigh = swingPoints[j].price;
                  break; // Most recent swing high (since array is sorted by time)
               }
            }
            
            // If we found a swing high and current price broke above it
            if(recentHigh > 0 && Close[0] > recentHigh) {
               double strength = (Close[0] - recentHigh) / (ExtATR[1] * InpATRMultiplier);
               strength = MathMin(strength * 1.5, 1.0);
               
               if(strength >= SmcFilterStrength && chochEventCount < maxChochEvents) {
                  chochEvents[chochEventCount].time = currentTime;
                  chochEvents[chochEventCount].price = Close[0];
                  chochEvents[chochEventCount].isBullish = true;
                  chochEvents[chochEventCount].strength = strength;
                  chochEventCount++;
                  Print("[SMC] Detected Bullish CHoCH with strength ", DoubleToString(strength, 2));
               }
            }
         }
         // For bearish BOS, look for price breaking below recent swing low
         else {
            // Find most recent swing low before this BOS
            double recentLow = 0;
            for(int j = 0; j < swingPointCount; j++) {
               if(!swingPoints[j].isHigh && swingPoints[j].time < bosEvents[i].time) {
                  recentLow = swingPoints[j].price;
                  break; // Most recent swing low (since array is sorted by time)
               }
            }
            
            // If we found a swing low and current price broke below it
            if(recentLow > 0 && Close[0] < recentLow) {
               double strength = (recentLow - Close[0]) / (ExtATR[1] * InpATRMultiplier);
               strength = MathMin(strength * 1.5, 1.0);
               
               if(strength >= SmcFilterStrength && chochEventCount < maxChochEvents) {
                  chochEvents[chochEventCount].time = currentTime;
                  chochEvents[chochEventCount].price = Close[0];
                  chochEvents[chochEventCount].isBullish = false;
                  chochEvents[chochEventCount].strength = strength;
                  chochEventCount++;
                  Print("[SMC] Detected Bearish CHoCH with strength ", DoubleToString(strength, 2));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for relevant news events                                   |
//+------------------------------------------------------------------+
bool IsNewsWindow()
{
   int fh = FileOpen(InpNewsFile, FILE_READ|FILE_CSV|FILE_ANSI);
   if(fh == INVALID_HANDLE)
     {
      Print("[ERROR] Failed to open news file: ", InpNewsFile);
      return false;
     }
     
   bool result = false;
   datetime now = TimeCurrent();
   
   while(!FileIsEnding(fh))
     {
      string dt = FileReadString(fh);
      string s = FileReadString(fh);
      string impact = FileReadString(fh);
      
      if(StringLen(dt) == 0 || StringLen(s) == 0 || StringLen(impact) == 0)
         continue;
         
      datetime newsTime = StringToTime(dt);
      if(s == _Symbol && MathAbs(newsTime - now) <= InpNewsWindow * 60 && impact == InpImpactLevel)
        {
         result = true;
         break;
        }
     }
     
   FileClose(fh);
   return result;
}

//+------------------------------------------------------------------+
//| Check trading conditions with SMC validation                     |
//+------------------------------------------------------------------+
void CheckTradingConditions()
{
   //--- Check for existing positions
   if(ExtPositionInfo.Select(_Symbol))
     {
      Print("[INFO] Existing position detected. No new trades.");
      CheckPositionExpiration();
      return;
     }
   
   //--- Check if we're in a news window
   bool newsPresent = IsNewsWindow();
   bool hasBuySignal = false;
   bool hasSellSignal = false;

   // Standard news-based signal
   if(newsPresent) {
      hasBuySignal = true;
      ExtSignalInfo = "High Impact News Trade";
      ExtSignal = NEWS_BUY;
   } else {
      ExtSignal = NO_NEWS;
      ExtSignalInfo = "No relevant news";
   }
   
   // Apply SMC filtering if enabled
   if(UseSmcFeatures && newsPresent) {
      bool hasStrongBearishSmc = false;
      bool hasStrongBullishSmc = false;
      datetime recentTime = TimeCurrent() - 5 * PeriodSeconds(_Period);
      
      // Check for recent BOS events
      for(int i = 0; i < bosEventCount; i++) {
         if(bosEvents[i].time >= recentTime && bosEvents[i].strength >= SmcFilterStrength * 1.2) {
            if(bosEvents[i].isBullish) {
               hasStrongBullishSmc = true;
               ExtSignalInfo = "BOS-Enhanced News Buy";
               hasSellSignal = false;
               hasBuySignal = true;
            } else {
               hasStrongBearishSmc = true;
               ExtSignalInfo = "BOS-Enhanced News Sell";
               hasBuySignal = false;
               hasSellSignal = true;
            }
         }
      }
      
      // CHoCH events are even stronger confirmation
      for(int i = 0; i < chochEventCount; i++) {
         if(chochEvents[i].time >= recentTime && chochEvents[i].strength >= SmcFilterStrength) {
            if(chochEvents[i].isBullish) {
               hasStrongBullishSmc = true;
               hasSellSignal = false; // Reject opposite signals
               hasBuySignal = true;
               ExtSignalInfo = "CHoCH-Enhanced News Buy";
            } else {
               hasStrongBearishSmc = true;
               hasBuySignal = false; // Reject opposite signals
               hasSellSignal = true;
               ExtSignalInfo = "CHoCH-Enhanced News Sell";
            }
         }
      }
      
      // Default to buy during news if no strong SMC signals present
      if(!hasStrongBearishSmc && !hasStrongBullishSmc) {
         hasBuySignal = true;
         hasSellSignal = false;
      }
   }
   
   // Execute trades based on final signals
   if(hasBuySignal) {
      ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
   } else if(hasSellSignal) {
      ExecuteTrade(ORDER_TYPE_SELL, ExtATR[1]);
   }
}

//+------------------------------------------------------------------+
//| Execute trade with SMC-enhanced parameters                       |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   ExtSymbolInfo.RefreshRates();
   
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double slMultiplier = InpATRMultiplier;
   double sl;
   
   // Enhance stop loss based on SMC events if enabled
   if(UseSmcFeatures) {
      datetime recentTime = TimeCurrent() - 5 * PeriodSeconds(_Period);
      
      // For Buy orders, check for confirming bullish SMC events
      if(type == ORDER_TYPE_BUY) {
         // Check for recent bullish BOS events
         for(int i = 0; i < bosEventCount; i++) {
            if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
               // Tighter stop, better placement with confirmation
               slMultiplier *= (1.0 - 0.2 * bosEvents[i].strength);
               Print("[SMC] Adjusting BUY stop with bullish BOS confirmation");
               break;
            }
         }
         
         // Find potential stronger swing lows for better stop placement
         for(int i = 0; i < swingPointCount; i++) {
            if(!swingPoints[i].isHigh && swingPoints[i].time >= recentTime) {
               double potentialSL = swingPoints[i].price - 5 * _Point;
               if(potentialSL < price - slMultiplier * atrValue) {
                  sl = potentialSL;
                  Print("[SMC] Using swing low for more efficient stop placement");
                  break;
               }
            }
         }
      }
      // For Sell orders, check for confirming bearish SMC events
      else {
         // Check for recent bearish BOS events
         for(int i = 0; i < bosEventCount; i++) {
            if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
               // Tighter stop, better placement with confirmation
               slMultiplier *= (1.0 - 0.2 * bosEvents[i].strength);
               Print("[SMC] Adjusting SELL stop with bearish BOS confirmation");
               break;
            }
         }
         
         // Find potential stronger swing highs for better stop placement
         for(int i = 0; i < swingPointCount; i++) {
            if(swingPoints[i].isHigh && swingPoints[i].time >= recentTime) {
               double potentialSL = swingPoints[i].price + 5 * _Point;
               if(potentialSL > price + slMultiplier * atrValue) {
                  sl = potentialSL;
                  Print("[SMC] Using swing high for more efficient stop placement");
                  break;
               }
            }
         }
      }
   }
   
   // If no SMC-based stop was set, use default ATR-based stop
   if(sl == 0) {
      sl = (type == ORDER_TYPE_BUY) ? price - slMultiplier * atrValue : price + slMultiplier * atrValue;
   }
   
   // Calculate position size based on risk
   double lot = CalculateLot(MathAbs(price - sl));
   
   if(!ExtTrade.PositionOpen(_Symbol, type, lot, price, sl, 0, ExtSignalInfo))
     {
      Print("[ERROR] Trade failed: ", ExtTrade.ResultRetcodeDescription());
     }
   else
     {
      Print("[SUCCESS] ", ExtSignalInfo, " executed: ", EnumToString(type), " ", lot, " lots");
     }
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculateLot(double stopDistance)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   double lot = risk / (stopDistance * 10 * _Point);
   lot = MathMax(lot, ExtSymbolInfo.LotsMin());
   lot = MathMin(lot, ExtSymbolInfo.LotsMax());
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Check position expiration with SMC validation                    |
//+------------------------------------------------------------------+
void CheckPositionExpiration()
{
   if(InpDuration <= 0) return;
   
   datetime positionTime = (datetime)ExtPositionInfo.Time();
   ENUM_POSITION_TYPE posType = ExtPositionInfo.PositionType();
   bool forceClose = false;
   string closeReason = "duration expiration";
   
   // Standard time-based expiration
   if(TimeCurrent() - positionTime >= InpDuration * 60) {
      forceClose = true;
   }
   
   // Enhanced expiration with SMC if enabled
   if(UseSmcFeatures) {
      // Check for strong counter trend SMC signals
      datetime recentTime = TimeCurrent() - 3 * PeriodSeconds(_Period);
      
      // For Buy positions, check bearish signals
      if(posType == POSITION_TYPE_BUY) {
         // Check for bearish BOS
         for(int i = 0; i < bosEventCount; i++) {
            if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime && 
               bosEvents[i].strength >= SmcFilterStrength * 1.3) {
               forceClose = true;
               closeReason = "bearish BOS detected";
               break;
            }
         }
         
         // Bearish CHoCH is even stronger exit signal
         for(int i = 0; i < chochEventCount; i++) {
            if(!chochEvents[i].isBullish && chochEvents[i].time >= recentTime && 
               chochEvents[i].strength >= SmcFilterStrength) {
               forceClose = true;
               closeReason = "bearish CHoCH detected";
               break;
            }
         }
      }
      // For Sell positions, check bullish signals
      else {
         // Check for bullish BOS
         for(int i = 0; i < bosEventCount; i++) {
            if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime && 
               bosEvents[i].strength >= SmcFilterStrength * 1.3) {
               forceClose = true;
               closeReason = "bullish BOS detected";
               break;
            }
         }
         
         // Bullish CHoCH is even stronger exit signal
         for(int i = 0; i < chochEventCount; i++) {
            if(chochEvents[i].isBullish && chochEvents[i].time >= recentTime && 
               chochEvents[i].strength >= SmcFilterStrength) {
               forceClose = true;
               closeReason = "bullish CHoCH detected";
               break;
            }
         }
      }
   }
   
   // Execute position closure if needed
   if(forceClose) {
      if(ExtTrade.PositionClose(_Symbol))
         Print("[INFO] Position closed due to ", closeReason);
      else
         Print("[ERROR] Failed to close position");
   }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop with SMC                                    |
//+------------------------------------------------------------------+
void ManageTrailingStopWithSmc()
{
   if(!ExtPositionInfo.Select(_Symbol)) return;
   
   double currentSL = ExtPositionInfo.StopLoss();
   ENUM_POSITION_TYPE posType = ExtPositionInfo.PositionType();
   double currentPrice = (posType == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
   double openPrice = ExtPositionInfo.PriceOpen();
   double newSL = currentSL;
   bool updateSL = false;
   
   // For buy positions
   if(posType == POSITION_TYPE_BUY) {
      // Only trail if in profit
      if(currentPrice > openPrice) {
         // Standard ATR-based trailing
         double basicTrailSL = currentPrice - ExtATR[1] * InpATRMultiplier * 0.8; // Tighter trail
         
         if(UseSmcFeatures) {
            // Check for recent swing lows for better trail placement
            datetime recentTime = TimeCurrent() - 20 * PeriodSeconds(_Period);
            for(int i = 0; i < swingPointCount; i++) {
               if(!swingPoints[i].isHigh && swingPoints[i].time >= recentTime && 
                  swingPoints[i].time < TimeCurrent() - PeriodSeconds(_Period)) { // Not the current bar
                  double swingTrailSL = swingPoints[i].price - 5 * _Point;
                  // Use swing low as SL if it's better than basic trail but still protecting profits
                  if(swingTrailSL > currentSL && swingTrailSL < basicTrailSL && swingTrailSL > openPrice) {
                     basicTrailSL = swingTrailSL;
                     Print("[SMC] Using swing low for BUY trail stop at ", DoubleToString(basicTrailSL, _Digits));
                     break;
                  }
               }
            }
         }
         
         // Only update if new SL is higher than current
         if(basicTrailSL > currentSL || currentSL == 0) {
            newSL = basicTrailSL;
            updateSL = true;
         }
      }
   }
   // For sell positions
   else {
      // Only trail if in profit
      if(currentPrice < openPrice) {
         // Standard ATR-based trailing
         double basicTrailSL = currentPrice + ExtATR[1] * InpATRMultiplier * 0.8; // Tighter trail
         
         if(UseSmcFeatures) {
            // Check for recent swing highs for better trail placement
            datetime recentTime = TimeCurrent() - 20 * PeriodSeconds(_Period);
            for(int i = 0; i < swingPointCount; i++) {
               if(swingPoints[i].isHigh && swingPoints[i].time >= recentTime && 
                  swingPoints[i].time < TimeCurrent() - PeriodSeconds(_Period)) { // Not the current bar
                  double swingTrailSL = swingPoints[i].price + 5 * _Point;
                  // Use swing high as SL if it's better than basic trail but still protecting profits
                  if((swingTrailSL < currentSL || currentSL == 0) && swingTrailSL > basicTrailSL && swingTrailSL < openPrice) {
                     basicTrailSL = swingTrailSL;
                     Print("[SMC] Using swing high for SELL trail stop at ", DoubleToString(basicTrailSL, _Digits));
                     break;
                  }
               }
            }
         }
         
         // Only update if new SL is lower than current or current is not set
         if(basicTrailSL < currentSL || currentSL == 0) {
            newSL = basicTrailSL;
            updateSL = true;
         }
      }
   }
   
   // Update stop loss if needed
   if(updateSL) {
      if(!ExtTrade.PositionModify(_Symbol, newSL, ExtPositionInfo.TakeProfit())) {
         Print("[ERROR] Failed to modify position: ", ExtTrade.ResultRetcodeDescription());
      } else {
         Print("[SMC] Updated trailing stop to ", DoubleToString(newSL, _Digits));
      }
   }
}

//+------------------------------------------------------------------+
//| Check for SMC-based exit conditions                              |
//+------------------------------------------------------------------+
void CheckSmcExitConditions()
{
   if(!UseSmcFeatures || !ExtPositionInfo.Select(_Symbol)) return;
   
   ENUM_POSITION_TYPE posType = ExtPositionInfo.PositionType();
   double currentPrice = (posType == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
   double openPrice = ExtPositionInfo.PriceOpen();
   bool shouldExit = false;
   string exitReason = "";
   
   // Only look for exit if we're in profit (otherwise rely on stop loss)
   if((posType == POSITION_TYPE_BUY && currentPrice > openPrice) ||
      (posType == POSITION_TYPE_SELL && currentPrice < openPrice)) {
      
      datetime recentTime = TimeCurrent() - 5 * PeriodSeconds(_Period);
      
      // Buy position checks
      if(posType == POSITION_TYPE_BUY) {
         // Check for counter-trend confirmation via multiple swing points
         int counterTrendCount = 0;
         for(int i = 0; i < swingPointCount && i < 3; i++) {
            if(swingPoints[i].time >= recentTime && !swingPoints[i].isHigh && i > 0) {
               // Detect sequence of lower lows
               if(!swingPoints[i-1].isHigh && swingPoints[i].price < swingPoints[i-1].price) {
                  counterTrendCount++;
                  if(counterTrendCount >= 2) {
                     shouldExit = true;
                     exitReason = "Lower lows sequence detected";
                     break;
                  }
               }
            }
         }
         
         // Check for bearish price action in most recent bars
         if(!shouldExit) {
            int bearishBars = 0;
            for(int i = 1; i < 4; i++) { // Check last 3 completed bars
               if(i < LookbackBars && Close[i] < Open[i] && 
                  MathAbs(Close[i] - Open[i]) > ExtATR[1] * 0.5) {
                  bearishBars++;
               }
            }
            if(bearishBars >= 2) {
               shouldExit = true;
               exitReason = "Strong bearish price action";
            }
         }
      }
      // Sell position checks
      else {
         // Check for counter-trend confirmation via multiple swing points
         int counterTrendCount = 0;
         for(int i = 0; i < swingPointCount && i < 3; i++) {
            if(swingPoints[i].time >= recentTime && swingPoints[i].isHigh && i > 0) {
               // Detect sequence of higher highs
               if(swingPoints[i-1].isHigh && swingPoints[i].price > swingPoints[i-1].price) {
                  counterTrendCount++;
                  if(counterTrendCount >= 2) {
                     shouldExit = true;
                     exitReason = "Higher highs sequence detected";
                     break;
                  }
               }
            }
         }
         
         // Check for bullish price action in most recent bars
         if(!shouldExit) {
            int bullishBars = 0;
            for(int i = 1; i < 4; i++) { // Check last 3 completed bars
               if(i < LookbackBars && Close[i] > Open[i] && 
                  MathAbs(Close[i] - Open[i]) > ExtATR[1] * 0.5) {
                  bullishBars++;
               }
            }
            if(bullishBars >= 2) {
               shouldExit = true;
               exitReason = "Strong bullish price action";
            }
         }
      }
   }
   
   // Exit position if conditions met
   if(shouldExit) {
      if(ExtTrade.PositionClose(_Symbol)) {
         Print("[SMC] Position closed due to SMC exit condition: ", exitReason);
      } else {
         Print("[ERROR] Failed to close position: ", ExtTrade.ResultRetcodeDescription());
      }
   }
}
