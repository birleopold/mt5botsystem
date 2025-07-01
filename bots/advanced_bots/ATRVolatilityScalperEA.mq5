//+------------------------------------------------------------------+
//|                    ATRVolatilityScalperEA.mq5                    |
//|          Advanced Volatility-Based Scalping Strategy             |
//+------------------------------------------------------------------+
#property version   "2.2"
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
input int      InpATRPeriod     = 14;       // ATR period (2-200)
input double   InpATRMultiplier = 1.5;      // ATR multiplier for SL/TP
input double   InpTPMultiplier  = 2.0;      // ATR multiplier for take profit

// [Trade Parameters]
input uint     InpSlippage      = 3;        // Slippage in points
input double   InpRiskPerTrade  = 1.0;      // Risk % per trade (0.1-100)
input uint     InpDuration      = 240;      // Position duration in minutes (0=no expiry)

// [Expert ID]
input long     InpMagicNumber   = 345678;   // Unique EA identifier

//--- Global Variables
int    ExtATRHandle      = INVALID_HANDLE;
int    ExtSignal         = SIGNAL_NOT;
string ExtSignalInfo     = "";
bool   ExtNewBar         = false;

//--- Indicator Buffers
double ExtATR[];

//--- Service Objects
CTrade       ExtTrade;
CSymbolInfo  ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippage);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   ExtTrade.LogLevel(LOG_LEVEL_ERRORS);
   if(!ExtSymbolInfo.Name(_Symbol)) {
      Print("[ERROR] Failed to initialize symbol info");
      return INIT_FAILED;
   }
   ExtATRHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(ExtATRHandle == INVALID_HANDLE) {
      Print("[ERROR] ATR indicator initialization failed");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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
   if(lastBarTime == currentTime)
      return;
   lastBarTime = currentTime;
   ExtNewBar = true;
   if(!RefreshIndicators())
      return;
   CheckTradingConditions();
   ManageTrailingStop();
}

//+------------------------------------------------------------------+
//| Refresh indicator data                                           |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   if(CopyBuffer(ExtATRHandle, 0, 0, 2, ExtATR) <= 0) {
      Print("[ERROR] Failed to copy ATR buffer");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check trading conditions                                         |
//+------------------------------------------------------------------+
void CheckTradingConditions()
{
   if(ExtPositionInfo.Select(_Symbol)) {
      Print("[INFO] Existing position detected. No new trades.");
      CheckPositionExpiration();
      return;
   }
   double atrValue = ExtATR[1];
   double open1 = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double candleRange = MathAbs(open1 - close1);
   //--- Buy condition: bullish candle with range > ATR threshold
   if(close1 > open1 && candleRange > InpATRMultiplier * atrValue) {
      ExtSignal = SIGNAL_BUY;
      ExtSignalInfo = "ATR Scalping Buy";
      ExecuteTrade(ORDER_TYPE_BUY, atrValue);
   }
   //--- Sell condition: bearish candle with range > ATR threshold
   else if(close1 < open1 && candleRange > InpATRMultiplier * atrValue) {
      ExtSignal = SIGNAL_SELL;
      ExtSignalInfo = "ATR Scalping Sell";
      ExecuteTrade(ORDER_TYPE_SELL, atrValue);
   }
   else {
      ExtSignal = SIGNAL_NOT;
      ExtSignalInfo = "No valid signal";
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
   double tp = (type == ORDER_TYPE_BUY) ? price + InpTPMultiplier * atrValue : price - InpTPMultiplier * atrValue;
   double lot = CalculateLot(atrValue);
   if(!ExtTrade.PositionOpen(_Symbol, type, lot, price, sl, tp, ExtSignalInfo)) {
      Print("[ERROR] Trade failed: ", ExtTrade.ResultRetcodeDescription());
      Alert("[ERROR] Trade failed: ", ExtTrade.ResultRetcodeDescription());
   } else {
      Print("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
      Alert("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
   }
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculateLot(double atrValue)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   double pointValue = ExtSymbolInfo.TickValue() / ExtSymbolInfo.TickSize();
   double lot = risk / (atrValue * InpATRMultiplier * pointValue);
   lot = MathMax(lot, ExtSymbolInfo.LotsMin());
   lot = MathMin(lot, ExtSymbolInfo.LotsMax());
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Manage trailing stop                                             |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!ExtPositionInfo.Select(_Symbol)) return;
   double atr = ExtATR[1];
   ExtSymbolInfo.RefreshRates();
   double price = (ExtPositionInfo.PositionType() == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
   double oldSL = ExtPositionInfo.StopLoss();
   double newSL;
   if(ExtPositionInfo.PositionType() == POSITION_TYPE_BUY)
      newSL = price - InpATRMultiplier * atr;
   else
      newSL = price + InpATRMultiplier * atr;
   // Only move stop if newSL is better
   if((ExtPositionInfo.PositionType() == POSITION_TYPE_BUY && newSL > oldSL) ||
      (ExtPositionInfo.PositionType() == POSITION_TYPE_SELL && newSL < oldSL)) {
      if(!ExtTrade.PositionModify(_Symbol, newSL, ExtPositionInfo.TakeProfit())) {
         Print("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
         Alert("[ERROR] Trailing stop modify failed: ", ExtTrade.ResultRetcodeDescription());
      } else {
         Print("[INFO] Trailing stop updated");
         Alert("[INFO] Trailing stop updated");
      }
   }
}

//+------------------------------------------------------------------+
//| Check position expiration                                        |
//+------------------------------------------------------------------+
void CheckPositionExpiration()
{
   if(InpDuration == 0) return;
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