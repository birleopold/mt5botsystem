//+------------------------------------------------------------------+
//|                                     ScalperV2 with SMC Hybrid    |
//|                        Enhanced for MetaTrader 5 (MQL5)         |
//+------------------------------------------------------------------+
#property version   "2.1"
#property strict

#include <Trade/Trade.mqh>
#include <Indicators/Indicators.mqh>
#include <Math/Stat/Normal.mqh>

// Core Constants and Definitions
#define MAX_BLOCKS 20
#define MAX_GRABS 10
#define MAX_FVGS 10
#define METRIC_WINDOW 100

// Market Regime Constants
#define TRENDING_UP 0
#define TRENDING_DOWN 1
#define HIGH_VOLATILITY 2
#define LOW_VOLATILITY 3
#define RANGING_NARROW 4
#define RANGING_WIDE 5
#define BREAKOUT 6
#define REVERSAL 7
#define CHOPPY 8
#define REGIME_COUNT 9

CTrade trade;

// --- Risk Management Inputs ---
input bool   TradingEnabled    = true;   // Enable/disable trading
input int    MagicNumber      = 12345;  // Unique identifier for this EA's trades
input double RiskPercentage   = 1.0;    // Risk percentage per trade
input double MaxLotSize       = 10.0;
input double MinLotSize       = 0.01;
input double DailyLossLimit   = 2.0;
input int    MaxSlippage      = 5;
input double MaxDrawdownPercent = 10.0;
input int    MaxTradesPerDay  = 20;

// --- Strategy Parameters ---
input int    FastMAPeriod     = 10;     // Fast MA period
input int    SlowMAPeriod     = 20;     // Slow MA period
input int    ATR_Period       = 14;
input int    ADX_Threshold    = 25;
input double SpreadThreshold  = 2.5;

// --- Dynamic SL/TP ---
input double BaseRiskReward   = 1.5;
input double TrailingStep     = 0.0005;
input double MinRiskReward    = 1.0;
input double MaxRiskReward    = 3.0;
input double SL_ATR_Mult      = 0.5;
input int    InitialStopLoss   = 20;     // Initial stop loss in pips
input int    InitialTakeProfit = 40;     // Initial take profit in pips
input int    TrailingStop      = 15;     // Trailing stop in pips
input int    TrailingStepPips  = 5;      // Pips of profit to activate trailing

// --- SMC Strategy Parameters ---
input int    MinBlockStrength  = 3;    // Minimum order block strength for valid signal
input double Trailing_ATR_Mult= 0.2;

// --- Advanced Filters and ML ---
input int    HighVolatilityHourStart = 8;  // London open
input int    HighVolatilityHourEnd   = 17; // NY close
input int    MinBarDistance    = 3;        // Bars between trades
input double MinADXStrength    = 20.0;     // ADX filter
input bool   EnableML          = true;     // Enable ML logic
input int    ML_MinTrades      = 50;
input double ML_LearningRate   = 0.01;

// --- Market Regime & SMC Parameters ---
input bool   EnableMarketRegimeFiltering = true; // Filter trades based on market regime
input bool   EnableAggressiveTrailing = true;   // Use aggressive trailing stops
input double TrailingActivationPct = 0.5;      // When to activate trailing (% of TP reached)
input double TrailingStopMultiplier = 0.5;     // Trailing stop multiplier of ATR
input bool   EnableFastExecution = true;       // Enable fast execution mode
input bool   UseOptimalStopLoss = true;        // Use optimal stop loss calculation
input bool   UseDynamicTakeProfit = true;      // Use dynamic take profit calculation
input int    MaxConsecutiveLosses = 3;         // Stop trading after this many consecutive losses
input int    LookbackBars = 100;               // Bars to look back for SMC patterns
input bool   DisplayDebugInfo = true;          // Display debug info in comments

// --- Trade Statistics ---
double totalProfit = 0;
int totalTrades = 0, winTrades = 0, lossTrades = 0;
double maxConsecWins = 0, maxConsecLosses = 0;
double currentConsecWins = 0, currentConsecLosses = 0;
int consecutiveLosses = 0;

// --- Market Regime Statistics ---
int regimeWins[REGIME_COUNT];
int regimeLosses[REGIME_COUNT];
double regimeProfit[REGIME_COUNT];
double regimeAccuracy[REGIME_COUNT];
int currentRegime = -1;
int lastRegime = -1;

// --- Trading Status ---
bool emergencyMode = false;
datetime lastTradeTime = 0;
datetime lastSignalTime = 0;
bool trailingActive = false;
double trailingLevel = 0;
double trailingTP = 0;
string lastErrorMessage = "";
int TradesToday = 0; // Counter for trades made today
bool isTradingAllowed = true; // Internal state variable for tracking if trading is allowed

// --- SMC Structures ---
struct LiquidityGrab { datetime time; double high; double low; bool bullish; bool active; };
struct FairValueGap { datetime startTime; datetime endTime; double high; double low; bool bullish; bool active; };
struct OrderBlock { datetime blockTime; double priceLevel; double highPrice; double lowPrice; bool bullish; bool valid; int strength; bool hasLiquidityGrab; bool hasSDConfirm; bool hasImbalance; bool hasFVG; };
struct SwingPoint { int barIndex; double price; int score; datetime time; };

// --- SMC Global Variables ---
LiquidityGrab recentGrabs[MAX_GRABS];
FairValueGap recentFVGs[MAX_FVGS];
OrderBlock recentBlocks[MAX_BLOCKS];
int grabIndex = 0, fvgIndex = 0, blockIndex = 0;
double FVGMinSize = 0.5;
bool UseLiquidityGrab = true, UseImbalanceFVG = true;

// --- ML Feature Analysis Tracking ---

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
    int atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
    if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) {
        IndicatorRelease(atrHandle);
        return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10; // Default value if ATR calculation fails
    }
    double result = atr[0];
    IndicatorRelease(atrHandle);
    return result;
}

//+------------------------------------------------------------------+
//| Convert regime code to descriptive string                        |
//+------------------------------------------------------------------+
string RegimeToString(int regime) {
    switch(regime) {
        case TRENDING_UP:    return "Trending Up";
        case TRENDING_DOWN:  return "Trending Down";
        case HIGH_VOLATILITY: return "High Volatility";
        case LOW_VOLATILITY:  return "Low Volatility";
        case RANGING_NARROW:  return "Ranging (Narrow)";
        case RANGING_WIDE:    return "Ranging (Wide)";
        case BREAKOUT:        return "Breakout";
        case REVERSAL:        return "Reversal";
        case CHOPPY:          return "Choppy";
        default:              return "Unknown Regime";
    }
}

