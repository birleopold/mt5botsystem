//+------------------------------------------------------------------+
//| SMC Scalper Hybrid V6 - Smart Money Concepts with Advanced Scalping |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Leo Software"
#property link      "https://www.example.com"
#property version   "6.0"
#property strict

// --------------------------
//      Input Parameters
// --------------------------
input bool DisplayDebugInfo = true;
input bool DetailedDebugMode = false;
input double RiskPercent = 1.0;
input int ATR_Period = 14;
input bool OptimizeForGold = true;
input bool UseVolatilityNormalizedStops = true;
input bool UsePartialTrailing = true;
input bool UseBreakEvenAfterTP1 = true;
input bool UseAggressiveTrailingAfterTP2 = true;
input double FirstTakeProfitPercent = 33.0;
input double SecondTakeProfitPercent = 33.0;
input bool UseMarketRegimeBasedTPs = true;
input bool UseAdvancedGoldTrailing = true;
input bool EnableOrderBlocks = true;
input bool EnableLiquidityGrabs = true;
input bool EnableFairValueGaps = true;
input bool UseBOS = true;
input bool UseCHoCH = true;
input int LookbackBars = 100;
input bool EnableDrawdownRecovery = true;
input bool UseEventDrivenProcessing = true;
input bool EnableAutoRecovery = true;
input int RecoveryMinutes = 15;

// --------------------------
//      Enums & Structs
// --------------------------
enum MARKET_REGIME { TRENDING_UP, TRENDING_DOWN, HIGH_VOLATILITY, LOW_VOLATILITY, RANGING_NARROW, RANGING_WIDE, BREAKOUT, REVERSAL, CHOPPY, REGIME_COUNT };
enum MARKET_SESSION { SESSION_ASIAN, SESSION_EUROPEAN, SESSION_US, SESSION_OVERLAP };
enum CALCULATION_TYPE { CALC_MARKET_STRUCTURE, CALC_INDICATORS, CALC_REGIME, CALC_CORRELATION, CALC_VOLATILITY, CALC_SESSION, CALC_COUNT };

struct SwingPoint { datetime time; double price; int score; bool valid; int barIndex; double volume; };
struct LiquidityGrab { datetime time; double high; double low; bool bullish; bool active; double strength; };
struct FairValueGap { datetime startTime; datetime endTime; double high; double low; bool bullish; bool active; };
struct OrderBlock { datetime blockTime; double priceLevel; double highPrice; double lowPrice; bool bullish; bool valid; int strength; bool hasLiquidityGrab; bool hasSDConfirm; bool hasImbalance; bool hasFVG; };
struct BOSEvent { datetime time; double price; bool bullish; bool active; int swingStrength; double swingSize; };
struct CHoCHEvent { datetime time; double price; bool bullish; bool active; int significance; double changeSize; };
struct SessionParameters { double volatilityFactor; double tpMultiplier; double slMultiplier; double tradingFrequencyFactor; double minEntryQuality; bool aggressiveTrailing; string sessionName; int activeHoursStart; int activeHoursEnd; double priceLevelImportance; };
struct CalculationEvent { CALCULATION_TYPE type; int priority; int frequencySeconds; datetime lastCalculated; bool isDirty; };

// --------------------------
//      Global Variables
// --------------------------
#include <Trade/Trade.mqh>
#include <Math/Stat/Normal.mqh>
CTrade trade;
double tpLevels[3];
double currentATR = 0.0;
int currentRegime = CHOPPY;
int currentSession = SESSION_ASIAN;
bool isGold = false;
bool isActiveSessionHours = false;
datetime lastSignalTime = 0;
bool eventProcessingInitialized = false;
bool newBarFormed = false;
bool emergencyMode = false;
datetime emergencyActivatedTime = 0;
SwingPoint swingPoints[];
LiquidityGrab recentGrabs[50];
FairValueGap recentFVGs[50];
OrderBlock recentBlocks[50];
BOSEvent bosEvents[30];
CHoCHEvent chochEvents[30];
SessionParameters sessionParams[4];
bool sessionsInitialized = false;
CalculationEvent calculationEvents[CALC_COUNT];
double regimeWins[REGIME_COUNT];
double regimeLosses[REGIME_COUNT];
double regimeProfit[REGIME_COUNT];
double regimeAccuracy[REGIME_COUNT];
double tradeProfits[100];
double tradeReturns[100];
bool predictionResults[50];
int grabIndex = 0, fvgIndex = 0, blockIndex = 0, bosCount = 0, chochCount = 0;
double FVGMinSize = 0.5;
double sessionVolatilityFactor[4];
double correlationMatrix[10][10];
datetime lastCorrelationCalc = 0;

