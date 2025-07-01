//+------------------------------------------------------------------+
//|                                                      ScalperV2.mq5 |
//|                        Enhanced for MetaTrader 5 (MQL5)         |
//+------------------------------------------------------------------+
#property version   "2.0"
#property strict

#include <Trade/Trade.mqh>
#include <Indicators/Indicators.mqh>

CTrade trade;

// --- Risk Management Inputs ---
input double RiskPercent      = 1.0;
input double MaxLotSize       = 10.0;
input double MinLotSize       = 0.01;
input double DailyLossLimit   = 2.0;
input int    MaxSlippage      = 5;
input double MaxDrawdownPercent = 10.0;
input int    MaxTradesPerDay  = 20;

// --- Strategy Parameters ---
input int    ATR_Period       = 14;
input int    ADX_Threshold    = 25;
input double SpreadThreshold  = 2.5;

// --- Dynamic SL/TP ---
input double BaseRiskReward   = 1.5;
input double TrailingStep     = 0.0005;
input double MinRiskReward    = 1.0;
input double MaxRiskReward    = 3.0;
input double SL_ATR_Mult      = 0.5;
input double Trailing_ATR_Mult= 0.2;

// --- Advanced Filters and ML ---
input int    HighVolatilityHourStart = 8;  // London open
input int    HighVolatilityHourEnd   = 17; // NY close
input int    MinBarDistance    = 3;        // Bars between trades
input double MinADXStrength    = 20.0;     // ADX filter
input bool   EnableML          = true;     // Enable ML logic
input int    ML_MinTrades      = 50;
input double ML_LearningRate   = 0.01;

// --- Trade Statistics ---
double totalProfit = 0;
int totalTrades = 0, winTrades = 0, lossTrades = 0;
double maxConsecWins = 0, maxConsecLosses = 0;
double currentConsecWins = 0, currentConsecLosses = 0;

// --- Expanded ML Feature Set ---
struct TradeFeatures {
    // Price/Market Features
    double spread, atr, adx, rsi14, rsi28, cci14, mom14, ma50_diff, ma200_diff, bands_width, volume, tick_volume;
    double candle_body, candle_upper_wick, candle_lower_wick;
    double prev_candle_body, prev_candle_upper, prev_candle_lower;
    // Time/Session Features
    double hour, day_of_week, is_london, is_ny, is_asian;
    // Multi-timeframe Features
    double htf_ma50_diff, htf_ma200_diff, htf_adx;
    // Trade Outcome
    int outcome;
    double profit_pips;
};
TradeFeatures features[2000]; // Rolling window
int features_index = 0;

// --- Indicator buffer helpers ---
double GetIndicatorValue(int handle, int buffer, int shift=0) {
    double val[];
    if(CopyBuffer(handle, buffer, shift, 1, val) > 0)
        return val[0];
    return 0.0;
}

