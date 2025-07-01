//+------------------------------------------------------------------+
//| Adaptive Portfolio Manager EA for MT5                           |
//| Robust multi-strategy, dynamic allocation, risk controls        |
//+------------------------------------------------------------------+
#property version   "2.01"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

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

// Arrays to store SMC events for each symbol
SwingPoint swingPoints[][100];   // Store up to 100 swing points per symbol
BOSEvent   bosEvents[][50];      // Store up to 50 BOS events per symbol
CHoCHEvent chochEvents[][50];    // Store up to 50 CHoCH events per symbol

// Counters for each type of event per symbol
int swingPointCount[];  // Count of swing points for each symbol
int bosEventCount[];    // Count of BOS events for each symbol
int chochEventCount[];  // Count of CHoCH events for each symbol

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
   
   //--- Initialize SMC arrays based on number of symbols
   int symbolCount = ArraySize(Symbols);
   ArrayResize(swingPointCount, symbolCount);
   ArrayResize(bosEventCount, symbolCount);
   ArrayResize(chochEventCount, symbolCount);
   
   //--- Initialize counters
   for(int i=0; i<symbolCount; i++) {
      swingPointCount[i] = 0;
      bosEventCount[i] = 0;
      chochEventCount[i] = 0;
   }
   
   Print("[INFO] Smart Money Concepts features initialized for ", symbolCount, " symbols");
   
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
      
      //--- Run SMC detection for this symbol
      DetectSwingPoints(symbol, i);
      DetectBreakOfStructure(symbol, i);
      DetectChangeOfCharacter(symbol, i);
      
      //--- Check for open position
      if(HasOpenPosition(symbol)) {
         ManageTrailingStop(symbol);
         CheckPositionExpiration(symbol);
         continue;
      }
      
      //--- Get strategy signal enhanced with SMC events
      int stratSignal = GetStrategySignal(symbol);
      
      //--- Execute trade if signal is valid
      if(stratSignal != 0) {
         double atr = iATR(symbol, _Period, ATRPeriod);
         double lot = CalculateLot(symbol, atr);
         ENUM_ORDER_TYPE type = (stratSignal == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         
         //--- Add SMC event type to trade comment for tracking performance
         string comment = "Portfolio";
         int symIdx = i;
         datetime recentTime = iTime(symbol, _Period, 5);
         
         //--- Check which SMC event triggered this trade
         for(int b=0; b<bosEventCount[symIdx]; b++) {
            if(bosEvents[symIdx][b].time >= recentTime) {
               comment += "-BOS";
               break;
            }
         }
         
         for(int c=0; c<chochEventCount[symIdx]; c++) {
            if(chochEvents[symIdx][c].time >= recentTime) {
               comment += "-CHoCH";
               break;
            }
         }
         
         ExecuteTrade(symbol, type, lot, comment);
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
   
   //--- Get symbol index for SMC data
   int symbolIndex = -1;
   for(int i=0; i<ArraySize(Symbols); i++) {
      if(Symbols[i] == symbol) {
         symbolIndex = i;
         break;
      }
   }
   
   //--- Check for opposing SMC events that might warrant an early exit
   if(symbolIndex >= 0) {
      bool hasOpposingSignal = false;
      datetime recentTime = iTime(symbol, _Period, 3); // Look for very recent opposing signals
      
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
         //--- Check for bearish signals that oppose our long position
         for(int i=0; i<bosEventCount[symbolIndex]; i++) {
            if(!bosEvents[symbolIndex][i].isBullish && bosEvents[symbolIndex][i].time >= recentTime && bosEvents[symbolIndex][i].strength >= 5.0) {
               hasOpposingSignal = true;
               Print("[SMC] Strong bearish BOS detected while in long position for ", symbol, ". Consider early exit.");
               break;
            }
         }
         
         if(!hasOpposingSignal) {
            for(int i=0; i<chochEventCount[symbolIndex]; i++) {
               if(!chochEvents[symbolIndex][i].isBullish && chochEvents[symbolIndex][i].time >= recentTime && chochEvents[symbolIndex][i].strength >= 5.0) {
                  hasOpposingSignal = true;
                  Print("[SMC] Strong bearish CHoCH detected while in long position for ", symbol, ". Consider early exit.");
                  break;
               }
            }
         }
      }
      else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
         //--- Check for bullish signals that oppose our short position
         for(int i=0; i<bosEventCount[symbolIndex]; i++) {
            if(bosEvents[symbolIndex][i].isBullish && bosEvents[symbolIndex][i].time >= recentTime && bosEvents[symbolIndex][i].strength >= 5.0) {
               hasOpposingSignal = true;
               Print("[SMC] Strong bullish BOS detected while in short position for ", symbol, ". Consider early exit.");
               break;
            }
         }
         
         if(!hasOpposingSignal) {
            for(int i=0; i<chochEventCount[symbolIndex]; i++) {
               if(chochEvents[symbolIndex][i].isBullish && chochEvents[symbolIndex][i].time >= recentTime && chochEvents[symbolIndex][i].strength >= 5.0) {
                  hasOpposingSignal = true;
                  Print("[SMC] Strong bullish CHoCH detected while in short position for ", symbol, ". Consider early exit.");
                  break;
               }
            }
         }
      }
      
      //--- Close position early if strong opposing signal detected
      if(hasOpposingSignal) {
         if(ExtTrade.PositionClose(PositionGetTicket(0))) {
            Print("[INFO] Position closed early for ", symbol, " due to opposing SMC signal");
            return; // Exit function as position is closed
         }
      }
   }
   
   //--- Calculate new stop loss (more aggressive if recent confirming SMC events are present)
   double oldSL = PositionGetDouble(POSITION_SL);
   double newSL;
   double multiplier = ATRMultiplier;
   
   //--- Use more aggressive trailing if there are confirming SMC events
   if(symbolIndex >= 0) {
      datetime recentTime = iTime(symbol, _Period, 3);
      bool hasConfirmingSignal = false;
      
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
         //--- Check for confirming bullish signals
         for(int i=0; i<bosEventCount[symbolIndex]; i++) {
            if(bosEvents[symbolIndex][i].isBullish && bosEvents[symbolIndex][i].time >= recentTime) {
               hasConfirmingSignal = true;
               multiplier = ATRMultiplier * 0.8; // More aggressive (tighter) trailing
               break;
            }
         }
         
         if(!hasConfirmingSignal) {
            for(int i=0; i<chochEventCount[symbolIndex]; i++) {
               if(chochEvents[symbolIndex][i].isBullish && chochEvents[symbolIndex][i].time >= recentTime) {
                  hasConfirmingSignal = true;
                  multiplier = ATRMultiplier * 0.7; // Even more aggressive for CHoCH
                  break;
               }
            }
         }
      }
      else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
         //--- Check for confirming bearish signals
         for(int i=0; i<bosEventCount[symbolIndex]; i++) {
            if(!bosEvents[symbolIndex][i].isBullish && bosEvents[symbolIndex][i].time >= recentTime) {
               hasConfirmingSignal = true;
               multiplier = ATRMultiplier * 0.8; // More aggressive (tighter) trailing
               break;
            }
         }
         
         if(!hasConfirmingSignal) {
            for(int i=0; i<chochEventCount[symbolIndex]; i++) {
               if(!chochEvents[symbolIndex][i].isBullish && chochEvents[symbolIndex][i].time >= recentTime) {
                  hasConfirmingSignal = true;
                  multiplier = ATRMultiplier * 0.7; // Even more aggressive for CHoCH
                  break;
               }
            }
         }
      }
   }
   
   //--- Calculate new stop loss with adjusted multiplier
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      newSL = price - multiplier * atr;
   else
      newSL = price + multiplier * atr;
   
   //--- Update stop loss if necessary
   if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSL > oldSL) || (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && newSL < oldSL)) {
      if(!ExtTrade.PositionModify(PositionGetInteger(POSITION_TICKET), newSL, PositionGetDouble(POSITION_TP))) {
         Print("[ERROR] Trailing stop modify failed for ", symbol);
      } else {
         Print("[INFO] Trailing stop updated for ", symbol, ", using multiplier: ", DoubleToString(multiplier, 2));
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
//| Smart Money Concepts (SMC) Detection Functions                   |
//+------------------------------------------------------------------+

//--- Function to detect swing points in the price action
void DetectSwingPoints(string symbol, int symbolIndex, int lookbackBars = 20)
{
   //--- Get highs and lows
   double highs[], lows[];
   ArrayResize(highs, lookbackBars);
   ArrayResize(lows, lookbackBars);
   
   for(int i=0; i<lookbackBars; i++) {
      highs[i] = iHigh(symbol, _Period, i);
      lows[i] = iLow(symbol, _Period, i);
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
         if(swingPointCount[symbolIndex] < 100) {
            swingPoints[symbolIndex][swingPointCount[symbolIndex]].time = iTime(symbol, _Period, i);
            swingPoints[symbolIndex][swingPointCount[symbolIndex]].price = highs[i];
            swingPoints[symbolIndex][swingPointCount[symbolIndex]].isHigh = true;
            swingPoints[symbolIndex][swingPointCount[symbolIndex]].strength = strength;
            swingPointCount[symbolIndex]++;
            
            Print("[SMC] New swing high detected for ", symbol, " at price ", DoubleToString(highs[i], 5));
         }
      }
      
      //--- Swing low detection
      if(lows[i] < lows[i-1] && lows[i] < lows[i-2] && lows[i] < lows[i+1] && lows[i] < lows[i+2]) {
         //--- Calculate strength based on surrounding bars
         int strength = 1;
         if(lows[i] < lows[i-3]) strength++;
         if(lows[i] < lows[i+3]) strength++;
         
         //--- Add a swing low if we have room in the array
         if(swingPointCount[symbolIndex] < 100) {
            swingPoints[symbolIndex][swingPointCount[symbolIndex]].time = iTime(symbol, _Period, i);
            swingPoints[symbolIndex][swingPointCount[symbolIndex]].price = lows[i];
            swingPoints[symbolIndex][swingPointCount[symbolIndex]].isHigh = false;
            swingPoints[symbolIndex][swingPointCount[symbolIndex]].strength = strength;
            swingPointCount[symbolIndex]++;
            
            Print("[SMC] New swing low detected for ", symbol, " at price ", DoubleToString(lows[i], 5));
         }
      }
   }
   
   //--- Limit the number of swing points by removing older ones if necessary
   if(swingPointCount[symbolIndex] > 50) {
      for(int i=0; i<swingPointCount[symbolIndex]-50; i++) {
         for(int j=0; j<swingPointCount[symbolIndex]-1; j++) {
            swingPoints[symbolIndex][j] = swingPoints[symbolIndex][j+1];
         }
         swingPointCount[symbolIndex]--;
      }
   }
}

//--- Function to detect Break of Structure (BOS) events
void DetectBreakOfStructure(string symbol, int symbolIndex)
{
   //--- Need at least a few swing points to detect BOS
   if(swingPointCount[symbolIndex] < 5) return;
   
   //--- Get current price
   double currentPrice = iClose(symbol, _Period, 0);
   datetime currentTime = iTime(symbol, _Period, 0);
   
   //--- Look for price breaking above significant swing highs (bullish BOS)
   for(int i=0; i<swingPointCount[symbolIndex]; i++) {
      if(swingPoints[symbolIndex][i].isHigh) {
         if(currentPrice > swingPoints[symbolIndex][i].price) {
            //--- Check if this is a new BOS (not already recorded)
            bool isNewBOS = true;
            for(int j=0; j<bosEventCount[symbolIndex]; j++) {
               if(bosEvents[symbolIndex][j].swingIndex == i) {
                  isNewBOS = false;
                  break;
               }
            }
            
            if(isNewBOS && bosEventCount[symbolIndex] < 50) {
               double bosStrength = swingPoints[symbolIndex][i].strength * 1.0;
               
               //--- Calculate additional strength based on volume
               double currentVolume = iVolume(symbol, _Period, 0);
               double avgVolume = 0;
               for(int v=1; v<=10; v++) avgVolume += iVolume(symbol, _Period, v);
               avgVolume /= 10;
               
               if(currentVolume > avgVolume * 1.5) bosStrength *= 1.5;
               
               //--- Record the BOS event
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].time = currentTime;
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].price = currentPrice;
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].isBullish = true;
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].strength = bosStrength;
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].swingIndex = i;
               bosEventCount[symbolIndex]++;
               
               Print("[SMC] Bullish BOS detected for ", symbol, " at price ", DoubleToString(currentPrice, 5), ", strength: ", DoubleToString(bosStrength, 1));
            }
         }
      }
   }
   
   //--- Look for price breaking below significant swing lows (bearish BOS)
   for(int i=0; i<swingPointCount[symbolIndex]; i++) {
      if(!swingPoints[symbolIndex][i].isHigh) {
         if(currentPrice < swingPoints[symbolIndex][i].price) {
            //--- Check if this is a new BOS (not already recorded)
            bool isNewBOS = true;
            for(int j=0; j<bosEventCount[symbolIndex]; j++) {
               if(bosEvents[symbolIndex][j].swingIndex == i) {
                  isNewBOS = false;
                  break;
               }
            }
            
            if(isNewBOS && bosEventCount[symbolIndex] < 50) {
               double bosStrength = swingPoints[symbolIndex][i].strength * 1.0;
               
               //--- Calculate additional strength based on volume
               double currentVolume = iVolume(symbol, _Period, 0);
               double avgVolume = 0;
               for(int v=1; v<=10; v++) avgVolume += iVolume(symbol, _Period, v);
               avgVolume /= 10;
               
               if(currentVolume > avgVolume * 1.5) bosStrength *= 1.5;
               
               //--- Record the BOS event
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].time = currentTime;
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].price = currentPrice;
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].isBullish = false;
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].strength = bosStrength;
               bosEvents[symbolIndex][bosEventCount[symbolIndex]].swingIndex = i;
               bosEventCount[symbolIndex]++;
               
               Print("[SMC] Bearish BOS detected for ", symbol, " at price ", DoubleToString(currentPrice, 5), ", strength: ", DoubleToString(bosStrength, 1));
            }
         }
      }
   }
}