// Helper function for getting ATR for different symbols and timeframes
double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift) {
    int handle = iATR(symbol, timeframe, period);
    double buffer[];
    if(CopyBuffer(handle, 0, shift, 1, buffer) > 0) {
        double result = buffer[0];
        IndicatorRelease(handle);
        return result;
    }
    IndicatorRelease(handle);
    return SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;
}

// Helper function for getting Bollinger Bands values
double GetBands(string symbol, ENUM_TIMEFRAMES timeframe, int period, double deviation, int shift, ENUM_APPLIED_PRICE applied_price, int band, int bar) {
    int handle = iBands(symbol, timeframe, period, deviation, 0, applied_price);
    double buffer[];
    if(CopyBuffer(handle, band, bar, 1, buffer) > 0) {
        double result = buffer[0];
        IndicatorRelease(handle);
        return result;
    }
    IndicatorRelease(handle);
    return 0;
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
    return NormalizeDouble(MathMin(MaxLotSize, MathMax(MinLotSize, AccountInfoDouble(ACCOUNT_BALANCE)*RiskPercentage*kellyFraction*0.25/100/1000)),2);
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
int TradeDay = -1;

double DailyStartBalance = 0;

//+------------------------------------------------------------------+
//| Check if trading is allowed based on various conditions          |
//+------------------------------------------------------------------+
bool CanTrade() {
    // Check if trading is enabled both manually and via internal state
    if(!TradingEnabled || !isTradingAllowed) return false;
    
    // Check daily trade limit
    if(TradesToday >= MaxTradesPerDay) {
        Print("Daily trade limit reached: ", TradesToday, "/", MaxTradesPerDay);
        return false;
    }
    
    // Check drawdown limit
    if(!CheckDrawdownLimit()) return false;
    
    // Check time between trades (prevent overtrading)
    if(TimeCurrent() - lastTradeTime < 60) {
        Print("Trade timeout: need to wait before next trade");
        return false;
    }
    
    return true;
}

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
        isTradingAllowed = true;
        lastCheckedDay = dt.day;
    }
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double lossPercentage = ((DailyStartBalance - currentBalance)/DailyStartBalance)*100;
    if(lossPercentage >= DailyLossLimit) {
        isTradingAllowed = false;
        Comment("\nDAILY LOSS LIMIT REACHED! Trading suspended until next day.");
    }
}

// --- SMC Pattern Detection Functions ---
//+------------------------------------------------------------------+
//| Detect liquidity grabs from SMC strategy                       |
//+------------------------------------------------------------------+
void DetectLiquidityGrabs() {
   int lookback = MathMin(LookbackBars, Bars(_Symbol, PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   
   ArrayResize(high, lookback);
   ArrayResize(low, lookback);
   ArrayResize(open, lookback);
   ArrayResize(close, lookback);
   ArrayResize(time, lookback);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
   CopyOpen(_Symbol, PERIOD_CURRENT, 0, lookback, open);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, lookback, close);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, lookback, time);
   
   // Reset all grab active flags
   for(int i=0; i<MAX_GRABS; i++)
      recentGrabs[i].active = false;
   
   // Find liquidity grabs
   int count = 0;
   for(int i=2; i<lookback-2; i++) {
      // Bullish liquidity grab (sweep below previous low, then reversal)
      if(low[i] < low[i+1] && low[i] < low[i+2] && close[i] > open[i] && close[i-1] > open[i-1]) {
         LiquidityGrab grab;
         grab.time = time[i];
         grab.high = high[i];
         grab.low = low[i];
         grab.bullish = true;
         grab.active = true;
         
         recentGrabs[grabIndex] = grab;
         grabIndex = (grabIndex + 1) % MAX_GRABS;
         count++;
         if(count >= MAX_GRABS) break;
      }
      
      // Bearish liquidity grab (sweep above previous high, then reversal)
      if(high[i] > high[i+1] && high[i] > high[i+2] && close[i] < open[i] && close[i-1] < open[i-1]) {
         LiquidityGrab grab;
         grab.time = time[i];
         grab.high = high[i];
         grab.low = low[i];
         grab.bullish = false;
         grab.active = true;
         
         recentGrabs[grabIndex] = grab;
         grabIndex = (grabIndex + 1) % MAX_GRABS;
         count++;
         if(count >= MAX_GRABS) break;
      }
   }
}

//+------------------------------------------------------------------+
//| Detect fair value gaps from SMC strategy                        |
//+------------------------------------------------------------------+
void DetectFairValueGaps() {
   int lookback = MathMin(LookbackBars, Bars(_Symbol, PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   
   ArrayResize(high, lookback);
   ArrayResize(low, lookback);
   ArrayResize(open, lookback);
   ArrayResize(close, lookback);
   ArrayResize(time, lookback);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
   CopyOpen(_Symbol, PERIOD_CURRENT, 0, lookback, open);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, lookback, close);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, lookback, time);
   
   // Reset all FVG active flags
   for(int i=0; i<MAX_FVGS; i++)
      recentFVGs[i].active = false;
   
   // Find fair value gaps
   int count = 0;
   double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minSize = FVGMinSize * 10 * pointSize;
   
   for(int i=2; i<lookback-1; i++) {
      // Bullish FVG (gap up)
      if(low[i] > high[i+1]) {
         double fvgSize = low[i] - high[i+1];
         if(fvgSize >= minSize) {
            FairValueGap fvg;
            fvg.startTime = time[i+1];
            fvg.endTime = time[i];
            fvg.high = low[i];
            fvg.low = high[i+1];
            fvg.bullish = true;
            fvg.active = true;
            
            // Check if this FVG has been filled in subsequent bars
            bool filled = false;
            for(int j=i-1; j>=0; j--) {
               if(low[j] <= fvg.low) {
                  filled = true;
                  break;
               }
            }
            
            if(!filled) {
               recentFVGs[fvgIndex] = fvg;
               fvgIndex = (fvgIndex + 1) % MAX_FVGS;
               count++;
            }
         }
      }
      
      // Bearish FVG (gap down)
      if(high[i] < low[i+1]) {
         double fvgSize = low[i+1] - high[i];
         if(fvgSize >= minSize) {
            FairValueGap fvg;
            fvg.startTime = time[i+1];
            fvg.endTime = time[i];
            fvg.high = low[i+1];
            fvg.low = high[i];
            fvg.bullish = false;
            fvg.active = true;
            
            // Check if this FVG has been filled in subsequent bars
            bool filled = false;
            for(int j=i-1; j>=0; j--) {
               if(high[j] >= fvg.high) {
                  filled = true;
                  break;
               }
            }
            
            if(!filled) {
               recentFVGs[fvgIndex] = fvg;
               fvgIndex = (fvgIndex + 1) % MAX_FVGS;
               count++;
            }
         }
      }
      
      if(count >= MAX_FVGS) break;
   }
}

