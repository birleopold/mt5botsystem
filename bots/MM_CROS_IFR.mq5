#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>
CTrade      trade;
datetime    lastTime;
double      highEquity;
bool        OpenNewPos = true;

//--- Inputs: Risk Management
input double RiskPct               = 1.0;   // {0.1,5.0,0.1}
input double EquityDrawdownLimit   = 10.0;  // {0,20,1}
input double TrailingStopLevelPct  = 50.0;  // {0,100,10}
input double TrailingActivationPts = 30.0;  // {0,200,10}

//--- Inputs: Entry Strategy
enum ESTRATEGIA_ENTRADA {
   APENAS_MM,   // Apenas Médias Móveis
   APENAS_IFR,  // Apenas IFR
   MM_E_IFR      // Médias + IFR
};
input ESTRATEGIA_ENTRADA estrategia = APENAS_MM;

//--- Inputs: Moving Averages
input int    mm_rapida_periodo     = 12;   // {5,50,1}
input int    mm_lenta_periodo      = 32;   // {10,100,1}
input ENUM_MA_METHOD mm_metodo     = MODE_EMA;
input ENUM_APPLIED_PRICE mm_preco  = PRICE_CLOSE;

//--- Inputs: RSI
input int    ifr_periodo           = 5;    // {3,30,1}
input int    ifr_sobrevenda        = 30;   // {10,50,1}
input int    ifr_sobrecompra       = 70;   // {50,90,1}

//--- Inputs: Strategy Settings
// Removed ENUM_SL as it is not defined. If you want to support different SL types, define your enum above.
input double TPCoef               = 1.5;  // {0.5,3.0,0.1}
//input ENUM_SL SLType              = SL_SWING;
input int    SLLookback           = 7;    // {1,50,1}
input int    SLDev                = 30;   // {10,200,5}

//--- Inputs: Execution & Timer
input int    Slippage             = 30;
input int    TimerInterval        = 30;
input ulong  MagicNumber          = 123456;

//--- Indicator handles & buffers
int    maFastHandle, maSlowHandle, ifrHandle;
double maFastBuf[], maSlowBuf[], ifrBuf[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    // Track highest equity
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Create MA handles
    maFastHandle = iMA(_Symbol,_Period,mm_rapida_periodo,0,mm_metodo,mm_preco);
    maSlowHandle = iMA(_Symbol,_Period,mm_lenta_periodo, 0,mm_metodo,mm_preco);
    // Create RSI handle
    ifrHandle    = iRSI(_Symbol,_Period,ifr_periodo,mm_preco);

    if(maFastHandle==INVALID_HANDLE || maSlowHandle==INVALID_HANDLE || ifrHandle==INVALID_HANDLE){
        Print("Handle error: ",GetLastError());
        return(INIT_FAILED);
    }
    // Prepare buffers
    ArraySetAsSeries(maFastBuf,true);
    ArraySetAsSeries(maSlowBuf,true);
    ArraySetAsSeries(ifrBuf,   true);

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
//| Timer: drawdown & trailing stop                                 |
//+------------------------------------------------------------------+
void OnTimer(){
    CheckDrawdown();
    CheckTrailing();
}

//+------------------------------------------------------------------+
//| OnTick: new bar logic                                           |
//+------------------------------------------------------------------+
void OnTick(){
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(barTime == lastTime) return;
    lastTime = barTime;

    // Copy indicator buffers once per bar
    if(CopyBuffer(maFastHandle,0,0,3,maFastBuf)<=0) return;
    if(CopyBuffer(maSlowHandle,0,0,3,maSlowBuf)<=0) return;
    if(CopyBuffer(ifrHandle,   0,0,3,ifrBuf)   <=0) return;

    // Generate signals
    bool compra_mm = maFastBuf[0] > maSlowBuf[0] && maFastBuf[2] < maSlowBuf[2];
    bool compra_ifr= ifrBuf[0] <= ifr_sobrevenda;
    bool vender_mm = maSlowBuf[0] > maFastBuf[0] && maSlowBuf[2] < maFastBuf[2];
    bool vender_ifr= ifrBuf[0] >= ifr_sobrecompra;

    bool doBuy  = (estrategia==APENAS_MM   && compra_mm)
                ||(estrategia==APENAS_IFR  && compra_ifr)
                ||(estrategia==MM_E_IFR    && compra_mm && compra_ifr);

    bool doSell = (estrategia==APENAS_MM   && vender_mm)
                ||(estrategia==APENAS_IFR  && vender_ifr)
                ||(estrategia==MM_E_IFR    && vender_mm && vender_ifr);

    // Execute trades
    if(OpenNewPos && PositionsTotal()==0){
        if(doBuy)  EnterTrade(ORDER_TYPE_BUY);
        if(doSell) EnterTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Place market order                                              |
//+------------------------------------------------------------------+
void EnterTrade(int type){
    double price  = (type==ORDER_TYPE_BUY)
                    ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                    : SymbolInfoDouble(_Symbol,SYMBOL_BID);
    double sl     = (type==ORDER_TYPE_BUY)
                    ? price - SLDev*_Point
                    : price + SLDev*_Point;
    double lot    = CalculateLot(price, sl);
    double tp     = (type==ORDER_TYPE_BUY)
                    ? price + TPCoef*MathAbs(price - sl)
                    : price - TPCoef*MathAbs(price - sl);

    if(type==ORDER_TYPE_BUY)
        trade.Buy(lot,_Symbol,price,sl,tp);
    else
        trade.Sell(lot,_Symbol,price,sl,tp);
}

//+------------------------------------------------------------------+
//| Dynamic position sizing                                         |
//+------------------------------------------------------------------+
double CalculateLot(double entry,double sl){
    double riskAmt = AccountInfoDouble(ACCOUNT_BALANCE)*RiskPct/100;
    double tickVal = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double pts     = MathAbs(entry-sl)/_Point;
    // Calculate digits from volume step
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int digits = 0;
    if(step > 0.0) {
        double logStep = MathLog10(1.0/step);
        digits = (int)MathRound(logStep);
    }
    return NormalizeDouble(riskAmt/(pts*tickVal/tickSz), digits);
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