//--- Function to detect Change of Character (CHoCH) events
void DetectChangeOfCharacter(string symbol, int symbolIndex)
{
   //--- Need BOS events to detect CHoCH
   if(bosEventCount[symbolIndex] < 3) return;
   
   double currentPrice = iClose(symbol, _Period, 0);
   datetime currentTime = iTime(symbol, _Period, 0);
   
   //--- For each BOS event, check for a change of character
   for(int i=0; i<bosEventCount[symbolIndex]; i++) {
      //--- For bullish BOS, look for price coming back to retest and then continuing higher
      if(bosEvents[symbolIndex][i].isBullish) {
         //--- Check if price retraced back to BOS level and then moved higher again
         double bosLevel = bosEvents[symbolIndex][i].price;
         bool wasBelow = false;
         
         //--- Check if price has retested the BOS level
         for(int j=5; j>0; j--) {
            if(iLow(symbol, _Period, j) <= bosLevel) {
               wasBelow = true;
               break;
            }
         }
         
         //--- If it retested and is now moving up, it's a CHoCH
         if(wasBelow && currentPrice > bosLevel) {
            //--- Check if this CHoCH is already recorded
            bool isNewCHoCH = true;
            for(int j=0; j<chochEventCount[symbolIndex]; j++) {
               if(chochEvents[symbolIndex][j].bosIndex == i) {
                  isNewCHoCH = false;
                  break;
               }
            }
            
            if(isNewCHoCH && chochEventCount[symbolIndex] < 50) {
               double chochStrength = bosEvents[symbolIndex][i].strength * 1.2;
               
               //--- Record the CHoCH event
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].time = currentTime;
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].price = currentPrice;
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].isBullish = true;
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].strength = chochStrength;
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].bosIndex = i;
               chochEventCount[symbolIndex]++;
               
               Print("[SMC] Bullish CHoCH detected for ", symbol, " at price ", DoubleToString(currentPrice, 5), ", strength: ", DoubleToString(chochStrength, 1));
            }
         }
      }
      //--- For bearish BOS, look for price coming back to retest and then continuing lower
      else {
         //--- Check if price retraced back to BOS level and then moved lower again
         double bosLevel = bosEvents[symbolIndex][i].price;
         bool wasAbove = false;
         
         //--- Check if price has retested the BOS level
         for(int j=5; j>0; j--) {
            if(iHigh(symbol, _Period, j) >= bosLevel) {
               wasAbove = true;
               break;
            }
         }
         
         //--- If it retested and is now moving down, it's a CHoCH
         if(wasAbove && currentPrice < bosLevel) {
            //--- Check if this CHoCH is already recorded
            bool isNewCHoCH = true;
            for(int j=0; j<chochEventCount[symbolIndex]; j++) {
               if(chochEvents[symbolIndex][j].bosIndex == i) {
                  isNewCHoCH = false;
                  break;
               }
            }
            
            if(isNewCHoCH && chochEventCount[symbolIndex] < 50) {
               double chochStrength = bosEvents[symbolIndex][i].strength * 1.2;
               
               //--- Record the CHoCH event
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].time = currentTime;
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].price = currentPrice;
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].isBullish = false;
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].strength = chochStrength;
               chochEvents[symbolIndex][chochEventCount[symbolIndex]].bosIndex = i;
               chochEventCount[symbolIndex]++;
               
               Print("[SMC] Bearish CHoCH detected for ", symbol, " at price ", DoubleToString(currentPrice, 5), ", strength: ", DoubleToString(chochStrength, 1));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Strategy Signal Functions                                        |