// --- Feature Extraction Helper (fixed) ---
void ExtractFeatures(TradeFeatures &f) {
    f.spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    f.atr = GetCurrentATR();
    int adx_handle = iADX(_Symbol, PERIOD_CURRENT, 14);
    f.adx = GetIndicatorValue(adx_handle, 0, 0);
    int rsi14_handle = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    f.rsi14 = GetIndicatorValue(rsi14_handle, 0, 0);
    int rsi28_handle = iRSI(_Symbol, PERIOD_CURRENT, 28, PRICE_CLOSE);
    f.rsi28 = GetIndicatorValue(rsi28_handle, 0, 0);
    int cci14_handle = iCCI(_Symbol, PERIOD_CURRENT, 14, PRICE_TYPICAL);
    f.cci14 = GetIndicatorValue(cci14_handle, 0, 0);
    int mom14_handle = iMomentum(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    f.mom14 = GetIndicatorValue(mom14_handle, 0, 0);
    int ma50_handle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
    int ma200_handle = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);
    f.ma50_diff = GetIndicatorValue(ma50_handle, 0, 0) - GetIndicatorValue(ma200_handle, 0, 0);
    int bands_handle = iBands(_Symbol, PERIOD_CURRENT, 20, 2.0, 0, PRICE_CLOSE);
    f.bands_width = GetIndicatorValue(bands_handle, 1, 0) - GetIndicatorValue(bands_handle, 2, 0);
    f.volume = iVolume(_Symbol, PERIOD_CURRENT, 0);
    f.tick_volume = iTickVolume(_Symbol, PERIOD_CURRENT, 0);
    double open = iOpen(_Symbol, PERIOD_CURRENT, 0), close = iClose(_Symbol, PERIOD_CURRENT, 0), high = iHigh(_Symbol, PERIOD_CURRENT, 0), low = iLow(_Symbol, PERIOD_CURRENT, 0);
    f.candle_body = MathAbs(close - open);
    f.candle_upper_wick = high - MathMax(open, close);
    f.candle_lower_wick = MathMin(open, close) - low;
    double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1), close1 = iClose(_Symbol, PERIOD_CURRENT, 1), high1 = iHigh(_Symbol, PERIOD_CURRENT, 1), low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
    f.prev_candle_body = MathAbs(close1 - open1);
    f.prev_candle_upper = high1 - MathMax(open1, close1);
    f.prev_candle_lower = MathMin(open1, close1) - low1;
    MqlDateTime now; TimeCurrent(now);
    f.hour = now.hour;
    f.day_of_week = now.day_of_week;
    f.is_london = (now.hour >= 7 && now.hour <= 16);
    f.is_ny = (now.hour >= 12 && now.hour <= 21);
    f.is_asian = (now.hour >= 0 && now.hour <= 6);
    int htf_ma50_handle = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
    int htf_ma200_handle = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
    int htf_ma800_handle = iMA(_Symbol, PERIOD_H4, 800, 0, MODE_EMA, PRICE_CLOSE);
    f.htf_ma50_diff = GetIndicatorValue(htf_ma50_handle, 0, 0) - GetIndicatorValue(htf_ma200_handle, 0, 0);
    f.htf_ma200_diff = GetIndicatorValue(htf_ma200_handle, 0, 0) - GetIndicatorValue(htf_ma800_handle, 0, 0);
    int htf_adx_handle = iADX(_Symbol, PERIOD_H4, 14);
    f.htf_adx = GetIndicatorValue(htf_adx_handle, 0, 0);
}

// --- Further Logic Tuning ---
// Example: Only allow trades if multi-timeframe and candle features align
bool AllowTrade(const TradeFeatures &f, int direction) {
    // Example: Only trade if H4 and M1 trends align
    if(direction == ORDER_TYPE_BUY && f.htf_ma50_diff > 0 && f.ma50_diff > 0 && f.adx > 20 && f.htf_adx > 20)
        return true;
    if(direction == ORDER_TYPE_SELL && f.htf_ma50_diff < 0 && f.ma50_diff < 0 && f.adx > 20 && f.htf_adx > 20)
        return true;
    // Example: Avoid trades during low volatility
    if(f.atr < 0.0003 || f.bands_width < 0.0005) return false;
    // Example: Avoid trades if candle is too small
    if(f.candle_body < 0.0001) return false;
    return false;
}

// --- Neural Network Parameters ---
double nn_weights1[10][8], nn_weights2[8][4], nn_weights3[4][1];
double nn_bias1[8], nn_bias2[4], nn_bias3[1];

// --- Helper Functions ---
double GetCurrentATR() {
    double atr[];
    if(CopyBuffer(iATR(_Symbol,PERIOD_CURRENT,ATR_Period), 0, 0, 1, atr) > 0)
        return atr[0];
    return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
}

// --- ML: Sigmoid Activation ---
double Sigmoid(double x) { return 1.0/(1.0+MathExp(-x)); }

