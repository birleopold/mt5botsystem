//+------------------------------------------------------------------+
//| Ensemble Voting EA for MT5                                      |
//| Robust multi-signal, ATR-based stops, risk controls             |
//+------------------------------------------------------------------+
#property version   "1.01"
#property strict

// Best practice headers
#property copyright ""
#property link      ""
#property description ""

input double RiskPerTrade = 1.0;
input double ATRMultiplier = 2.0;
input int ATRPeriod = 14;
input double Slippage = 3;
input int MagicNumber = 567890;

double atr[];
int atrHandle;
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

int OnInit()
  {
   ExtTrade.SetExpertMagicNumber(MagicNumber);
   ExtTrade.SetDeviationInPoints((int)Slippage);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   if(RiskPerTrade <= 0 || RiskPerTrade > 100) {
     Print("[ERROR] RiskPerTrade must be between 0 and 100");
     return(INIT_FAILED);
   }
   if(ATRMultiplier <= 0) {
     Print("[ERROR] ATRMultiplier must be positive");
     return(INIT_FAILED);
   }
   if(ATRPeriod < 2 || ATRPeriod > 200) {
     Print("[ERROR] ATRPeriod must be between 2 and 200");
     return(INIT_FAILED);
   }
   if(Slippage < 0) {
     Print("[ERROR] Slippage must be non-negative");
     return(INIT_FAILED);
   }
   atrHandle = iATR(_Symbol, _Period, ATRPeriod);
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason)
  {
   IndicatorRelease(atrHandle);
  }

void OnTick()
{
   if(!RefreshATR()) return;
   if(ExtPositionInfo.Select(_Symbol)) {
      ManageTrailingStop();
      CheckPositionExpiration();
      return;
   }
   if(BuySignal()) {
      ExecuteTrade(ORDER_TYPE_BUY, atr[1]);
   } else if(SellSignal()) {
      ExecuteTrade(ORDER_TYPE_SELL, atr[1]);
   }
}

bool RefreshATR()
{
   if(CopyBuffer(atrHandle, 0, 0, 2, atr) <= 0) { Print("[ERROR] ATR buffer"); return false; }
   return true;
}

bool BuySignal()
  {
   int votes = 0;
   double macd[], signal[];
   int macdHandle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
   if(CopyBuffer(macdHandle, 0, 0, 2, macd) > 0 && CopyBuffer(macdHandle, 1, 0, 2, signal) > 0)
      if(macd[1]>signal[1]) votes++;
   IndicatorRelease(macdHandle);
   double bbUpper[], bbLower[], bbMiddle[];
   int bbHandle = iBands(_Symbol, _Period, 20, 0, 2.0, PRICE_CLOSE);
   if(CopyBuffer(bbHandle, 1, 0, 2, bbLower) > 0)
      if(iClose(_Symbol, _Period, 1) < bbLower[1]) votes++;
   IndicatorRelease(bbHandle);
   // Supertrend logic placeholder: always neutral for demo
   // if(SupertrendBuy()) votes++;
   return votes >= 2;
  }
bool SellSignal()
  {
   int votes = 0;
   double macd[], signal[];
   int macdHandle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
   if(CopyBuffer(macdHandle, 0, 0, 2, macd) > 0 && CopyBuffer(macdHandle, 1, 0, 2, signal) > 0)
      if(macd[1]<signal[1]) votes++;
   IndicatorRelease(macdHandle);
   double bbUpper[], bbLower[], bbMiddle[];
   int bbHandle = iBands(_Symbol, _Period, 20, 0, 2.0, PRICE_CLOSE);
   if(CopyBuffer(bbHandle, 0, 0, 2, bbUpper) > 0)
      if(iClose(_Symbol, _Period, 1) > bbUpper[1]) votes++;
   IndicatorRelease(bbHandle);
   // Supertrend logic placeholder: always neutral for demo
   // if(SupertrendSell()) votes++;
   return votes >= 2;
  }

void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   ExtSymbolInfo.RefreshRates();
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? price - ATRMultiplier * atrValue : price + ATRMultiplier * atrValue;
   double tp = (type == ORDER_TYPE_BUY) ? price + ATRMultiplier * atrValue : price - ATRMultiplier * atrValue;
   double lot = CalculateLot(atrValue);
   if(!ExtTrade.PositionOpen(_Symbol, type, lot, price, sl, tp, "Ensemble")) {
      Print("[ERROR] Trade open failed: ", ExtTrade.ResultRetcodeDescription());
      Alert("[ERROR] Trade open failed: ", ExtTrade.ResultRetcodeDescription());
   } else {
      Print("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
      Alert("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
   }
}
double CalculateLot(double atrValue)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPerTrade / 100.0;
   CSymbolInfo info; info.Name(_Symbol);
   double lot = risk / (atrValue * 10 * info.Point());
   lot = MathMax(lot, info.LotsMin());
   lot = MathMin(lot, info.LotsMax());
   return NormalizeDouble(lot, 2);
}
void ManageTrailingStop()
{
   double atrVal = atr[1];
   ExtSymbolInfo.RefreshRates();
   double price = (ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
   double oldSL = ExtPositionInfo.StopLoss();
   double newSL;
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY)
      newSL = price - ATRMultiplier * atrVal;
   else
      newSL = price + ATRMultiplier * atrVal;
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
   // For demo, no expiration logic (add as needed)
}
