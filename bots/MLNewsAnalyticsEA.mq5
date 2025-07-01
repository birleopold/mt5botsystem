//+------------------------------------------------------------------+
//|                      MLNewsAnalyticsEA.mq5                       |
//|         ML+News Trading with Robust Risk Management              |
//+------------------------------------------------------------------+
#property version   "1.11"
#property strict

//+------------------------------------------------------------------+
//| Best Practice Headers                                             |
//+------------------------------------------------------------------+
// 1. Always use meaningful variable names
// 2. Use comments to explain complex logic
// 3. Keep functions short and focused
// 4. Use error handling and logging
// 5. Test thoroughly before deploying

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input string InpMLSignalFile = "C:/MT5Signals/ml_signals.csv";  // ML signals CSV
input string InpNewsFile     = "C:/MT5Signals/news.csv";        // News data CSV
input string InpLogFile      = "C:/MT5Signals/trade_log.csv";   // Trade log CSV
input uint   InpSlippage      = 3;          // Slippage in points
input uint   InpDuration      = 1440;       // Position duration in minutes
input double InpATRMultiplier = 2.0;        // ATR multiplier for stops
input int    InpATRPeriod     = 14;         // ATR period
input double InpRiskPerTrade  = 1.0;        // Risk % per trade
input long   InpMagicNumber   = 700001;     // Unique EA identifier

//+------------------------------------------------------------------+
//| Symbol Configuration                                              |
//+------------------------------------------------------------------+
string ExtSymbols[] = {"EURUSD","GBPUSD","USDJPY"};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int    ExtATRHandles[];
CTrade       ExtTrade;
CSymbolInfo  ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize trading objects
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippage);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   
   //--- Initialize ATR handles for each symbol
   ArrayResize(ExtATRHandles, ArraySize(ExtSymbols));
   for(int i=0; i<ArraySize(ExtSymbols); i++)
      ExtATRHandles[i] = iATR(ExtSymbols[i], _Period, InpATRPeriod);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   for(int i=0; i<ArraySize(ExtATRHandles); i++)
      if(ExtATRHandles[i] != INVALID_HANDLE) IndicatorRelease(ExtATRHandles[i]);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   for(int i=0; i<ArraySize(ExtSymbols); i++) {
      string symbol = ExtSymbols[i];
      if(!ExtSymbolInfo.Name(symbol)) continue;
      
      //--- Check for existing positions
      if(PositionSelect(symbol)) {
         ManageTrailingStop(symbol, i);
         CheckPositionExpiration(symbol);
         continue;
      }
      
      //--- Get ML/news signal
      int signal = GetMLNewsSignal(symbol);
      if(signal == 1 || signal == -1) {
         double atr[];
         if(CopyBuffer(ExtATRHandles[i], 0, 0, 2, atr) <= 0) continue;
         ExecuteTrade(symbol, (signal == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, atr[1]);
      }
   }
}

//+------------------------------------------------------------------+
//| Get ML/news signal                                               |
//+------------------------------------------------------------------+
int GetMLNewsSignal(string symbol)
{
   // Placeholder: Replace with real ML/news logic
   static int flip = 1;
   flip = -flip;
   return flip;
}

//+------------------------------------------------------------------+
//| Execute trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, ENUM_ORDER_TYPE type, double atrValue)
{
   ExtSymbolInfo.Name(symbol);
   ExtSymbolInfo.RefreshRates();
   
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? price - InpATRMultiplier * atrValue : price + InpATRMultiplier * atrValue;
   double tp = (type == ORDER_TYPE_BUY) ? price + InpATRMultiplier * atrValue : price - InpATRMultiplier * atrValue;
   double lot = CalculateLot(symbol, atrValue);
   
   if(!ExtTrade.PositionOpen(symbol, type, lot, price, sl, tp, "MLNews")) {
      Print("[ERROR] Trade open failed for ", symbol, ": ", ExtTrade.ResultRetcodeDescription());
      Alert("[ERROR] Trade open failed for ", symbol, ": ", ExtTrade.ResultRetcodeDescription());
   } else {
      Print("[SUCCESS] Trade executed: ", symbol, " ", EnumToString(type), " ", lot, " lots");
      Alert("[SUCCESS] Trade executed: ", symbol, " ", EnumToString(type), " ", lot, " lots");
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                               |
//+------------------------------------------------------------------+
double CalculateLot(string symbol, double atrValue)
{
   CSymbolInfo info; info.Name(symbol);
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   double lot = risk / (atrValue * 10 * info.Point());
   lot = MathMax(lot, info.LotsMin());
   lot = MathMin(lot, info.LotsMax());
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Manage trailing stop                                              |
//+------------------------------------------------------------------+
void ManageTrailingStop(string symbol, int idx)
{
   double atr[];
   if(CopyBuffer(ExtATRHandles[idx], 0, 0, 1, atr) <= 0) return;
   ExtSymbolInfo.Name(symbol);
   ExtSymbolInfo.RefreshRates();
   double price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   double oldSL = PositionGetDouble(POSITION_SL);
   double newSL;
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      newSL = price - InpATRMultiplier * atr[0];
   else
      newSL = price + InpATRMultiplier * atr[0];
   if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSL > oldSL) || (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && newSL < oldSL)) {
      if(!ExtTrade.PositionModify(PositionGetInteger(POSITION_TICKET), newSL, PositionGetDouble(POSITION_TP))) {
         Print("[ERROR] Trailing stop modify failed for ", symbol);
         Alert("[ERROR] Trailing stop modify failed for ", symbol);
      } else {
         Print("[INFO] Trailing stop updated for ", symbol);
         Alert("[INFO] Trailing stop updated for ", symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| Check position expiration                                        |
//+------------------------------------------------------------------+
void CheckPositionExpiration(string symbol)
{
   if(InpDuration <= 0) return;
   datetime positionTime = (datetime)PositionGetInteger(POSITION_TIME);
   if(TimeCurrent() - positionTime >= InpDuration * 60) {
      if(ExtTrade.PositionClose(symbol)) {
         Print("[INFO] Position closed for ", symbol, " due to duration expiration");
         Alert("[INFO] Position closed for ", symbol, " due to duration expiration");
      } else {
         Print("[ERROR] Failed to close expired position for ", symbol);
         Alert("[ERROR] Failed to close expired position for ", symbol);
      }
   }
}