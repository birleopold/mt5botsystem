#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>
CTrade      trade;
datetime    lastTime;
double      highEquity;
bool        OpenNewPos = true;

//--- Inputs: Risk Management
input double RiskPct               = 2.0;   // {0.1,5.0,0.1} % per trade
input double EquityDrawdownLimit   = 10.0;  // {0,20,1} % drawdown
input double TrailingStopLevelPct  = 50.0;  // {0,100,10} % profit to trail
input double TrailingActivationPts = 30.0;  // {0,200,10} pts before trailing

//--- Inputs: Entry Strategy
enum ENUM_ENTRY_STRATEGY {
    SIGNAL_CROSSES_HISTOGRAM, // Signal crosses MACD line
    HISTOGRAM_CROSSES_ZERO,   // MACD line crosses zero
    SIGNAL_CROSSES_ZERO       // Signal crosses zero
};
input ENUM_ENTRY_STRATEGY EntryStrategy = SIGNAL_CROSSES_HISTOGRAM;

//--- Inputs: MACD Parameters
input int    MACDFastPeriod   = 12;  // {5,50,1}
input int    MACDSlowPeriod   = 26;  // {10,200,1}
input int    MACDSignalPeriod = 9;   // {3,50,1}
input ENUM_APPLIED_PRICE MACDPrice = PRICE_CLOSE;

//--- Inputs: Take Profit / Stop Loss Coefficients
input double TPCoef           = 1.0; // {0.5,3.0,0.1}
//input ENUM_SL SLType          = SL_SWING; // Removed undefined ENUM_SL
input int    SLLookback       = 10;  // {1,50,1}
input int    SLDev            = 30;  // {10,200,5}

//--- Inputs: Execution & Timer
input int    Slippage         = 30;
input int    TimerInterval    = 30;
input ulong  MagicNumber      = 123456;

//--- Indicator handle & buffers
int    macdHandle;
double macdMain[], macdSignal[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    // Track high equity
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Create MACD handle
    macdHandle = iMACD(_Symbol, _Period,
                       MACDFastPeriod, MACDSlowPeriod, MACDSignalPeriod, MACDPrice);
    if(macdHandle == INVALID_HANDLE){
        Print("iMACD handle error: ",GetLastError());
        return(INIT_FAILED);
    }
    ArraySetAsSeries(macdMain, true);
    ArraySetAsSeries(macdSignal, true);

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
//| Timer: drawdown & trailing checks                               |
//+------------------------------------------------------------------+
void OnTimer(){
    CheckDrawdown();
    CheckTrailing();
}

//+------------------------------------------------------------------+
//| Tick: new bar processing                                        |
//+------------------------------------------------------------------+
void OnTick(){
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(barTime == lastTime) return;
    lastTime = barTime;

    // Fetch MACD buffers once per bar
    if(CopyBuffer(macdHandle,0,0,2,macdMain)   <=0) return;
    if(CopyBuffer(macdHandle,1,0,2,macdSignal) <=0) return;

    // Get entry signals
    bool openBuy=false, openSell=false;
    GetEntrySignals(openBuy, openSell);

    // Execute orders if allowed
    if(OpenNewPos && PositionsTotal()==0){
        if(openBuy)  EnterTrade(ORDER_TYPE_BUY);
        if(openSell) EnterTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Determine entry signals                                         |
//+------------------------------------------------------------------+
void GetEntrySignals(bool &buy, bool &sell){
    switch(EntryStrategy){
        case SIGNAL_CROSSES_HISTOGRAM:
            buy  = macdMain[1] <= 0 && macdSignal[0] > macdMain[0] && macdSignal[1] <= macdMain[1];
            sell = macdMain[1] >= 0 && macdSignal[0] < macdMain[0] && macdSignal[1] >= macdMain[1];
            break;
        case HISTOGRAM_CROSSES_ZERO:
            buy  = macdMain[0] > 0 && macdMain[1] <= 0;
            sell = macdMain[0] < 0 && macdMain[1] >= 0;
            break;
        case SIGNAL_CROSSES_ZERO:
            buy  = macdSignal[0] > 0 && macdSignal[1] <= 0;
            sell = macdSignal[0] < 0 && macdSignal[1] >= 0;
            break;
    }
}

//+------------------------------------------------------------------+
//| Place market order                                              |
//+------------------------------------------------------------------+
void EnterTrade(ENUM_ORDER_TYPE type){
    double price = (type==ORDER_TYPE_BUY)
                   ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                   : SymbolInfoDouble(_Symbol,SYMBOL_BID);
    double sl    = (type==ORDER_TYPE_BUY)
                   ? price - SLDev*_Point
                   : price + SLDev*_Point;
    double lot   = CalculateLot(price, sl);
    double tp    = (type==ORDER_TYPE_BUY)
                   ? price + TPCoef * MathAbs(price - sl)
                   : price - TPCoef * MathAbs(price - sl);

    if(type==ORDER_TYPE_BUY)
        trade.Buy(lot,_Symbol,price,sl,tp);
    else
        trade.Sell(lot,_Symbol,price,sl,tp);
}

//+------------------------------------------------------------------+
//| Dynamic position sizing                                         |
//+------------------------------------------------------------------+
double CalculateLot(double entry,double sl){
    double riskAmt = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPct / 100.0;
    double tickVal = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double pts     = MathAbs(entry - sl) / _Point;
    double costLot = pts * tickVal / tickSz;
    // Calculate digits from volume step
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int digits = 0;
    if(step > 0.0) {
        double logStep = MathLog10(1.0/step);
        digits = (int)MathRound(logStep);
    }
    return NormalizeDouble(riskAmt / costLot, digits);
}

//+------------------------------------------------------------------+
//| Equity drawdown limiter                                         |
//+------------------------------------------------------------------+
void CheckDrawdown(){
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq > highEquity) highEquity = eq;
    if(eq < highEquity * (1 - EquityDrawdownLimit/100.0))
        OpenNewPos = false;
}

//+------------------------------------------------------------------+
//| Flexible trailing stop                                          |
//+------------------------------------------------------------------+
void CheckTrailing(){
    for(int i=0; i<PositionsTotal(); i++){
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        double open  = PositionGetDouble(POSITION_PRICE_OPEN);
        double cur   = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                       ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                       : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double pts   = MathAbs(cur - open) / _Point;
        if(pts >= TrailingActivationPts){
            double newSL = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                           ? cur - TrailingStopLevelPct/100*pts*_Point
                           : cur + TrailingStopLevelPct/100*pts*_Point;
            trade.PositionModify(ticket,newSL,0);
        }
    }
}
