#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade      trade;
datetime    lastTime;
double      highEquity;

//--- Inputs: Symbols
input bool   MultipleSymbols         = true;
input string Symbols                 = "USDCAD,AUDUSD,EURCHF"; // comma-delimited

//--- Inputs: Indicators
input double NweBandWidth            = 8.0;   // {1,20,1}
input double NweMultiplier           = 3.0;   // {1,5,0.5}
input int    NweWindowSize           = 500;   // {100,2000,100}
input int    RsiLength               = 5;     // {3,30,1}
input int    AsfLength               = 14;    // {5,50,1}
input double AsfMultiplier           = 0.75;  // {0.1,2.0,0.1}

//--- Inputs: Strategy & Timing
input double TPCoef                  = 1.5;   // {0.5,3.0,0.1}
input int    MinPosInterval          = 4;     // {1,10,1} bars
input bool   Reverse                 = false;

//--- Inputs: Risk Management
input double RiskPct                 = 1.2;   // {0.1,5.0,0.1} % per trade
input double EquityDrawdownLimit     = 10.0;  // {0,20,1} % max drawdown
input bool   IgnoreSL                = false;
input bool   IgnoreTP                = true;
input bool   Trail                   = true;
input double TrailingStopLevelPct    = 50.0;  // {0,100,10} % of profit
input double TrailingActivationPts   = 30.0;  // {0,200,10} pts before trail

//--- Inputs: Execution & Timer
input bool   Grid                    = true;
input double GridVolMult             = 1.1;   // grid volume multiplier
input int    GridMaxLevels           = 20;
input int    Slippage                = 30;
input int    TimerInterval           = 120;
input ulong  MagicNumber             = 1002;

//--- Global Data
string      symbols[];
int         hNWE, hRSI, hASF;
double      NWE_Upper[], NWE_Lower[], RSI_Buf[], ASF_Up[], ASF_Dn[];

//--- Control flags and limits
bool   OpenNewPos     = true;    // Allow opening new positions
input double MarginLimit = 100;  // Minimum margin level to allow new positions

//--- Indicator names (should match your custom indicator file names)
#define I_NWE "NWE"
#define I_ASF "ASF"

//--- Helper functions for multi-symbol OHLCV and price
// These functions safely get price data for any symbol and shift
// If symbol is "", use _Symbol

double GetLow(int shift, string symbol)   { return iLow(symbol==""?_Symbol:symbol, 0, shift); }
double GetHigh(int shift, string symbol)  { return iHigh(symbol==""?_Symbol:symbol, 0, shift); }
double GetClose(int shift, string symbol) { return iClose(symbol==""?_Symbol:symbol, 0, shift); }
double GetOpen(int shift, string symbol)  { return iOpen(symbol==""?_Symbol:symbol, 0, shift); }
double GetAsk(string symbol)              { return SymbolInfoDouble(symbol==""?_Symbol:symbol, SYMBOL_ASK); }
double GetBid(string symbol)              { return SymbolInfoDouble(symbol==""?_Symbol:symbol, SYMBOL_BID); }

//--- Helper: check for recent deals for symbol/magic/interval
bool hasDealRecently(ulong magic, string symbol, int barsInterval) {
    datetime lastDeal = 0;
    for(int i=0; i<HistoryDealsTotal(); i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == magic &&
           HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol) {
            datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            if(t > lastDeal) lastDeal = t;
        }
    }
    if(lastDeal == 0) return false;
    datetime lastBarTime = iTime(symbol, 0, 0);
    datetime prevBarTime = iTime(symbol, 0, barsInterval);
    return (lastDeal >= prevBarTime);
}

