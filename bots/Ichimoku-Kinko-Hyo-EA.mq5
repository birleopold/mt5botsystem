#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>
CTrade      trade;
datetime    lastTime;
double      highEquity;
bool        OpenNewPos = true;

//--- Inputs: Risk Management
input double RiskPct               = 2.0;   // {0.1,5.0,0.1} risk % per trade
input double EquityDrawdownLimit   = 10.0;  // {0,20,1} max drawdown %
input double TrailingStopLevelPct  = 50.0;  // {0,100,10} % of profit
input double TrailingActivationPts = 30.0;  // {0,200,10} activation in pts

//--- Inputs: Ichimoku
input int    TenkanSen   = 9;    // {5,20,1}
input int    KijunSen    = 26;   // {10,50,1}
input int    SenkouSpanB = 52;   // {20,100,2}

//--- Inputs: Optional Exit & Filters
input bool   UseExit     = false;
input bool   UseFilters  = false;
input int    RSIPeriod   = 14;   // {5,30,1}
input double RSILower    = 30.0; // {10,50,1}
input double RSIUpper    = 70.0; // {50,90,1}
input int    HTF_MALen   = 50;   // {20,200,10}

//--- Inputs: Strategy
input double TPCoef      = 1.5;  // {0.5,3.0,0.1}
input int    SLLookback  = 7;
input int    SLDev       = 60;

//--- Execution & Timer
input int    Slippage     = 30;
input int    TimerInterval= 30;
input ulong  MagicNumber  = 12345;

// Handles & Buffers
int ichimokuHandle, RSI_handle, HTF_handle;
double Tenkan[], Kijun[], RSI_buf[], HTF_buf[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Ichimoku
    ichimokuHandle = iIchimoku(_Symbol,_Period,
                               TenkanSen,KijunSen,SenkouSpanB);
    ArraySetAsSeries(Tenkan,true);
    ArraySetAsSeries(Kijun,true);

    // Filters
    if(UseFilters){
        RSI_handle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
        HTF_handle = iMA(_Symbol,PERIOD_H1,HTF_MALen,0,MODE_EMA,PRICE_CLOSE);
        ArraySetAsSeries(RSI_buf,true);
        ArraySetAsSeries(HTF_buf,true);
    }

    EventSetTimer(TimerInterval);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer: drawdown & trailing                                      |
//+------------------------------------------------------------------+
void OnTimer(){
    CheckDrawdown();
    CheckTrailing();
}

//+------------------------------------------------------------------+
//| Tick: new bar logic                                             |
//+------------------------------------------------------------------+
void OnTick(){
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(lastTime==barTime) return;
    lastTime=barTime;

    // Copy Ichimoku
    if(CopyBuffer(ichimokuHandle,0,0,2,Tenkan)<=0) return;
    if(CopyBuffer(ichimokuHandle,1,0,2,Kijun)<=0)  return;

    bool doBuy  = Tenkan[1] <= Kijun[1] && Tenkan[0] > Kijun[0];
    bool doSell = Tenkan[1] >= Kijun[1] && Tenkan[0] < Kijun[0];

    // Optional filters
    if(UseFilters){
        CopyBuffer(RSI_handle,0,1,1,RSI_buf);
        CopyBuffer(HTF_handle,0,1,1,HTF_buf);
        bool filtOK = (RSI_buf[0]>RSILower && RSI_buf[0]<RSIUpper)
                      && ((SymbolInfoDouble(_Symbol,SYMBOL_BID)>HTF_buf[0])==doBuy);
        doBuy  &= filtOK;
        doSell &= filtOK;
    }

    // Execute
    if(doBuy && OpenNewPos){
        double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double sl    = entry - SLDev * _Point;
        double lot   = CalculateLot(entry,sl);
        double tp    = entry + TPCoef * MathAbs(entry-sl);
        trade.Buy(lot,_Symbol,entry,sl,tp);
    }
    if(doSell && OpenNewPos){
        double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
        double sl    = entry + SLDev * _Point;
        double lot   = CalculateLot(entry,sl);
        double tp    = entry - TPCoef * MathAbs(entry-sl);
        trade.Sell(lot,_Symbol,entry,sl,tp);
    }

    // Optional exit signals
    if(UseExit){
        bool exitBuy  = Tenkan[0]<=Kijun[0];
        bool exitSell = Tenkan[0]>=Kijun[0];
        if(exitBuy)  CloseAllPositions(POSITION_TYPE_BUY);
        if(exitSell) CloseAllPositions(POSITION_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Close all positions of a given type                             |
//+------------------------------------------------------------------+
void CloseAllPositions(int posType) {
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            if(PositionGetInteger(POSITION_TYPE)==posType)
                trade.PositionClose(ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Equity drawdown limiter                                         |
//+------------------------------------------------------------------+
void CheckDrawdown(){
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq>highEquity) highEquity=eq;
    if(eq<highEquity*(1-EquityDrawdownLimit/100)) OpenNewPos=false;
}

//+------------------------------------------------------------------+
//| Flexible trailing stop                                          |
//+------------------------------------------------------------------+
void CheckTrailing(){
    for(int i=0;i<PositionsTotal();i++){
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        double o = PositionGetDouble(POSITION_PRICE_OPEN);
        double c = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                   ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                   : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double pts = MathAbs(c-o)/_Point;
        if(pts>=TrailingActivationPts){
            double newSL = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                           ? c - TrailingStopLevelPct/100*pts*_Point
                           : c + TrailingStopLevelPct/100*pts*_Point;
            trade.PositionModify(ticket,newSL,0);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size                                      |
//+------------------------------------------------------------------+
double CalculateLot(double entry, double sl) {
    double riskAmt = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPct / 100;
    double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pts     = MathAbs(entry - sl) / _Point;
    // Calculate digits from volume step
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int digits = 0;
    if (step > 0.0) {
        double logStep = MathLog10(1.0 / step);
        digits = (int)MathRound(logStep);
    }
    return NormalizeDouble(riskAmt / (pts * tickVal / tickSz), digits);
}