// --- ML: Forward Pass ---
double NN_Predict(const double &inputs[]) {
    double h1[8], h2[4], output;
    for(int i=0; i<8; i++) {
        h1[i] = nn_bias1[i];
        for(int j=0; j<10; j++) h1[i] += inputs[j]*nn_weights1[j][i];
        h1[i] = Sigmoid(h1[i]);
    }
    for(int i=0; i<4; i++) {
        h2[i] = nn_bias2[i];
        for(int j=0; j<8; j++) h2[i] += h1[j]*nn_weights2[j][i];
        h2[i] = Sigmoid(h2[i]);
    }
    output = nn_bias3[0];
    for(int j=0; j<4; j++) output += h2[j]*nn_weights3[j][0];
    return Sigmoid(output);
}

// --- ML: Online Training ---
void TrainNN() {
    if(totalTrades < ML_MinTrades) return;
    int idx = MathRand()%totalTrades;
    double inputs[10];
    inputs[0]=features[idx].spread/10.0; inputs[1]=features[idx].atr/0.001; inputs[2]=features[idx].adx/50.0;
    inputs[3]=features[idx].rsi14/100.0; inputs[4]=features[idx].ma50_diff/0.01; inputs[5]=features[idx].bands_width/0.01;
    inputs[6]=features[idx].volume/1000.0; inputs[7]=features[idx].hour/24.0; inputs[8]=features[idx].day_of_week/7.0;
    inputs[9]=features[idx].profit_pips/100.0;
    double target = features[idx].outcome;
    double pred = NN_Predict(inputs);
    double error = target - pred;
    // Simple SGD update for output layer
    for(int j=0;j<4;j++) nn_weights3[j][0] += ML_LearningRate*error*inputs[j];
    // ... (add more updates for hidden layers as needed for more accuracy)
}

// --- Calculate Lot Size (Kelly) ---
double CalculateOptimalLotSize() {
    if(totalTrades < 10) return MinLotSize;
    double winRate = (double)winTrades/totalTrades;
    double avgWin = totalProfit/winTrades;
    double avgLoss = -totalProfit/lossTrades;
    double kellyFraction = winRate - (1-winRate)/(avgWin/avgLoss);
    return NormalizeDouble(MathMin(MaxLotSize, MathMax(MinLotSize, AccountInfoDouble(ACCOUNT_BALANCE)*RiskPercent*kellyFraction*0.25/100/1000)),2);
}

// --- Session Filter ---
bool IsTradingSession() {
    MqlDateTime now; TimeCurrent(now);
    return now.hour >= HighVolatilityHourStart && now.hour <= HighVolatilityHourEnd;
}

// --- Multi-timeframe Trend Filter ---
bool IsHTFAligned(int direction) {
    double maFast = GetIndicatorValue(iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE), 0, 0);
    double maSlow = GetIndicatorValue(iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE), 0, 0);
    return (direction==ORDER_TYPE_BUY && maFast>maSlow) || (direction==ORDER_TYPE_SELL && maFast<maSlow);
}

// --- Add missing helpers and state ---
// Trade day and count
int TradesToday = 0;
int TradeDay = -1;
datetime lastTradeTime = 0;
bool TradingEnabled = true;

double DailyStartBalance = 0;

// --- Drawdown checker ---
bool CheckDrawdownLimit() {
    double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    return ((bal - eq) / bal * 100.0 < MaxDrawdownPercent);
}

// --- ADX Filter ---
bool AdxFilter() {
    int adx_handle = iADX(_Symbol, PERIOD_CURRENT, ADX_Threshold);
    double adx = GetIndicatorValue(adx_handle, 0, 0);
    return (adx >= MinADXStrength);
}

// --- Trade type constants (MQL5) ---
#define ORDER_TYPE_BUY 0
#define ORDER_TYPE_SELL 1

