#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>
CTrade      trade;
datetime    lastTime;
double      highEquity;
bool        OpenNewPos = true;

//--- Inputs: Risk Management
input double RiskPct               = 0.6;   // {0.1,2.0,0.1} %
input double EquityDrawdownLimit   = 5.0;   // {0,20,1} %
input double TrailingStopLevelPct  = 50.0;  // {0,100,10} %
input double TrailingActivationPts = 30.0;  // {0,200,10} pts

//--- Inputs: Indicators
input int    LrLen       = 11; // {5,50,1}
input int    LrSmaLen    = 7;  // {3,30,1}
input double UtbAtrCoef  = 2.0;// {0.5,5.0,0.5}
input int    UtbAtrLen   = 1;  // {1,10,1}

//--- Inputs: Strategy
input double TPCoef      = 1.0;  // {0.5,3.0,0.1}
//input ENUM_SL SLType     = SL_SWING;
input int    SLLookback  = 10;   // {1,50,1}
input int    SLDev       = 100;  // {10,500,10}
input bool   CloseOrders = false;
input bool   CloseOnProfit = true;

//--- Inputs: Execution & Timer
input int    Slippage     = 30;
input int    TimerInterval= 30;
input ulong  MagicNumber  = 1003;

//--- Handles & Buffers
int    hLRC, hUTB;
double LRC_O[], LRC_C[], LRC_S[];
double UTB_BULL[], UTB_BEAR[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    InitIndicators();
    EventSetTimer(TimerInterval);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Initialize indicator handles                                    |
//+------------------------------------------------------------------+
void InitIndicators(){
    hLRC = iCustom(_Symbol,_Period,"Indicators\\LinearRegressionCandles.ex5",LrLen,LrSmaLen);
    hUTB = iCustom(_Symbol,_Period,"Indicators\\UTBot.ex5",UtbAtrCoef,UtbAtrLen);
    ArraySetAsSeries(LRC_O,true); ArraySetAsSeries(LRC_C,true);
    ArraySetAsSeries(LRC_S,true);
    ArraySetAsSeries(UTB_BULL,true); ArraySetAsSeries(UTB_BEAR,true);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer: risk checks & trailing                                   |
//+------------------------------------------------------------------+
void OnTimer(){
    CheckDrawdown();
    CheckTrailing();
}

//+------------------------------------------------------------------+
//| Tick: copy buffers & execute signals                            |
//+------------------------------------------------------------------+
void OnTick(){
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(lastTime==barTime) return;
    lastTime=barTime;
    if(!OpenNewPos) return;
    if(!CopyAll()) return;

    // Close conditions
    if(CloseOrders) CheckClose();

    // Entries
    if(BuySignal()) return;
    SellSignal();
}

//+------------------------------------------------------------------+
//| Copy all buffers                                                |
//+------------------------------------------------------------------+
bool CopyAll(){
    const int sz = 4;
    if(CopyBuffer(hLRC, 0, 0, sz, LRC_O)    <=0) return false;
    if(CopyBuffer(hLRC, 3, 0, sz, LRC_C)    <=0) return false;
    if(CopyBuffer(hLRC, 5, 0, sz, LRC_S)    <=0) return false;
    if(CopyBuffer(hUTB, 0, 0, sz, UTB_BULL) <=0) return false;
    if(CopyBuffer(hUTB, 1, 0, sz, UTB_BEAR) <=0) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Buy signal                                                      |
//+------------------------------------------------------------------+
bool BuySignal(){
    if(!(LRC_C[1]>LRC_O[1] && LRC_C[1]>LRC_S[1])) return false;
    bool alert=false;
    for(int i=1;i<4;i++) if(UTB_BULL[i]) { alert=true; break; }
    if(!alert) return false;
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    // Use fixed stop-loss
    double sl    = entry - SLDev * _Point;
    double lot   = CalculateLot(entry, sl);
    double tp    = entry + TPCoef*MathAbs(entry-sl);
    trade.Buy(lot,_Symbol,entry,sl,tp);
    return true;
}

//+------------------------------------------------------------------+
//| Sell signal                                                     |
//+------------------------------------------------------------------+
bool SellSignal(){
    if(!(LRC_C[1]<LRC_O[1] && LRC_C[1]<LRC_S[1])) return false;
    bool alert=false;
    for(int i=1;i<4;i++) if(UTB_BEAR[i]) { alert=true; break; }
    if(!alert) return false;
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
    // Use fixed stop-loss
    double sl    = entry + SLDev * _Point;
    double lot   = CalculateLot(entry, sl);
    double tp    = entry - TPCoef*MathAbs(entry-sl);
    trade.Sell(lot,_Symbol,entry,sl,tp);
    return true;
}

//+------------------------------------------------------------------+
//| Close on LRC reversal                                           |
//+------------------------------------------------------------------+
void CheckClose(){
    // The following lines are commented out because they reference undefined functions/objects
    // if(CloseOnProfit){
    //     double p = getProfit(ea.GetMagic()) - calcCost(ea.GetMagic());
    //     if(p < 0) return;
    // }
    // if(LRC_C[2]>LRC_O[2] && LRC_C[1]<LRC_O[1]) ea.BuyClose();
    // if(LRC_C[2]<LRC_O[2] && LRC_C[1]>LRC_O[1]) ea.SellClose();
}

//+------------------------------------------------------------------+
//| Risk and trailing-stop helpers                                  |
//+------------------------------------------------------------------+
double CalculateLot(double e,double s){
    double riskAmt = AccountInfoDouble(ACCOUNT_BALANCE)*RiskPct/100;
    double tickVal = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double pts     = MathAbs(e-s)/_Point;
    // Calculate digits from volume step
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int digits = 0;
    if(step > 0.0) {
        double logStep = MathLog10(1.0/step);
        digits = (int)MathRound(logStep);
    }
    return NormalizeDouble(riskAmt/(pts*tickVal/tickSz), digits);
}

void CheckDrawdown(){
    double eq=AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq>highEquity) highEquity=eq;
    if(eq<highEquity*(1-EquityDrawdownLimit/100)) OpenNewPos=false;
}

void CheckTrailing(){
    for(int i=0;i<PositionsTotal();i++){
        ulong t=PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        double o=PositionGetDouble(POSITION_PRICE_OPEN);
        double c=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                 ?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                 :SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double pts=MathAbs(c-o)/_Point;
        if(pts>=TrailingActivationPts){
            double newSL=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                         ?c - TrailingStopLevelPct/100*pts*_Point
                         :c + TrailingStopLevelPct/100*pts*_Point;
            trade.PositionModify(t,newSL,0);
        }
    }
}
