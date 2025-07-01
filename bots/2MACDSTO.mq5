//--- Expert settings
#property version   "2.0"
#property strict

#include <Trade\Trade.mqh>

//--- Global state
bool OpenNewPos = true;

input double RiskPct               = 0.02;      // risk per trade (2%)
input double EquityDrawdownLimit   = 0.10;      // max drawdown (10%)
input double TrailingStopLevelPct  = 0.5;       // trailing stop % of profit
input double TrailingActivationPts = 50;        // trailing activation (points)

input int    M1Fast  = 13, M1Slow = 21;
input int    M2Fast  = 34, M2Slow = 144;
input int    StoK    = 7,  StoD   = 3, StoSl = 3;
input int    RSI_Period = 14;
input int    VolMAPer   = 20;

CTrade trade;
datetime lastTime;
double   highEquity;

// Indicator handles
int M1h, M2h, Stoh, RSIh, VolMAh, HTFh;
double M1_buf[], M2_buf[], StoM_buf[], StoS_buf[];
double RSI_buf[], Vol_buf[], VolMA_buf[], HTF_buf[];

//--- Local arrays for times and volumes (MQL5 style)
datetime timeArray[3];
long volumeArray[3];

int OnInit() {
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    //--- Init indicators
    M1h   = iMACD(_Symbol,_Period,M1Fast,M1Slow,1,PRICE_CLOSE);
    M2h   = iMACD(_Symbol,_Period,M2Fast,M2Slow,1,PRICE_CLOSE);
    Stoh  = iStochastic(_Symbol,_Period,StoK,StoD,StoSl,MODE_SMA,STO_LOWHIGH);
    RSIh  = iRSI(_Symbol,_Period,RSI_Period,PRICE_CLOSE);
    VolMAh= iMA(_Symbol,_Period,VolMAPer,0,MODE_SMA,PRICE_CLOSE);
    HTFh  = iMA(_Symbol,PERIOD_H4,50,0,MODE_EMA,PRICE_CLOSE);
    //--- Set buffers as series
    ArraySetAsSeries(M1_buf,true); ArraySetAsSeries(M2_buf,true);
    ArraySetAsSeries(StoM_buf,true);ArraySetAsSeries(StoS_buf,true);
    ArraySetAsSeries(RSI_buf,true); ArraySetAsSeries(VolMA_buf,true);
    ArraySetAsSeries(HTF_buf,true);
    EventSetTimer(30);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTimer() {
    CheckDrawdown();
    CheckTrailing();
}

void OnTick() {
    // Fill local arrays for time and volume
    if(CopyTime(_Symbol, _Period, 0, 3, timeArray) <= 0) return;
    if(CopyTickVolume(_Symbol, _Period, 0, 3, volumeArray) <= 0) return;
    if(lastTime == timeArray[0]) return;
    lastTime = timeArray[0];
    if(!CopyAllBuffers()) return;

    if(!OpenNewPos) return;
    if(BuySignal())  return;
    if(SellSignal()) return;
}

//--- Buffer copying
bool CopyAllBuffers(){
    if(CopyBuffer(M1h,0,0,3,M1_buf)<=0)    return false;
    if(CopyBuffer(M2h,0,0,3,M2_buf)<=0)    return false;
    if(CopyBuffer(Stoh,0,0,3,StoM_buf)<=0) return false;
    if(CopyBuffer(Stoh,1,0,3,StoS_buf)<=0) return false;
    if(CopyBuffer(RSIh,0,1,1,RSI_buf)<=0)  return false;
    if(CopyBuffer(VolMAh,0,1,1,VolMA_buf)<=0)return false;
    if(CopyBuffer(HTFh,0,1,1,HTF_buf)<=0)  return false;
    return true;
}

//--- Signals
bool BuySignal(){
    if(!(M2_buf[2]>0 && M1_buf[2]<0
      && StoM_buf[2]<20 && StoM_buf[2]<=StoS_buf[2]
      && StoM_buf[1]>StoS_buf[1]
      && RSI_buf[0]>30 && volumeArray[1]>=VolMA_buf[0]
      && SymbolInfoDouble(_Symbol,SYMBOL_BID)>HTF_buf[0]))
        return false;
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    double sl    = entry - StoSl*_Point;
    double lot   = CalculateLot(entry, sl);
    trade.Buy(lot, _Symbol, entry, sl, 0);
    return true;
}

bool SellSignal(){
    if(!(M2_buf[2]<0 && M1_buf[2]>0
      && StoM_buf[2]>80 && StoM_buf[2]>=StoS_buf[2]
      && StoM_buf[1]<StoS_buf[1]
      && RSI_buf[0]<70 && volumeArray[1]>=VolMA_buf[0]
      && SymbolInfoDouble(_Symbol,SYMBOL_ASK)<HTF_buf[0]))
        return false;
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
    double sl    = entry + StoSl*_Point;
    double lot   = CalculateLot(entry, sl);
    trade.Sell(lot, _Symbol, entry, sl, 0);
    return true;
}

//--- Risk helpers
// Replace SYMBOL_VOLUME_DIGITS with lot digits calculation
// Use SYMBOL_VOLUME_STEP to infer lot digits
int GetLotDigits() {
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int digits = 0;
    while (step < 1.0) { step *= 10.0; digits++; }
    return digits;
}

double CalculateLot(double price, double sl) {
    double riskAmt  = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPct;
    double pipValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE)
                    / SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double dist     = MathAbs(price - sl) * pipValue;
    double rawLots  = riskAmt / dist;
    return NormalizeDouble(rawLots, GetLotDigits());
}

void CheckDrawdown() {
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq > highEquity) highEquity = eq;
    if(eq < highEquity * (1 - EquityDrawdownLimit))
        OpenNewPos = false;
}

void CheckTrailing() {
    for(int i=PositionsTotal()-1; i>=0; i--){
        ulong ticket = PositionGetTicket(i);
        if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
        double open  = PositionGetDouble(POSITION_PRICE_OPEN);
        double cur   = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                       ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                       : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double profitPts = MathAbs(cur - open)/_Point;
        if(profitPts >= TrailingActivationPts)
            trade.PositionModify(ticket, 0, cur - TrailingStopLevelPct/100 * profitPts * _Point);
    }
}