// --- ExecuteTradeWithCustomSLTP ---
void ExecuteTradeWithCustomSLTP(int cmd, double lotSize, double customSL, double customTrail) {
    double price = (cmd == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl_price = (cmd == ORDER_TYPE_BUY) ? price - customSL : price + customSL;
    double tp_price = (cmd == ORDER_TYPE_BUY) ? price + customSL*BaseRiskReward : price - customSL*BaseRiskReward;
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetDeviationInPoints(MaxSlippage);
    bool result = false;
    if(cmd == ORDER_TYPE_BUY)
        result = trade.Buy(lotSize, _Symbol, price, sl_price, tp_price);
    else
        result = trade.Sell(lotSize, _Symbol, price, sl_price, tp_price);
    if(!result)
        Print("Trade failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
}

// --- UpdateStatsEnhanced ---
void UpdateStatsEnhanced() {
    static datetime lastUpdate = 0;
    datetime now = TimeCurrent();
    if(now == lastUpdate) return;
    lastUpdate = now;
    for(int i=0; i<HistoryDealsTotal(); i++) {
        ulong ticket = HistoryDealGetTicket(i);
        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
        static long lastDeal = 0;
        if(ticket == lastDeal) continue;
        lastDeal = ticket;
        if(entryType == DEAL_ENTRY_OUT) {
            totalProfit += profit;
            totalTrades++;
            if(profit > 0) { winTrades++; currentConsecWins++; currentConsecLosses = 0; }
            else if(profit < 0) { lossTrades++; currentConsecLosses++; currentConsecWins = 0; }
            if(currentConsecWins > maxConsecWins) maxConsecWins = currentConsecWins;
            if(currentConsecLosses > maxConsecLosses) maxConsecLosses = currentConsecLosses;
            lastTradeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        }
    }
}

// --- Reset daily trade count ---
void ResetDailyTradeCount() {
    MqlDateTime dt; TimeCurrent(dt);
    if(dt.day != TradeDay) {
        TradesToday = 0;
        TradeDay = dt.day;
    }
}

// --- Daily loss monitor ---
void CheckDailyLossLimit() {
    static int lastCheckedDay = -1;
    MqlDateTime dt; TimeCurrent(dt);
    if(dt.day != lastCheckedDay) {
        DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        TradingEnabled = true;
        lastCheckedDay = dt.day;
    }
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double lossPercentage = ((DailyStartBalance - currentBalance)/DailyStartBalance)*100;
    if(lossPercentage >= DailyLossLimit) {
        TradingEnabled = false;
        Comment("\nDAILY LOSS LIMIT REACHED! Trading suspended until next day.");
    }
}

// --- Market condition dummy (not used in logic, but for compatibility) ---
int CurrentMarketCondition = 0;
int DetectMarketCondition() { return 0; }

// --- MinBarDistancePassed ---
bool MinBarDistancePassed() {
    datetime now = TimeCurrent();
    return (iBarShift(_Symbol, PERIOD_M1, now) - iBarShift(_Symbol, PERIOD_M1, lastTradeTime) >= MinBarDistance);
}

// --- Add missing helpers for price and trade management ---
double GetAsk() { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
double GetBid() { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }

// --- Advanced trade management stub (user can expand as needed) ---
void AdvancedTradeManagement() {
    // Example: trailing stop, break-even, partial close, etc.
    // You can enhance this with your own advanced logic.
}

// --- Add missing trailing stop and trade stats print helpers ---
void TrailStopLossCustom(double customTrail) {
    for(int i=0; i<PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double stopLoss = PositionGetDouble(POSITION_SL);
            int type = (int)PositionGetInteger(POSITION_TYPE);
            double newSl = 0;
            if(type == ORDER_TYPE_BUY) {
                newSl = stopLoss + customTrail;
                if(GetBid() - newSl > customTrail)
                    trade.PositionModify(ticket, newSl, PositionGetDouble(POSITION_TP));
            } else if(type == ORDER_TYPE_SELL) {
                newSl = stopLoss - customTrail;
                if(newSl - GetAsk() > customTrail)
                    trade.PositionModify(ticket, newSl, PositionGetDouble(POSITION_TP));
            }
        }
    }
}

void PrintTradeStats() {
    Print("Total Trades: ", totalTrades, " | Wins: ", winTrades, " | Losses: ", lossTrades,
          " | Profit: ", DoubleToString(totalProfit, 2),
          " | Max Win Streak: ", maxConsecWins, " | Max Loss Streak: ", maxConsecLosses);
}

// --- Add/fuse: Utility for pip size ---
double GetPipSize() {
    double pip = 0.0;
    if(_Digits == 3 || _Digits == 5)
        pip = 10 * _Point;
    else
        pip = 1 * _Point;
    return pip;
}

// --- Add/fuse: ATR filter for volatility ---
bool ATRFilter(int period, double minATR) {
    int handle = iATR(_Symbol, _Period, period);
    double atr[];
    bool result = false;
    if(CopyBuffer(handle, 0, 0, 1, atr) == 1)
        result = (atr[0] >= minATR);
    IndicatorRelease(handle);
    return result;
}

// --- Add/fuse: Calculate lot size based on risk and SL (pip-based) ---
double CalculateLotSize(double riskPercent, int slPips) {
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * riskPercent / 100.0;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double pipValue = tickValue * (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) / _Point);
    double lotSize = riskAmount / (slPips * pipValue);
    lotSize = MathMax(MinLotSize, MathMin(MaxLotSize, lotSize));
    return NormalizeDouble(lotSize, 2);
}

// --- Add/fuse: Trailing stop management (pip-based, MagicNumber aware) ---
void TrailPositions() {
    double pip = GetPipSize();
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double profitPips = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / pip : (openPrice - currentPrice) / pip;
            if(profitPips >= TrailingStepPips) {
                double newSL = (posType == POSITION_TYPE_BUY) ? currentPrice - TrailingStop * pip
                                                             : currentPrice + TrailingStop * pip;
                double newTP = (posType == POSITION_TYPE_BUY) ? currentPrice + InitialTakeProfit * pip
                                                             : currentPrice - InitialTakeProfit * pip;
                // Only update if new SL is better
                if((posType == POSITION_TYPE_BUY && newSL > currentSL) || 
                   (posType == POSITION_TYPE_SELL && newSL < currentSL)) {
                    MqlTradeRequest request; ZeroMemory(request);
                    MqlTradeResult result; ZeroMemory(result);
                    request.action = TRADE_ACTION_SLTP;
                    request.position = ticket;
                    request.symbol = _Symbol;
                    request.sl = newSL;
                    request.tp = newTP;
                    request.magic = MagicNumber;
                    OrderSend(request, result);
                }
            }
        }
    }
}

