//+------------------------------------------------------------------+
//|                     ScalpingEA with SMC Hybrid                   |
//|         Smart Money Concepts & Adaptive Market Regime Logic      |
//+------------------------------------------------------------------+
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Math\Stat\Normal.mqh>

// Core SMC Constants and Definitions
#define MAX_BLOCKS 20
#define MAX_GRABS 10
#define MAX_FVGS 10
#define METRIC_WINDOW 100
#define REGIME_COUNT 9

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

// SMC structure definitions
struct LiquidityGrab { 
   datetime time; 
   double high; 
   double low; 
   bool bullish; 
   bool active; 
   double score; // quality score
};

struct FairValueGap { 
   datetime startTime; 
   datetime endTime; 
   double high; 
   double low; 
   bool bullish; 
   bool active; 
   double score; // quality score
};

struct OrderBlock { 
   datetime blockTime; 
   double priceLevel; 
   double highPrice; 
   double lowPrice; 
   bool bullish; 
   bool valid; 
   int strength; 
};

struct SwingPoint {
    int barIndex;
    double price;
    int score;
    datetime time;
};

//--- Original Input Parameters
input group "===== GENERAL SETTINGS ====="
input int    InpFastMAPeriod   = 5;        // Fast MA period (EMA)
input int    InpSlowMAPeriod   = 20;       // Slow MA period (EMA)
input int    InpATRPeriod      = 7;        // ATR period for stops
input double InpATRMultiplier  = 1.0;      // ATR multiplier for tight stops
input uint   InpSlippage       = 2;        // Maximum allowed slippage
input uint   InpDuration       = 60;       // Position duration in minutes (scalping)
input double InpRiskPerTrade   = 0.5;      // Risk % per trade (small for scalping)
input double InpTakeProfit     = 5.0;      // Take profit in ATR multiples
input double InpTrailingStop   = 2.0;      // Trailing stop in ATR multiples
input long   InpMagicNumber    = 800001;   // Unique EA identifier

//--- Entry and Confirmation Parameters
input group "===== ENTRY FILTERS ====="
input double InpMaxSpread      = 20;       // Max spread in points to allow trading
input int    InpRSIPeriod      = 7;        // RSI period for confirmation
input double InpRSIBuyLevel    = 55.0;     // Minimum RSI to allow buy
input double InpRSISellLevel   = 45.0;     // Maximum RSI to allow sell
input int    InpTradeStartHour = 2;        // Trading start hour (broker time)
input int    InpTradeEndHour   = 22;       // Trading end hour (broker time)

//--- SMC Enhancement Parameters
input group "===== SMC FEATURES ====="
input bool   InpEnableSMC         = true;   // Enable SMC advanced features
input bool   InpRegimeFiltering   = true;   // Filter trades based on market regime
input bool   InpOptimalStopLoss   = true;   // Use swing-based optimal stop loss
input bool   InpDynamicTakeProfit = true;   // Use dynamic take profit calculation
input bool   InpAdvancedTrailing  = true;   // Use advanced trailing methods
input int    InpLookbackBars      = 100;    // Bars to look back for structures
input double InpBaseRiskReward    = 2.0;    // Base risk:reward ratio
input double InpTrailMultiplier   = 0.5;    // Trailing stop multiplier of ATR
input int    InpMaxLosses         = 3;      // Max consecutive losses before protection
input bool   InpDisplayInfo       = true;    // Display debug info in comments

//--- News Filter Settings
input group "===== NEWS FILTER ====="
input int    InpNewsCount      = 3;        // Number of news events to block (manual input)
input datetime InpNewsTime1    = 0;        // News event time 1
input datetime InpNewsTime2    = 0;        // News event time 2
input datetime InpNewsTime3    = 0;        // News event time 3
input int    InpNewsBlockMins  = 15;       // Minutes before/after news to block trading

// Original indicator handles
int    ExtFastMAHandle  = INVALID_HANDLE;
int    ExtSlowMAHandle  = INVALID_HANDLE;
int    ExtATRHandle     = INVALID_HANDLE;
int    ExtRSIHandle     = INVALID_HANDLE;
double ExtFastMA[], ExtSlowMA[], ExtATR[], ExtRSI[];
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

// SMC Global Variables
LiquidityGrab ExtLiquidityGrabs[MAX_GRABS];
FairValueGap ExtFairValueGaps[MAX_FVGS];
OrderBlock ExtOrderBlocks[MAX_BLOCKS];
SwingPoint ExtSwingPoints[20];

// Liquidity grab and FVG counts
int ExtGrabCount = 0;
int ExtFVGCount = 0;
int ExtBlockCount = 0;
int ExtSwingCount = 0;

// Trading stats and performance tracking
bool ExtEmergencyMode = false;
datetime ExtLastTradeTime = 0;
datetime ExtLastSignalTime = 0;
bool ExtTrailingActive = false;
double ExtTrailingLevel = 0;
int ExtConsecutiveLosses = 0;
int ExtCurrentRegime = -1;
int ExtPrevRegime = -1;
double ExtRegimeProfit[REGIME_COUNT];
double ExtRegimeAccuracy[REGIME_COUNT];
int ExtRegimeWins[REGIME_COUNT];
int ExtRegimeLosses[REGIME_COUNT];

