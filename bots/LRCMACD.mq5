#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

datetime lastTime;
double   highEquity;

//--- Global flags
bool OpenNewPos = true;

//--- Buffer indices (define if not provided by indicator)
#define LRC_BI_CLOSE 0
#define LRC_BI_OPEN  1
#define LRC_BI_SIGNAL 2
#define MODE_LOW   1
#define MODE_HIGH  2

//--- Inputs: Risk Management
input double RiskPct               = 1.0;   // {0.1,5.0,0.1} %
input double EquityDrawdownLimit   = 10.0;  // {0,20,1} %
input double TrailingStopLevelPct  = 50.0;  // {0,100,10} %
input double TrailingActivationPts = 30.0;  // {0,200,10} pts

//--- Inputs: Indicators
input int    LrLen       = 11; // {5,50,1}
input int    LrSmaLen    = 5;  // {3,20,1}
input int    MacdFast    = 34; // {5,50,1}
input int    MacdSlow    = 144;// {10,200,1}

//--- Inputs: Strategy
input int    PullbackLookback = 4;   // {1,10,1}
input double TPCoef           = 1.0; // {0.5,3.0,0.1}
input int    SLLookback       = 10;  // {1,50,1}
input int    SLDev            = 60;  // {10,200,5}
input bool   Reverse          = false;

//--- Inputs: Execution & Timer
input int    Slippage     = 30;
input int    TimerInterval= 30;
input ulong  MagicNumber  = 1000;

//--- Handles & Buffers
int    hLRC, hMACD;
double LRC_Close[], LRC_Open[], LRC_Sig[], MACD_Hist[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    // Equity tracking
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    // Init indicators
    InitIndicators();
    EventSetTimer(TimerInterval);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Initialize indicator handles                                    |
//+------------------------------------------------------------------+
void InitIndicators(){
    hLRC  = iCustom(_Symbol,_Period,"Indicators\\LinearRegressionCandles.ex5",LrLen,LrSmaLen);
    hMACD = iMACD(_Symbol,_Period,MacdFast,MacdSlow,1,PRICE_CLOSE);
    ArraySetAsSeries(LRC_Close,true); ArraySetAsSeries(LRC_Open,true);
    ArraySetAsSeries(LRC_Sig,true);   ArraySetAsSeries(MACD_Hist,true);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer: Risk checks & trailing                                   |
//+------------------------------------------------------------------+
void OnTimer(){
    CheckDrawdown();
    CheckTrailing();
}

//+------------------------------------------------------------------+
//| Tick: Copy buffers & evaluate signals                           |
//+------------------------------------------------------------------+
void OnTick(){
    datetime barTime = iTime(_Symbol, _Period, 0);
    if(lastTime==barTime) return;
    lastTime=barTime;
    if(!CopyAll() || !OpenNewPos) return;

    // Entry logic
    if(BuySignal())  return;
    if(SellSignal()) return;
}

//+------------------------------------------------------------------+
//| Copy all required buffers                                       |
//+------------------------------------------------------------------+
bool CopyAll(){
    int total = PullbackLookback+3;
    if(CopyBuffer(hLRC,   LRC_BI_CLOSE, 0, total, LRC_Close)  <=0) return false;
    if(CopyBuffer(hLRC,   LRC_BI_OPEN,  0, total, LRC_Open)   <=0) return false;
    if(CopyBuffer(hLRC,   LRC_BI_SIGNAL,0, total, LRC_Sig)    <=0) return false;
    if(CopyBuffer(hMACD,0,0, total, MACD_Hist)              <=0) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Determine Buy signal                                            |
//+------------------------------------------------------------------+
bool BuySignal(){
    // MACD rising and LRC crossing above signal on latest bar
    if(!(MACD_Hist[1]>0 && MACD_Hist[2]>0 &&
         LRC_Close[1]>LRC_Open[1] && LRC_Close[1]>LRC_Sig[1] &&
         LRC_Close[2]<=LRC_Sig[2] && LRC_Close[2]>LRC_Open[2]))
        return false;
    // Pullback check: require a bearish swing before entry
    int j=0;
    for(int i=2;i<PullbackLookback+2;i++){
        if(MACD_Hist[i]>0 && LRC_Close[i]<LRC_Open[i]){
            j=i; break;
        }
    }
    if(j==0) return false;
    // Ensure MACD stays positive throughout the pullback
    for(int i=j; i<j+PullbackLookback; i++){
        if(MACD_Hist[i]<=0 || LRC_Close[i]>LRC_Open[i]) return false;
    }
    // Place Buy order
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    double sl    = iLow(_Symbol,0,iLowest(_Symbol,0,MODE_LOW,SLLookback,1)) - SLDev*_Point;
    double lot   = CalculateLot(entry, sl);
    double tp    = entry + TPCoef * MathAbs(entry - sl);
    trade.Buy(lot,_Symbol,entry,sl,tp);
    return true;
}

//+------------------------------------------------------------------+
//| Determine Sell signal                                           |
//+------------------------------------------------------------------+
bool SellSignal(){
    if(!(MACD_Hist[1]<0 && MACD_Hist[2]<0 &&
         LRC_Close[1]<LRC_Open[1] && LRC_Close[1]<LRC_Sig[1] &&
         LRC_Close[2]>=LRC_Sig[2] && LRC_Close[2]<LRC_Open[2]))
        return false;
    int j=0;
    for(int i=2;i<PullbackLookback+2;i++){
        if(MACD_Hist[i]<0 && LRC_Close[i]>LRC_Open[i]){
            j=i; break;
        }
    }
    if(j==0) return false;
    for(int i=j; i<j+PullbackLookback; i++){
        if(MACD_Hist[i]>=0 || LRC_Close[i]<LRC_Open[i]) return false;
    }
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
    double sl    = iHigh(_Symbol,0,iHighest(_Symbol,0,MODE_HIGH,SLLookback,1)) + SLDev*_Point;
    double lot   = CalculateLot(entry, sl);
    double tp    = entry - TPCoef * MathAbs(entry - sl);
    trade.Sell(lot,_Symbol,entry,sl,tp);
    return true;
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size                                       |
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

//+------------------------------------------------------------------+
//| Drawdown limiter                                                |
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