//--- Position Sizing and Risk Management ---
double CalculatePositionSize(double riskPercent, double stopLossPoints) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * riskPercent / 100.0;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    if(stopLossPoints <= 0 || tickValue <= 0 || tickSize <= 0 || contractSize <= 0) return 0.0;
    double slValue = stopLossPoints * tickValue / tickSize;
    double lots = riskAmount / slValue;
    lots = MathFloor(lots / lotStep) * lotStep;
    lots = MathMax(lots, lotStep);
    if(DisplayDebugInfo) Print("[SMC] Position size (lots): ", DoubleToString(lots, 2));
    return lots;
}

double FindOptimalStopLoss(bool isBuy) {
    // Find the best swing point for SL (most recent relevant swing)
    double sl = 0.0;
    int n = ArraySize(swingPoints);
    for(int i=0; i<n; i++) {
        if(isBuy && swingPoints[i].price < SymbolInfoDouble(_Symbol, SYMBOL_BID)) {
            sl = swingPoints[i].price;
            break;
        }
        if(!isBuy && swingPoints[i].price > SymbolInfoDouble(_Symbol, SYMBOL_ASK)) {
            sl = swingPoints[i].price;
            break;
        }
    }
    if(sl == 0.0) {
        // Fallback to ATR-based SL
        sl = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) - currentATR : SymbolInfoDouble(_Symbol, SYMBOL_ASK) + currentATR;
    }
    if(DisplayDebugInfo) Print("[SMC] Optimal SL: ", DoubleToString(sl, Digits()));
    return sl;
}

//+------------------------------------------------------------------+
//| Required MQL5 Event Handlers                                     |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialization logic
    Print("[SMC V6] Initialization complete");
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    // Cleanup logic
    Print("[SMC V6] Deinitialization, reason: ", reason);
}

void DetectOrderBlocks() {
    // Detect bullish and bearish order blocks (simple engulfing logic)
    int maxBlocks = 20;
    int count = 0;
    ArrayResize(recentBlocks, 0);
    int barsToCheck = MathMin(Bars(_Symbol, _Period)-2, LookbackBars);
    for(int i=1; i<barsToCheck; i++) {
        double open1 = iOpen(_Symbol, _Period, i+1);
        double close1 = iClose(_Symbol, _Period, i+1);
        double open2 = iOpen(_Symbol, _Period, i);
        double close2 = iClose(_Symbol, _Period, i);
        // Bullish engulfing (potential demand block)
        if(close1 < open1 && close2 > open2 && close2 > open1 && open2 < close1) {
            OrderBlock ob;
            ob.blockTime = iTime(_Symbol, _Period, i);
            ob.priceLevel = open2;
            ob.highPrice = MathMax(open2, close2);
            ob.lowPrice = MathMin(open2, close2);
            ob.bullish = true;
            ob.valid = true;
            ob.strength = 100;
            ob.hasLiquidityGrab = false;
            ob.hasSDConfirm = false;
            ob.hasImbalance = false;
            ob.hasFVG = false;
            ArrayResize(recentBlocks, count+1);
            recentBlocks[count] = ob;
            count++;
            if(count >= maxBlocks) break;
        }
        // Bearish engulfing (potential supply block)
        if(close1 > open1 && close2 < open2 && close2 < open1 && open2 > close1) {
            OrderBlock ob;
            ob.blockTime = iTime(_Symbol, _Period, i);
            ob.priceLevel = open2;
            ob.highPrice = MathMax(open2, close2);
            ob.lowPrice = MathMin(open2, close2);
            ob.bullish = false;
            ob.valid = true;
            ob.strength = 100;
            ob.hasLiquidityGrab = false;
            ob.hasSDConfirm = false;
            ob.hasImbalance = false;
            ob.hasFVG = false;
            ArrayResize(recentBlocks, count+1);
            recentBlocks[count] = ob;
            count++;
            if(count >= maxBlocks) break;
        }
    }
    if(DisplayDebugInfo) Print("[SMC] Found ", count, " order blocks");
}