// --- Add/fuse: MA crossover and higher timeframe filter logic ---
void CheckForEntry() {
    if(PositionsTotal() > 0) return;
    double fastMA[2], slowMA[2];
    int fastMAHandle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    int slowMAHandle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    if(CopyBuffer(fastMAHandle, 0, 0, 2, fastMA) != 2) { IndicatorRelease(fastMAHandle); IndicatorRelease(slowMAHandle); return; }
    if(CopyBuffer(slowMAHandle, 0, 0, 2, slowMA) != 2) { IndicatorRelease(fastMAHandle); IndicatorRelease(slowMAHandle); return; }
    // Higher timeframe trend filter
    int htMAHandle = iMA(_Symbol, PERIOD_H1, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    double htMA[];
    if(CopyBuffer(htMAHandle, 0, 0, 1, htMA) != 1) { IndicatorRelease(htMAHandle); return; }
    double htMAValue = htMA[0];
    IndicatorRelease(htMAHandle);
    double htClose[];
    if(CopyClose(_Symbol, PERIOD_H1, 0, 1, htClose) != 1) return;
    double htCloseValue = htClose[0];
    bool trendUp = htCloseValue > htMAValue;
    bool trendDown = htCloseValue < htMAValue;
    // ATR filter (volatility)
    bool volatilityOK = ATRFilter(14, 1.5 * GetPipSize());
    bool buySignal = fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0] && trendUp && volatilityOK;
    bool sellSignal = fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0] && trendDown && volatilityOK;
    IndicatorRelease(fastMAHandle); IndicatorRelease(slowMAHandle);
    if(buySignal || sellSignal) {
        double lotSize = CalculateLotSize(RiskPercentage, InitialStopLoss);
        int orderType = buySignal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        OpenPosition(orderType, lotSize);
    }
}