// Performance tracking
int ExtWinStreak = 0;
int ExtLossStreak = 0;
double ExtTradeProfits[METRIC_WINDOW];
double ExtTradeReturns[METRIC_WINDOW];
int ExtProfitCount = 0; // Number of trades tracked

//+------------------------------------------------------------------+
//| Convert regime code to string description                         |
//+------------------------------------------------------------------+
string RegimeToString(int regime) {
   switch(regime) {
      case TRENDING_UP:      return "Trending Up";
      case TRENDING_DOWN:    return "Trending Down";
      case HIGH_VOLATILITY:  return "High Volatility";
      case LOW_VOLATILITY:   return "Low Volatility";
      case RANGING_NARROW:   return "Ranging Narrow";
      case RANGING_WIDE:     return "Ranging Wide";
      case BREAKOUT:         return "Breakout";
      case REVERSAL:         return "Reversal";
      case CHOPPY:           return "Choppy";
      default:               return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade object
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippage);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Initialize symbol info
   if(!ExtSymbolInfo.Name(_Symbol)) {
      Print("[ERROR] Symbol info init failed");
      return INIT_FAILED;
   }
   
   // Initialize standard indicators
   ExtFastMAHandle = iMA(_Symbol, _Period, InpFastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ExtSlowMAHandle = iMA(_Symbol, _Period, InpSlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ExtATRHandle = iATR(_Symbol, _Period, InpATRPeriod);
   ExtRSIHandle = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   
   if(ExtFastMAHandle == INVALID_HANDLE || ExtSlowMAHandle == INVALID_HANDLE || 
      ExtATRHandle == INVALID_HANDLE || ExtRSIHandle == INVALID_HANDLE) {
      Print("[ERROR] Indicator init failed");
      return INIT_FAILED;
   }
   
   // Initialize SMC arrays if enabled
   if(InpEnableSMC) {
      // Reset SMC structure counts
      ExtGrabCount = 0;
      ExtFVGCount = 0;
      ExtBlockCount = 0;
      ExtSwingCount = 0;
      
      // Reset performance tracking arrays
      ArrayInitialize(ExtRegimeWins, 0);
      ArrayInitialize(ExtRegimeLosses, 0);
      ArrayInitialize(ExtRegimeProfit, 0.0);
      ArrayInitialize(ExtRegimeAccuracy, 0.0);
      ArrayInitialize(ExtTradeProfits, 0.0);
      ArrayInitialize(ExtTradeReturns, 0.0);
      
      // Reset trading status variables
      ExtEmergencyMode = false;
      ExtLastTradeTime = 0;
      ExtLastSignalTime = 0;
      ExtTrailingActive = false;
      ExtTrailingLevel = 0;
      ExtConsecutiveLosses = 0;
      ExtWinStreak = 0;
      ExtLossStreak = 0;
      ExtProfitCount = 0;
      
      // Initialize market regime
      if(InpRegimeFiltering) {
         ExtCurrentRegime = DetectMarketRegime();
         ExtPrevRegime = ExtCurrentRegime;
         Print("[INFO] Initial market regime: ", RegimeToString(ExtCurrentRegime));
      }
   }
   
   Print("[INFO] ScalpingEA with SMC Hybrid initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Detect market regime based on price patterns and volatility       |
//+------------------------------------------------------------------+
int DetectMarketRegime() {
    // Get price data for multiple timeframes
    double close0 = iClose(_Symbol, _Period, 0);
    double close1 = iClose(_Symbol, _Period, 1);
    double close3 = iClose(_Symbol, _Period, 3);
    double close5 = iClose(_Symbol, _Period, 5);
    double close10 = iClose(_Symbol, _Period, 10);
    
    // Get high/low data
    double high0 = iHigh(_Symbol, _Period, 0);
    double high1 = iHigh(_Symbol, _Period, 1);
    double high3 = iHigh(_Symbol, _Period, 3);
    double low0 = iLow(_Symbol, _Period, 0);
    double low1 = iLow(_Symbol, _Period, 1);
    double low3 = iLow(_Symbol, _Period, 3);
    
    // Calculate multiple moving averages for trend detection
    double ma3 = 0, ma5 = 0, ma10 = 0, ma20 = 0;
    for(int i=0; i<3; i++) ma3 += iClose(_Symbol, _Period, i);
    for(int i=0; i<5; i++) ma5 += iClose(_Symbol, _Period, i);
    for(int i=0; i<10; i++) ma10 += iClose(_Symbol, _Period, i);
    for(int i=0; i<20; i++) ma20 += iClose(_Symbol, _Period, i);
    ma3 /= 3;
    ma5 /= 5;
    ma10 /= 10;
    ma20 /= 20;
    
    // Calculate volatility metrics
    double atr = 0;
    if(CopyBuffer(ExtATRHandle, 0, 0, 1, ExtATR) > 0) {
        atr = ExtATR[0];
    } else {
        // Fallback calculation
        double sum = 0;
        for(int i=0; i<10; i++) {
            sum += MathAbs(iHigh(_Symbol, _Period, i) - iLow(_Symbol, _Period, i));
        }
        atr = sum / 10;
    }
    
    double avgRange = 0;
    for(int i=0; i<5; i++) {
        avgRange += MathAbs(iHigh(_Symbol, _Period, i) - iLow(_Symbol, _Period, i));
    }
    avgRange /= 5;
    
    // Calculate price range over different periods
    double range3 = MathMax(high0, high1) - MathMin(low0, low1);
    double range10 = 0;
    double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, 10, 0));
    double lowestLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, 10, 0));
    range10 = highestHigh - lowestLow;
    
    // Calculate momentum and direction changes
    double momentum3 = close0 - close3;
    double momentum5 = close0 - close5;
    double momentum10 = close0 - close10;
    
    // Count direction changes (choppiness)
    int directionChanges = 0;
    for(int i=1; i<5; i++) {
        if((iClose(_Symbol, _Period, i) > iClose(_Symbol, _Period, i+1) && 
            iClose(_Symbol, _Period, i-1) < iClose(_Symbol, _Period, i)) ||
           (iClose(_Symbol, _Period, i) < iClose(_Symbol, _Period, i+1) && 
            iClose(_Symbol, _Period, i-1) > iClose(_Symbol, _Period, i))) {
            directionChanges++;
        }
    }
    
    // Calculate Bollinger Band width for range detection
    double bbUpper = 0, bbLower = 0, bbWidth = 0;
    int bbHandle = iBands(_Symbol, _Period, 20, 2.0, 0, PRICE_CLOSE);
    if(bbHandle != INVALID_HANDLE) {
        double bbBuffer[];
        if(CopyBuffer(bbHandle, 1, 0, 1, bbBuffer) > 0) bbUpper = bbBuffer[0]; // Upper band
        if(CopyBuffer(bbHandle, 2, 0, 1, bbBuffer) > 0) bbLower = bbBuffer[0]; // Lower band
        bbWidth = (bbUpper - bbLower) / ma20;
        IndicatorRelease(bbHandle);
    }
    
    // Check for breakouts
    bool breakoutUp = close0 > bbUpper && close1 <= bbUpper;
    bool breakoutDown = close0 < bbLower && close1 >= bbLower;
    bool insideBands = close0 > bbLower && close0 < bbUpper;
    
    // Check for reversals
    bool potentialReversal = (momentum3 * momentum10 < 0) && MathAbs(momentum3) > atr * 0.3;
    
    // Detect market conditions
    bool isVolatile = atr > avgRange * 1.2;
    bool isVeryVolatile = atr > avgRange * 1.8;
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

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(ExtFastMAHandle != INVALID_HANDLE) IndicatorRelease(ExtFastMAHandle);
   if(ExtSlowMAHandle != INVALID_HANDLE) IndicatorRelease(ExtSlowMAHandle);
   if(ExtATRHandle != INVALID_HANDLE) IndicatorRelease(ExtATRHandle);
   if(ExtRSIHandle != INVALID_HANDLE) IndicatorRelease(ExtRSIHandle);
   
   // Output performance statistics if we had trades
   if(InpEnableSMC && InpRegimeFiltering && ExtProfitCount > 0) {
      Print("===== SMC Performance Statistics =====");
      double totalProfit = 0;
      int totalWins = 0, totalLosses = 0;
      
      for(int i=0; i<REGIME_COUNT; i++) {
         int trades = ExtRegimeWins[i] + ExtRegimeLosses[i];
         if(trades > 0) {
            double winRate = (trades > 0) ? 100.0 * ExtRegimeWins[i] / trades : 0;
            Print("Regime: ", RegimeToString(i), 
                  ", Trades: ", trades, 
                  ", Win rate: ", DoubleToString(winRate, 1), "%",
                  ", Profit: ", DoubleToString(ExtRegimeProfit[i], 2));
            
            totalProfit += ExtRegimeProfit[i];
            totalWins += ExtRegimeWins[i];
            totalLosses += ExtRegimeLosses[i];
         }
      }
      
      double overallWinRate = (totalWins + totalLosses > 0) ? 100.0 * totalWins / (totalWins + totalLosses) : 0;
      Print("Total trades: ", totalWins + totalLosses,
            ", Overall win rate: ", DoubleToString(overallWinRate, 1), "%",
            ", Total profit: ", DoubleToString(totalProfit, 2));
   }
}