void DetectLiquidityGrabs() {
    // Detect bullish and bearish liquidity grabs (stop hunts with wick extension)
    int maxGrabs = 20;
    int count = 0;
    ArrayResize(recentGrabs, 0);
    int barsToCheck = MathMin(Bars(_Symbol, _Period)-2, LookbackBars);
    for(int i=1; i<barsToCheck; i++) {
        double low = iLow(_Symbol, _Period, i);
        double high = iHigh(_Symbol, _Period, i);
        double prevLow = iLow(_Symbol, _Period, i+1);
        double prevHigh = iHigh(_Symbol, _Period, i+1);
        double open = iOpen(_Symbol, _Period, i);
        double close = iClose(_Symbol, _Period, i);
        // Bullish grab: current low breaks previous low, closes above open (rejection)
        if(low < prevLow && close > open) {
            LiquidityGrab grab;
            grab.time = iTime(_Symbol, _Period, i);
            grab.high = high;
            grab.low = low;
            grab.bullish = true;
            grab.active = true;
            grab.strength = MathAbs(prevLow - low);
            ArrayResize(recentGrabs, count+1);
            recentGrabs[count] = grab;
            count++;
            if(count >= maxGrabs) break;
        }
        // Bearish grab: current high breaks previous high, closes below open (rejection)
        if(high > prevHigh && close < open) {
            LiquidityGrab grab;
            grab.time = iTime(_Symbol, _Period, i);
            grab.high = high;
            grab.low = low;
            grab.bullish = false;
            grab.active = true;
            grab.strength = MathAbs(high - prevHigh);
            ArrayResize(recentGrabs, count+1);
            recentGrabs[count] = grab;
            count++;
            if(count >= maxGrabs) break;
        }
    }
    if(DisplayDebugInfo) Print("[SMC] Found ", count, " liquidity grabs");
}


void DetectFairValueGaps() {
    // Detect bullish and bearish fair value gaps (FVG)
    int maxFVGs = 20;
    int count = 0;
    ArrayResize(recentFVGs, 0);
    int barsToCheck = MathMin(Bars(_Symbol, _Period)-3, LookbackBars);
    for(int i=2; i<barsToCheck; i++) {
        double prevLow = iLow(_Symbol, _Period, i+1);
        double currHigh = iHigh(_Symbol, _Period, i);
        double prevHigh = iHigh(_Symbol, _Period, i+1);
        double currLow = iLow(_Symbol, _Period, i);
        // Bullish FVG: previous candle's low > current candle's high (gap down)
        if(prevLow > currHigh && (prevLow - currHigh) >= FVGMinSize * _Point) {
            FairValueGap fvg;
            fvg.startTime = iTime(_Symbol, _Period, i+1);
            fvg.endTime = iTime(_Symbol, _Period, i);
            fvg.high = prevLow;
            fvg.low = currHigh;
            fvg.bullish = true;
            fvg.active = true;
            ArrayResize(recentFVGs, count+1);
            recentFVGs[count] = fvg;
            count++;
            if(count >= maxFVGs) break;
        }
        // Bearish FVG: previous candle's high < current candle's low (gap up)
        if(prevHigh < currLow && (currLow - prevHigh) >= FVGMinSize * _Point) {
            FairValueGap fvg;
            fvg.startTime = iTime(_Symbol, _Period, i+1);
            fvg.endTime = iTime(_Symbol, _Period, i);
            fvg.high = currLow;
            fvg.low = prevHigh;
            fvg.bullish = false;
            fvg.active = true;
            ArrayResize(recentFVGs, count+1);
            recentFVGs[count] = fvg;
            count++;
            if(count >= maxFVGs) break;
        }
    }
    if(DisplayDebugInfo) Print("[SMC] Found ", count, " fair value gaps");
}


