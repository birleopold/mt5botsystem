#property version   "2.0"
#property strict

#include <Trade\Trade.mqh>
bool OpenNewPos = true;
CTrade trade;

//--- Inputs: Risk Management
input double RiskPct               = 1.0;   // risk % per trade {0.1,5.0,0.1}
input double EquityDrawdownLimit   = 10.0;  // max drawdown % {1,20,1}
input double TrailingStopLevelPct  = 50;    // % of profit {10,100,5}
input double TrailingActivationPts = 50;    // points {10,200,10}

//--- Inputs: Indicators
input int MA1Len   = 60;   // {20,200,10}
input int MA2Len   = 350;  // {100,500,50}
input int MA3Len   = 600;  // {200,800,50}
input int RSIPeriod= 14;   // {5,30,1}
input int VolMAPeriod =20; // {5,50,5}
input int HTF_MALen = 50;  // {20,200,10}

//--- Inputs: Filters & Strategy
input double MinSLPoints = 100;   // points {10,500,10}
input double TPCoef      = 1.5;   // TP = SL×coef {0.5,3.0,0.1}

//--- Globals
datetime lastTime;
double   highEquity;

//--- Handles & Buffers
int MA1h, MA2h, MA3h, FRh;
int RSIh, VMh, HTFh;
double MA1[], MA2[], MA3[], FRUp[], FRDn[];
double RSI_buf[], VolMA_buf[], HTF_buf[];

//--- Local arrays for MQL5 compatibility
long volumeArray[3];
datetime timeArray[2];
double lowArray[2], highArray[2];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Indicator handles
    MA1h = iMA(_Symbol,_Period,MA1Len,0,MODE_EMA,PRICE_CLOSE);
    MA2h = iMA(_Symbol,_Period,MA2Len,0,MODE_EMA,PRICE_CLOSE);
    MA3h = iMA(_Symbol,_Period,MA3Len,0,MODE_EMA,PRICE_CLOSE);
    FRh  = iFractals(_Symbol,_Period);
    RSIh = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
    VMh  = iMA(_Symbol,_Period,VolMAPeriod,0,MODE_SMA,PRICE_CLOSE);
    HTFh = iMA(_Symbol,PERIOD_H1,HTF_MALen,0,MODE_EMA,PRICE_CLOSE);

    // Series arrays
    ArraySetAsSeries(MA1,true); ArraySetAsSeries(MA2,true); ArraySetAsSeries(MA3,true);
    ArraySetAsSeries(FRUp,true); ArraySetAsSeries(FRDn,true);
    ArraySetAsSeries(RSI_buf,true); ArraySetAsSeries(VolMA_buf,true);
    ArraySetAsSeries(HTF_buf,true);

    EventSetTimer(30);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer: Check drawdown & trailing                                |
//+------------------------------------------------------------------+
void OnTimer(){
    CheckDrawdown();
    CheckTrailing();
}

//+------------------------------------------------------------------+
//| Tick: copy buffers & trade logic                                |
//+------------------------------------------------------------------+
void OnTick(){
    // Fill local arrays for time, low, high, and volume
    if(CopyTime(_Symbol, _Period, 0, 2, timeArray) <= 0) return;
    if(CopyLow(_Symbol, _Period, 0, 2, lowArray) <= 0) return;
    if(CopyHigh(_Symbol, _Period, 0, 2, highArray) <= 0) return;
    if(CopyTickVolume(_Symbol, _Period, 0, 3, volumeArray) <= 0) return;
    if(lastTime==timeArray[0]) return;
    lastTime=timeArray[0];

    if(!CopyAll()) return;
    if(!OpenNewPos)  return;

    if(BuySignal())  return;
    if(SellSignal()) return;
}

//+------------------------------------------------------------------+
//| Copy all required buffers                                       |
//+------------------------------------------------------------------+
bool CopyAll(){
    if(CopyBuffer(MA1h,0,0,3,MA1)<=0)   return false;
    if(CopyBuffer(MA2h,0,0,3,MA2)<=0)   return false;
    if(CopyBuffer(MA3h,0,0,3,MA3)<=0)   return false;
    if(CopyBuffer(FRh,0,0,3,FRUp)<=0)    return false;
    if(CopyBuffer(FRh,1,0,3,FRDn)<=0)    return false;
    if(CopyBuffer(RSIh,0,1,1,RSI_buf)<=0)return false;
    if(CopyBuffer(VMh,0,1,1,VolMA_buf)<=0)return false;
    if(CopyBuffer(HTFh,0,1,1,HTF_buf)<=0)return false;
    return true;
}

