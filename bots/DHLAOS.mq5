#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>

CTrade      trade;
datetime    lastTime;
double      highEquity;

//--- Inputs: Risk Management
input double RiskPct               = 0.5;   // {0.1,2.0,0.1}
input double EquityDrawdownLimit   = 5.0;   // {0,10,1}
input double TrailingStopLevelPct  = 50.0;  // {0,100,10}
input double TrailingActivationPts = 30.0;  // {0,100,10}

//--- Inputs: Indicators
input int    AosPeriod      = 50;  // {10,200,10}
input int    AosSignalPeriod= 9;   // {3,30,3}
input int    AosNCheck      = 300; // {50,500,50}
input int    DhlNCheck      = 50;  // {10,200,10}

//--- Inputs: General Strategy
input double TPCoef         = 1.5; // {0.5,3.0,0.1}
//input ENUM_SL SLType        = SL_SWING; // ENUM_SL not defined
input int    SLLookback     = 7;
input int    SLDev          = 60;

//--- Inputs: Grid & Other Controls
bool   OpenNewPos     = true;
input double GridVolMult    = 1.1;
input int    GridMaxLvl     = 50;
input bool   Grid           = true;
input int    SpreadLimit    = -1;  // Disable
input double MarginLimit    = 300; // Disable

//--- Inputs: Engine & Timer
input int    Slippage       = 30;
input int    TimerInterval  = 30;
input ulong  MagicNumber    = 4000;

//--- Indicator handles & buffers
int    AOS_handle, DHL_handle;
double AOS_Bull[], AOS_Bear[], AOS_Signal[];
double DHL_H[], DHL_L[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    //--- Load custom indicators
    AOS_handle = iCustom(_Symbol,_Period,"Indicators\\AndeanOscillator.ex5",
                         AosPeriod,AosSignalPeriod);
    DHL_handle = iCustom(_Symbol,_Period,"Indicators\\DailyHighLow.ex5");

    //--- Prepare buffers
    ArraySetAsSeries(AOS_Bull,true);
    ArraySetAsSeries(AOS_Bear,true);
    ArraySetAsSeries(AOS_Signal,true);
    ArraySetAsSeries(DHL_H,true);
    ArraySetAsSeries(DHL_L,true);

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
//| Timer: trailing and drawdown checks                             |
//+------------------------------------------------------------------+
void OnTimer(){
    CheckDrawdown();
    CheckTrailing();
}

//+------------------------------------------------------------------+
//| Tick: copy buffers & trade logic                                |
//+------------------------------------------------------------------+
void OnTick(){
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(lastTime == barTime) return;
    lastTime = barTime;

    if(!CopyAll()) return;
    if(!OpenNewPos) return;

    if(BuySignal())  return;
    if(SellSignal()) return;
}

//+------------------------------------------------------------------+
//| Copy all necessary buffers                                      |
//+------------------------------------------------------------------+
bool CopyAll(){
    int total = AosNCheck + DhlNCheck + 2;
    if(CopyBuffer(AOS_handle,0,0,total,AOS_Bull)<=0)   return false;
    if(CopyBuffer(AOS_handle,1,0,total,AOS_Bear)<=0)   return false;
    if(CopyBuffer(AOS_handle,2,0,total,AOS_Signal)<=0) return false;
    if(CopyBuffer(DHL_handle,0,0,total,DHL_H)<=0)      return false;
    if(CopyBuffer(DHL_handle,1,0,total,DHL_L)<=0)      return false;
    return true;
}

//+------------------------------------------------------------------+
//| Buy signal                                                      |
//+------------------------------------------------------------------+
bool BuySignal(){
    // Primary oscillator crossover
    if(!(AOS_Bull[2] <= AOS_Signal[2] && AOS_Bull[1] > AOS_Signal[1]))
        return false;

    // Find previous bearish cross for confluence
    int j=0;
    for(int i=3; i<AosNCheck; i++){
        if(AOS_Bull[i+1] <= AOS_Bear[i+1] && AOS_Bull[i] > AOS_Bear[i]){
            j=i; break;
        }
    }
    bool dhlOk=false;
    for(int i=j; i<j+DhlNCheck; i++){
        double barLow = iLow(_Symbol, _Period, i);
        if(barLow < DHL_L[i] && AOS_Bull[i] < AOS_Bear[i]){
            dhlOk=true; break;
        }
    }
    if(!dhlOk) return false;

    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    // Use fixed stop-loss
    double sl    = entry - SLDev*_Point;
    double lot   = CalculateLot(entry, sl);
    double tp    = entry + TPCoef * MathAbs(entry - sl);

    trade.Buy(lot, _Symbol, entry, sl, tp);
    return true;
}

//+------------------------------------------------------------------+
//| Sell signal                                                     |
//+------------------------------------------------------------------+
bool SellSignal(){
    if(!(AOS_Bear[2] <= AOS_Signal[2] && AOS_Bear[1] > AOS_Signal[1]))
        return false;

    int j=0;
    for(int i=3; i<AosNCheck; i++){
        if(AOS_Bull[i+1] >= AOS_Bear[i+1] && AOS_Bull[i] < AOS_Bear[i]){
            j=i; break;
        }
    }
    bool dhlOk=false;
    for(int i=j; i<j+DhlNCheck; i++){
        double barHigh = iHigh(_Symbol, _Period, i);
        if(barHigh > DHL_H[i] && AOS_Bull[i] > AOS_Bear[i]){
            dhlOk=true; break;
        }
    }
    if(!dhlOk) return false;

    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    // Use fixed stop-loss
    double sl    = entry + SLDev*_Point;
    double lot   = CalculateLot(entry, sl);
    double tp    = entry - TPCoef * MathAbs(entry - sl);

    trade.Sell(lot, _Symbol, entry, sl, tp);
    return true;
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size                                       |
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
    if(eq > highEquity) highEquity = eq;
    if(eq < highEquity*(1-EquityDrawdownLimit/100)) OpenNewPos = false;
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
        if(pts >= TrailingActivationPts){
            double newSL = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                           ? cur - TrailingStopLevelPct/100*pts*_Point
                           : cur + TrailingStopLevelPct/100*pts*_Point;
            trade.PositionModify(ticket, newSL, 0);
        }
    }
}
