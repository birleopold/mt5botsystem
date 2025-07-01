//+------------------------------------------------------------------+
//| Adaptive Portfolio Manager EA with SMC Features                 |
//| Robust multi-strategy, dynamic allocation, risk controls        |
//| Enhanced with Smart Money Concepts (BOS & CHoCH)               |
//+------------------------------------------------------------------+
#property version   "2.50"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Arrays\ArrayObj.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input double MaxPortfolioRisk    = 5.0;    // Max risk % for all open trades
input double RiskPerTrade        = 1.0;    // Risk % per trade (0.1-5.0)
input double ATRMultiplier       = 2.0;    // ATR multiplier for SL/TP
input int    ATRPeriod           = 14;     // ATR period
input int    Lookback            = 50;     // Bars for performance analytics
input uint   Slippage            = 3;      // Slippage in points
input long   MagicNumber         = 600001; // Unique EA identifier
input uint   PositionDuration    = 1440;   // Position duration in minutes (0=no expiry)
input double MomentumWeight      = 0.34;   // Momentum strategy weight
input double MeanReversionWeight = 0.33;   // Mean reversion weight  
input double BreakoutWeight      = 0.33;   // Breakout strategy weight

// SMC (Smart Money Concepts) Parameters
input int    BOSLookback         = 20;     // Bars to look back for BOS detection
input int    ChochLookback       = 15;     // Bars to look back for CHoCH detection
input double BOSThreshold        = 0.5;    // Threshold for BOS significance (0-1)
input double ChochWeight         = 0.65;   // Weight of CHoCH events in signal generation
input bool   DrawSMCStructures   = true;   // Draw BOS and CHoCH on chart

//+------------------------------------------------------------------+
//| Symbol Configuration                                             |
//+------------------------------------------------------------------+
string Symbols[] = {"EURUSD","GBPUSD","USDJPY"};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade       ExtTrade;
CSymbolInfo  ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Strategy Analytics                                               |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_TYPE {STRAT_MOMENTUM, STRAT_MEANREV, STRAT_BREAKOUT};
struct StrategyStats {
   int       trades;
   int       wins;
   double    profit;
   double    drawdown;
   double    sharpe;
};

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

// Arrays to store detected SMC events for each symbol
BOSEvent    g_bos_events[][20];       // Store recent BOS events [symbol_index][event_index]
CHoCHEvent  g_choch_events[][20];     // Store recent CHoCH events [symbol_index][event_index]
int         g_bos_count[];            // Count of detected BOS events per symbol
int         g_choch_count[];          // Count of detected CHoCH events per symbol
ENUM_MARKET_REGIME g_market_regime[]; // Current market regime for each symbol
StrategyStats Stats[3];