//+------------------------------------------------------------------+
//| Buy signal                                                      |
//+------------------------------------------------------------------+
bool BuySignal(){
    bool fractalDown = FRDn[2]!=EMPTY_VALUE;
    bool trendOK     = MA1[1]>MA2[1] && MA2[1]>MA3[1];
    bool priceOK     = lowArray[1]>MA3[1] && lowArray[1]<MA1[1];
    bool filtersOK   = ExtraFilters() && HTF_TrendUp();
    if(!(fractalDown && trendOK && priceOK && filtersOK)) return false;

    double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    double sl    = MathMax(MA2[1],MA3[1]);
    double dist  = MathAbs(entry - sl)/_Point;
    if(dist < MinSLPoints) return false;

    double lot = CalculateLot(entry, sl);
    double tp  = entry + TPCoef * dist * _Point;
    trade.Buy(lot,_Symbol,entry,sl,tp);
    return true;
}

//+------------------------------------------------------------------+
//| Sell signal                                                     |
//+------------------------------------------------------------------+
bool SellSignal(){
    bool fractalUp   = FRUp[2]!=EMPTY_VALUE;
    bool trendOK     = MA3[1]>MA2[1] && MA2[1]>MA1[1];
    bool priceOK     = highArray[1]<MA3[1] && highArray[1]>MA1[1];
    bool filtersOK   = ExtraFilters() && !HTF_TrendUp();
    if(!(fractalUp && trendOK && priceOK && filtersOK)) return false;

    double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
    double sl    = MathMin(MA2[1],MA3[1]);
    double dist  = MathAbs(entry - sl)/_Point;
    if(dist < MinSLPoints) return false;

    double lot = CalculateLot(entry, sl);
    double tp  = entry - TPCoef * dist * _Point;
    trade.Sell(lot,_Symbol,entry,sl,tp);
    return true;
}

//+------------------------------------------------------------------+
//| Extra filters: RSI & Volume                                     |
//+------------------------------------------------------------------+
bool ExtraFilters(){
    double rsi = RSI_buf[0], vol=volumeArray[1], vma=VolMA_buf[0];
    return(rsi>30 && rsi<70 && vol>=vma);
}

//+------------------------------------------------------------------+
//| Higher-TF trend                                                   |
//+------------------------------------------------------------------+
bool HTF_TrendUp(){
    return(SymbolInfoDouble(_Symbol,SYMBOL_BID)>HTF_buf[0]);
}

//+------------------------------------------------------------------+
//| Helper to get lot digits for NormalizeDouble                    |
//+------------------------------------------------------------------+
int GetLotDigits() {
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int digits = 0;
    while (step < 1.0) { step *= 10.0; digits++; }
    return digits;
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size                                       |
//+------------------------------------------------------------------+
double CalculateLot(double e,double s){
    double riskAmt   = AccountInfoDouble(ACCOUNT_BALANCE)*RiskPct/100;
    double tickVal   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    double tickSz    = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double pts       = MathAbs(e-s)/_Point;
    double costLot   = pts*tickVal/tickSz;
    double rawLots   = riskAmt/costLot;
    return(NormalizeDouble(rawLots, GetLotDigits()));
}

//+------------------------------------------------------------------+
//| Equity drawdown check                                           |
//+------------------------------------------------------------------+
void CheckDrawdown(){
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq>highEquity) highEquity=eq;
    if(eq<highEquity*(1-EquityDrawdownLimit/100))
        OpenNewPos=false;
}

//+------------------------------------------------------------------+
//| Flexible trailing stop                                          |
//+------------------------------------------------------------------+
void CheckTrailing(){
    for(int i=0;i<PositionsTotal();i++){
        ulong t = PositionGetTicket(i);
        if(t==0 || !PositionSelectByTicket(t)) continue;
        double o = PositionGetDouble(POSITION_PRICE_OPEN);
        double c = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY
                   ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                   : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double pts = MathAbs(c-o)/_Point;
        if(pts>=TrailingActivationPts){
            double newSL = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                           ? c - TrailingStopLevelPct/100*pts*_Point
                           : c + TrailingStopLevelPct/100*pts*_Point;
            trade.PositionModify(t,newSL,0);
        }
    }
}