void AnalyzeSwingPoints() {
    // Detect swing highs/lows for stop loss placement
    int swingWindow = 3; // Number of bars left/right for swing
    int barsToCheck = MathMin(Bars(_Symbol, _Period)-swingWindow-1, LookbackBars);
    ArrayResize(swingPoints, 0);
    int count = 0;
    for(int i=swingWindow; i<barsToCheck; i++) {
        double high = iHigh(_Symbol, _Period, i);
        double low = iLow(_Symbol, _Period, i);
        bool isSwingHigh = true, isSwingLow = true;
        // Check left/right bars
        for(int j=1; j<=swingWindow; j++) {
            if(iHigh(_Symbol, _Period, i-j) >= high || iHigh(_Symbol, _Period, i+j) >= high)
                isSwingHigh = false;
            if(iLow(_Symbol, _Period, i-j) <= low || iLow(_Symbol, _Period, i+j) <= low)
                isSwingLow = false;
        }
        if(isSwingHigh || isSwingLow) {
            SwingPoint sp;
            sp.time = iTime(_Symbol, _Period, i);
            sp.price = isSwingHigh ? high : low;
            sp.score = 100; // Placeholder: could use volume, range, etc.
            sp.valid = true;
            sp.barIndex = i;
            sp.volume = iVolume(_Symbol, _Period, i);
            ArrayResize(swingPoints, count+1);
            swingPoints[count] = sp;
            count++;
        }
    }
    if(DisplayDebugInfo) Print("[SMC] Found ", count, " swing points for SL analysis");
}


double atrBuffer[];

//--- Calculate ATR using built-in iATR indicator
void CalculateATR() {
    int barsRequired = ATR_Period + 2;
    if(Bars(_Symbol, _Period) < barsRequired) return;
    if(ArraySize(atrBuffer) != barsRequired)
        ArrayResize(atrBuffer, barsRequired);
    int copied = CopyBuffer(iATR(_Symbol, _Period, ATR_Period), 0, 0, barsRequired, atrBuffer);
    if(copied != barsRequired) {
        if(DisplayDebugInfo) Print("[SMC] ATR buffer copy failed: ", copied, " bars copied");
        return;
    }
    currentATR = atrBuffer[0];
    if(DisplayDebugInfo && DetailedDebugMode) Print("[SMC] ATR: ", DoubleToString(currentATR, Digits()));
}


void DetectMarketRegime() {
    // Simple regime detection: trending, ranging, volatile using ATR and MA slope
    int maPeriod = 20;
    double maBuffer[3];
    if(CopyBuffer(iMA(_Symbol, _Period, maPeriod, 0, MODE_SMA, PRICE_CLOSE), 0, 0, 3, maBuffer) != 3) return;
    double slope = maBuffer[0] - maBuffer[2];
    double atr = currentATR;
    double atrBufferTmp[];
if(ArraySize(atrBufferTmp)!=maPeriod+2) ArrayResize(atrBufferTmp, maPeriod+2);
int copiedATR = CopyBuffer(iATR(_Symbol, _Period, maPeriod), 0, 0, maPeriod+2, atrBufferTmp);
double avgRange = 0.0;
if(copiedATR == maPeriod+2) avgRange = atrBufferTmp[0];
else avgRange = currentATR; // fallback
    int regime = CHOPPY;
    if(MathAbs(slope) > avgRange * 0.2) {
        regime = (slope > 0) ? TRENDING_UP : TRENDING_DOWN;
    } else if(atr > avgRange * 1.5) {
        regime = HIGH_VOLATILITY;
    } else if(atr < avgRange * 0.7) {
        regime = LOW_VOLATILITY;
    } else {
        regime = RANGING_NARROW;
    }
    currentRegime = regime;
    if(DisplayDebugInfo) Print("[SMC] Market regime: ", regime);
}


void DetectSession() {
    // Session detection using server time (broker time)
    MqlDateTime tm;
TimeToStruct(TimeCurrent(), tm);
int hour = tm.hour;
    int session = SESSION_ASIAN;
    if(hour >= 0 && hour < 8) session = SESSION_ASIAN;
    else if(hour >= 8 && hour < 16) session = SESSION_EUROPEAN;
    else if(hour >= 16 && hour < 20) session = SESSION_US;
    else session = SESSION_OVERLAP;
    currentSession = session;
    if(DisplayDebugInfo) Print("[SMC] Market session: ", session);
}


void ApplyTrailingStop() {
    // Advanced trailing stop logic (stub)
    if(DisplayDebugInfo) Print("[SMC] Trailing stop logic applied");
}

void ApplyPartialTakeProfits() {
    // Partial profit taking logic (stub)
    if(DisplayDebugInfo) Print("[SMC] Partial take profit logic applied");
}