//+------------------------------------------------------------------+
//| Detect order blocks from SMC strategy                           |
//+------------------------------------------------------------------+
void DetectOrderBlocks() {
   int lookback = MathMin(LookbackBars, Bars(_Symbol, PERIOD_CURRENT));
   double high[], low[], open[], close[];
   datetime time[];
   long volume[];
   
   ArrayResize(high, lookback);
   ArrayResize(low, lookback);
   ArrayResize(open, lookback);
   ArrayResize(close, lookback);
   ArrayResize(time, lookback);
   ArrayResize(volume, lookback);
   
   CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback, high);
   CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback, low);
   CopyOpen(_Symbol, PERIOD_CURRENT, 0, lookback, open);
   CopyClose(_Symbol, PERIOD_CURRENT, 0, lookback, close);
   CopyTime(_Symbol, PERIOD_CURRENT, 0, lookback, time);
   CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, lookback, volume);
   
   // Reset order blocks validity
   for(int i=0; i<MAX_BLOCKS; i++)
      recentBlocks[i].valid = false;
   
   // Find bullish order blocks
   for(int i=3; i<lookback-3; i++) {
      // Identify potential bullish order block (a strong bearish candle followed by bullish move)
      if(close[i] < open[i] && close[i-3] > close[i+1] && close[i-1] > open[i-1] && close[i-2] > open[i-2]) {
         OrderBlock block;
         block.blockTime = time[i];
         block.priceLevel = (high[i] + low[i]) / 2;
         block.highPrice = high[i];
         block.lowPrice = low[i];
         block.bullish = true;
         block.valid = true;
         block.strength = 1; // Base strength
         
         // Check for additional strength factors
         
         // 1. Increased volume
         if(volume[i] > volume[i+1]*1.5 && volume[i] > volume[i-1]*1.5)
            block.strength++;
            
         // 2. Block created a fair value gap
         for(int j=0; j<MAX_FVGS; j++) {
            if(recentFVGs[j].active && recentFVGs[j].bullish && 
              MathAbs(time[i] - recentFVGs[j].startTime) < 60*60*12) { // Within 12 hours
               block.strength++;
               block.hasFVG = true;
               break;
            }
         }
         
         // 3. Block preceded by a liquidity grab
         for(int j=0; j<MAX_GRABS; j++) {
            if(recentGrabs[j].active && recentGrabs[j].bullish && 
              time[i] > recentGrabs[j].time && time[i] - recentGrabs[j].time < 60*60*24) { // Within 24 hours
               block.strength++;
               block.hasLiquidityGrab = true;
               break;
            }
         }
         
         // 4. Higher timeframe confirmation
         int htf_handle = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
         double htf_ma[];
         if(CopyBuffer(htf_handle, 0, 0, 1, htf_ma) > 0) {
            if(low[i] > htf_ma[0]) // Price above H4 50 EMA
               block.strength++;
         }
         IndicatorRelease(htf_handle);
         
         // 5. Order block formed at major swing low
         int swingStrength = 0;
         for(int j=i+1; j<MathMin(i+20, lookback); j++) {
            if(low[i] < low[j])
               swingStrength++;
         }
         if(swingStrength >= 15) {
            block.strength++;
            block.hasSDConfirm = true;
         }
         
         // Add to recent blocks
         if(block.strength >= MinBlockStrength) {
            recentBlocks[blockIndex] = block;
            blockIndex = (blockIndex + 1) % MAX_BLOCKS;
         }
      }
      
      // Identify potential bearish order block (a strong bullish candle followed by bearish move)
      if(close[i] > open[i] && close[i-3] < close[i+1] && close[i-1] < open[i-1] && close[i-2] < open[i-2]) {
         OrderBlock block;
         block.blockTime = time[i];
         block.priceLevel = (high[i] + low[i]) / 2;
         block.highPrice = high[i];
         block.lowPrice = low[i];
         block.bullish = false;
         block.valid = true;
         block.strength = 1; // Base strength
         
         // Check for additional strength factors (similar to bullish case)
         
         // 1. Increased volume
         if(volume[i] > volume[i+1]*1.5 && volume[i] > volume[i-1]*1.5)
            block.strength++;
            
         // 2. Block created a fair value gap
         for(int j=0; j<MAX_FVGS; j++) {
            if(recentFVGs[j].active && !recentFVGs[j].bullish && 
              MathAbs(time[i] - recentFVGs[j].startTime) < 60*60*12) { // Within 12 hours
               block.strength++;
               block.hasFVG = true;
               break;
            }
         }
         
         // 3. Block preceded by a liquidity grab
         for(int j=0; j<MAX_GRABS; j++) {
            if(recentGrabs[j].active && !recentGrabs[j].bullish && 
              time[i] > recentGrabs[j].time && time[i] - recentGrabs[j].time < 60*60*24) { // Within 24 hours
               block.strength++;
               block.hasLiquidityGrab = true;
               break;
            }
         }
         
         // 4. Higher timeframe confirmation
         int htf_handle = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
         double htf_ma[];
         if(CopyBuffer(htf_handle, 0, 0, 1, htf_ma) > 0) {
            if(high[i] < htf_ma[0]) // Price below H4 50 EMA
               block.strength++;
         }
         IndicatorRelease(htf_handle);
         
         // 5. Order block formed at major swing high
         int swingStrength = 0;
         for(int j=i+1; j<MathMin(i+20, lookback); j++) {
            if(high[i] > high[j])
               swingStrength++;
         }
         if(swingStrength >= 15) {
            block.strength++;
            block.hasSDConfirm = true;
         }
         
         // Add to recent blocks
         if(block.strength >= MinBlockStrength) {
            recentBlocks[blockIndex] = block;
            blockIndex = (blockIndex + 1) % MAX_BLOCKS;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Validate supply/demand zones                                    |
//+------------------------------------------------------------------+
void ValidateSupplyDemandZones() {
   // Get recent price action
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // Validate blocks by checking if they are still relevant
   for(int i=0; i<MAX_BLOCKS; i++) {
      if(!recentBlocks[i].valid) continue;
      
      // Check if price has moved through the block (invalidating it)
      if(recentBlocks[i].bullish) {
         // For bullish blocks, price should not go below the low
         if(close < recentBlocks[i].lowPrice) {
            recentBlocks[i].valid = false;
         }
      } else {
         // For bearish blocks, price should not go above the high
         if(close > recentBlocks[i].highPrice) {
            recentBlocks[i].valid = false;
         }
      }
   }
}

// --- Market condition using regime detection ---
int CurrentMarketCondition = 0;
int DetectMarketCondition() { 
    if(EnableMarketRegimeFiltering) {
        return FastRegimeDetection(_Symbol);
    } else {
        return LOW_VOLATILITY; // Default condition
    }
}

// --- MinBarDistancePassed ---
bool MinBarDistancePassed() {
    datetime now = TimeCurrent();
    return (iBarShift(_Symbol, PERIOD_M1, now) - iBarShift(_Symbol, PERIOD_M1, lastTradeTime) >= MinBarDistance);
}

// --- Add missing helpers for price and trade management ---
double GetAsk() { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
double GetBid() { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }

//+------------------------------------------------------------------+
//| Find quality swing points for optimal stop loss placement        |
//+------------------------------------------------------------------+
void FindQualitySwingPoints(bool isBuy, int lookbackBars, SwingPoint &swingPoints[], int &count) {
    count = 0;
    double high[], low[], close[], open[], volume[];
    long vol[];
    datetime time[];
    
    int bars = MathMin(lookbackBars, Bars(_Symbol, PERIOD_CURRENT));
    
    ArrayResize(high, bars);
    ArrayResize(low, bars);
    ArrayResize(open, bars);
    ArrayResize(close, bars);
    ArrayResize(volume, bars);
    ArrayResize(time, bars);
    
    CopyHigh(_Symbol, PERIOD_CURRENT, 0, bars, high);
    CopyLow(_Symbol, PERIOD_CURRENT, 0, bars, low);
    CopyOpen(_Symbol, PERIOD_CURRENT, 0, bars, open);
    CopyClose(_Symbol, PERIOD_CURRENT, 0, bars, close);
    CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, bars, vol);
    CopyTime(_Symbol, PERIOD_CURRENT, 0, bars, time);
    
    // Convert to double for calculations
    for(int i=0; i<bars; i++) {
        volume[i] = (double)vol[i];
    }
    
    // Find swing points
    int maxSwings = 20;
    ArrayResize(swingPoints, maxSwings);
    
    // For buy trades we look for swing lows
    if(isBuy) {
        for(int i=2; i<bars-2; i++) {
            // Check if this is a swing low
            if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i+1] && low[i] < low[i+2]) {
                SwingPoint sp;
                sp.barIndex = i;
                sp.price = low[i];
                sp.time = time[i];
                sp.score = 1; // Base score
                
                // Calculate swing score based on various factors
                
                // 1. Volume at the swing point
                if(volume[i] > volume[i-1]*1.5 && volume[i] > volume[i+1]*1.5)
                    sp.score += 2;
                
                // 2. Price rejection after swing (bullish confirmation)
                if(close[i] > (high[i] + low[i])/2 && close[i-1] > open[i-1])
                    sp.score += 2;
                
                // 3. Higher timeframe alignment
                int htf_handle = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
                double htf_ma[];
                if(CopyBuffer(htf_handle, 0, 0, 1, htf_ma) > 0) {
                    if(low[i] > htf_ma[0])
                        sp.score += 3;
                }
                IndicatorRelease(htf_handle);
                
                // 4. Depth of the swing (how much lower than surrounding bars)
                double depthLeft = MathAbs((low[i] - low[i-2])/low[i]*100);
                double depthRight = MathAbs((low[i] - low[i+2])/low[i]*100);
                sp.score += (int)MathFloor((depthLeft + depthRight)/2);
                
                // Only add swings with good scores
                if(sp.score >= 3) {
                    swingPoints[count] = sp;
                    count++;
                    if(count >= maxSwings) break;
                }
            }
        }
    }
    // For sell trades we look for swing highs
    else {
        for(int i=2; i<bars-2; i++) {
            // Check if this is a swing high
            if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i+1] && high[i] > high[i+2]) {
                SwingPoint sp;
                sp.barIndex = i;
                sp.price = high[i];
                sp.time = time[i];
                sp.score = 1; // Base score
                
                // Calculate swing score similar to swing lows
                
                // 1. Volume at the swing point
                if(volume[i] > volume[i-1]*1.5 && volume[i] > volume[i+1]*1.5)
                    sp.score += 2;
                
                // 2. Price rejection after swing (bearish confirmation)
                if(close[i] < (high[i] + low[i])/2 && close[i-1] < open[i-1])
                    sp.score += 2;
                
                // 3. Higher timeframe alignment
                int htf_handle = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
                double htf_ma[];
                if(CopyBuffer(htf_handle, 0, 0, 1, htf_ma) > 0) {
                    if(high[i] < htf_ma[0])
                        sp.score += 3;
                }
                IndicatorRelease(htf_handle);
                
                // 4. Depth of the swing (how much higher than surrounding bars)
                double depthLeft = MathAbs((high[i] - high[i-2])/high[i]*100);
                double depthRight = MathAbs((high[i] - high[i+2])/high[i]*100);
                sp.score += (int)MathFloor((depthLeft + depthRight)/2);
                
                // Only add swings with good scores
                if(sp.score >= 3) {
                    swingPoints[count] = sp;
                    count++;
                    if(count >= maxSwings) break;
                }
            }
        }
    }
    
    // Sort swings by score (descending)
    if(count > 1) {
        for(int i=0; i<count-1; i++) {
            for(int j=i+1; j<count; j++) {
                if(swingPoints[j].score > swingPoints[i].score) {
                    SwingPoint temp = swingPoints[i];
                    swingPoints[i] = swingPoints[j];
                    swingPoints[j] = temp;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Determine optimal stop loss based on swing points                |
//+------------------------------------------------------------------+
double DetermineOptimalStopLoss(int signal, double entryPrice) {
    // Array to store potential swing points
    SwingPoint swingPoints[];
    int swingCount = 0;
    
    // Find relevant swing points
    bool isBuy = (signal == ORDER_TYPE_BUY);
    FindQualitySwingPoints(isBuy, 100, swingPoints, swingCount);
    
    if(swingCount == 0) {
        // Fallback to ATR-based stop loss if no good swing points found
        double atr = GetCurrentATR();
        return isBuy ? entryPrice - atr * SL_ATR_Mult : entryPrice + atr * SL_ATR_Mult;
    }
    
    // Find the best swing point to use for stop loss
    double optimalStopPrice = 0;
    double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double minDistance = 999999;
    double maxDistance = currentPrice * 0.02; // Max 2% away
    double preferredDistance = GetCurrentATR() * SL_ATR_Mult; // Preferred distance based on ATR
    
    for(int i=0; i<swingCount; i++) {
        double distance = isBuy ? MathAbs(currentPrice - swingPoints[i].price) : MathAbs(swingPoints[i].price - currentPrice);
        
        // Skip if too close or too far
        if(distance < preferredDistance * 0.5) continue;
        if(distance > maxDistance) continue;
        
        // Rate the stop loss points
        double fitness = MathAbs(distance - preferredDistance) * (1.0 / (1 + swingPoints[i].score * 0.1));
        
        if(fitness < minDistance || optimalStopPrice == 0) {
            minDistance = fitness;
            optimalStopPrice = swingPoints[i].price;
        }
    }
    
    // If no suitable swing point, fall back to ATR-based stop
    if(optimalStopPrice == 0) {
        double atr = GetCurrentATR();
        optimalStopPrice = isBuy ? currentPrice - atr * SL_ATR_Mult : currentPrice + atr * SL_ATR_Mult;
    }
    
    // Add a small buffer to avoid immediate stop hits
    double buffer = isBuy ? -_Point * 5 : _Point * 5;
    return optimalStopPrice + buffer;
}

//+------------------------------------------------------------------+
//| Calculate dynamic take profit based on market conditions         |
//+------------------------------------------------------------------+
double CalculateDynamicTakeProfit(int signal, double entryPrice, double stopLossPrice) {
    // Calculate base risk in price
    double baseRisk = MathAbs(entryPrice - stopLossPrice);
    
    // Get ATR for volatility measurement
    double atr = GetCurrentATR();
    
    // Base RR ratio
    double baseRR = BaseRiskReward;
    
    // Adjust based on market regime
    if(EnableMarketRegimeFiltering && currentRegime >= 0) {
        switch(currentRegime) {
            case TRENDING_UP:
            case TRENDING_DOWN:
                baseRR *= 1.3; // Extend targets in trending markets
                break;
            case HIGH_VOLATILITY:
                baseRR *= 1.5; // Extend targets in high volatility
                break;
            case RANGING_NARROW:
                baseRR *= 0.7; // Reduce targets in tight ranges
                break;
            case CHOPPY:
                baseRR *= 0.8; // Reduce targets in choppy markets
                break;
            case BREAKOUT:
                baseRR *= 1.8; // Maximize targets on breakouts
                break;
        }
    }
    
    // Calculate dynamic reward
    double reward = baseRisk * baseRR;
    
    // Adjust for volatility
    double volatilityFactor = atr / (GetPipSize() * 10); // Normalize ATR
    reward *= (1.0 + (volatilityFactor - 1.0) * 0.5); // Dampened adjustment
    
    // Calculate take profit
    double takeProfit = signal == ORDER_TYPE_BUY ? entryPrice + reward : entryPrice - reward;
    
    // Ensure the risk-reward stays within limits
    double currentRR = reward / baseRisk;
    if(currentRR < MinRiskReward)
        takeProfit = signal == ORDER_TYPE_BUY ? entryPrice + baseRisk * MinRiskReward : entryPrice - baseRisk * MinRiskReward;
    else if(currentRR > MaxRiskReward)
        takeProfit = signal == ORDER_TYPE_BUY ? entryPrice + baseRisk * MaxRiskReward : entryPrice - baseRisk * MaxRiskReward;
    
    return takeProfit;
}

// --- Advanced trade management with SMC features ---
void AdvancedTradeManagement() {
    // Manage trailing stops with enhanced algorithm
    if(EnableAggressiveTrailing) {
        ManageTrailingStops();
    }
}

//+------------------------------------------------------------------+
//| Enhanced trailing stop management that uses percent activation  |
//+------------------------------------------------------------------+
void ManageTrailingStops() {
    if(!EnableAggressiveTrailing) return;
    
    for(int i=0; i<PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double currentTP = PositionGetDouble(POSITION_TP);
        double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        // Calculate profit in pips and as percentage of target
        double profitPips = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / GetPipSize() : (openPrice - currentPrice) / GetPipSize();
        double targetPips = (posType == POSITION_TYPE_BUY) ? (currentTP - openPrice) / GetPipSize() : (openPrice - currentTP) / GetPipSize();
        double profitPct = (targetPips > 0) ? profitPips / targetPips : 0;
        
        // Only activate trailing once profit reaches the activation threshold
        if(profitPct >= TrailingActivationPct) {
            double newSL = 0;
            
            if(posType == POSITION_TYPE_BUY) {
                // For buy positions, check if we should update SL (move it up)
                double atr = GetCurrentATR();
                newSL = currentPrice - atr * TrailingStopMultiplier;
                
                if(newSL > currentSL && newSL < currentPrice) {
                    // Only modify if the new SL is better than current SL
                    trade.PositionModify(ticket, newSL, currentTP);
                    if(trailingActive == false) {
                        trailingActive = true;
                        if(DisplayDebugInfo) Print("Trailing activated for ticket ", ticket, " at ", TimeToString(TimeCurrent()));
                    }
                }
            }
            else if(posType == POSITION_TYPE_SELL) {
                // For sell positions, check if we should update SL (move it down)
                double atr = GetCurrentATR();
                newSL = currentPrice + atr * TrailingStopMultiplier;
                
                if(newSL < currentSL && newSL > currentPrice) {
                    // Only modify if the new SL is better than current SL
                    trade.PositionModify(ticket, newSL, currentTP);
                    if(trailingActive == false) {
                        trailingActive = true;
                        if(DisplayDebugInfo) Print("Trailing activated for ticket ", ticket, " at ", TimeToString(TimeCurrent()));
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Execute trade with advanced stop loss and take profit           |
//+------------------------------------------------------------------+
bool ExecuteTradeOptimized(int signal) {
    if(!CanTrade()) return false;
    
    double entryPrice = (signal == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Get local copies of the input parameters to avoid ambiguity
    int stop_loss_pips = InitialStopLoss;
    int take_profit_pips = InitialTakeProfit;
    
    // Calculate optimal stop loss level
    double stopLossPrice = UseOptimalStopLoss ? DetermineOptimalStopLoss(signal, entryPrice) : 
                           (signal == ORDER_TYPE_BUY ? entryPrice - stop_loss_pips * GetPipSize() : entryPrice + stop_loss_pips * GetPipSize());
    
    // Calculate take profit level
    double takeProfitPrice = UseDynamicTakeProfit ? CalculateDynamicTakeProfit(signal, entryPrice, stopLossPrice) :
                              (signal == ORDER_TYPE_BUY ? entryPrice + take_profit_pips * GetPipSize() : entryPrice - take_profit_pips * GetPipSize());
    
    // Calculate position size based on risk
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercentage / 100;
    double riskPips = MathAbs(entryPrice - stopLossPrice) / GetPipSize();
    double lotSize = CalculateLotSize(RiskPercentage, (int)riskPips);
    
    // Place trade
    trade.SetDeviationInPoints(MaxSlippage);
    bool result = false;
    if(signal == ORDER_TYPE_BUY)
        result = trade.Buy(lotSize, _Symbol, entryPrice, stopLossPrice, takeProfitPrice, "SMC Buy");
    else
        result = trade.Sell(lotSize, _Symbol, entryPrice, stopLossPrice, takeProfitPrice, "SMC Sell");
    
    if(result) {
        lastTradeTime = TimeCurrent();
        TradesToday++;
    } else {
        lastErrorMessage = "Trade failed: " + IntegerToString(trade.ResultRetcode()) + " - " + trade.ResultRetcodeDescription();
        if(DisplayDebugInfo) Print(lastErrorMessage);
    }
    
    return result;
}

// --- Add missing trailing stop and trade stats print helpers ---
void TrailStopLossCustom(double customTrail) {
    // Legacy function, now we use ManageTrailingStops instead
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

//+------------------------------------------------------------------+
//| Display detailed debug information on chart                      |
//+------------------------------------------------------------------+
void ShowDebugInfo() {
    string info = "=== ScalperV2 with SMC Hybrid ===\n";
    info += "Market Regime: " + GetMarketRegimeText(currentRegime) + "\n";
    info += "Current ATR: " + DoubleToString(GetCurrentATR(), 5) + "\n";
    info += "Active Blocks: " + GetActiveBlocksInfo() + "\n";
    info += "Active FVGs: " + GetActiveFVGsInfo() + "\n";
    info += "Performance: " + IntegerToString(winTrades) + " wins, " + IntegerToString(lossTrades) + " losses\n";
    info += "Total Profit: " + DoubleToString(totalProfit, 2) + "\n";
    info += "Consecutive Losses: " + IntegerToString(consecutiveLosses) + "\n";
    
    if(trailingActive) {
        info += "Trailing Stop: ACTIVE\n";
    }
    
    if(emergencyMode) {
        info += "*** EMERGENCY MODE ACTIVE ***\n";
    }
    
    if(lastErrorMessage != "") {
        info += "Last Error: " + lastErrorMessage + "\n";
    }
    
    Comment(info);
}

//+------------------------------------------------------------------+
//| Get text description of market regime                            |
//+------------------------------------------------------------------+
string GetMarketRegimeText(int regime) {
    switch(regime) {
        case TRENDING_UP: return "TRENDING UP";
        case TRENDING_DOWN: return "TRENDING DOWN";
        case HIGH_VOLATILITY: return "HIGH VOLATILITY";
        case LOW_VOLATILITY: return "LOW VOLATILITY";
        case RANGING_NARROW: return "RANGING NARROW";
        case RANGING_WIDE: return "RANGING WIDE";
        case BREAKOUT: return "BREAKOUT";
        case REVERSAL: return "REVERSAL";
        case CHOPPY: return "CHOPPY";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Get info about active order blocks                              |
//+------------------------------------------------------------------+
string GetActiveBlocksInfo() {
    int buyBlocks = 0, sellBlocks = 0;
    int strongBuyBlocks = 0, strongSellBlocks = 0;
    
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            if(recentBlocks[i].bullish) {
                buyBlocks++;
                if(recentBlocks[i].strength >= 3) strongBuyBlocks++;
            } else {
                sellBlocks++;
                if(recentBlocks[i].strength >= 3) strongSellBlocks++;
            }
        }
    }
    
    return IntegerToString(buyBlocks) + " buy (" + IntegerToString(strongBuyBlocks) + 
           " strong), " + IntegerToString(sellBlocks) + " sell (" + IntegerToString(strongSellBlocks) + " strong)";
}

//+------------------------------------------------------------------+
//| Get info about active fair value gaps                           |
//+------------------------------------------------------------------+
string GetActiveFVGsInfo() {
    int buyFVGs = 0, sellFVGs = 0;
    
    for(int i=0; i<MAX_FVGS; i++) {
        if(recentFVGs[i].active) {
            if(recentFVGs[i].bullish) buyFVGs++;
            else sellFVGs++;
        }
    }
    
    return IntegerToString(buyFVGs) + " bullish, " + IntegerToString(sellFVGs) + " bearish";
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

//+------------------------------------------------------------------+
//| Market Regime Detection from SMC Scalper Hybrid                  |
//+------------------------------------------------------------------+
int FastRegimeDetection(string symbol) {
    // Get price data for multiple timeframes
    double close0 = iClose(symbol, PERIOD_M5, 0);
    double close1 = iClose(symbol, PERIOD_M5, 1);
    double close3 = iClose(symbol, PERIOD_M5, 3);
    double close5 = iClose(symbol, PERIOD_M5, 5);
    double close10 = iClose(symbol, PERIOD_M5, 10);
    
    // Get high/low data
    double high0 = iHigh(symbol, PERIOD_M5, 0);
    double high1 = iHigh(symbol, PERIOD_M5, 1);
    double high3 = iHigh(symbol, PERIOD_M5, 3);
    double low0 = iLow(symbol, PERIOD_M5, 0);
    double low1 = iLow(symbol, PERIOD_M5, 1);
    double low3 = iLow(symbol, PERIOD_M5, 3);
    
    // Calculate multiple moving averages for trend detection
    double ma3 = 0, ma5 = 0, ma10 = 0, ma20 = 0;
    for(int i=0; i<3; i++) ma3 += iClose(symbol, PERIOD_M5, i);
    for(int i=0; i<5; i++) ma5 += iClose(symbol, PERIOD_M5, i);
    for(int i=0; i<10; i++) ma10 += iClose(symbol, PERIOD_M5, i);
    for(int i=0; i<20; i++) ma20 += iClose(symbol, PERIOD_M5, i);
    ma3 /= 3;
    ma5 /= 5;
    ma10 /= 10;
    ma20 /= 20;
    
    // Calculate volatility metrics
    double quickAtr = GetATR(symbol, PERIOD_M5, 14, 0);
    double avgRange = 0;
    for(int i=0; i<5; i++) {
        avgRange += MathAbs(iHigh(symbol, PERIOD_M5, i) - iLow(symbol, PERIOD_M5, i));
    }
    avgRange /= 5;
    
    // Calculate price range over different periods
    double range3 = MathMax(high0, high1) - MathMin(low0, low1);
    double range10 = 0;
    double highestHigh = iHigh(symbol, PERIOD_M5, iHighest(symbol, PERIOD_M5, MODE_HIGH, 10, 0));
    double lowestLow = iLow(symbol, PERIOD_M5, iLowest(symbol, PERIOD_M5, MODE_LOW, 10, 0));
    range10 = highestHigh - lowestLow;
    
    // Calculate momentum and direction changes
    double momentum3 = close0 - close3;
    double momentum5 = close0 - close5;
    double momentum10 = close0 - close10;
    
    // Count direction changes (choppiness)
    int directionChanges = 0;
    for(int i=1; i<5; i++) {
        if((iClose(symbol, PERIOD_M5, i) > iClose(symbol, PERIOD_M5, i+1) && 
            iClose(symbol, PERIOD_M5, i-1) < iClose(symbol, PERIOD_M5, i)) ||
           (iClose(symbol, PERIOD_M5, i) < iClose(symbol, PERIOD_M5, i+1) && 
            iClose(symbol, PERIOD_M5, i-1) > iClose(symbol, PERIOD_M5, i))) {
            directionChanges++;
        }
    }
    
    // Calculate Bollinger Band width (for range detection)
    double bbUpper = GetBands(symbol, PERIOD_M5, 20, 2.0, 0, PRICE_CLOSE, 1, 0);
    double bbLower = GetBands(symbol, PERIOD_M5, 20, 2.0, 0, PRICE_CLOSE, 2, 0);
    double bbWidth = (bbUpper - bbLower) / ma20;
    
    // Check for breakouts
    bool breakoutUp = close0 > bbUpper && close1 <= bbUpper;
    bool breakoutDown = close0 < bbLower && close1 >= bbLower;
    bool insideBands = close0 > bbLower && close0 < bbUpper;
    
    // Check for reversals
    bool potentialReversal = (momentum3 * momentum10 < 0) && MathAbs(momentum3) > quickAtr * 0.3;
    
    // Detect market conditions
    bool isVolatile = quickAtr > avgRange * 1.2;
    bool isVeryVolatile = quickAtr > avgRange * 1.8;
    bool isTrendingUp = ma3 > ma5 && ma5 > ma10 && momentum5 > 0;
    bool isTrendingDown = ma3 < ma5 && ma5 < ma10 && momentum5 < 0;
    bool isChoppy = directionChanges >= 3;
    bool isRangingNarrow = bbWidth < 0.01 && !isVolatile && insideBands;
    bool isRangingWide = bbWidth >= 0.01 && bbWidth < 0.03 && insideBands;
    
    // Determine market regime based on all factors
    int regime = LOW_VOLATILITY; // Default regime
    
    if(breakoutUp || breakoutDown) {
        regime = BREAKOUT;
    }
    else if(potentialReversal) {
        regime = REVERSAL;
    }
    else if(isChoppy) {
        regime = CHOPPY;
    }
    else if(isRangingNarrow) {
        regime = RANGING_NARROW;
    }
    else if(isRangingWide) {
        regime = RANGING_WIDE;
    }
    else if(isVeryVolatile) {
        regime = HIGH_VOLATILITY;
    }
    else if(isTrendingUp) {
        regime = TRENDING_UP;
    }
    else if(isTrendingDown) {
        regime = TRENDING_DOWN;
    }
    
    return regime;
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
    // Get local copies of parameters to avoid ambiguity
    int trailing_step = TrailingStepPips;
    int trailing_stop = TrailingStop;
    int take_profit_pips = InitialTakeProfit;
    int magic_num = MagicNumber;
    
    double pip = GetPipSize();
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == magic_num) {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);
            double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double profitPips = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / pip : (openPrice - currentPrice) / pip;
            if(profitPips >= trailing_step) {
                double newSL = (posType == POSITION_TYPE_BUY) ? currentPrice - trailing_stop * pip
                                                             : currentPrice + trailing_stop * pip;
                double newTP = (posType == POSITION_TYPE_BUY) ? currentPrice + take_profit_pips * pip
                                                             : currentPrice - take_profit_pips * pip;
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
                    request.magic = magic_num; // Use local variable to avoid ambiguity
                    bool success = OrderSend(request, result);
                    if (!success) {
                        Print("Failed to modify SL/TP: ", GetLastError());
                    }
                }
            }
        }
    }
}

// --- Advanced entry with SMC patterns and market regime filtering ---
void CheckForEntry() {
    if(PositionsTotal() > 0) return;
    
    // Check if sufficient time has passed since last trade
    bool cooldownPassed = (TimeCurrent() - lastSignalTime) >= 60; // 60 seconds minimum between signals
    if(!cooldownPassed) return;
    
    // Get traditional MA crossover signal
    double fastMA[2], slowMA[2];
    // Get local copies of the period parameters to avoid ambiguity
    int fast_period = FastMAPeriod;
    int slow_period = SlowMAPeriod;
    
    // Use local ma_fast_handle and ma_slow_handle names to avoid hiding global variables
    int ma_fast_handle = iMA(_Symbol, _Period, fast_period, 0, MODE_SMA, PRICE_CLOSE);
    int ma_slow_handle = iMA(_Symbol, _Period, slow_period, 0, MODE_SMA, PRICE_CLOSE);
    if(CopyBuffer(ma_fast_handle, 0, 0, 2, fastMA) != 2) { IndicatorRelease(ma_fast_handle); IndicatorRelease(ma_slow_handle); return; }
    if(CopyBuffer(ma_slow_handle, 0, 0, 2, slowMA) != 2) { IndicatorRelease(ma_fast_handle); IndicatorRelease(ma_slow_handle); return; }
    
    // Higher timeframe trend filter
    int htMAHandle = iMA(_Symbol, PERIOD_H1, slow_period, 0, MODE_SMA, PRICE_CLOSE);
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
    
    // Traditional MA signals
    bool maBuySignal = fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0] && trendUp && volatilityOK;
    bool maSellSignal = fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0] && trendDown && volatilityOK;
    // Note: ma_fast_handle and ma_slow_handle were already released above
    
    // Check for valid order blocks that could enhance the signal
    bool hasValidBuyBlock = false;
    bool hasValidSellBlock = false;
    datetime newestBuyBlock = 0;
    datetime newestSellBlock = 0;
    
    for(int i=0; i<MAX_BLOCKS; i++) {
        if(recentBlocks[i].valid) {
            if(recentBlocks[i].bullish && recentBlocks[i].strength >= MinBlockStrength) {
                if(recentBlocks[i].blockTime > newestBuyBlock) {
                    hasValidBuyBlock = true;
                    newestBuyBlock = recentBlocks[i].blockTime;
                }
            } else if(!recentBlocks[i].bullish && recentBlocks[i].strength >= MinBlockStrength) {
                if(recentBlocks[i].blockTime > newestSellBlock) {
                    hasValidSellBlock = true;
                    newestSellBlock = recentBlocks[i].blockTime;
                }
            }
        }
    }
    
    // Filter by market regime if enabled
    bool regimeAllowsBuy = true;
    bool regimeAllowsSell = true;
    
    if(EnableMarketRegimeFiltering && currentRegime >= 0) {
        switch(currentRegime) {
            case TRENDING_UP:
                regimeAllowsBuy = true;
                regimeAllowsSell = false;
                break;
            case TRENDING_DOWN:
                regimeAllowsBuy = false;
                regimeAllowsSell = true;
                break;
            case HIGH_VOLATILITY:
                // Both allowed but be careful
                break;
            case RANGING_NARROW:
                // Both allowed but be careful with targets
                break;
            case CHOPPY:
                // Avoid trading in choppy markets
                regimeAllowsBuy = false;
                regimeAllowsSell = false;
                break;
        }
    }
    
    // Final signal determination
    bool finalBuySignal = maBuySignal && hasValidBuyBlock && regimeAllowsBuy;
    bool finalSellSignal = maSellSignal && hasValidSellBlock && regimeAllowsSell;
    
    // If using ML and we have enough data, get ML prediction to confirm
    if(EnableML && totalTrades >= ML_MinTrades) {
        // Create a feature vector for current market conditions
        TradeFeatures currentFeatures;
        ExtractFeatures(currentFeatures);
        
        // Convert to input for neural network
        double inputs[10];
        inputs[0]=currentFeatures.spread/10.0; inputs[1]=currentFeatures.atr/0.001; inputs[2]=currentFeatures.adx/50.0;
        inputs[3]=currentFeatures.rsi14/100.0; inputs[4]=currentFeatures.ma50_diff/0.01; inputs[5]=currentFeatures.bands_width/0.01;
        inputs[6]=currentFeatures.volume/1000.0; inputs[7]=currentFeatures.hour/24.0; inputs[8]=currentFeatures.day_of_week/7.0;
        inputs[9]=(finalBuySignal ? 0.8 : (finalSellSignal ? 0.2 : 0.5)); // Prior based on technical signals
        
        // Get prediction
        double prediction = NN_Predict(inputs);
        
        // Use prediction to adjust signals
        if(finalBuySignal && prediction < 0.4) finalBuySignal = false; // ML disagrees with buy
        if(finalSellSignal && prediction > 0.6) finalSellSignal = false; // ML disagrees with sell
    }
    
    // Execute trades if we have a signal
    int signal = 0;
    if(finalBuySignal) signal = ORDER_TYPE_BUY;
    else if(finalSellSignal) signal = ORDER_TYPE_SELL;
    
    if(signal != 0) {
        if(EnableFastExecution) {
            ExecuteTradeOptimized(signal);
        } else {
            double lotSize = CalculateLotSize(RiskPercentage, InitialStopLoss);
            OpenPosition(signal, lotSize);
        }
        lastSignalTime = TimeCurrent();
    }
}

// --- Add/fuse: Open position with pip-based SL/TP ---
void OpenPosition(int orderType, double lotSize) {
    MqlTradeRequest request; ZeroMemory(request);
    MqlTradeResult result; ZeroMemory(result);
    // Get local copies to avoid ambiguity
    int stop_loss_pips = InitialStopLoss;
    int take_profit_pips = InitialTakeProfit;
    int magic_num = MagicNumber;
    
    double pip = GetPipSize();
    double entryPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = (orderType == ORDER_TYPE_BUY) ? entryPrice - stop_loss_pips * pip : entryPrice + stop_loss_pips * pip;
    double tp = (orderType == ORDER_TYPE_BUY) ? entryPrice + take_profit_pips * pip : entryPrice - take_profit_pips * pip;
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = (ENUM_ORDER_TYPE)orderType;  // Explicit cast to ENUM_ORDER_TYPE
    request.price = entryPrice;
    request.sl = sl;
    request.tp = tp;
    request.deviation = MaxSlippage;
    request.magic = magic_num; // Use local variable to avoid ambiguity
    request.type_filling = ORDER_FILLING_FOK;
    bool success = OrderSend(request, result);
    if(!success) {
        Print("Failed to open position: ", GetLastError());
        lastErrorMessage = "Trade failed: " + IntegerToString(GetLastError());
    } else {
        lastTradeTime = TimeCurrent();
        TradesToday++;
    }
}

// --- Add/fuse: OnInit/OnDeinit logic for handle and lot limits ---
int fastMAHandle, slowMAHandle;
int OnInit() {
    // Initialize MA handles using the input parameters
    int fast_period = FastMAPeriod; // Use local variable to avoid ambiguity
    int slow_period = SlowMAPeriod; // Use local variable to avoid ambiguity
    fastMAHandle = iMA(_Symbol, _Period, fast_period, 0, MODE_SMA, PRICE_CLOSE);
    slowMAHandle = iMA(_Symbol, _Period, slow_period, 0, MODE_SMA, PRICE_CLOSE);
    
    // Initialize trade object
    trade.SetDeviationInPoints(MaxSlippage);
    
    // Reset regime statistics
    for(int i=0; i<REGIME_COUNT; i++) {
        regimeWins[i] = 0;
        regimeLosses[i] = 0;
        regimeProfit[i] = 0.0;
        regimeAccuracy[i] = 0.0;
    }
    
    // Reset trading status variables
    emergencyMode = false;
    trailingActive = false;
    trailingLevel = 0;
    trailingTP = 0;
    consecutiveLosses = 0;
    lastErrorMessage = "";
    
    // Set current market regime
    if(EnableMarketRegimeFiltering) {
        currentRegime = FastRegimeDetection(_Symbol);
    } else {
        currentRegime = LOW_VOLATILITY; // Default regime
    }
    
    Print("[Init] ScalperV2 with SMC Hybrid initialized successfully");
    return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {
    IndicatorRelease(fastMAHandle);
    IndicatorRelease(slowMAHandle);
}

// --- Trading Logic ---

// --- Main Trading Logic ---
void OnTick() {
    // Step 1: Update internal state and check trading conditions
    UpdateStatsEnhanced();
    ResetDailyTradeCount();
    CheckDailyLossLimit();
    if(!TradingEnabled) return;
    if(!CheckDrawdownLimit()) return;
    if(emergencyMode) return;
    if(consecutiveLosses >= MaxConsecutiveLosses) {
        emergencyMode = true;
        if(DisplayDebugInfo) Print("[SMC] EMERGENCY MODE ACTIVATED: Too many consecutive losses (", consecutiveLosses, ")");
        return;
    }
    
    // Check for new bar
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_M1, 0);
    if(lastBar == currentBar) return;
    lastBar = currentBar;
    
    // Check trading conditions
    if(!IsTradingSession()) return;
    if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > SpreadThreshold) return;
    
    // Step 2: Run SMC pattern detection
    DetectLiquidityGrabs();
    DetectFairValueGaps();
    DetectOrderBlocks();
    ValidateSupplyDemandZones();
    
    // Step 3: Detect current market regime
    if(EnableMarketRegimeFiltering) {
        currentRegime = FastRegimeDetection(_Symbol);
    }
    
    // Step 4: Check for entry signals
    CheckForEntry();
    
    // Step 5: Manage open positions
    if(EnableAggressiveTrailing) {
        ManageTrailingStops();
    } else {
        TrailPositions();
    }
    
    // Step 6: Display stats and train ML
    if(DisplayDebugInfo) {
        ShowDebugInfo();
    } else {
        PrintTradeStats();
    }
    
    if(EnableML && totalTrades % 10 == 0) TrainNN();
}

//+------------------------------------------------------------------+