void OnTick()
{
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(lastBar == curBar) return;
   lastBar = curBar;
   if(!RefreshIndicators()) return;
   if(!WithinTradingHours()) return;
   if(!SpreadIsAcceptable()) return;
   if(IsNewsTime()) return;
   if(ExtPositionInfo.Select(_Symbol)) {
      // Close position if opposite signal
      int signal = TradeSignal();
      if((ExtPositionInfo.PositionType() == POSITION_TYPE_BUY && signal == -1) ||
         (ExtPositionInfo.PositionType() == POSITION_TYPE_SELL && signal == 1)) {
         if(ExtTrade.PositionClose(_Symbol)) {
            Print("[INFO] Position closed on opposite signal");
            Alert("[INFO] Position closed on opposite signal");
         }
      } else {
         ManageTrailingStop();
         CheckPositionExpiration();
      }
      return;
   }
   int signal = TradeSignal();
   if(signal == 1) {
      ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
   } else if(signal == -1) {
      ExecuteTrade(ORDER_TYPE_SELL, ExtATR[1]);
   }
}

bool RefreshIndicators()
{
   if(CopyBuffer(ExtFastMAHandle, 0, 0, 2, ExtFastMA) <= 0) { Print("[ERROR] FastMA buffer"); return false; }
   if(CopyBuffer(ExtSlowMAHandle, 0, 0, 2, ExtSlowMA) <= 0) { Print("[ERROR] SlowMA buffer"); return false; }
   if(CopyBuffer(ExtATRHandle, 0, 0, 2, ExtATR) <= 0) { Print("[ERROR] ATR buffer"); return false; }
   if(CopyBuffer(ExtRSIHandle, 0, 0, 2, ExtRSI) <= 0) { Print("[ERROR] RSI buffer"); return false; }
   return true;
}

