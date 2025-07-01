//+------------------------------------------------------------------+
//|                     NewsEventTraderEA.mq5                        |
//|                              AI Cascade                          |
//|                News-Based Trading Strategy                       |
//+------------------------------------------------------------------+
#property copyright "AI Cascade"
#property link      ""
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Signal Constants
#define NEWS_BUY      1
#define NO_NEWS       0
#define NEWS_SELL    -1

//--- Input Parameters
// [News Parameters]
input string   InpNewsFile      = "C:/MT5Signals/news.csv";  // Path to news CSV file
input int      InpNewsWindow    = 15;                        // Minutes before/after news to trade (window size)
input string   InpImpactLevel   = "high";                    // Minimum impact level to trade (high/medium/low)

// [Trade Parameters]
input uint     InpSlippage      = 3;                         // Slippage in points
input uint     InpDuration      = 1440;                      // Position duration in minutes
input double   InpATRMultiplier = 2.0;                       // ATR multiplier for stops
input int      InpATRPeriod     = 14;                        // ATR period

// [Money Management]
input double   InpRiskPerTrade  = 1.0;                       // Risk % per trade

// [Expert ID]
input long     InpMagicNumber   = 950001;                    // Unique EA identifier

//--- Global Variables
int    ExtATRHandle     = INVALID_HANDLE;
int    ExtSignal        = NO_NEWS;
string ExtSignalInfo    = "";
bool   ExtNewBar        = false;

//--- Indicator Buffers
double ExtATR[];

//--- Service Objects
CTrade       ExtTrade;
CSymbolInfo  ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parameter validation
   if(InpRiskPerTrade <= 0 || InpRiskPerTrade > 100)
     {
      Print("[ERROR] RiskPerTrade must be between 0 and 100");
      return INIT_FAILED;
     }
   if(InpATRMultiplier <= 0)
     {
      Print("[ERROR] ATRMultiplier must be positive");
      return INIT_FAILED;
     }
   if(InpNewsWindow <= 0)
     {
      Print("[ERROR] NewsWindow must be positive");
      return INIT_FAILED;
     }

   //--- Initialize trading objects
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippage);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   
   if(!ExtSymbolInfo.Name(_Symbol))
     {
      Print("Failed to initialize symbol info");
      return INIT_FAILED;
     }

   //--- Initialize indicators
   ExtATRHandle = iATR(_Symbol, _Period, InpATRPeriod);
   
   if(ExtATRHandle == INVALID_HANDLE)
     {
      Print("Indicator initialization failed");
      return INIT_FAILED;
     }
     
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(ExtATRHandle != INVALID_HANDLE)
      IndicatorRelease(ExtATRHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBarTime = 0;
   datetime currentTime = iTime(_Symbol, _Period, 0);
   
   //--- Check for new bar
   if(lastBarTime == currentTime)
      return;
   lastBarTime = currentTime;
   ExtNewBar = true;

   //--- Refresh indicator data
   if(!RefreshIndicators())
      return;
      
   //--- Check trading conditions
   CheckTradingConditions();
}

//+------------------------------------------------------------------+
//| Refresh indicator data                                           |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   //--- Refresh ATR
   if(CopyBuffer(ExtATRHandle, 0, 0, 2, ExtATR) <= 0)
     {
      Print("[ERROR] Failed to copy ATR buffer");
      return false;
     }
     
   return true;
}

//+------------------------------------------------------------------+
//| Check for relevant news events                                   |
//+------------------------------------------------------------------+
bool IsNewsWindow()
{
   int fh = FileOpen(InpNewsFile, FILE_READ|FILE_CSV|FILE_ANSI);
   if(fh == INVALID_HANDLE)
     {
      Print("[ERROR] Failed to open news file: ", InpNewsFile);
      return false;
     }
     
   bool result = false;
   datetime now = TimeCurrent();
   
   while(!FileIsEnding(fh))
     {
      string dt = FileReadString(fh);
      string s = FileReadString(fh);
      string impact = FileReadString(fh);
      
      if(StringLen(dt) == 0 || StringLen(s) == 0 || StringLen(impact) == 0)
         continue;
         
      datetime newsTime = StringToTime(dt);
      if(s == _Symbol && MathAbs(newsTime - now) <= InpNewsWindow * 60 && impact == InpImpactLevel)
        {
         result = true;
         break;
        }
     }
     
   FileClose(fh);
   return result;
}

//+------------------------------------------------------------------+
//| Check trading conditions                                         |
//+------------------------------------------------------------------+
void CheckTradingConditions()
{
   //--- Check for existing positions
   if(ExtPositionInfo.Select(_Symbol))
     {
      Print("[INFO] Existing position detected. No new trades.");
      CheckPositionExpiration();
      return;
     }
   
   //--- Check if we're in a news window
   if(IsNewsWindow())
     {
      ExtSignal = NEWS_BUY;
      ExtSignalInfo = "High Impact News Trade";
      ExecuteTrade(ORDER_TYPE_BUY, ExtATR[1]);
     }
   else
     {
      ExtSignal = NO_NEWS;
      ExtSignalInfo = "No relevant news";
     }
}

//+------------------------------------------------------------------+
//| Execute trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   ExtSymbolInfo.RefreshRates();
   
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? price - InpATRMultiplier * atrValue : price + InpATRMultiplier * atrValue;
   double lot = CalculateLot(atrValue);
   
   if(!ExtTrade.PositionOpen(_Symbol, type, lot, price, sl, 0, ExtSignalInfo))
     {
      Print("[ERROR] Trade failed: ", ExtTrade.ResultRetcodeDescription());
     }
   else
     {
      Print("[SUCCESS] Trade executed: ", EnumToString(type), " ", lot, " lots");
     }
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculateLot(double atrValue)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   double lot = risk / (atrValue * 10 * _Point);
   lot = MathMax(lot, ExtSymbolInfo.LotsMin());
   lot = MathMin(lot, ExtSymbolInfo.LotsMax());
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Check position expiration                                        |
//+------------------------------------------------------------------+
void CheckPositionExpiration()
{
   if(InpDuration <= 0) return;
   
   datetime positionTime = (datetime)ExtPositionInfo.Time();
   if(TimeCurrent() - positionTime >= InpDuration * 60)
     {
      if(ExtTrade.PositionClose(_Symbol))
         Print("[INFO] Position closed due to duration expiration");
      else
         Print("[ERROR] Failed to close expired position");
     }
}