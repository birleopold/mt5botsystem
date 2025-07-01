#property version   "2.0"
#property strict
#include <Trade\Trade.mqh>
#include <Cot.mqh>
#include <Sql.mqh>

CTrade      trade;
double      highEquity;
datetime    lastTime;
bool        OpenNewPos = true;

// Inputs: Risk Management
input double RiskPct               = 3.5;   // {0.1,10.0,0.1}
input double EquityDrawdownLimit   = 10.0;  // {1,20,1}
input double TrailingStopLevelPct  = 50.0;  // {10,100,5}
input double TrailingActivationPts = 50.0;  // {10,200,10}

// Inputs: COT & SuperTrend
input ENUM_COT_CLASS_CO CotPrimaryClass   = COT_CLASS_CO_DEALER;
input ENUM_COT_MODE      CotPrimaryMode    = COT_MODE_FO;
input ENUM_COT_CLASS_CO CotSecondaryClass = COT_CLASS_CO_LEV;
input ENUM_COT_MODE      CotSecondaryMode  = COT_MODE_FO;
input bool              StEnable          = false;
input double            StMultiplier      = 3.0;   // {1,5,0.5}
input int               StPeriod          = 10;    // {5,30,5}
input ENUM_TIMEFRAMES   IndTimeframe      = PERIOD_M15;

// Inputs: General Strategy
input string            OpenTime          = "03:00";
input double            TPCoef            = 2.0;   // TP = SL×coef {1,5,0.1}
input ENUM_SL           SLType            = SL_AR;
input int               SLLookback        = 6;
input int               SLDev             = 30;
input bool              Reverse           = false;

// Inputs: Grid & News
input bool              Grid              = true;
input double            GridVolMult       = 1.2;
input int               GridMaxLvl        = 20;
input bool              News              = false;

// Inputs: Execution
input int               Slippage          = 30;
input int               TimerInterval     = 120;
input ulong             MagicNumber       = 1004;
input ENUM_FILLING      Filling           = FILLING_DEFAULT;
input int               SignalCheckInterval=15;   // minutes

// Buffers & handles
int ST_handle, RSI_handle, HTF_handle;
double ST_buf[], RSI_buf[], HTF_buf[];

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit(){
    // Risk tracking
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    // Init COT database
    if(!CotInit(CotGetReportType(CotPrimaryClass,CotPrimaryMode)))
        return(INIT_FAILED);
    if(!CotInit(CotGetReportType(CotSecondaryClass,CotSecondaryMode)))
        return(INIT_FAILED);

    // Init SuperTrend
    if(StEnable){
        ST_handle = iCustom(_Symbol,IndTimeframe,"Indicators\\SuperTrend.ex5",StPeriod,StMultiplier,false);
        ArraySetAsSeries(ST_buf,true);
    }
    // RSI for filter
    RSI_handle = iRSI(_Symbol,_Period,14,PRICE_CLOSE);
    ArraySetAsSeries(RSI_buf,true);

    // HTF EMA filter (H1)
    HTF_handle = iMA(_Symbol,PERIOD_H1,50,0,MODE_EMA,PRICE_CLOSE);
    ArraySetAsSeries(HTF_buf,true);

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
//| Timer: risk checks and signal polling                           |
//+------------------------------------------------------------------+
void OnTimer(){
    datetime tc = TimeCurrent();
    CheckDrawdown();
    CheckTrailing();
    CheckForSignal(tc);
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size                                      |
//+------------------------------------------------------------------+
double CalculateLot(double entry,double sl){
    double riskAmt = AccountInfoDouble(ACCOUNT_BALANCE)*RiskPct/100;
    double tickVal = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double pts     = MathAbs(entry-sl)/_Point;
    double costLot = pts*tickVal/tickSz;
    return NormalizeDouble(riskAmt/costLot, GetLotDigits());
}

// Helper to get lot digits for NormalizeDouble
int GetLotDigits() {
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int digits = 0;
    while (step < 1.0) { step *= 10.0; digits++; }
    return digits;
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

//+------------------------------------------------------------------+
//| Signal polling using COT & SuperTrend                           |
//+------------------------------------------------------------------+
void CheckForSignal(datetime tc){
    static datetime lastCheck=0;
    if(tc-lastCheck < SignalCheckInterval*60) return;
    lastCheck = tc;
    if(!OpenNewPos || TimeDayOfWeek(tc)>TUESDAY) return;

    // Fetch COT signals
    SSignal sigs[];
    if(!FetchSignals(CotPrimaryClass,CotPrimaryMode,sigs,tc)) return;
    if(!FetchSignals(CotSecondaryClass,CotSecondaryMode,sigs,tc)) return;

    // Loop through signals
    for(int i=0;i<ArraySize(sigs);i++){
        string sym = sigs[i].symbol, type = sigs[i].type;
        if(ea.OPTotal(sym)>0 || hasDealCurrentWeek(MagicNumber,sym)) continue;
        if(SpreadLimit>=0 && Spread(sym)>SpreadLimit) continue;

        // SuperTrend filter
        if(StEnable){
            double buf;
            CopyBuffer(ST_handle,2,1,1,ST_buf);
            buf = ST_buf[0];
            double c = iClose(sym,IndTimeframe,0);
            if((type=="buy" && c<=buf) || (type=="sell" && c>=buf))
                continue;
        }

        // Place order
        double entry = (type=="buy")?Ask(sym):Bid(sym);
        double sl    = (type=="buy")
                       ? BuySL(SLType,SLLookback,entry,SLDev,0,sym,PERIOD_D1)
                       : SellSL(SLType,SLLookback,entry,SLDev,0,sym,PERIOD_D1);
        double tp    = (type=="buy")
                       ? entry + TPCoef*MathAbs(entry-sl)
                       : entry - TPCoef*MathAbs(entry-sl);

        if(type=="buy"){
            trade.Buy(CalculateLot(entry,sl),sym,entry,sl,tp);
        } else {
            trade.Sell(CalculateLot(entry,sl),sym,entry,sl,tp);
        }
        Sleep(5000);
    }
}
