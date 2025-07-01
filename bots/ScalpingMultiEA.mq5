//+------------------------------------------------------------------+
//| Scalping EA - Final Optimized Version                           |
//+------------------------------------------------------------------+
#property copyright "LeoSoft"
#property version   "3.0"
#property strict
#include <Trade\Trade.mqh>

//--- Global Variables
CTrade   trade;
datetime lastBarTime;
double   highEquity;

//--- Input Parameters
input string   MAIN_SETTINGS    = "--- Main Settings ---";  //.
input double   RiskPerTrade     = 0.5;                      // Risk % per trade
input double   AO_Threshold     = 0.00015;                  // AO Entry Threshold
input int      ConsecutiveBars  = 2;                        // Consecutive Signals

input string   RISK_MGMT       = "--- Risk Management ---"; //.
input double   MaxDrawdown      = 2.0;                      // Max Equity Drawdown %
input int      MaxTrades        = 5;                        // Max Simultaneous Trades

input string   ORDER_SETTINGS  = "--- Order Settings ---";  //.
input int      SL_Points        = 15;                       // Stop Loss (points)
input double   RR_Ratio         = 1.5;                      // Risk:Reward Ratio
input bool     UseBreakeven     = true;                     // Use Breakeven Stops
input int      BreakevenAfter   = 5;                        // Points for Breakeven

input string   SYMBOL_SETTINGS = "--- Symbol Settings ---"; //.
input string   TradeSymbol      = "EURUSD";                 // Trading Symbol
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M1;                // Chart Timeframe

//--- Indicator Handles
int    aoHandle;
double aoBuffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                  |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize AO indicator
    aoHandle = iAC(TradeSymbol, TimeFrame);
    if(aoHandle == INVALID_HANDLE){
        Alert("Error creating Accelerator Oscillator");
        return(INIT_FAILED);
    }
    ArraySetAsSeries(aoBuffer, true);
    
    // Initialize trade object
    trade.SetExpertMagicNumber(2024);
    trade.SetDeviationInPoints(3);
    
    // Initialize equity tracking
    highEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    EventSetTimer(10);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
    static datetime lastTickTime;
    datetime currentTime = iTime(TradeSymbol, TimeFrame, 0);
    
    // Only process once per bar
    if(currentTime == lastBarTime) return;
    lastBarTime = currentTime;
    
    // Core trading logic
    CheckTradingPermission();
    ManageOpenPositions();
    CheckTradingSignals();
    UpdateEquityHigh();
}

//+------------------------------------------------------------------+
//| Trading Signal Detection                                         |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
    if(!CopyAOData(ConsecutiveBars + 1)) return;
    
    bool buySignal = true;
    bool sellSignal = true;
    
    // Check consecutive signals
    for(int i = 0; i < ConsecutiveBars; i++){
        if(aoBuffer[i] >= -AO_Threshold) buySignal = false;
        if(aoBuffer[i] <= AO_Threshold) sellSignal = false;
    }
    
    // Execute trades if signals valid
    if(buySignal && CountPositions(POSITION_TYPE_BUY) < MaxTrades){
        ExecuteTrade(ORDER_TYPE_BUY);
    }
    else if(sellSignal && CountPositions(POSITION_TYPE_SELL) < MaxTrades){
        ExecuteTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Trade Execution Logic                                            |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE tradeType)
{
    double price = (tradeType == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(TradeSymbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
    
    double stopLoss = (tradeType == ORDER_TYPE_BUY) ? 
                      price - SL_Points * _Point : 
                      price + SL_Points * _Point;
    
    double takeProfit = (tradeType == ORDER_TYPE_BUY) ? 
                        price + (SL_Points * RR_Ratio) * _Point : 
                        price - (SL_Points * RR_Ratio) * _Point;
    
    double lotSize = CalculatePositionSize(price, stopLoss);
    
    if(tradeType == ORDER_TYPE_BUY){
        trade.Buy(lotSize, TradeSymbol, price, stopLoss, takeProfit);
    }
    else{
        trade.Sell(lotSize, TradeSymbol, price, stopLoss, takeProfit);
    }
}

//+------------------------------------------------------------------+
//| Money Management System                                          |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double stopLoss)
{
    double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * (RiskPerTrade / 100);
    double tickValue = SymbolInfoDouble(TradeSymbol, SYMBOL_TRADE_TICK_VALUE);
    double riskPoints = MathAbs(entryPrice - stopLoss) / _Point;
    
    return NormalizeDouble(riskAmount / (riskPoints * tickValue), 2);
}

//+------------------------------------------------------------------+
//| Position Management System                                       |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    for(int i = PositionsTotal()-1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        
        if(UseBreakeven) CheckBreakeven(ticket);
        CheckTrailingStop(ticket);
    }
}

