//+------------------------------------------------------------------+
//| Scalping EA using Accelerator Oscillator                        |
//+------------------------------------------------------------------+
#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>

bool OpenNewPos = true;
CTrade      trade;
datetime    lastBarTime;
double      highEquity;

//--- Inputs: Risk & Position Sizing
input double RiskPct               = 1.0;   // Still present, not used
input double EquityDrawdownLimit   = 10.0;  // Max equity drawdown %
input double Threshold             = 0.0001;// AO threshold for entry
input int    MaxPositions          = 100;   // Max trades

//--- Inputs: Stop Loss / Take Profit
input int    SLPoints              = 50;    // 5 pips stop loss
input double TPCoef                = 1.2;   // TP = 1.2x SL

//--- Inputs: Trailing Stop
input bool   UseTrailing           = true;
input double TrailingLevelPct      = 80.0;  // Trail 80% of profit
input double TrailingActivationPts = 10.0;  // Activate after 1 pip

//--- Inputs: Execution & Timer
input int    Slippage              = 5;
input int    TimerInterval         = 30;
input ulong  MagicNumber           = 2023;

//--- Global handles & buffers
int    hAO;
double AO_Buf[3];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    hAO = iAC(_Symbol,_Period);
    if(hAO == INVALID_HANDLE){
        Print("iAC handle error: ",GetLastError());
        return(INIT_FAILED);
    }
    ArraySetAsSeries(AO_Buf,true);
    EventSetTimer(TimerInterval);

    // Set magic number for the trade object
    trade.SetExpertMagicNumber(MagicNumber);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer: check drawdown and trailing                              |
//+------------------------------------------------------------------+
void OnTimer(){
    CheckDrawdown();
    if(UseTrailing) CheckTrailing();
}

//+------------------------------------------------------------------+
//| Tick event: trade only once per new bar                         |
//+------------------------------------------------------------------+
void OnTick(){
    datetime t = iTime(_Symbol,_Period,0);
    if(t == lastBarTime) return;
    lastBarTime = t;
    CheckForSignals();
}

//+------------------------------------------------------------------+
//| Copy AO values                                                  |
//+------------------------------------------------------------------+
bool CopyAO(){
    if(CopyBuffer(hAO,0,0,3,AO_Buf) <= 0){
        Print("AO CopyBuffer error: ",GetLastError());
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Count open positions by type                                    |
//+------------------------------------------------------------------+
int CountPositions(int type){
    int count = 0;
    for(int i=0; i<PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_TYPE) == type &&
           PositionGetInteger(POSITION_MAGIC) == MagicNumber) count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Entry signal generation                                         |
//+------------------------------------------------------------------+
void CheckForSignals(){
    if(!OpenNewPos) return;
    if(!CopyAO()) return;

    int buys  = CountPositions(POSITION_TYPE_BUY);
    int sells = CountPositions(POSITION_TYPE_SELL);

    double ao = AO_Buf[0];

    if(ao > Threshold && sells < MaxPositions){
        EnterTrade(ORDER_TYPE_SELL);
    }
    else if(ao < -Threshold && buys < MaxPositions){
        EnterTrade(ORDER_TYPE_BUY);
    }
}

//+------------------------------------------------------------------+
//| Fixed lot size for scalping                                     |
//+------------------------------------------------------------------+
double CalculateLot(double entry, double sl){
    return 0.05;  // Fixed 0.05 lots
}

//+------------------------------------------------------------------+
//| Market order execution                                          |
//+------------------------------------------------------------------+
void EnterTrade(int type){
    double price = (type == ORDER_TYPE_BUY)
                   ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = (type == ORDER_TYPE_BUY)
                ? price - SLPoints * _Point
                : price + SLPoints * _Point;
    double lot = CalculateLot(price, sl);
    double tp = (type == ORDER_TYPE_BUY)
                ? price + TPCoef * MathAbs(price - sl)
                : price - TPCoef * MathAbs(price - sl);

    // Send order
    if(type == ORDER_TYPE_BUY)
        trade.Buy(lot, _Symbol, price, sl, tp, NULL);
    else
        trade.Sell(lot, _Symbol, price, sl, tp, NULL);
}

//+------------------------------------------------------------------+
//| Limit drawdown by disabling new positions                       |
//+------------------------------------------------------------------+
void CheckDrawdown(){
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    if(eq > highEquity) highEquity = eq;
    if(eq < highEquity * (1 - EquityDrawdownLimit / 100.0))
        OpenNewPos = false;
}

//+------------------------------------------------------------------+
//| Trailing stop logic                                             |
//+------------------------------------------------------------------+
void CheckTrailing(){
    for(int i=0; i<PositionsTotal(); i++){
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;

        int type = PositionGetInteger(POSITION_TYPE);
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        double open  = PositionGetDouble(POSITION_PRICE_OPEN);
        double cur   = (type == POSITION_TYPE_BUY)
                       ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double pts   = MathAbs(cur - open) / _Point;

        if(pts >= TrailingActivationPts){
            double newSL = (type == POSITION_TYPE_BUY)
                           ? cur - TrailingLevelPct / 100.0 * pts * _Point
                           : cur + TrailingLevelPct / 100.0 * pts * _Point;
            trade.PositionModify(ticket, newSL, 0);
        }
    }
}
