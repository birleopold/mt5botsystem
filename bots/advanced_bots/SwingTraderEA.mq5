//+------------------------------------------------------------------+
//|                     SwingTraderEA.mq5                            |
//|        Swing Trading with SMC & Robust Risk Management           |
//|        Enhanced with Smart Money Concepts (BOS & CHoCH)          |
//+------------------------------------------------------------------+
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
// Main Strategy Parameters
input int    InpTrendMAPeriod   = 50;     // Trend MA period
input int    InpSignalMAPeriod  = 14;     // Signal MA period
input int    InpATRPeriod       = 14;     // ATR period
input double InpATRMultiplier   = 2.0;    // ATR multiplier for SL
input double InpTPMultiplier    = 3.0;    // ATR multiplier for TP
input double InpRiskPerTrade    = 1.0;    // Risk % per trade
input uint   InpSlippage        = 5;      // Slippage
input uint   InpDuration        = 1440;   // Max trade duration (min)
input long   InpMagicNumber     = 900001; // Magic number

// Smart Money Concepts Parameters
input int    InpBOSLookback     = 20;     // Bars to look back for BOS detection
input int    InpChochLookback   = 15;     // Bars to look back for CHoCH detection
input double InpBOSThreshold    = 0.5;    // Threshold for BOS significance (0-1)
input bool   InpUseSmcFilters   = true;   // Use SMC to filter swing trade signals
input bool   InpDrawSmcStructures = true; // Draw SMC structures on chart

int    ExtTrendMAHandle = INVALID_HANDLE;
int    ExtSignalMAHandle = INVALID_HANDLE;
int    ExtATRHandle = INVALID_HANDLE;
double ExtTrendMA[], ExtSignalMA[], ExtATR[];
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Smart Money Concepts Structures                                  |
//+------------------------------------------------------------------+
enum ENUM_MARKET_STRUCTURE {BOS_BULLISH, BOS_BEARISH, CHOCH_BULLISH, CHOCH_BEARISH, NONE};
enum ENUM_MARKET_REGIME {REGIME_BULLISH, REGIME_BEARISH, REGIME_NEUTRAL};

// Break of Structure (BOS) event structure
struct BOSEvent {
   datetime time;        // Time of the BOS event
   double   price;       // Price level where BOS occurred
   double   strength;    // Relative strength of the BOS (0-1)
   int      direction;   // 1 for bullish, -1 for bearish
   int      bar_index;   // Bar index where BOS was detected
   bool     confirmed;   // Whether the BOS has been confirmed by additional price action
};

// Change of Character (CHoCH) event structure
struct CHoCHEvent {
   datetime time;        // Time of the CHoCH event
   double   price;       // Price level where CHoCH occurred
   double   strength;    // Relative strength of the CHoCH (0-1)
   int      direction;   // 1 for bullish, -1 for bearish
   int      bar_index;   // Bar index where CHoCH was detected
   bool     followed_bos; // Whether this CHoCH followed a BOS event
};

// SMC Global Variables
BOSEvent      g_bos_events[20];        // Store recent BOS events
CHoCHEvent    g_choch_events[20];      // Store recent CHoCH events
int           g_bos_count = 0;         // Count of detected BOS events
int           g_choch_count = 0;       // Count of detected CHoCH events
ENUM_MARKET_REGIME g_market_regime = REGIME_NEUTRAL; // Current market regime

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
   
   // Initialize SMC structures
   g_bos_count = 0;
   g_choch_count = 0;
   g_market_regime = REGIME_NEUTRAL;
   
   Print("[INFO] SwingTraderEA v2.00 initialized with SMC features");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(ExtTrendMAHandle != INVALID_HANDLE) IndicatorRelease(ExtTrendMAHandle);
   if(ExtSignalMAHandle != INVALID_HANDLE) IndicatorRelease(ExtSignalMAHandle);
   if(ExtATRHandle != INVALID_HANDLE) IndicatorRelease(ExtATRHandle);
   
   // Print SMC statistics
   PrintFormat("SMC Stats: BOS events: %d, CHoCH events: %d, Market Regime: %s",
               g_bos_count, g_choch_count, EnumToString(g_market_regime));
   
   // Clear chart objects created by this EA
   if(InpDrawSmcStructures) {
      ObjectsDeleteAll(0, "BOS_", -1, -1);
      ObjectsDeleteAll(0, "CHOCH_", -1, -1);
   }
}