// --- Add/fuse: Open position with pip-based SL/TP ---
void OpenPosition(int orderType, double lotSize) {
    MqlTradeRequest request; ZeroMemory(request);
    MqlTradeResult result; ZeroMemory(result);
    double pip = GetPipSize();
    double entryPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = (orderType == ORDER_TYPE_BUY) ? entryPrice - InitialStopLoss * pip : entryPrice + InitialStopLoss * pip;
    double tp = (orderType == ORDER_TYPE_BUY) ? entryPrice + InitialTakeProfit * pip : entryPrice - InitialTakeProfit * pip;
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = orderType;
    request.price = entryPrice;
    request.sl = sl;
    request.tp = tp;
    request.deviation = MaxSlippage;
    request.magic = MagicNumber;
    request.type_filling = ORDER_FILLING_FOK;
    OrderSend(request, result);
}

// --- Add/fuse: OnInit/OnDeinit logic for handle and lot limits ---
int fastMAHandle, slowMAHandle;
double minLot, maxLot;
int OnInit() {
    fastMAHandle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    slowMAHandle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {
    IndicatorRelease(fastMAHandle);
    IndicatorRelease(slowMAHandle);
}

// --- Add/fuse: Inputs for new parameters ---
input double   RiskPercentage = 1.0;
input int      InitialStopLoss = 50;
input int      InitialTakeProfit = 100;
input int      TrailingStop = 30;
input int      TrailingStepPips = 20;
input int      FastMAPeriod = 5;
input int      SlowMAPeriod = 20;
input int      MagicNumber = 12345;

// --- Guaranteed Trade Logic ---
void OnTick() {
    UpdateStatsEnhanced();
    ResetDailyTradeCount();
    CheckDailyLossLimit();
    if(!TradingEnabled) return;
    if(!CheckDrawdownLimit()) return;
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_M1, 0);
    if(lastBar == currentBar) return;
    lastBar = currentBar;
    if(!IsTradingSession()) return;
    if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > SpreadThreshold) return;
    if(PositionsTotal() > 0) { TrailPositions(); PrintTradeStats(); return; }

    // --- Simple Price Action Entry ---
    double lastClose = iClose(_Symbol, PERIOD_M1, 1);
    double lastOpen = iOpen(_Symbol, PERIOD_M1, 1);
    
    int orderType = -1;
    if(lastClose > lastOpen) orderType = ORDER_TYPE_BUY;
    else if(lastClose < lastOpen) orderType = ORDER_TYPE_SELL;
    
    // --- Fallback: Random Entry if no signal ---
    if(orderType == -1 && TradesToday < 1) {
        orderType = (MathRand() % 2 == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    }
    
    if(orderType != -1) {
        double lotSize = MinLotSize;
        OpenPosition(orderType, lotSize);
        Print("Trade placed: ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"), " Lot: ", lotSize);
        TradesToday++;
    }
    
    TrailPositions();
    PrintTradeStats();
    if(EnableML && totalTrades % 10 == 0) TrainNN();
}

//+------------------------------------------------------------------+