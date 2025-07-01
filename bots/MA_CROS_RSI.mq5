#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>
CTrade      trade;
datetime    lastTime;
double      highEquity;

//--- Global flags
bool OpenNewPos = true;

//--- Inputs: Risk Management
input double RiskPct               = 1.0;   // {0.1,5.0,0.1} % risk per trade
input double EquityDrawdownLimit   = 10.0;  // {0,20,1} % max drawdown
input double TrailingStopLevelPct  = 50.0;  // {0,100,10} % of profit
input double TrailingActivationPts = 30.0;  // {0,200,10} pts before trail

//--- Inputs: Moving Averages
input int    ma_fast_period        = 12;    // {5,50,1}
input int    ma_slow_period        = 32;    // {10,100,1}
input ENUM_MA_METHOD ma_method     = MODE_EMA;
input ENUM_APPLIED_PRICE ma_price  = PRICE_CLOSE;

//--- Inputs: RSI
input int    rsi_period            = 5;     // {3,30,1}
input int    rsi_overbought        = 70;    // {50,90,1}
input int    rsi_oversold          = 30;    // {10,50,1}

//--- Inputs: Strategy
input double TPCoef               = 1.0;   // {0.5,3.0,0.1} TP = SL×coef
//input ENUM_SL SLType              = SL_SWING; // ENUM_SL not defined
input int    SLLookback           = 7;     // {1,50,1}
input int    SLDev                = 30;    // {10,200,5}
//input ENUM_STRATEGY_IN strategy   = ONLY_MA; // ENUM_STRATEGY_IN not defined

//--- Use a simple int for strategy selection for now
enum STRATEGY_IN { ONLY_MA, ONLY_RSI, MA_AND_RSI };
input STRATEGY_IN strategy = ONLY_MA;

//--- Inputs: Execution & Timer
input int    Slippage             = 30;
input int    TimerInterval        = 30;
input ulong  MagicNumber          = 123456;

//--- Indicator handles & buffers
int    maFastHandle, maSlowHandle, rsiHandle;
double maFastBuf[], maSlowBuf[], rsiBuf[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    // Equity tracking
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Create indicator handles
    maFastHandle = iMA(_Symbol,_Period,ma_fast_period,0,ma_method,ma_price);
    maSlowHandle = iMA(_Symbol,_Period,ma_slow_period,0,ma_method,ma_price);
    rsiHandle    = iRSI(_Symbol,_Period,rsi_period,PRICE_CLOSE);

    // Validate handles
    if(maFastHandle==INVALID_HANDLE || maSlowHandle==INVALID_HANDLE || rsiHandle==INVALID_HANDLE){
        Print("Indicator handle error: ",GetLastError());
        return(INIT_FAILED);
    }

    // Prepare buffers as series
    ArraySetAsSeries(maFastBuf,true);
    ArraySetAsSeries(maSlowBuf,true);
    ArraySetAsSeries(rsiBuf,true);

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
//| Tick: signal evaluation                                         |
//+------------------------------------------------------------------+
void OnTick(){
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(barTime==lastTime) return;
    lastTime=barTime;

    // Copy indicator buffers once per new bar
    if(CopyBuffer(maFastHandle,0,0,3,maFastBuf)<=0) return;
    if(CopyBuffer(maSlowHandle,0,0,3,maSlowBuf)<=0) return;
    if(CopyBuffer(rsiHandle,0,0,3,rsiBuf)<=0)       return;

    // Entry logic
    bool maCrossUp   = maFastBuf[1] <= maSlowBuf[1] && maFastBuf[0] > maSlowBuf[0];
    bool maCrossDown = maFastBuf[1] >= maSlowBuf[1] && maFastBuf[0] < maSlowBuf[0];
    bool rsiBuy      = rsiBuf[0] <= rsi_oversold;
    bool rsiSell     = rsiBuf[0] >= rsi_overbought;

    bool doBuy  = (strategy==ONLY_MA   && maCrossUp)
                || (strategy==ONLY_RSI  && rsiBuy)
                || (strategy==MA_AND_RSI&& maCrossUp && rsiBuy);

    bool doSell = (strategy==ONLY_MA   && maCrossDown)
                || (strategy==ONLY_RSI  && rsiSell)
                || (strategy==MA_AND_RSI&& maCrossDown && rsiSell);

    // Execute entries if allowed
    if(OpenNewPos){
        if(doBuy && PositionsTotal()==0)  EnterTrade(ORDER_TYPE_BUY);
        if(doSell && PositionsTotal()==0) EnterTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Enter a market trade                                            |
//+------------------------------------------------------------------+
void EnterTrade(int type){
    double price = (type==ORDER_TYPE_BUY)
                   ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                   : SymbolInfoDouble(_Symbol,SYMBOL_BID);
    double sl    = (type==ORDER_TYPE_BUY)
                   ? price - SLDev*_Point
                   : price + SLDev*_Point;
    double lot   = CalculateLot(price,sl);
    double tp    = (type==ORDER_TYPE_BUY)
                   ? price + TPCoef*MathAbs(price-sl)
                   : price - TPCoef*MathAbs(price-sl);

    if(type==ORDER_TYPE_BUY)
        trade.Buy(lot,_Symbol,price,sl,tp);
    else
        trade.Sell(lot,_Symbol,price,sl,tp);
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size                                      |
//+------------------------------------------------------------------+
double CalculateLot(double entry,double sl){
    double riskAmt = AccountInfoDouble(ACCOUNT_BALANCE)*RiskPct/100;
    double tickVal = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double pts     = MathAbs(entry-sl)/_Point;
    double costLot = pts * tickVal / tickSz;
    // Calculate digits from volume step
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int digits = 0;
    if(step > 0.0) {
        double logStep = MathLog10(1.0/step);
        digits = (int)MathRound(logStep);
    }
    return NormalizeDouble(riskAmt/costLot, digits);
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
        double open  = PositionGetDouble(POSITION_PRICE_OPEN);
        double cur   = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                       ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                       : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double pts   = MathAbs(cur-open)/_Point;
        if(pts>=TrailingActivationPts){
            double newSL = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                           ? cur - TrailingStopLevelPct/100*pts*_Point
                           : cur + TrailingStopLevelPct/100*pts*_Point;
            trade.PositionModify(ticket,newSL,0);
        }
    }
}
