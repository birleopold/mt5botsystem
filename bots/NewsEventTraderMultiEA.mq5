//+------------------------------------------------------------------+
//|                NewsEventTraderMultiEA.mq5                        |
//|                              AI Cascade                          |
//|       Multi-Symbol News Trading with Trailing Stops              |
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
// [Symbol Parameters]
input string   InpSymbolsList  = "EURUSD,GBPUSD,USDJPY";  // Comma-separated symbols to trade
input int      InpMaxPositions = 3;                       // Maximum concurrent positions

// [News Parameters]
input string   InpNewsFile      = "C:/MT5Signals/news.csv";  // Path to news CSV file
input int      InpNewsWindow    = 15;                        // Minutes before/after news to trade
input string   InpImpactLevel   = "high";                    // Minimum impact level to trade

// [Trade Parameters]
input uint     InpSlippage      = 3;                         // Slippage in points
input uint     InpDuration      = 1440;                      // Position duration in minutes
input double   InpATRMultiplier = 2.0;                       // ATR multiplier for stops
input double   InpTrailingATR   = 1.5;                       // Trailing stop ATR multiple
input int      InpATRPeriod     = 14;                        // ATR period

// [Money Management]
input double   InpRiskPerTrade  = 1.0;                       // Risk % per trade

// [Expert ID]
input long     InpMagicNumber   = 960001;                    // Unique EA identifier

//--- Global Variables
string   ExtSymbols[];
int      ExtATRHandles[];
int      ExtSignal        = NO_NEWS;
string   ExtSignalInfo    = "";
bool     ExtNewBar        = false;
datetime ExtLastTrailTime = 0;

//--- Indicator Buffers
double   ExtATR[];

//--- Service Objects
CTrade        ExtTrade;
CSymbolInfo   ExtSymbolInfo;
CPositionInfo ExtPositionInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Split symbols list
   StringSplit(InpSymbolsList, ',', ExtSymbols);
   
   //--- Parameter validation
   if(ArraySize(ExtSymbols) == 0)
     {
      Print("[ERROR] No symbols specified");
      return INIT_FAILED;
     }
   if(InpRiskPerTrade <= 0 || InpRiskPerTrade > 100)
     {
      Print("[ERROR] RiskPerTrade must be between 0 and 100");
      return INIT_FAILED;
     }
   if(InpATRMultiplier <= 0 || InpTrailingATR <= 0)
     {
      Print("[ERROR] ATR multipliers must be positive");
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
   
   //--- Initialize ATR handles array
   ArrayResize(ExtATRHandles, ArraySize(ExtSymbols));
   ArrayInitialize(ExtATRHandles, INVALID_HANDLE);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   for(int i=0; i<ArraySize(ExtATRHandles); i++)
      if(ExtATRHandles[i] != INVALID_HANDLE)
         IndicatorRelease(ExtATRHandles[i]);
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

   //--- Process all symbols
   for(int i=0; i<ArraySize(ExtSymbols); i++)
     {
      string symbol = ExtSymbols[i];
      
      //--- Initialize ATR handle if needed
      if(ExtATRHandles[i] == INVALID_HANDLE)
         ExtATRHandles[i] = iATR(symbol, _Period, InpATRPeriod);
      
      //--- Check trading conditions
      ProcessSymbol(symbol, i);
     }
     
   //--- Update trailing stops (once per minute)
   if(TimeCurrent() - ExtLastTrailTime >= 60)
     {
      UpdateTrailingStops();
      ExtLastTrailTime = TimeCurrent();
     }
}

//+------------------------------------------------------------------+
//| Process trading for a single symbol                              |
//+------------------------------------------------------------------+
void ProcessSymbol(string symbol, int idx)
{
   //--- Refresh indicator data
   if(!RefreshIndicators(symbol, idx))
      return;
      
   //--- Check if we're in a news window
   if(IsNewsWindow(symbol))
     {
      //--- Check for existing position
      if(!ExtPositionInfo.Select(symbol))
        {
         //--- Check max positions
         if(CountPositions() < InpMaxPositions)
           {
            ExtSignal = NEWS_BUY;
            ExtSignalInfo = "High Impact News Trade: " + symbol;
            ExecuteTrade(symbol, ORDER_TYPE_BUY, ExtATR[1]);
           }
        }
     }
}

