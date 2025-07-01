//+------------------------------------------------------------------+
//|                                                      ScalperV1.mq5 |
//|                        Refactored for MetaTrader 5 (MQL5)       |
//+------------------------------------------------------------------+
#property version   "1.20"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// Risk Management
input double RiskPercent     = 1.0;    // Risk per trade (% of balance)
input double MaxLotSize      = 10.0;   // Maximum allowed lot size
input double MinLotSize      = 0.01;   // Minimum allowed lot size

// Strategy Parameters
input int    ATR_Period      = 14;     // Volatility detection period
input int    ADX_Threshold   = 25;     // Trend strength threshold
input double SpreadThreshold = 2.5;    // Max allowed spread (points)

// Dynamic SL/TP
input double BaseRiskReward  = 1.5;    // Base Risk/Reward ratio
input double TrailingStep    = 0.0005; // Trailing SL step (in price)

// Market Condition Detection
enum MARKET_CONDITION { RANGING, TRENDING, HIGH_VOLATILITY };
MARKET_CONDITION CurrentMarketCondition;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check for sufficient liquidity and broker restrictions
   if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Alert("Trading disabled!");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size based on account balance              |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercent / 100);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotSize = NormalizeDouble(riskAmount / (tickValue * 100), 2);
   
   return MathMax(MathMin(lotSize, MaxLotSize), MinLotSize);
}

//+------------------------------------------------------------------+
//| Detect market condition using ADX and ATR                        |
//+------------------------------------------------------------------+
MARKET_CONDITION DetectMarketCondition()
{
   int adx_handle = iADX(_Symbol, PERIOD_CURRENT, ATR_Period);
   int atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   double adx[], atr[], atr_prev[];
   if(CopyBuffer(adx_handle, 0, 0, 2, adx) <= 0 ||
      CopyBuffer(atr_handle, 0, 0, 2, atr) <= 0)
      return RANGING;
   if(CopyBuffer(atr_handle, 0, 1, 1, atr_prev) <= 0)
      return RANGING;
   double adx_val = adx[0];
   double atr_val = atr[0];
   double atr_prev_val = atr_prev[0];
   
   if (adx_val > ADX_Threshold) return TRENDING;
   else if (atr_val > (atr_prev_val * 1.5)) return HIGH_VOLATILITY;
   else return RANGING;
}

//+------------------------------------------------------------------+
//| Dynamic SL/TP calculation                                        |
//+------------------------------------------------------------------+
void CalculateDynamicSLTP(double &sl, double &tp, int direction)
{
   int atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   double atr[];
   if(CopyBuffer(atr_handle, 0, 0, 1, atr) <= 0)
      atr[0] = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if (CurrentMarketCondition == TRENDING)
   {
      sl = atr[0] * 1.2;
      tp = sl * BaseRiskReward;
   }
   else if (CurrentMarketCondition == HIGH_VOLATILITY)
   {
      sl = atr[0] * 0.8;
      tp = sl * 1.8;
   }
   else // RANGING
   {
      sl = atr[0] * 0.5;
      tp = sl * 1.2;
   }
   // Add spread buffer
   sl += spread;
   tp += spread;
}

//+------------------------------------------------------------------+
//| Trailing Stop System                                             |
//+------------------------------------------------------------------+
void TrailStopLoss()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         double stopLoss = PositionGetDouble(POSITION_SL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume = PositionGetDouble(POSITION_VOLUME);
         int type = (int)PositionGetInteger(POSITION_TYPE);
         double newSl = 0;
         if(type == OP_BUY)
         {
            newSl = stopLoss + TrailingStep;
            if(Bid - newSl > TrailingStep)
               trade.PositionModify(ticket, newSl, PositionGetDouble(POSITION_TP));
         }
         else if(type == OP_SELL)
         {
            newSl = stopLoss - TrailingStep;
            if(newSl - Ask > TrailingStep)
               trade.PositionModify(ticket, newSl, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Main trading logic                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Prevent multiple trades on same bar
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_M1, 0);
   if (lastBar == currentBar) return;
   lastBar = currentBar;

   // Update market condition
   CurrentMarketCondition = DetectMarketCondition();

   // Check spread and liquidity
   if (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > SpreadThreshold) return;

   // Calculate position size
   double lotSize = CalculateLotSize();

   // Strategy selection based on market condition
   if (CurrentMarketCondition == TRENDING)
   {
      // Trend-following strategy
      int ma50_handle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      int ma200_handle = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);
      double ma50[], ma200[];
      if(CopyBuffer(ma50_handle, 0, 0, 1, ma50) <= 0 || CopyBuffer(ma200_handle, 0, 0, 1, ma200) <= 0)
         return;
      if (ma50[0] > ma200[0])
         ExecuteTrade(OP_BUY, lotSize);
      else
         ExecuteTrade(OP_SELL, lotSize);
   }
   else
   {
      // Mean-reversion strategy
      int bands_handle = iBands(_Symbol, PERIOD_CURRENT, 20, 2, 0, PRICE_CLOSE);
      double upperBand[], lowerBand[];
      if(CopyBuffer(bands_handle, 1, 0, 1, upperBand) <= 0 || CopyBuffer(bands_handle, 2, 0, 1, lowerBand) <= 0)
         return;
      if (SymbolInfoDouble(_Symbol, SYMBOL_ASK) < lowerBand[0]) ExecuteTrade(OP_BUY, lotSize);
      else if (SymbolInfoDouble(_Symbol, SYMBOL_BID) > upperBand[0]) ExecuteTrade(OP_SELL, lotSize);
   }

   // Manage open positions
   TrailStopLoss();
}

//+------------------------------------------------------------------+
//| Execute trade with risk management                               |
//+------------------------------------------------------------------+
void ExecuteTrade(int cmd, double lotSize)
{
   double sl, tp;
   CalculateDynamicSLTP(sl, tp, cmd);
   double price = (cmd == OP_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl_price = (cmd == OP_BUY) ? price - sl : price + sl;
   double tp_price = (cmd == OP_BUY) ? price + tp : price - tp;

   trade.SetTypeFilling(ORDER_FILLING_FOK);
   bool result = false;
   if(cmd == OP_BUY)
      result = trade.Buy(lotSize, _Symbol, price, sl_price, tp_price);
   else
      result = trade.Sell(lotSize, _Symbol, price, sl_price, tp_price);
   if(!result)
      Print("Trade failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
}
//+------------------------------------------------------------------+