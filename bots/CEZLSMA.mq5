#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

// Inputs: Risk Management
input double RiskPct               = 3.0;   // {0.1,10.0,0.1} risk % per trade
input double EquityDrawdownLimit   = 10.0;  // {1,20,1} max drawdown %
input double TrailingStopLevelPct  = 50.0;  // {10,100,5} % of profit to trail
input double TrailingActivationPts = 50.0;  // {10,200,10} activation in pts

// Inputs: Indicators
input int    CeAtrPeriod = 1;    // {1,10,1}
input double CeAtrMult   = 0.75; // {0.1,3.0,0.05}
input int    ZlPeriod    = 50;   // {10,200,10}

// Inputs: Filters & Strategy
input int    RSIPeriod      = 14; // {5,30,1}
input int    VolMAPeriod    = 20; // {5,50,5}
input double RSILower       = 30.0; // {10,50,1}
input double RSIUpper       = 70.0; // {50,90,1}
input int    HTF_MALen      = 50;   // {20,200,10}
input double MinSLPoints    = 100.0;// {10,500,10}
input bool   CloseOrders    = true;
bool   OpenNewPos     = true;

// Globals
datetime lastTime;
double   highEquity;

// Handles & Buffers
int HA_handle, CE_handle, ZL_handle;
int RSI_handle, VolMA_handle, HTF_handle;
double HA_buf[], CE_buf[], ZL_buf[];
double RSI_buf[], VolMA_buf[], HTF_buf[];

// Local arrays for MQL5 compatibility
long volumeArray[2];
datetime timeArray[2];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Init custom indicators
    HA_handle    = iCustom(_Symbol,_Period,"Indicators\\Heiken_Ashi.ex5");
    CE_handle    = iCustom(_Symbol,_Period,"Indicators\\ChandelierExit.ex5",CeAtrPeriod,CeAtrMult);
    ZL_handle    = iCustom(_Symbol,_Period,"Indicators\\ZLSMA.ex5",ZlPeriod,true);
    RSI_handle   = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
    VolMA_handle = iMA(_Symbol,_Period,VolMAPeriod,0,MODE_SMA,PRICE_CLOSE);
    HTF_handle   = iMA(_Symbol,PERIOD_H1,HTF_MALen,0,MODE_EMA,PRICE_CLOSE);

    // Series arrays
    ArraySetAsSeries(HA_buf,true);  ArraySetAsSeries(CE_buf,true);
    ArraySetAsSeries(ZL_buf,true);  ArraySetAsSeries(RSI_buf,true);
    ArraySetAsSeries(VolMA_buf,true);ArraySetAsSeries(HTF_buf,true);

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
//| Timer: drawdown & trailing                                      |
//+------------------------------------------------------------------+
void OnTimer(){
    CheckDrawdown();
    CheckTrailing();
}

//+------------------------------------------------------------------+
//| Tick: buffer copy & trading                                      |
//+------------------------------------------------------------------+
void OnTick(){
    if(CopyTickVolume(_Symbol, _Period, 0, 2, volumeArray) <= 0) return;
    if(CopyTime(_Symbol, _Period, 0, 2, timeArray) <= 0) return;
    if(lastTime == timeArray[0]) return;
    lastTime = timeArray[0];

    if(!CopyAll()) return;
    if(!OpenNewPos)  return;

    if(BuySignal())  return;
    if(SellSignal()) return;
}

//+------------------------------------------------------------------+
//| Copy all buffers                                                |
//+------------------------------------------------------------------+
bool CopyAll(){
    if(CopyBuffer(HA_handle,3,0,2,HA_buf)<=0)    return false;
    if(CopyBuffer(CE_handle,0,0,2,CE_buf)<=0)    return false;
    if(CopyBuffer(ZL_handle,0,1,1,ZL_buf)<=0)    return false;
    if(CopyBuffer(RSI_handle,0,1,1,RSI_buf)<=0)  return false;
    if(CopyBuffer(VolMA_handle,0,1,1,VolMA_buf)<=0)return false;
    if(CopyBuffer(HTF_handle,0,1,1,HTF_buf)<=0)  return false;
    return true;
}

//+------------------------------------------------------------------+
//| Buy signal                                                       |
//+------------------------------------------------------------------+
bool BuySignal(){
    double haC = HA_buf[1], zl = ZL_buf[0], ceStop = CE_buf[0];
    if(!(haC > zl && ceStop > 0 && ExtraFilters() && HTF_TrendUp())) return false;
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    double sl    = ceStop;
    double dist  = MathAbs(entry - sl)/_Point;
    if(dist < MinSLPoints) return false;
    double lot   = CalculateLot(entry, sl);
    trade.Buy(lot,_Symbol,entry,sl,0);
    return true;
}

//+------------------------------------------------------------------+
//| Sell signal                                                      |
//+------------------------------------------------------------------+
bool SellSignal(){
    double haC = HA_buf[1], zl = ZL_buf[0], ceStop = CE_buf[1];
    if(!(haC < zl && ceStop > 0 && ExtraFilters() && !HTF_TrendUp())) return false;
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
    double sl    = ceStop;
    double dist  = MathAbs(entry - sl)/_Point;
    if(dist < MinSLPoints) return false;
    double lot   = CalculateLot(entry, sl);
    trade.Sell(lot,_Symbol,entry,sl,0);
    return true;
}

//+------------------------------------------------------------------+
//| Filters: RSI & Volume                                           |
//+------------------------------------------------------------------+
bool ExtraFilters(){
    double rsi = RSI_buf[0], vol = (double)volumeArray[1], vMA = VolMA_buf[0];
    return (rsi > RSILower && rsi < RSIUpper && vol >= vMA);
}

//+------------------------------------------------------------------+
//| HTF trend                                                       |
//+------------------------------------------------------------------+
bool HTF_TrendUp(){
    return (SymbolInfoDouble(_Symbol,SYMBOL_BID) > HTF_buf[0]);
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
//| Position sizing                                                  |
//+------------------------------------------------------------------+
double CalculateLot(double e,double s){
    double riskAmt = AccountInfoDouble(ACCOUNT_BALANCE)*RiskPct/100;
    double tickVal = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double pts     = MathAbs(e-s)/_Point;
    double costLot = pts*tickVal/tickSz;
    return NormalizeDouble(riskAmt/costLot, GetLotDigits());
}

//+------------------------------------------------------------------+
//| Drawdown check                                                  |
//+------------------------------------------------------------------+
void CheckDrawdown(){
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq > highEquity) highEquity = eq;
    if(eq < highEquity*(1-EquityDrawdownLimit/100)) OpenNewPos = false;
}

//+------------------------------------------------------------------+
//| Trailing stop                                                   |
//+------------------------------------------------------------------+
void CheckTrailing(){
    for(int i=0;i<PositionsTotal();i++){
        ulong t = PositionGetTicket(i);
        if(t==0 || !PositionSelectByTicket(t)) continue;
        double o = PositionGetDouble(POSITION_PRICE_OPEN);
        double c = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
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