//+------------------------------------------------------------------+
//| Breakeven Stop System                                            |
//+------------------------------------------------------------------+
void CheckBreakeven(ulong ticket)
{
    double currentProfit = PositionGetDouble(POSITION_PROFIT);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){
        double newSL = openPrice + (BreakevenAfter * _Point);
        if(currentSL < newSL && currentProfit >= BreakevenAfter * _Point){
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
    }
    else{
        double newSL = openPrice - (BreakevenAfter * _Point);
        if(currentSL > newSL && currentProfit >= BreakevenAfter * _Point){
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
    }
}

//+------------------------------------------------------------------+
//| Trailing Stop System                                            |
//+------------------------------------------------------------------+
void CheckTrailingStop(ulong ticket)
{
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    int positionType = PositionGetInteger(POSITION_TYPE);
    double price = (positionType == POSITION_TYPE_BUY) ? SymbolInfoDouble(TradeSymbol, SYMBOL_BID) : SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(TradeSymbol, SYMBOL_POINT);
    int trailingDistance = SL_Points; // Use SL_Points as trailing distance, or create a new input if desired

    // Only trail if in profit by at least trailing distance
    if(positionType == POSITION_TYPE_BUY)
    {
        double newSL = price - trailingDistance * point;
        if(newSL > currentSL && price - openPrice > trailingDistance * point)
        {
            trade.PositionModify(ticket, newSL, currentTP);
        }
    }
    else if(positionType == POSITION_TYPE_SELL)
    {
        double newSL = price + trailingDistance * point;
        if(newSL < currentSL && openPrice - price > trailingDistance * point)
        {
            trade.PositionModify(ticket, newSL, currentTP);
        }
    }
}

//+------------------------------------------------------------------+
//| Close All Positions Function                                     |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == 2024 && PositionGetString(POSITION_SYMBOL) == TradeSymbol)
            {
                int type = PositionGetInteger(POSITION_TYPE);
                double volume = PositionGetDouble(POSITION_VOLUME);
                if(type == POSITION_TYPE_BUY)
                    trade.PositionClose(ticket);
                else if(type == POSITION_TYPE_SELL)
                    trade.PositionClose(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Core Utility Functions                                           |
//+------------------------------------------------------------------+
bool CopyAOData(int barsNeeded)
{
    if(CopyBuffer(aoHandle, 0, 0, barsNeeded, aoBuffer) < barsNeeded){
        Print("Error copying AO data: ", GetLastError());
        return false;
    }
    return true;
}

int CountPositions(int positionType)
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++){
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && 
           PositionGetInteger(POSITION_TYPE) == positionType && 
           PositionGetInteger(POSITION_MAGIC) == 2024){
            count++;
        }
    }
    return count;
}

void CheckTradingPermission()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(currentEquity < highEquity * (1 - (MaxDrawdown / 100))){
        CloseAllPositions();
        ExpertRemove();
    }
}

void UpdateEquityHigh()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(currentEquity > highEquity) highEquity = currentEquity;
}

//+------------------------------------------------------------------+
//| Timer Function for Regular Checks                                |
//+------------------------------------------------------------------+
void OnTimer()
{
    CheckTradingPermission();
    UpdateEquityHigh();
}

//+------------------------------------------------------------------+
//| Deinitialization Function                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    IndicatorRelease(aoHandle);
}