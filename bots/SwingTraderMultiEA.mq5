//+------------------------------------------------------------------+
//|                  SwingTraderMultiEA.mq5                          |
//|         Multi-Symbol Swing Trading with Robust Risk Control      |
//+------------------------------------------------------------------+
#property version   "1.08"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input string InpSymbols = "EURUSD,GBPUSD"; // Symbols to trade
input int    InpTrendMAPeriod   = 50;
input int    InpSignalMAPeriod  = 14;
input int    InpATRPeriod       = 14;
input double InpATRMultiplier   = 2.0;
input double InpTPMultiplier    = 3.0;
input double InpRiskPerTrade    = 1.0;
input uint   InpSlippage        = 5;
input uint   InpDuration        = 1440;
input long   InpMagicNumber     = 900002;

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
string ExtSymbols[];
int    ExtTrendMAHandles[];
int    ExtSignalMAHandles[];
int    ExtATRHandles[];
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculateLot(string symbol, double atrValue)
{
   if(!ExtSymbolInfo.Name(symbol)) {
      Print("[ERROR] Symbol info for lot calc");
      return 0;
   }
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double lot = risk / (atrValue * 10 * point);
   lot = MathMax(lot, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN));
   lot = MathMin(lot, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX));
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   StringSplit(InpSymbols, ',', ExtSymbols);
   if(ArraySize(ExtSymbols)==0) { Print("[ERROR] No symbols"); return INIT_FAILED; }
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippage);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   ArrayResize(ExtTrendMAHandles, ArraySize(ExtSymbols));
   ArrayResize(ExtSignalMAHandles, ArraySize(ExtSymbols));
   ArrayResize(ExtATRHandles, ArraySize(ExtSymbols));
   ArrayInitialize(ExtTrendMAHandles, INVALID_HANDLE);
   ArrayInitialize(ExtSignalMAHandles, INVALID_HANDLE);
   ArrayInitialize(ExtATRHandles, INVALID_HANDLE);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i=0; i<ArraySize(ExtTrendMAHandles); i++)
      if(ExtTrendMAHandles[i] != INVALID_HANDLE)
         IndicatorRelease(ExtTrendMAHandles[i]);
   for(int i=0; i<ArraySize(ExtSignalMAHandles); i++)
      if(ExtSignalMAHandles[i] != INVALID_HANDLE)
         IndicatorRelease(ExtSignalMAHandles[i]);
   for(int i=0; i<ArraySize(ExtATRHandles); i++)
      if(ExtATRHandles[i] != INVALID_HANDLE)
         IndicatorRelease(ExtATRHandles[i]);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(lastBar == curBar) return;
   lastBar = curBar;
   for(int i=0; i<ArraySize(ExtSymbols); i++) {
      string symbol = ExtSymbols[i];
      if(!ExtSymbolInfo.Name(symbol)) continue;
      if(ExtTrendMAHandles[i] == INVALID_HANDLE)
         ExtTrendMAHandles[i] = iMA(symbol, _Period, InpTrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(ExtSignalMAHandles[i] == INVALID_HANDLE)
         ExtSignalMAHandles[i] = iMA(symbol, _Period, InpSignalMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(ExtATRHandles[i] == INVALID_HANDLE)
         ExtATRHandles[i] = iATR(symbol, _Period, InpATRPeriod);
      double trend[2], signal[2], atr[2];
      if(CopyBuffer(ExtTrendMAHandles[i], 0, 0, 2, trend) <= 0 ||
         CopyBuffer(ExtSignalMAHandles[i], 0, 0, 2, signal) <= 0 ||
         CopyBuffer(ExtATRHandles[i], 0, 0, 2, atr) <= 0) continue;
      ProcessSymbol(symbol, i, trend, signal, atr);
   }
}

//+------------------------------------------------------------------+
//| Process trading for a single symbol                              |
//+------------------------------------------------------------------+
void ProcessSymbol(string symbol, int idx, double &trend[], double &signal[], double &atr[])
{
   if(PositionSelect(symbol)) {
      Print("[INFO] Existing position for ", symbol);
      ManageTrailingStop(symbol, idx);
      CheckPositionExpiration(symbol);
      return;
   }
   if(trend[1] > signal[1]) {
      Print("[INFO] Swing Buy Signal ", symbol);
      ExecuteTrade(symbol, ORDER_TYPE_BUY, atr[1]);
   } else if(trend[1] < signal[1]) {
      Print("[INFO] Swing Sell Signal ", symbol);
      ExecuteTrade(symbol, ORDER_TYPE_SELL, atr[1]);
   }
}

//+------------------------------------------------------------------+
//| Execute trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, ENUM_ORDER_TYPE type, double atrValue)
{
   if(!ExtSymbolInfo.Name(symbol)) return;
   ExtSymbolInfo.RefreshRates();
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? price - InpATRMultiplier * atrValue : price + InpATRMultiplier * atrValue;
   double tp = (type == ORDER_TYPE_BUY) ? price + InpTPMultiplier * atrValue : price - InpTPMultiplier * atrValue;
   double lot = CalculateLot(symbol, atrValue);
   if(!ExtTrade.PositionOpen(symbol, type, lot, price, sl, tp, "SwingMulti")) {
      Print("[ERROR] Trade open failed for ", symbol, ": ", ExtTrade.ResultRetcodeDescription());
      Alert("[ERROR] Trade open failed for ", symbol, ": ", ExtTrade.ResultRetcodeDescription());
   } else {
      Print("[SUCCESS] Trade executed: ", symbol, " ", EnumToString(type), " ", lot, " lots");
      Alert("[SUCCESS] Trade executed: ", symbol, " ", EnumToString(type), " ", lot, " lots");
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stop for a position                              |
//+------------------------------------------------------------------+
void ManageTrailingStop(string symbol, int idx)
{
   double atr[];
   if(CopyBuffer(ExtATRHandles[idx], 0, 0, 1, atr) <= 0) return;
   ExtSymbolInfo.Name(symbol);
   ExtSymbolInfo.RefreshRates();
   double price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   double stopLoss = PositionGetDouble(POSITION_SL);
   double takeProfit = PositionGetDouble(POSITION_TP);
   double newSL;
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      newSL = price - InpATRMultiplier * atr[0];
   else
      newSL = price + InpATRMultiplier * atr[0];
   if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSL > stopLoss) || (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && newSL < stopLoss)) {
      if(!ExtTrade.PositionModify(PositionGetInteger(POSITION_TICKET), newSL, takeProfit)) {
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