//+------------------------------------------------------------------+
//| Expert init                                                      |
//+------------------------------------------------------------------+
int OnInit(){
    // Parse symbols
    StringSplit(Symbols, ',', symbols);
    // Equity tracking
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    // Init indicators
    InitIndicators();
    EventSetTimer(TimerInterval);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Init custom & built-in indicator handles                         |
//+------------------------------------------------------------------+
void InitIndicators(){
    hNWE = iCustom(NULL,0,I_NWE,NweBandWidth,NweMultiplier,NweWindowSize);
    hRSI = iRSI(NULL,0,RsiLength,PRICE_CLOSE);
    hASF = iCustom(NULL,0,I_ASF,AsfLength,AsfMultiplier);
    ArraySetAsSeries(NWE_Upper,true); ArraySetAsSeries(NWE_Lower,true);
    ArraySetAsSeries(RSI_Buf,true);
    ArraySetAsSeries(ASF_Up,true); ArraySetAsSeries(ASF_Dn,true);
}

//+------------------------------------------------------------------+
//| Expert deinit                                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer: trailing & drawdown                                       |
//+------------------------------------------------------------------+
void OnTimer(){
    if(Trail)    CheckTrailing();
    if(EquityDrawdownLimit>0) CheckDrawdown();
    if(Grid)    // placeholder for grid logic
    CheckForSignal();
}

//+------------------------------------------------------------------+
//| OnTick: new bar logic & signal processing                        |
//+------------------------------------------------------------------+
void OnTick(){
    datetime barTime = iTime(_Symbol, 0, 0);
    if(barTime==lastTime) return;
    lastTime=barTime;
    CheckForSignal();
}

//+------------------------------------------------------------------+
//| Copy buffers for one symbol                                      |
//+------------------------------------------------------------------+
bool CopyAll(string s){
    if(CopyBuffer(hNWE,0,0,3,NWE_Upper)<=0) return false;
    if(CopyBuffer(hNWE,1,0,3,NWE_Lower)<=0) return false;
    if(CopyBuffer(hRSI,0,0,3,RSI_Buf)   <=0) return false;
    if(CopyBuffer(hASF,0,0,3,ASF_Up)    <=0) return false;
    if(CopyBuffer(hASF,1,0,3,ASF_Dn)    <=0) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Generate and execute signals                                     |
//+------------------------------------------------------------------+
void CheckForSignal(){
    if(!OpenNewPos) return;
    for(int i=0;i<ArraySize(symbols);i++){
        string s = symbols[i];
        if(PositionsTotal()>0 && !MultipleSymbols) break;
        if(!CopyAll(s)) continue;
        if(PositionsTotal()>0 && AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)<MarginLimit) continue;
        if(TrailingStopLevelPct>0) CheckTrailing();
        // Conditions
        bool bc = (GetLow(2,s) < NWE_Lower[2]) && (GetClose(1,s)>GetOpen(1,s))
                  && (GetAsk(s) < NWE_Lower[1] + 0.5*(NWE_Upper[1]-NWE_Lower[1]))
                  && (RSI_Buf[1] < 30);
        bool sc = (GetHigh(2,s)>NWE_Upper[2]) && (GetClose(1,s)<GetOpen(1,s))
                  && (GetBid(s) > NWE_Upper[1] - 0.5*(NWE_Upper[1]-NWE_Lower[1]))
                  && (RSI_Buf[1] > 70);
        if(bc && !hasDealRecently(MagicNumber,s,MinPosInterval)){
            double in = GetAsk(s);
            double sl = ASF_Dn[1];
            double lot= CalculateLot(s, in,sl);
            double tp = in + TPCoef * MathAbs(in-sl);
            trade.Buy(lot,s,in, sl, tp);
        } else if(sc && !hasDealRecently(MagicNumber,s,MinPosInterval)){
            double in = GetBid(s);
            double sl = ASF_Up[1];
            double lot= CalculateLot(s, in,sl);
            double tp = in - TPCoef * MathAbs(in-sl);
            trade.Sell(lot,s,in, sl, tp);
        }
    }
}

//+------------------------------------------------------------------+
//| Dynamic lot sizing                                               |
//+------------------------------------------------------------------+
double CalculateLot(string symbol, double e,double s){
    double riskAmt = AccountInfoDouble(ACCOUNT_BALANCE)*RiskPct/100;
    double tickVal = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
    double pts     = MathAbs(e-s)/SymbolInfoDouble(symbol,SYMBOL_POINT);
    // Calculate digits from volume step
    double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    int digits = 0;
    if(step > 0.0) {
        double logStep = MathLog10(1.0/step);
        digits = (int)MathRound(logStep);
    }
    return NormalizeDouble(riskAmt/(pts*tickVal/tickSz), digits);
}

//+------------------------------------------------------------------+
//| Drawdown limiter                                                 |
//+------------------------------------------------------------------+
void CheckDrawdown(){
    double eq=AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq>highEquity) highEquity=eq;
    if(eq<highEquity*(1-EquityDrawdownLimit/100)) OpenNewPos=false;
}

//+------------------------------------------------------------------+
//| Flexible trailing stop                                           |
//+------------------------------------------------------------------+
void CheckTrailing(){
    for(int i=0;i<PositionsTotal();i++){
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        string symbol = PositionGetString(POSITION_SYMBOL);
        ulong t=PositionGetInteger(POSITION_TICKET);
        double o=PositionGetDouble(POSITION_PRICE_OPEN);
        double c=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                 ?SymbolInfoDouble(symbol,SYMBOL_BID)
                 :SymbolInfoDouble(symbol,SYMBOL_ASK);
        double pts=MathAbs(c-o)/SymbolInfoDouble(symbol,SYMBOL_POINT);
        if(pts>=TrailingActivationPts){
            double ns=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                      ?c - TrailingStopLevelPct/100*pts*SymbolInfoDouble(symbol,SYMBOL_POINT)
                      :c + TrailingStopLevelPct/100*pts*SymbolInfoDouble(symbol,SYMBOL_POINT);
            trade.PositionModify(t,ns,0);
        }
    }
}