//+------------------------------------------------------------------+
//| Utility functions for market conditions                          |
//+------------------------------------------------------------------+
bool SpreadIsAcceptable()
{
   double spread = (ExtSymbolInfo.Ask() - ExtSymbolInfo.Bid()) / ExtSymbolInfo.Point();
   if(spread > InpMaxSpread) {
      Print("[INFO] Spread too high: ", spread, " > ", InpMaxSpread);
      return false;
   }
   return true;
}

bool WithinTradingHours()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int hour = tm.hour;
   if(hour < InpTradeStartHour || hour >= InpTradeEndHour) {
      Print("[INFO] Not within trading hours: ", hour);
      return false;
   }
   return true;
}

bool IsNewsTime()
{
   datetime now = TimeCurrent();
   datetime arr[3] = {InpNewsTime1, InpNewsTime2, InpNewsTime3};
   for(int i=0; i<3; i++) {
      if(arr[i]==0) continue;
      if(MathAbs(now - arr[i]) <= InpNewsBlockMins*60) {
         Print("[INFO] Trade blocked due to news event at ", TimeToString(arr[i], TIME_DATE|TIME_MINUTES));
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Pattern recognition for candlestick patterns                      |
//+------------------------------------------------------------------+
bool IsBullishEngulfing()
{
   double open1 = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double open2 = iOpen(_Symbol, _Period, 2);
   double close2 = iClose(_Symbol, _Period, 2);
   return (close2 < open2 && close1 > open1 && close1 > open2 && open1 < close2);
}

bool IsBearishEngulfing()
{
   double open1 = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double open2 = iOpen(_Symbol, _Period, 2);
   double close2 = iClose(_Symbol, _Period, 2);
   return (close2 > open2 && close1 < open1 && close1 < open2 && open1 > close2);
}

//+------------------------------------------------------------------+
//| Enhanced trade signal with SMC considerations                    |
//+------------------------------------------------------------------+
int TradeSignal()
{
   // Base signal from MA crossover with RSI and price action confirmation
   int baseSignal = 0;
   
   if(ExtFastMA[1] > ExtSlowMA[1] && ExtRSI[1] >= InpRSIBuyLevel && IsBullishEngulfing())
      baseSignal = 1;
   else if(ExtFastMA[1] < ExtSlowMA[1] && ExtRSI[1] <= InpRSISellLevel && IsBearishEngulfing())
      baseSignal = -1;
   
   // If no base signal or SMC features disabled, return base signal
   if(baseSignal == 0 || !InpEnableSMC)
      return baseSignal;
   
   // Apply market regime filtering if enabled
   if(InpRegimeFiltering) {
      // If current regime is unfavorable, reject the signal
      switch(ExtCurrentRegime) {
         // For buy signals
         case CHOPPY:
         case HIGH_VOLATILITY:
            if(baseSignal > 0 && InpDisplayInfo) {
               Print("Buy signal rejected due to ", RegimeToString(ExtCurrentRegime), " market regime");
               return 0; // Reject bullish signals in choppy/volatile markets
            }
            break;
            
         // For sell signals
         case TRENDING_UP:
         case BREAKOUT:
            if(baseSignal < 0 && InpDisplayInfo) {
               Print("Sell signal rejected due to ", RegimeToString(ExtCurrentRegime), " market regime");
               return 0; // Reject bearish signals in strong uptrends
            }
            break;
      }
   }
   
   // Check for SMC entry confirmations
   bool smcConfirmation = false;
   
   if(baseSignal > 0) { // For buy signals
      // Check for bullish liquidity grabs
      for(int i=0; i<ExtGrabCount; i++) {
         if(ExtLiquidityGrabs[i].bullish && ExtLiquidityGrabs[i].active) {
            // If a recent bullish liquidity grab exists, confirm the buy signal
            datetime grabTime = ExtLiquidityGrabs[i].time;
            if(TimeCurrent() - grabTime < 4 * PeriodSeconds(_Period)) {
               smcConfirmation = true;
               if(InpDisplayInfo) Print("Buy signal confirmed by bullish liquidity grab");
               break;
            }
         }
      }
      
      // Check for bullish fair value gaps
      for(int i=0; i<ExtFVGCount; i++) {
         if(ExtFairValueGaps[i].bullish && ExtFairValueGaps[i].active) {
            // Check if price is near the bottom of the FVG
            double currentPrice = iClose(_Symbol, _Period, 0);
            if(MathAbs(currentPrice - ExtFairValueGaps[i].low) < ExtATR[0] * 0.5) {
               smcConfirmation = true;
               if(InpDisplayInfo) Print("Buy signal confirmed by bullish fair value gap");
               break;
            }
         }
      }
   }
   else if(baseSignal < 0) { // For sell signals
      // Check for bearish liquidity grabs
      for(int i=0; i<ExtGrabCount; i++) {
         if(!ExtLiquidityGrabs[i].bullish && ExtLiquidityGrabs[i].active) {
            // If a recent bearish liquidity grab exists, confirm the sell signal
            datetime grabTime = ExtLiquidityGrabs[i].time;
            if(TimeCurrent() - grabTime < 4 * PeriodSeconds(_Period)) {
               smcConfirmation = true;
               if(InpDisplayInfo) Print("Sell signal confirmed by bearish liquidity grab");
               break;
            }
         }
      }
      
      // Check for bearish fair value gaps
      for(int i=0; i<ExtFVGCount; i++) {
         if(!ExtFairValueGaps[i].bullish && ExtFairValueGaps[i].active) {
            // Check if price is near the top of the FVG
            double currentPrice = iClose(_Symbol, _Period, 0);
            if(MathAbs(currentPrice - ExtFairValueGaps[i].high) < ExtATR[0] * 0.5) {
               smcConfirmation = true;
               if(InpDisplayInfo) Print("Sell signal confirmed by bearish fair value gap");
               break;
            }
         }
      }
   }
   
   // Return the final signal: only return the base signal if we have SMC confirmation
   // or if no SMC structures were detected (in which case we fall back to the base signal)
   return (smcConfirmation || ExtGrabCount == 0 && ExtFVGCount == 0) ? baseSignal : 0;
}

//+------------------------------------------------------------------+
//| Enhanced trade execution with SMC optimizations                   |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   // Update rates
   ExtSymbolInfo.RefreshRates();
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = 0, tp = 0;
   
   // Calculate standard stop loss based on ATR
   double standardSL = (type == ORDER_TYPE_BUY) ? 
                       price - InpATRMultiplier * atrValue : 
                       price + InpATRMultiplier * atrValue;
                       
   // Calculate standard take profit based on ATR                    
   double standardTP = (type == ORDER_TYPE_BUY) ? 
                       price + InpTakeProfit * atrValue : 
                       price - InpTakeProfit * atrValue;
   
   // Use enhanced stop loss if SMC features are enabled
   if(InpEnableSMC && InpOptimalStopLoss) {
      sl = CalculateOptimalStopLoss(type, price, standardSL, atrValue);
      
      // If optimal stop loss is too far, revert to standard
      double slDistance = MathAbs(price - sl);
      if(slDistance > atrValue * 2.5) {
         sl = standardSL;
      }
   } else {
      // Use standard stop loss
      sl = standardSL;
   }
   
   // Use dynamic take profit if enabled
   if(InpEnableSMC && InpDynamicTakeProfit) {
      tp = CalculateDynamicTakeProfit(type, price, sl, atrValue);
   } else {
      // Use standard take profit
      tp = standardTP;
   }
   
   // Calculate lot size based on risk management
   double slDistance = MathAbs(price - sl);
   double lot = CalculateLot(slDistance);
   
   // Open position
   if(!ExtTrade.PositionOpen(_Symbol, type, lot, price, sl, tp, "SMC Scalping")) {
      Print("[ERROR] Trade open failed: ", ExtTrade.ResultRetcodeDescription());
      Alert("[ERROR] Trade open failed: ", ExtTrade.ResultRetcodeDescription());
      
      // Increment consecutive losses counter on error
      ExtConsecutiveLosses++;
      if(ExtConsecutiveLosses >= InpMaxLosses) {
         ExtEmergencyMode = true;
         Print("[WARNING] Emergency mode activated due to multiple failed trade attempts");
      }
   } else {
      // Store trade information
      ExtLastTradeTime = TimeCurrent();
      ExtLastSignalTime = TimeCurrent();
      ExtTrailingActive = false;
      ExtTrailingLevel = 0;
      
      // Reset emergency mode if successful trade
      if(ExtEmergencyMode) {
         ExtEmergencyMode = false;
         ExtConsecutiveLosses = 0;
      }
      
      // Log trade details
      string tradeInfo = StringFormat("[SUCCESS] %s trade executed: %.2f lots at %.5f, SL: %.5f, TP: %.5f, Risk: %.2f%%, Regime: %s", 
                                     EnumToString(type), lot, price, sl, tp, InpRiskPerTrade, 
                                     RegimeToString(ExtCurrentRegime));
      Print(tradeInfo);
      if(InpDisplayInfo) Comment(tradeInfo);
      
      // Check if advanced trailing is enabled
      if(InpEnableSMC && InpAdvancedTrailing) {
         ExtTrailingActive = true;
         ExtTrailingLevel = (type == ORDER_TYPE_BUY) ? sl : sl;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate optimal stop loss based on swing points and SMC         |
//+------------------------------------------------------------------+
double CalculateOptimalStopLoss(ENUM_ORDER_TYPE type, double entryPrice, double defaultSL, double atrValue)
{
   // If no swing points found, use default stop loss
   if(ExtSwingCount == 0) return defaultSL;
   
   double optimalSL = defaultSL;
   double bestScore = 0;
   
   if(type == ORDER_TYPE_BUY) {
      // For buy orders, find recent swing lows
      for(int i=0; i<ExtSwingCount; i++) {
         // Only consider swing lows (price points below current price)
         if(ExtSwingPoints[i].price < entryPrice) {
            // Validate stop distance isn't too close or too far
            double distance = entryPrice - ExtSwingPoints[i].price;
            if(distance > atrValue * 0.5 && distance < atrValue * 3) {
               // Calculate score based on swing strength and recency
               double score = ExtSwingPoints[i].score * (1.0 - (0.05 * ExtSwingPoints[i].barIndex));
               
               // If this swing point has better score, use it for SL
               if(score > bestScore) {
                  bestScore = score;
                  // Place SL slightly below the swing point
                  optimalSL = ExtSwingPoints[i].price - (10 * _Point);
               }
            }
         }
      }
   } else { // SELL order
      // For sell orders, find recent swing highs
      for(int i=0; i<ExtSwingCount; i++) {
         // Only consider swing highs (price points above current price)
         if(ExtSwingPoints[i].price > entryPrice) {
            // Validate stop distance isn't too close or too far
            double distance = ExtSwingPoints[i].price - entryPrice;
            if(distance > atrValue * 0.5 && distance < atrValue * 3) {
               // Calculate score based on swing strength and recency
               double score = ExtSwingPoints[i].score * (1.0 - (0.05 * ExtSwingPoints[i].barIndex));
               
               // If this swing point has better score, use it for SL
               if(score > bestScore) {
                  bestScore = score;
                  // Place SL slightly above the swing point
                  optimalSL = ExtSwingPoints[i].price + (10 * _Point);
               }
            }
         }
      }
   }
   
   // If no suitable swing point found, use default SL
   if(bestScore == 0) {
      optimalSL = defaultSL;
   }
   
   return optimalSL;
}

//+------------------------------------------------------------------+
//| Calculate dynamic take profit based on market structures          |
//+------------------------------------------------------------------+
double CalculateDynamicTakeProfit(ENUM_ORDER_TYPE type, double entryPrice, double stopLoss, double atrValue)
{
   double riskDistance = MathAbs(entryPrice - stopLoss);
   double baseTP = 0;
   
   // Default risk:reward ratio
   double riskReward = InpBaseRiskReward;
   
   // Adjust risk:reward based on market regime
   if(InpRegimeFiltering) {
      switch(ExtCurrentRegime) {
         case TRENDING_UP:
            if(type == ORDER_TYPE_BUY) riskReward = InpBaseRiskReward * 1.5; // More aggressive TP in uptrend for buys
            break;
         case TRENDING_DOWN:
            if(type == ORDER_TYPE_SELL) riskReward = InpBaseRiskReward * 1.5; // More aggressive TP in downtrend for sells
            break;
         case RANGING_NARROW:
            riskReward = InpBaseRiskReward * 0.7; // Smaller targets in tight ranges
            break;
         case HIGH_VOLATILITY:
            riskReward = InpBaseRiskReward * 2.0; // Larger targets in volatile markets
            break;
      }
   }
   
   // Calculate base take profit using risk:reward ratio
   if(type == ORDER_TYPE_BUY) {
      baseTP = entryPrice + (riskDistance * riskReward);
   } else {
      baseTP = entryPrice - (riskDistance * riskReward);
   }
   
   // Check for SMC-based target levels if we have fair value gaps or liquidity grabs
   if(type == ORDER_TYPE_BUY) {
      // For buys, look for resistance levels or bearish FVGs
      double closestResistance = entryPrice + (riskDistance * 5); // Default far value
      
      // Check bearish fair value gaps as resistance
      for(int i=0; i<ExtFVGCount; i++) {
         if(!ExtFairValueGaps[i].bullish && ExtFairValueGaps[i].active) {
            double gapBottom = ExtFairValueGaps[i].low;
            if(gapBottom > entryPrice && gapBottom < closestResistance) {
               closestResistance = gapBottom;
            }
         }
      }
      
      // Adjust TP if we found a closer resistance level
      if(closestResistance < baseTP && closestResistance > entryPrice + atrValue) {
         baseTP = closestResistance - (5 * _Point); // Slightly below resistance
      }
   } else { // SELL order
      // For sells, look for support levels or bullish FVGs
      double closestSupport = entryPrice - (riskDistance * 5); // Default far value
      
      // Check bullish fair value gaps as support
      for(int i=0; i<ExtFVGCount; i++) {
         if(ExtFairValueGaps[i].bullish && ExtFairValueGaps[i].active) {
            double gapTop = ExtFairValueGaps[i].high;
            if(gapTop < entryPrice && gapTop > closestSupport) {
               closestSupport = gapTop;
            }
         }
      }
      
      // Adjust TP if we found a closer support level
      if(closestSupport > baseTP && closestSupport < entryPrice - atrValue) {
         baseTP = closestSupport + (5 * _Point); // Slightly above support
      }
   }
   
   return baseTP;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk management                  |
//+------------------------------------------------------------------+
double CalculateLot(double slDistance)
{
   // Calculate risk amount based on account balance
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   
   // Convert price distance to money risk
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pipValue = (tickValue * point) / tickSize;
   double pipDistance = MathRound(slDistance / point);
   
   // Avoid division by zero
   if(pipDistance == 0) pipDistance = 1;
   
   // Calculate lot size based on risk
   double lotSize = NormalizeDouble(risk / (pipDistance * pipValue), 2);
   
   // Check for min/max lot size and step
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Ensure lot size is within broker limits
   lotSize = MathFloor(lotSize / lotStep) * lotStep; // Adjust to lot step
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize)); // Ensure within limits
   
   // Reduce position size in high volatility or choppy markets
   if(InpEnableSMC && InpRegimeFiltering) {
      if(ExtCurrentRegime == HIGH_VOLATILITY || ExtCurrentRegime == CHOPPY) {
         lotSize *= 0.7; // Reduce risk in volatile conditions
         lotSize = NormalizeDouble(lotSize, 2);
      }
   }
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Enhanced trailing stop management with SMC concepts               |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   // Skip if advanced trailing isn't active or not enabled
   if(!ExtTrailingActive && !InpAdvancedTrailing) return;
   
   // Get ATR value and current prices
   double atr = ExtATR[0];
   ExtSymbolInfo.RefreshRates();
   
   // Get current position type and price
   ENUM_POSITION_TYPE posType = ExtPositionInfo.PositionType();
   double price = (posType == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
   double oldSL = ExtPositionInfo.StopLoss();
   double oldTP = ExtPositionInfo.TakeProfit();
   double newSL = oldSL;
   double entryPrice = ExtPositionInfo.PriceOpen();
   
   // Calculate standard trail stop based on ATR
   double stdTrailAmount = InpTrailingStop * atr;
   
   // Check if we're using SMC enhanced trailing
   if(InpEnableSMC && InpAdvancedTrailing) {
      // Get position profit in points
      double profitPoints = (posType == POSITION_TYPE_BUY) ? 
                           (price - entryPrice) / _Point : 
                           (entryPrice - price) / _Point;
                           
      // Only start trailing once position is in profit
      if(profitPoints > atr / _Point) {
         double trailMultiplier = InpTrailMultiplier;
         
         // Adjust trailing based on market regime
         if(InpRegimeFiltering) {
            switch(ExtCurrentRegime) {
               case TRENDING_UP:
                  if(posType == POSITION_TYPE_BUY) trailMultiplier *= 0.7; // Looser trail in trending markets
                  break;
               case TRENDING_DOWN:
                  if(posType == POSITION_TYPE_SELL) trailMultiplier *= 0.7; // Looser trail in trending markets
                  break;
               case CHOPPY:
               case HIGH_VOLATILITY:
                  trailMultiplier *= 1.3; // Tighter trail in choppy/volatile markets
                  break;
            }
         }
         
         // Use proper swing points for trailing if available
         if(ExtSwingCount > 0) {
            // For buys, look for closest swing low above entry but below price as potential trail level
            if(posType == POSITION_TYPE_BUY) {
               double bestTrailLevel = price - (stdTrailAmount * trailMultiplier); // Default trail level
               
               // Check if any swing lows make better trailing stops
               for(int i=0; i<ExtSwingCount; i++) {
                  double swingLevel = ExtSwingPoints[i].price;
                  if(swingLevel > entryPrice && swingLevel < price - (atr * 0.5)) {
                     if(swingLevel > bestTrailLevel) {
                        bestTrailLevel = swingLevel;
                     }
                  }
               }
               
               // Set new stop loss if it's better than current
               if(bestTrailLevel > oldSL) {
                  newSL = bestTrailLevel;
               }
            }
            // For sells, look for closest swing high below entry but above price
            else {
               double bestTrailLevel = price + (stdTrailAmount * trailMultiplier); // Default trail level
               
               // Check if any swing highs make better trailing stops
               for(int i=0; i<ExtSwingCount; i++) {
                  double swingLevel = ExtSwingPoints[i].price;
                  if(swingLevel < entryPrice && swingLevel > price + (atr * 0.5)) {
                     if(swingLevel < bestTrailLevel) {
                        bestTrailLevel = swingLevel;
                     }
                  }
               }
               
               // Set new stop loss if it's better than current
               if(bestTrailLevel < oldSL) {
                  newSL = bestTrailLevel;
               }
            }
         }
         else {
            // No suitable swing points, use standard ATR-based trail
            if(posType == POSITION_TYPE_BUY) {
               newSL = price - (stdTrailAmount * trailMultiplier);
               // Only modify if new SL is better
               if(newSL <= oldSL) newSL = oldSL;
            }
            else {
               newSL = price + (stdTrailAmount * trailMultiplier);
               // Only modify if new SL is better
               if(newSL >= oldSL) newSL = oldSL;
            }
         }
      }
   }
   else {
      // Standard trailing stop logic
      if(posType == POSITION_TYPE_BUY) {
         newSL = price - stdTrailAmount;
         if(newSL <= oldSL) return; // No update needed
      }
      else {
         newSL = price + stdTrailAmount;
         if(newSL >= oldSL) return; // No update needed
      }
   }
   
   // Only update if there's a meaningful change
   bool updateNeeded = false;
   
   if(posType == POSITION_TYPE_BUY && newSL > oldSL) {
      updateNeeded = true;
   }
   else if(posType == POSITION_TYPE_SELL && newSL < oldSL) {
      updateNeeded = true;
   }
   
   // Update stop loss if needed
   if(updateNeeded) {
      if(!ExtTrade.PositionModify(_Symbol, newSL, oldTP)) {
         Print("[ERROR] Trail stop modify failed: ", ExtTrade.ResultRetcodeDescription());
      }
      else {
         Print("[INFO] Trail stop updated to ", DoubleToString(newSL, _Digits),
               ", Profit points: ", DoubleToString((posType == POSITION_TYPE_BUY) ? 
                                 (price - entryPrice) / _Point : 
                                 (entryPrice - price) / _Point, 1));
      }
   }
}

void CheckPositionExpiration()
{
   if(InpDuration <= 0) return;
   datetime positionTime = (datetime)ExtPositionInfo.Time();
   if(TimeCurrent() - positionTime >= InpDuration * 60) {
      if(ExtTrade.PositionClose(_Symbol)) {
         Print("[INFO] Position closed due to duration expiration");
         Alert("[INFO] Position closed due to duration expiration");
      } else {
         Print("[ERROR] Failed to close expired position");
         Alert("[ERROR] Failed to close expired position");
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function - main trading logic                         |
//+------------------------------------------------------------------+
void OnTick()
{
   // Skip if emergency mode is active
   if(ExtEmergencyMode && ExtConsecutiveLosses >= InpMaxLosses) {
      if(InpDisplayInfo) Comment("Emergency mode active: ", ExtConsecutiveLosses, " consecutive losses");
      return;
   }
   
   // Refresh market data
   ExtSymbolInfo.Refresh();
   ExtSymbolInfo.RefreshRates();
   if(!IsTradeAllowed()) return;
   
   // Check trading conditions
   if(IsNewsTime()) return;
   if(!WithinTradingHours()) return;
   if(!SpreadIsAcceptable()) return;
   
   // Update indicators
   if(!RefreshIndicators()) return;
   
   // Update market regime detection and SMC structures on new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != lastBarTime) {
      lastBarTime = currentBarTime;
      
      // Update regime detection if enabled
      if(InpEnableSMC && InpRegimeFiltering) {
         ExtPrevRegime = ExtCurrentRegime;
         ExtCurrentRegime = DetectMarketRegime();
         
         if(ExtPrevRegime != ExtCurrentRegime && InpDisplayInfo) {
            Print("Market regime changed from ", RegimeToString(ExtPrevRegime), 
                  " to ", RegimeToString(ExtCurrentRegime));
         }
      }
      
      // Update SMC structures on new bar if enabled
      if(InpEnableSMC) {
         DetectLiquidityGrabs();
         DetectFairValueGaps();
         IdentifySwingPoints();
         
         // Display current structures info if requested
         if(InpDisplayInfo) {
            string info = StringFormat("SMC Structures: %d Liquidity Grabs, %d FVGs, %d Swing Points\n"
                                      "Current Regime: %s", 
                                      ExtGrabCount, ExtFVGCount, ExtSwingCount,
                                      RegimeToString(ExtCurrentRegime));
            Comment(info);
         }
      }
   }
   
   // Check for open positions first
   if(ExtPositionInfo.Select(_Symbol)) {
      // Check for position expiration
      CheckPositionExpiration();
      
      // Update trailing stop if we have an open position
      if(InpTrailingStop > 0) {
         ManageTrailingStop();
      }
      
      // Check for position close conditions if using SMC features
      if(InpEnableSMC) {
         ENUM_POSITION_TYPE posType = ExtPositionInfo.PositionType();
         bool shouldClose = false;
         
         // Check for regime change exit signals
         if(InpRegimeFiltering && ExtPrevRegime != ExtCurrentRegime) {
            // Exit long positions if regime changes to bearish or high volatility
            if(posType == POSITION_TYPE_BUY && 
               (ExtCurrentRegime == TRENDING_DOWN || ExtCurrentRegime == HIGH_VOLATILITY || ExtCurrentRegime == CHOPPY)) {
               shouldClose = true;
            }
            // Exit short positions if regime changes to bullish
            else if(posType == POSITION_TYPE_SELL && 
                    (ExtCurrentRegime == TRENDING_UP || ExtCurrentRegime == BREAKOUT)) {
               shouldClose = true;
            }
         }
         
         // Close position if conditions met
         if(shouldClose) {
            double closePrice = (posType == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
            if(ExtTrade.PositionClose(_Symbol)) {
               Print("[INFO] Position closed due to regime change from ", RegimeToString(ExtPrevRegime), 
                     " to ", RegimeToString(ExtCurrentRegime));
            }
            return; // Exit after closing position
         }
      }
      
      return; // Skip signal detection if we already have a position
   }
   
   // Check for trading signals
   int signal = TradeSignal();
   if(signal == 1) {
      ExecuteTrade(ORDER_TYPE_BUY, ExtATR[0]);
   } else if(signal == -1) {
      ExecuteTrade(ORDER_TYPE_SELL, ExtATR[0]);
   }
}