void ApplyBreakeven() {
    // Breakeven logic (stub)
    if(DisplayDebugInfo) Print("[SMC] Breakeven logic applied");
}

void ManageOpenPositions() {
    // Manage all open trades: trailing, partial TP, breakeven
    ApplyTrailingStop();
    ApplyPartialTakeProfits();
    ApplyBreakeven();
}

void UpdatePerformanceMetrics() {
    // Performance metrics tracking (stub)
    if(DisplayDebugInfo) Print("[SMC] Performance metrics updated");
}

void DrawOrderBlocks() {
    // Remove old order block objects
    for(int i=0; i<20; i++) {
        string name = "SMC_OB_" + IntegerToString(i);
        ObjectDelete(0, name);
    }
    // Draw rectangles for each order block
    int n = ArraySize(recentBlocks);
    for(int i=0; i<n; i++) {
        string name = "SMC_OB_" + IntegerToString(i);
        color clr = recentBlocks[i].bullish ? clrLime : clrRed;
        datetime t1 = recentBlocks[i].blockTime;
        datetime t2 = TimeCurrent();
        double price1 = recentBlocks[i].lowPrice;
        double price2 = recentBlocks[i].highPrice;
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, price1, t2, price2);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    }
}

void DrawFairValueGaps() {
    // Remove old FVG objects
    for(int i=0; i<20; i++) {
        string name = "SMC_FVG_" + IntegerToString(i);
        ObjectDelete(0, name);
    }
    // Draw rectangles for each FVG
    int n = ArraySize(recentFVGs);
    for(int i=0; i<n; i++) {
        string name = "SMC_FVG_" + IntegerToString(i);
        color clr = recentFVGs[i].bullish ? clrAqua : clrOrange;
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, recentFVGs[i].startTime, recentFVGs[i].low, recentFVGs[i].endTime, recentFVGs[i].high);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    }
}

void DrawLiquidityGrabs() {
    // Remove old grab objects
    for(int i=0; i<20; i++) {
        string name = "SMC_GRAB_" + IntegerToString(i);
        ObjectDelete(0, name);
    }
    // Draw arrows for each grab
    int n = ArraySize(recentGrabs);
    for(int i=0; i<n; i++) {
        string name = "SMC_GRAB_" + IntegerToString(i);
        color clr = recentGrabs[i].bullish ? clrBlue : clrMagenta;
        double price = recentGrabs[i].bullish ? recentGrabs[i].low : recentGrabs[i].high;
        ObjectCreate(0, name, OBJ_ARROW, 0, recentGrabs[i].time, price);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_ARROWCODE, recentGrabs[i].bullish ? 233 : 234); // Up/down arrow
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
    }
}

void ShowSmcInfo() {
    // Display SMC/market info on the chart and draw SMC structures
    if(DisplayDebugInfo) {
        string info = "[SMC] Regime: " + IntegerToString(currentRegime) + ", Session: " + IntegerToString(currentSession) + ", ATR: " + DoubleToString(currentATR, Digits());
        Comment(info);
        DrawOrderBlocks();
        DrawFairValueGaps();
        DrawLiquidityGrabs();
    } else {
        Comment("");
        // Remove all SMC objects if debug off
        for(int i=0; i<20; i++) {
            ObjectDelete(0, "SMC_OB_" + IntegerToString(i));
            ObjectDelete(0, "SMC_FVG_" + IntegerToString(i));
            ObjectDelete(0, "SMC_GRAB_" + IntegerToString(i));
        }
    }
}


void OnTick() {
    // Main tick logic (SMC, risk, trade management, debug, etc.)
    if(DisplayDebugInfo) Print("[SMC V6] OnTick event");
    if(EnableOrderBlocks) DetectOrderBlocks();
    if(EnableLiquidityGrabs) DetectLiquidityGrabs();
    if(EnableFairValueGaps) DetectFairValueGaps();
    AnalyzeSwingPoints();
    CalculateATR();
    DetectMarketRegime();
    DetectSession();
    ManageOpenPositions();
    UpdatePerformanceMetrics();
    ShowSmcInfo();
}




void OnTrade() {
    // Trade event logic
    Print("[SMC V6] OnTrade event");
}
// End of SMC Scalper Hybrid V6