//+------------------------------------------------------------------+
//| Expert Initialization Function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize trading objects
   ExtTrade.SetExpertMagicNumber(MagicNumber);
   ExtTrade.SetDeviationInPoints(Slippage);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   
   //--- Verify strategy weights
   double totalWeight = MomentumWeight + MeanReversionWeight + BreakoutWeight;
   if(MathAbs(totalWeight-1.0) > 0.01) {
      Print("[ERROR] Strategy weights must sum to 1.0");
      return INIT_FAILED;
   }
   
   //--- Initialize SMC arrays for each symbol
   int symbolCount = ArraySize(Symbols);
   ArrayResize(g_bos_count, symbolCount);
   ArrayResize(g_choch_count, symbolCount);
   ArrayResize(g_market_regime, symbolCount);
   ArrayResize(g_bos_events, symbolCount);
   ArrayResize(g_choch_events, symbolCount);
   
   //--- Set initial market regime to neutral for all symbols
   for(int i=0; i<symbolCount; i++) {
      g_bos_count[i] = 0;
      g_choch_count[i] = 0;
      g_market_regime[i] = REGIME_NEUTRAL;
   }
   
   Print("[INFO] AdaptivePortfolioManagerEA initialized with SMC features");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Print final performance stats
   PrintFormat("Final Stats: Momentum %.2f%%, MeanRev %.2f%%, Breakout %.2f%%",
               Stats[STRAT_MOMENTUM].profit, 
               Stats[STRAT_MEANREV].profit,
               Stats[STRAT_BREAKOUT].profit);
   
   //--- Print SMC statistics
   for(int i=0; i<ArraySize(Symbols); i++) {
      string symbol = Symbols[i];
      PrintFormat("SMC Stats for %s: BOS events: %d, CHoCH events: %d, Market Regime: %s",
                  symbol, g_bos_count[i], g_choch_count[i], 
                  EnumToString(g_market_regime[i]));
   }
   
   //--- Clear chart objects created by this EA
   ObjectsDeleteAll(0, "BOS_", -1, -1);
   ObjectsDeleteAll(0, "CHOCH_", -1, -1);
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Process each symbol
   for(int i=0; i<ArraySize(Symbols); i++) {
      string symbol = Symbols[i];
      
      //--- Skip if invalid symbol
      if(!ExtSymbolInfo.Name(symbol)) continue;
      
      //--- Detect SMC structures
      DetectBreakOfStructure(symbol, i);
      DetectChangeOfCharacter(symbol, i);
      DetermineMarketRegime(symbol, i);
      
      //--- Check for open position
      if(HasOpenPosition(symbol)) {
         ManageTrailingStop(symbol);
         CheckPositionExpiration(symbol);
         CheckEarlyExitConditions(symbol, i);
         continue;
      }
      
      //--- Get strategy signal incorporating SMC
      int stratSignal = GetStrategySignal(symbol, i);
      
      //--- Execute trade if signal is valid
      if(stratSignal != 0) {
         double atr = iATR(symbol, PERIOD_CURRENT, ATRPeriod);
         double lot = CalculateLot(symbol, atr);
         ENUM_ORDER_TYPE type = (stratSignal == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         ExecuteTrade(symbol, type, lot, "Portfolio-SMC");
      }
      
      //--- Visualize SMC structures if enabled
      if(DrawSMCStructures) {
         VisualizeSMCStructures(symbol, i);
      }
   }
}

//+------------------------------------------------------------------+
//| Position Management Functions                                    |
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol)
{
   //--- Iterate through all positions
   for(int i=0; i<PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      
      //--- Check if position matches symbol and magic number
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   
   return false;
}

void ManageTrailingStop(string symbol)
{
   //--- Calculate ATR value
   double atr = iATR(symbol, _Period, ATRPeriod);
   
   //--- Get current price
   double price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   
   //--- Calculate new stop loss
   double oldSL = PositionGetDouble(POSITION_SL);
   double newSL;
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      newSL = price - ATRMultiplier * atr;
   else
      newSL = price + ATRMultiplier * atr;
   
   //--- Update stop loss if necessary
   if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSL > oldSL) || (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && newSL < oldSL)) {
      if(!ExtTrade.PositionModify(PositionGetInteger(POSITION_TICKET), newSL, PositionGetDouble(POSITION_TP))) {
         Print("[ERROR] Trailing stop modify failed for ", symbol);
      } else {
         Print("[INFO] Trailing stop updated for ", symbol);
      }
   }
}