//+------------------------------------------------------------------+
int GetStrategySignal(string symbol)
{
   //--- Get index of the symbol in our arrays
   int symbolIndex = -1;
   for(int i=0; i<ArraySize(Symbols); i++) {
      if(Symbols[i] == symbol) {
         symbolIndex = i;
         break;
      }
   }
   
   if(symbolIndex == -1) return 0; // Symbol not found
   
   //--- Look for recent BOS and CHoCH events (last 5 bars)
   bool recentBullishBOS = false;
   bool recentBearishBOS = false;
   bool recentBullishCHoCH = false;
   bool recentBearishCHoCH = false;
   double bullishStrength = 0;
   double bearishStrength = 0;
   
   datetime recentTime = iTime(symbol, _Period, 5); // Events in the last 5 bars
   
   //--- Check for recent BOS events
   for(int i=0; i<bosEventCount[symbolIndex]; i++) {
      if(bosEvents[symbolIndex][i].time >= recentTime) {
         if(bosEvents[symbolIndex][i].isBullish) {
            recentBullishBOS = true;
            bullishStrength += bosEvents[symbolIndex][i].strength;
         } else {
            recentBearishBOS = true;
            bearishStrength += bosEvents[symbolIndex][i].strength;
         }
      }
   }
   
   //--- Check for recent CHoCH events (these are more significant)
   for(int i=0; i<chochEventCount[symbolIndex]; i++) {
      if(chochEvents[symbolIndex][i].time >= recentTime) {
         if(chochEvents[symbolIndex][i].isBullish) {
            recentBullishCHoCH = true;
            bullishStrength += chochEvents[symbolIndex][i].strength * 1.5; // CHoCH gets 1.5x weight
         } else {
            recentBearishCHoCH = true;
            bearishStrength += chochEvents[symbolIndex][i].strength * 1.5; // CHoCH gets 1.5x weight
         }
      }
   }
   
   //--- Generate signal based on SMC events
   if((recentBullishBOS || recentBullishCHoCH) && bullishStrength > bearishStrength) {
      return 1; // Buy signal
   } else if((recentBearishBOS || recentBearishCHoCH) && bearishStrength > bullishStrength) {
      return -1; // Sell signal
   }
   
   //--- No strong SMC signal, revert to basic strategy logic
   //--- For demo, alternate signals
   static int flip = 1;
   flip = -flip;
   return flip;
}