void OnTick()
{
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(lastBar == curBar) return;
   lastBar = curBar;
   
   // Refresh indicators
   if(!RefreshIndicators()) return;
   
   // Detect SMC structures
   DetectBreakOfStructure();
   DetectChangeOfCharacter();
   DetermineMarketRegime();
   
   // Check if position exists
   if(ExtPositionInfo.Select(_Symbol)) {
      Print("[INFO] Existing position. Managing risk.");
      ManageTrailingStop();
      CheckPositionExpiration();
      
      // Check for early exit based on SMC
      if(InpUseSmcFilters) CheckEarlyExitConditions();
      return;
   }
   
   // Get trade signal
   int signal = TradeSignal();
   
   // Apply SMC filters if enabled
   if(InpUseSmcFilters && signal != 0) {
      signal = ApplySmcFilters(signal);
   }
   
   // Execute trade if signal is valid
   if(signal == 1) {
      Print("[INFO] Swing Buy Signal");
      ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
   } else if(signal == -1) {
      Print("[INFO] Swing Sell Signal");
      ExecuteTrade(ORDER_TYPE_SELL, ExtATR[1]);
   }
   
   // Visualize SMC structures if enabled
   if(InpDrawSmcStructures) {
      VisualizeSMCStructures();
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
   if(ExtTrendMA[1] > ExtSignalMA[1]) return 1;
   if(ExtTrendMA[1] < ExtSignalMA[1]) return -1;
   return 0;
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
   double newSL;
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY)
      newSL = price - InpATRMultiplier * atr;
   else
      newSL = price + InpATRMultiplier * atr;
   if((ExtPositionInfo.PositionType() == POSITION_TYPE_BUY && newSL > oldSL) || (ExtPositionInfo.PositionType() == POSITION_TYPE_SELL && newSL < oldSL)) {
      if(!ExtTrade.PositionModify(_Symbol, newSL, ExtPositionInfo.TakeProfit())) {
         Print("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
         Alert("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
      } else {
         Print("[INFO] Trailing stop updated");
         Alert("[INFO] Trailing stop updated");
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
//| Smart Money Concepts Detection Functions                          |
//+------------------------------------------------------------------+
void DetectBreakOfStructure()
{
   // Get recent price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, InpBOSLookback + 10, rates);
   if(copied < InpBOSLookback + 10) return;
   
   // Find swing highs and lows
   for(int i = 2; i < InpBOSLookback - 2; i++) {
      // Check for bullish BOS (break of a swing low)
      if(rates[i+1].low > rates[i].low && rates[i-1].low > rates[i].low && 
         rates[i+2].low > rates[i].low && rates[i-2].low > rates[i].low) {
         
         // Look for a break of this structure
         for(int j = 0; j < i-1; j++) {
            if(rates[j].close < rates[i].low) {
               // Bullish BOS detected
               if(g_bos_count < 20) { // Limit to array size
                  BOSEvent bos;
                  bos.time = rates[j].time;
                  bos.price = rates[j].close;
                  bos.strength = MathAbs(rates[j].close - rates[i].low) / (rates[i].high - rates[i].low);
                  bos.direction = 1; // Bullish
                  bos.bar_index = j;
                  bos.confirmed = false;
                  
                  // Only add if strength is above threshold
                  if(bos.strength >= InpBOSThreshold) {
                     g_bos_events[g_bos_count] = bos;
                     g_bos_count++;
                     Print("[BOS] Bullish break of structure detected at ", TimeToString(rates[j].time));
                  }
                  break;
               }
            }
         }
      }
      
      // Check for bearish BOS (break of a swing high)
      if(rates[i+1].high < rates[i].high && rates[i-1].high < rates[i].high && 
         rates[i+2].high < rates[i].high && rates[i-2].high < rates[i].high) {
         
         // Look for a break of this structure
         for(int j = 0; j < i-1; j++) {
            if(rates[j].close > rates[i].high) {
               // Bearish BOS detected
               if(g_bos_count < 20) { // Limit to array size
                  BOSEvent bos;
                  bos.time = rates[j].time;
                  bos.price = rates[j].close;
                  bos.strength = MathAbs(rates[j].close - rates[i].high) / (rates[i].high - rates[i].low);
                  bos.direction = -1; // Bearish
                  bos.bar_index = j;
                  bos.confirmed = false;
                  
                  // Only add if strength is above threshold
                  if(bos.strength >= InpBOSThreshold) {
                     g_bos_events[g_bos_count] = bos;
                     g_bos_count++;
                     Print("[BOS] Bearish break of structure detected at ", TimeToString(rates[j].time));
                  }
                  break;
               }
            }
         }
      }
   }
}

void DetectChangeOfCharacter()
{
   // Get recent price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, InpChochLookback + 10, rates);
   if(copied < InpChochLookback + 10) return;
   
   // Need at least one BOS event to detect CHoCH
   if(g_bos_count == 0) return;
   
   // Check for CHoCH following the most recent BOS
   BOSEvent recent_bos = g_bos_events[g_bos_count-1];
   
   // For bullish BOS, look for price making a higher low
   if(recent_bos.direction == 1) {
      for(int i = 1; i < InpChochLookback-1; i++) {
         // Check for a higher low after a bullish BOS
         if(rates[i].low > recent_bos.price && 
            rates[i+1].low > rates[i].low && rates[i-1].low > rates[i].low) {
            
            // Bullish CHoCH detected
            if(g_choch_count < 20) { // Limit to array size
               CHoCHEvent choch;
               choch.time = rates[i].time;
               choch.price = rates[i].low;
               choch.strength = MathAbs(rates[i].low - recent_bos.price) / MathAbs(recent_bos.price);
               choch.direction = 1; // Bullish
               choch.bar_index = i;
               choch.followed_bos = true;
               
               g_choch_events[g_choch_count] = choch;
               g_choch_count++;
               
               // Mark BOS as confirmed
               g_bos_events[g_bos_count-1].confirmed = true;
               
               Print("[CHoCH] Bullish change of character detected at ", TimeToString(rates[i].time));
               break;
            }
         }
      }
   }
   // For bearish BOS, look for price making a lower high
   else if(recent_bos.direction == -1) {
      for(int i = 1; i < InpChochLookback-1; i++) {
         // Check for a lower high after a bearish BOS
         if(rates[i].high < recent_bos.price && 
            rates[i+1].high < rates[i].high && rates[i-1].high < rates[i].high) {
            
            // Bearish CHoCH detected
            if(g_choch_count < 20) { // Limit to array size
               CHoCHEvent choch;
               choch.time = rates[i].time;
               choch.price = rates[i].high;
               choch.strength = MathAbs(rates[i].high - recent_bos.price) / MathAbs(recent_bos.price);
               choch.direction = -1; // Bearish
               choch.bar_index = i;
               choch.followed_bos = true;
               
               g_choch_events[g_choch_count] = choch;
               g_choch_count++;
               
               // Mark BOS as confirmed
               g_bos_events[g_bos_count-1].confirmed = true;
               
               Print("[CHoCH] Bearish change of character detected at ", TimeToString(rates[i].time));
               break;
            }
         }
      }
   }
}

void DetermineMarketRegime()
{
   // Get recent price data
   double ma_fast[], ma_slow[];
   ArraySetAsSeries(ma_fast, true);
   ArraySetAsSeries(ma_slow, true);
   
   // Calculate moving averages for regime determination
   int ma_fast_handle = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);
   int ma_slow_handle = iMA(_Symbol, _Period, 50, 0, MODE_EMA, PRICE_CLOSE);
   
   int copied_fast = CopyBuffer(ma_fast_handle, 0, 0, 3, ma_fast);
   int copied_slow = CopyBuffer(ma_slow_handle, 0, 0, 3, ma_slow);
   
   // Release handles
   IndicatorRelease(ma_fast_handle);
   IndicatorRelease(ma_slow_handle);
   
   if(copied_fast < 3 || copied_slow < 3) return;
   
   // Determine market regime based on moving averages
   if(ma_fast[0] > ma_slow[0] && ma_fast[1] > ma_slow[1]) {
      g_market_regime = REGIME_BULLISH;
   }
   else if(ma_fast[0] < ma_slow[0] && ma_fast[1] < ma_slow[1]) {
      g_market_regime = REGIME_BEARISH;
   }
   else {
      g_market_regime = REGIME_NEUTRAL;
   }
}

// Apply SMC filters to the swing trade signal
int ApplySmcFilters(int signal)
{
   // No SMC events, keep original signal
   if(g_bos_count == 0) return signal;
   
   // Get latest BOS event
   BOSEvent recent_bos = g_bos_events[g_bos_count-1];
   
   // Filter buy signals in bearish regime or after bearish BOS
   if(signal == 1) {
      if(g_market_regime == REGIME_BEARISH) {
         Print("[SMC] Filtered out BUY signal in bearish regime");
         return 0; // Filter out buy signal
      }
      
      // Check if recent strong bearish BOS contradicts buy signal
      if(recent_bos.direction == -1 && recent_bos.strength > 0.7 && !recent_bos.confirmed) {
         Print("[SMC] Filtered out BUY signal due to recent bearish BOS");
         return 0; // Filter out buy signal
      }
   }
   // Filter sell signals in bullish regime or after bullish BOS
   else if(signal == -1) {
      if(g_market_regime == REGIME_BULLISH) {
         Print("[SMC] Filtered out SELL signal in bullish regime");
         return 0; // Filter out sell signal
      }
      
      // Check if recent strong bullish BOS contradicts sell signal
      if(recent_bos.direction == 1 && recent_bos.strength > 0.7 && !recent_bos.confirmed) {
         Print("[SMC] Filtered out SELL signal due to recent bullish BOS");
         return 0; // Filter out sell signal
      }
   }
   
   // Strengthen signals that align with BOS and CHoCH
   if(g_choch_count > 0) {
      CHoCHEvent recent_choch = g_choch_events[g_choch_count-1];
      
      // BUY signal aligns with bullish CHoCH - this is a very strong setup for swing trading
      if(signal == 1 && recent_choch.direction == 1 && recent_choch.followed_bos) {
         Print("[SMC] Enhanced BUY signal confirmed by bullish CHoCH - Strong swing trade setup");
         // Signal is already 1, we keep it
      }
      // SELL signal aligns with bearish CHoCH - this is a very strong setup for swing trading
      else if(signal == -1 && recent_choch.direction == -1 && recent_choch.followed_bos) {
         Print("[SMC] Enhanced SELL signal confirmed by bearish CHoCH - Strong swing trade setup");
         // Signal is already -1, we keep it
      }
   }
   
   return signal;
}

// Check for early exit conditions based on SMC
void CheckEarlyExitConditions()
{
   // Skip if no recent SMC events
   if(g_bos_count == 0) return;
   
   // Get position type
   ENUM_POSITION_TYPE posType = ExtPositionInfo.PositionType();
   
   // Check for counter-trend BOS that would warrant early exit
   BOSEvent recent_bos = g_bos_events[g_bos_count-1];
   
   // For a buy position, exit on bearish BOS
   if(posType == POSITION_TYPE_BUY && recent_bos.direction == -1 && recent_bos.strength >= 0.7) {
      Print("[Exit] Early exit from BUY due to strong bearish BOS");
      ExtTrade.PositionClose(_Symbol);
   }
   // For a sell position, exit on bullish BOS
   else if(posType == POSITION_TYPE_SELL && recent_bos.direction == 1 && recent_bos.strength >= 0.7) {
      Print("[Exit] Early exit from SELL due to strong bullish BOS");
      ExtTrade.PositionClose(_Symbol);
   }
   
   // Also check for CHoCH in opposite direction
   if(g_choch_count > 0) {
      CHoCHEvent recent_choch = g_choch_events[g_choch_count-1];
      
      // For a buy position, exit on bearish CHoCH
      if(posType == POSITION_TYPE_BUY && recent_choch.direction == -1 && recent_choch.followed_bos) {
         Print("[Exit] Early exit from BUY due to confirmed bearish CHoCH");
         ExtTrade.PositionClose(_Symbol);
      }
      // For a sell position, exit on bullish CHoCH
      else if(posType == POSITION_TYPE_SELL && recent_choch.direction == 1 && recent_choch.followed_bos) {
         Print("[Exit] Early exit from SELL due to confirmed bullish CHoCH");
         ExtTrade.PositionClose(_Symbol);
      }
   }
}

// Visualize the SMC structures on the chart
void VisualizeSMCStructures()
{
   // Draw BOS events
   for(int i=0; i<g_bos_count; i++) {
      BOSEvent bos = g_bos_events[i];
      string objName = "BOS_" + TimeToString(bos.time);
      
      // Create or update arrow object
      if(ObjectFind(0, objName) < 0) {
         ObjectCreate(0, objName, OBJ_ARROW, 0, bos.time, bos.price);
         ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, bos.direction > 0 ? 233 : 234); // Up/down arrow
         ObjectSetInteger(0, objName, OBJPROP_COLOR, bos.direction > 0 ? clrGreen : clrRed);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
         ObjectSetString(0, objName, OBJPROP_TOOLTIP, "BOS " + (bos.direction > 0 ? "Bullish" : "Bearish") + 
                         "\nStrength: " + DoubleToString(bos.strength, 2) +
                         "\nSwing Trade Setup");
      }
   }
   
   // Draw CHoCH events
   for(int i=0; i<g_choch_count; i++) {
      CHoCHEvent choch = g_choch_events[i];
      string objName = "CHOCH_" + TimeToString(choch.time);
      
      // Create or update arrow object
      if(ObjectFind(0, objName) < 0) {
         ObjectCreate(0, objName, OBJ_ARROW, 0, choch.time, choch.price);
         ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, choch.direction > 0 ? 225 : 226); // Up/down arrow
         ObjectSetInteger(0, objName, OBJPROP_COLOR, choch.direction > 0 ? clrLime : clrOrange);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
         ObjectSetString(0, objName, OBJPROP_TOOLTIP, "CHoCH " + (choch.direction > 0 ? "Bullish" : "Bearish") + 
                         "\nStrength: " + DoubleToString(choch.strength, 2) +
                         "\nPrime Swing Entry Point");
      }
   }
}