//+------------------------------------------------------------------+
//| Refresh indicator data for a symbol                              |
//+------------------------------------------------------------------+
bool RefreshIndicators(string symbol, int idx)
{
   //--- Refresh ATR
   if(CopyBuffer(ExtATRHandles[idx], 0, 0, 2, ExtATR) <= 0)
     {
      Print("[ERROR] Failed to copy ATR buffer for ", symbol);
      return false;
     }
     
   return true;
}

//+------------------------------------------------------------------+
//| Check for relevant news events                                   |
//+------------------------------------------------------------------+
bool IsNewsWindow(string symbol)
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
      if(s == symbol && MathAbs(newsTime - now) <= InpNewsWindow * 60 && impact == InpImpactLevel)
        {
         result = true;
         break;
        }
     }
     
   FileClose(fh);
   return result;
}

//+------------------------------------------------------------------+
//| Execute trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, ENUM_ORDER_TYPE type, double atrValue)
{
   if(!ExtSymbolInfo.Name(symbol))
     {
      Print("[ERROR] Failed to initialize symbol info for ", symbol);
      return;
     }
     
   ExtSymbolInfo.RefreshRates();
   
   double price = (type == ORDER_TYPE_BUY) ? ExtSymbolInfo.Ask() : ExtSymbolInfo.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? price - InpATRMultiplier * atrValue : price + InpATRMultiplier * atrValue;
   double lot = CalculateLot(symbol, atrValue);
   
   if(!ExtTrade.PositionOpen(symbol, type, lot, price, sl, 0, ExtSignalInfo))
     {
      Print("[ERROR] Trade failed for ", symbol, ": ", ExtTrade.ResultRetcodeDescription());
     }
   else
     {
      Print("[SUCCESS] Trade executed for ", symbol, ": ", EnumToString(type), " ", lot, " lots");
     }
}

//+------------------------------------------------------------------+
//| Helper: Find index of a symbol in ExtSymbols                    |
//+------------------------------------------------------------------+
int FindSymbolIndex(string symbol)
{
   for(int i=0; i<ArraySize(ExtSymbols); i++)
      if(ExtSymbols[i] == symbol)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Update trailing stops for all positions                          |
//+------------------------------------------------------------------+
void UpdateTrailingStops()
{
   for(int i=0; i<PositionsTotal(); i++)
     {
      if(PositionGetSymbol(i) == "") continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      int idx = FindSymbolIndex(symbol);
      if(idx == -1) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         if(ExtATRHandles[idx] != INVALID_HANDLE)
           {
            double atr[];
            if(CopyBuffer(ExtATRHandles[idx], 0, 0, 1, atr) > 0)
              {
               double newSl = 0;
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                 {
                  newSl = PositionGetDouble(POSITION_PRICE_OPEN) + (PositionGetDouble(POSITION_SL) - PositionGetDouble(POSITION_PRICE_OPEN))/2;
                  newSl = MathMax(newSl, PositionGetDouble(POSITION_PRICE_CURRENT) - InpTrailingATR * atr[0]);
                 }
               else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                 {
                  newSl = PositionGetDouble(POSITION_PRICE_OPEN) - (PositionGetDouble(POSITION_PRICE_OPEN) - PositionGetDouble(POSITION_SL))/2;
                  newSl = MathMin(newSl, PositionGetDouble(POSITION_PRICE_CURRENT) + InpTrailingATR * atr[0]);
                 }
               
               if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSl > PositionGetDouble(POSITION_SL)) ||
                  (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && newSl < PositionGetDouble(POSITION_SL)))
                 {
                  if(!ExtTrade.PositionModify(PositionGetInteger(POSITION_TICKET), newSl, 0))
                     Print("[ERROR] Failed to modify trailing stop for ", symbol);
                 }
              }
           }
        }
     }
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculateLot(string symbol, double atrValue)
{
   if(!ExtSymbolInfo.Name(symbol))
     {
      Print("[ERROR] Failed to initialize symbol info for lot calculation");
      return 0;
     }
     
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   double lot = risk / (atrValue * 10 * ExtSymbolInfo.Point());
   lot = MathMax(lot, ExtSymbolInfo.LotsMin());
   lot = MathMin(lot, ExtSymbolInfo.LotsMax());
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Count current positions                                          |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i=0; i<PositionsTotal(); i++)
      if(PositionGetSymbol(i) != "" && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         count++;
   return count;
}