void CheckPositionExpiration(string symbol)
{
   //--- Check if position duration is set
   if(PositionDuration <= 0) return;
   
   //--- Get position time
   datetime positionTime = (datetime)PositionGetInteger(POSITION_TIME);
   
   //--- Check if position has expired
   if(TimeCurrent() - positionTime >= PositionDuration * 60) {
      if(ExtTrade.PositionClose(symbol)) {
         Print("[INFO] Position closed for ", symbol, " due to duration expiration");
      } else {
         Print("[ERROR] Failed to close expired position for ", symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| Trade Execution Functions                                        |
//+------------------------------------------------------------------+
double CalculateLot(string symbol, double atrValue)
{
   //--- Calculate risk amount
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPerTrade / 100.0;
   
   //--- Calculate point value
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   //--- Calculate lot size
   double lot = risk / (atrValue * 10 * point);
   
   //--- Normalize lot size
   lot = MathMax(lot, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN));
   lot = MathMin(lot, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX));
   
   return NormalizeDouble(lot, 2);
}

bool ExecuteTrade(string symbol, ENUM_ORDER_TYPE type, double lot, string comment)
{
   //--- Check if symbol is valid
   if(!ExtSymbolInfo.Name(symbol)) {
      Print("Invalid symbol: ", symbol);
      return false;
   }
   
   //--- Refresh symbol rates
   ExtSymbolInfo.RefreshRates();
   
   //--- Calculate price and stop loss
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? price - ATRMultiplier * iATR(symbol, _Period, ATRPeriod) : price + ATRMultiplier * iATR(symbol, _Period, ATRPeriod);
   double tp = (type == ORDER_TYPE_BUY) ? price + ATRMultiplier * iATR(symbol, _Period, ATRPeriod) : price - ATRMultiplier * iATR(symbol, _Period, ATRPeriod);
   
   //--- Execute trade
   if(!ExtTrade.PositionOpen(symbol, type, lot, price, sl, tp, comment)) {
      Print("[ERROR] Trade open failed for ", symbol, ": ", ExtTrade.ResultRetcodeDescription());
      return false;
   } else {
      Print("[SUCCESS] Trade executed: ", symbol, " ", EnumToString(type), " ", lot, " lots");
      return true;
   }
}

//+------------------------------------------------------------------+
//| Strategy Signal Functions                                        |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Smart Money Concepts Detection Functions                          |
//+------------------------------------------------------------------+
void DetectBreakOfStructure(string symbol, int symbolIndex)
{
   //--- Get recent price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_CURRENT, 0, BOSLookback + 10, rates);
   if(copied < BOSLookback + 10) return;
   
   //--- Find swing highs and lows
   for(int i = 2; i < BOSLookback - 2; i++) {
      //--- Check for bullish BOS (break of a swing low)
      if(rates[i+1].low > rates[i].low && rates[i-1].low > rates[i].low && 
         rates[i+2].low > rates[i].low && rates[i-2].low > rates[i].low) {
         
         //--- Look for a break of this structure
         for(int j = 0; j < i-1; j++) {
            if(rates[j].close < rates[i].low) {
               //--- Bullish BOS detected
               if(g_bos_count[symbolIndex] < 20) { // Limit to array size
                  BOSEvent bos;
                  bos.time = rates[j].time;
                  bos.price = rates[j].close;
                  bos.strength = MathAbs(rates[j].close - rates[i].low) / (rates[i].high - rates[i].low);
                  bos.direction = 1; // Bullish
                  bos.bar_index = j;
                  bos.confirmed = false;
                  
                  //--- Only add if strength is above threshold
                  if(bos.strength >= BOSThreshold) {
                     g_bos_events[symbolIndex][g_bos_count[symbolIndex]] = bos;
                     g_bos_count[symbolIndex]++;
                     Print("[BOS] Bullish break of structure detected on ", symbol, " at ", TimeToString(rates[j].time));
                  }
                  break;
               }
            }
         }
      }
      
      //--- Check for bearish BOS (break of a swing high)
      if(rates[i+1].high < rates[i].high && rates[i-1].high < rates[i].high && 
         rates[i+2].high < rates[i].high && rates[i-2].high < rates[i].high) {
         
         //--- Look for a break of this structure
         for(int j = 0; j < i-1; j++) {
            if(rates[j].close > rates[i].high) {
               //--- Bearish BOS detected
               if(g_bos_count[symbolIndex] < 20) { // Limit to array size
                  BOSEvent bos;
                  bos.time = rates[j].time;
                  bos.price = rates[j].close;
                  bos.strength = MathAbs(rates[j].close - rates[i].high) / (rates[i].high - rates[i].low);
                  bos.direction = -1; // Bearish
                  bos.bar_index = j;
                  bos.confirmed = false;
                  
                  //--- Only add if strength is above threshold
                  if(bos.strength >= BOSThreshold) {
                     g_bos_events[symbolIndex][g_bos_count[symbolIndex]] = bos;
                     g_bos_count[symbolIndex]++;
                     Print("[BOS] Bearish break of structure detected on ", symbol, " at ", TimeToString(rates[j].time));
                  }
                  break;
               }
            }
         }
      }
   }
}

void DetectChangeOfCharacter(string symbol, int symbolIndex)
{
   //--- Get recent price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_CURRENT, 0, ChochLookback + 10, rates);
   if(copied < ChochLookback + 10) return;
   
   //--- Need at least one BOS event to detect CHoCH
   if(g_bos_count[symbolIndex] == 0) return;
   
   //--- Check for CHoCH following the most recent BOS
   BOSEvent recent_bos = g_bos_events[symbolIndex][g_bos_count[symbolIndex]-1];
   
   //--- For bullish BOS, look for price making a higher low
   if(recent_bos.direction == 1) {
      for(int i = 1; i < ChochLookback-1; i++) {
         //--- Check for a higher low after a bullish BOS
         if(rates[i].low > recent_bos.price && 
            rates[i+1].low > rates[i].low && rates[i-1].low > rates[i].low) {
            
            //--- Bullish CHoCH detected
            if(g_choch_count[symbolIndex] < 20) { // Limit to array size
               CHoCHEvent choch;
               choch.time = rates[i].time;
               choch.price = rates[i].low;
               choch.strength = MathAbs(rates[i].low - recent_bos.price) / MathAbs(recent_bos.price);
               choch.direction = 1; // Bullish
               choch.bar_index = i;
               choch.followed_bos = true;
               
               g_choch_events[symbolIndex][g_choch_count[symbolIndex]] = choch;
               g_choch_count[symbolIndex]++;
               
               //--- Mark BOS as confirmed
               g_bos_events[symbolIndex][g_bos_count[symbolIndex]-1].confirmed = true;
               
               Print("[CHoCH] Bullish change of character detected on ", symbol, " at ", TimeToString(rates[i].time));
               break;
            }
         }
      }
   }
   //--- For bearish BOS, look for price making a lower high
   else if(recent_bos.direction == -1) {
      for(int i = 1; i < ChochLookback-1; i++) {
         //--- Check for a lower high after a bearish BOS
         if(rates[i].high < recent_bos.price && 
            rates[i+1].high < rates[i].high && rates[i-1].high < rates[i].high) {
            
            //--- Bearish CHoCH detected
            if(g_choch_count[symbolIndex] < 20) { // Limit to array size
               CHoCHEvent choch;
               choch.time = rates[i].time;
               choch.price = rates[i].high;
               choch.strength = MathAbs(rates[i].high - recent_bos.price) / MathAbs(recent_bos.price);
               choch.direction = -1; // Bearish
               choch.bar_index = i;
               choch.followed_bos = true;
               
               g_choch_events[symbolIndex][g_choch_count[symbolIndex]] = choch;
               g_choch_count[symbolIndex]++;
               
               //--- Mark BOS as confirmed
               g_bos_events[symbolIndex][g_bos_count[symbolIndex]-1].confirmed = true;
               
               Print("[CHoCH] Bearish change of character detected on ", symbol, " at ", TimeToString(rates[i].time));
               break;
            }
         }
      }
   }
}

void DetermineMarketRegime(string symbol, int symbolIndex)
{
   //--- Get recent price data
   double ma_fast[], ma_slow[];
   ArraySetAsSeries(ma_fast, true);
   ArraySetAsSeries(ma_slow, true);
   
   //--- Calculate moving averages for regime determination
   int copied_fast = CopyBuffer(iMA(symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 3, ma_fast);
   int copied_slow = CopyBuffer(iMA(symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 3, ma_slow);
   
   if(copied_fast < 3 || copied_slow < 3) return;
   
   //--- Determine market regime based on moving averages
   if(ma_fast[0] > ma_slow[0] && ma_fast[1] > ma_slow[1]) {
      g_market_regime[symbolIndex] = REGIME_BULLISH;
   }
   else if(ma_fast[0] < ma_slow[0] && ma_fast[1] < ma_slow[1]) {
      g_market_regime[symbolIndex] = REGIME_BEARISH;
   }
   else {
      g_market_regime[symbolIndex] = REGIME_NEUTRAL;
   }
}

//--- Visualize the SMC structures on the chart
void VisualizeSMCStructures(string symbol, int symbolIndex)
{
   //--- Draw BOS events
   for(int i=0; i<g_bos_count[symbolIndex]; i++) {
      BOSEvent bos = g_bos_events[symbolIndex][i];
      string objName = "BOS_" + symbol + "_" + TimeToString(bos.time);
      
      //--- Create or update arrow object
      if(ObjectFind(0, objName) < 0) {
         ObjectCreate(0, objName, OBJ_ARROW, 0, bos.time, bos.price);
         ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, bos.direction > 0 ? 233 : 234); // Up/down arrow
         ObjectSetInteger(0, objName, OBJPROP_COLOR, bos.direction > 0 ? clrGreen : clrRed);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
         ObjectSetString(0, objName, OBJPROP_TOOLTIP, "BOS " + (bos.direction > 0 ? "Bullish" : "Bearish") + 
                         "\nStrength: " + DoubleToString(bos.strength, 2));
      }
   }
   
   //--- Draw CHoCH events
   for(int i=0; i<g_choch_count[symbolIndex]; i++) {
      CHoCHEvent choch = g_choch_events[symbolIndex][i];
      string objName = "CHOCH_" + symbol + "_" + TimeToString(choch.time);
      
      //--- Create or update arrow object
      if(ObjectFind(0, objName) < 0) {
         ObjectCreate(0, objName, OBJ_ARROW, 0, choch.time, choch.price);
         ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, choch.direction > 0 ? 225 : 226); // Up/down arrow
         ObjectSetInteger(0, objName, OBJPROP_COLOR, choch.direction > 0 ? clrLime : clrOrange);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
         ObjectSetString(0, objName, OBJPROP_TOOLTIP, "CHoCH " + (choch.direction > 0 ? "Bullish" : "Bearish") + 
                         "\nStrength: " + DoubleToString(choch.strength, 2));
      }
   }
}

//--- Check for early exit conditions based on SMC
void CheckEarlyExitConditions(string symbol, int symbolIndex)
{
   //--- Skip if no open position or no recent SMC events
   if(!HasOpenPosition(symbol) || g_bos_count[symbolIndex] == 0) return;
   
   //--- Get position type
   long posType = -1;
   for(int i=0; i<PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == symbol && 
         PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         posType = PositionGetInteger(POSITION_TYPE);
         break;
      }
   }
   
   if(posType == -1) return;
   
   //--- Check for counter-trend BOS that would warrant early exit
   BOSEvent recent_bos = g_bos_events[symbolIndex][g_bos_count[symbolIndex]-1];
   
   //--- For a buy position, exit on bearish BOS
   if(posType == POSITION_TYPE_BUY && recent_bos.direction == -1 && recent_bos.strength >= 0.7) {
      Print("[Exit] Early exit from BUY due to strong bearish BOS on ", symbol);
      ExtTrade.PositionClose(symbol);
   }
   //--- For a sell position, exit on bullish BOS
   else if(posType == POSITION_TYPE_SELL && recent_bos.direction == 1 && recent_bos.strength >= 0.7) {
      Print("[Exit] Early exit from SELL due to strong bullish BOS on ", symbol);
      ExtTrade.PositionClose(symbol);
   }
   
   //--- Also check for CHoCH in opposite direction
   if(g_choch_count[symbolIndex] > 0) {
      CHoCHEvent recent_choch = g_choch_events[symbolIndex][g_choch_count[symbolIndex]-1];
      
      //--- For a buy position, exit on bearish CHoCH
      if(posType == POSITION_TYPE_BUY && recent_choch.direction == -1 && recent_choch.followed_bos) {
         Print("[Exit] Early exit from BUY due to confirmed bearish CHoCH on ", symbol);
         ExtTrade.PositionClose(symbol);
      }
      //--- For a sell position, exit on bullish CHoCH
      else if(posType == POSITION_TYPE_SELL && recent_choch.direction == 1 && recent_choch.followed_bos) {
         Print("[Exit] Early exit from SELL due to confirmed bullish CHoCH on ", symbol);
         ExtTrade.PositionClose(symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| Strategy Signal Functions                                        |
//+------------------------------------------------------------------+
int GetStrategySignal(string symbol, int symbolIndex)
{
   //--- Combine traditional strategies with SMC insights
   int momentum_signal = CalculateMomentumSignal(symbol);
   int meanrev_signal = CalculateMeanReversionSignal(symbol);
   int breakout_signal = CalculateBreakoutSignal(symbol);
   
   //--- Apply strategy weights
   double weighted_signal = momentum_signal * MomentumWeight + 
                           meanrev_signal * MeanReversionWeight + 
                           breakout_signal * BreakoutWeight;
   
   //--- Apply SMC filters and confirmation
   //--- Only trade in the direction of the market regime
   if(g_market_regime[symbolIndex] == REGIME_BULLISH && weighted_signal < 0) {
      return 0; // Filter out sell signals in bullish regime
   }
   else if(g_market_regime[symbolIndex] == REGIME_BEARISH && weighted_signal > 0) {
      return 0; // Filter out buy signals in bearish regime
   }
   
   //--- Use SMC events for signal confirmation
   if(g_bos_count[symbolIndex] > 0) {
      BOSEvent recent_bos = g_bos_events[symbolIndex][g_bos_count[symbolIndex]-1];
      
      //--- BOS confirmation - if signal matches BOS direction, enhance it
      if(weighted_signal > 0 && recent_bos.direction > 0) {
         weighted_signal += recent_bos.strength;
      }
      else if(weighted_signal < 0 && recent_bos.direction < 0) {
         weighted_signal -= recent_bos.strength;
      }
      //--- If signal contradicts recent strong BOS, reduce its strength
      else if(weighted_signal > 0 && recent_bos.direction < 0 && recent_bos.strength > 0.7) {
         weighted_signal *= (1.0 - recent_bos.strength);
      }
      else if(weighted_signal < 0 && recent_bos.direction > 0 && recent_bos.strength > 0.7) {
         weighted_signal *= (1.0 - recent_bos.strength);
      }
   }
   
   //--- CHoCH provides even stronger confirmation when it follows BOS
   if(g_choch_count[symbolIndex] > 0) {
      CHoCHEvent recent_choch = g_choch_events[symbolIndex][g_choch_count[symbolIndex]-1];
      
      if(weighted_signal > 0 && recent_choch.direction > 0 && recent_choch.followed_bos) {
         weighted_signal += recent_choch.strength * ChochWeight;
      }
      else if(weighted_signal < 0 && recent_choch.direction < 0 && recent_choch.followed_bos) {
         weighted_signal -= recent_choch.strength * ChochWeight;
      }
   }
   
   //--- Apply final thresholding to get trade signal
   if(weighted_signal > 0.5) {
      return 1;  // Buy signal
   }
   else if(weighted_signal < -0.5) {
      return -1; // Sell signal
   }
   
   return 0; // No signal
}

//--- Sub-strategy signal calculations
int CalculateMomentumSignal(string symbol)
{
   //--- Simple momentum based on MACD
   double macd_main[], macd_signal[];
   ArraySetAsSeries(macd_main, true);
   ArraySetAsSeries(macd_signal, true);
   
   int copied = CopyBuffer(iMACD(symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE), 0, 0, 3, macd_main);
   int copied_signal = CopyBuffer(iMACD(symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE), 1, 0, 3, macd_signal);
   
   if(copied < 3 || copied_signal < 3) return 0;
   
   //--- MACD crossover logic
   if(macd_main[1] < macd_signal[1] && macd_main[0] > macd_signal[0]) {
      return 1;  // Bullish crossover
   }
   else if(macd_main[1] > macd_signal[1] && macd_main[0] < macd_signal[0]) {
      return -1; // Bearish crossover
   }
   
   return 0;
}

int CalculateMeanReversionSignal(string symbol)
{
   //--- Mean reversion based on RSI
   double rsi[];
   ArraySetAsSeries(rsi, true);
   
   int copied = CopyBuffer(iRSI(symbol, PERIOD_CURRENT, 14, PRICE_CLOSE), 0, 0, 3, rsi);
   
   if(copied < 3) return 0;
   
   //--- RSI oversold/overbought conditions
   if(rsi[0] < 30 && rsi[1] < 30 && rsi[0] > rsi[1]) {
      return 1;  // Oversold and starting to rise
   }
   else if(rsi[0] > 70 && rsi[1] > 70 && rsi[0] < rsi[1]) {
      return -1; // Overbought and starting to fall
   }
   
   return 0;
}

int CalculateBreakoutSignal(string symbol)
{
   //--- Breakout based on Bollinger Bands
   double upper[], lower[], middle[];
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(lower, true);
   ArraySetAsSeries(middle, true);
   
   int handle = iBands(symbol, PERIOD_CURRENT, 20, 2, 0, PRICE_CLOSE);
   int copied_up = CopyBuffer(handle, 1, 0, 3, upper);
   int copied_low = CopyBuffer(handle, 2, 0, 3, lower);
   int copied_mid = CopyBuffer(handle, 0, 0, 3, middle);
   
   if(copied_up < 3 || copied_low < 3 || copied_mid < 3) return 0;
   
   //--- Get price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied_rates = CopyRates(symbol, PERIOD_CURRENT, 0, 3, rates);
   
   if(copied_rates < 3) return 0;
   
   //--- Breakout logic with confirmation
   if(rates[1].close <= upper[1] && rates[0].close > upper[0] && rates[0].close > rates[1].close) {
      return 1;  // Bullish breakout
   }
   else if(rates[1].close >= lower[1] && rates[0].close < lower[0] && rates[0].close < rates[1].close) {
      return -1; // Bearish breakout
   }
   
   return 0;
}