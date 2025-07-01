//+------------------------------------------------------------------+
//|                                                 TestSimple.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   // Test reference syntax
   double stoplevel = 0.0;
   bool success = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stoplevel);
   
   Print("Success: ", success);
   Print("Stop level: ", stoplevel);
   Print("Last error: ", GetLastError());
   
   // Test alternative (debugging if original doesn't work)
   double sl = 0.0;
   bool ok = false;
   
   // Try with SYMBOL_TRADE_STOPS_LEVEL 
   ok = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, sl);
   Print("SYMBOL_TRADE_STOPS_LEVEL success: ", ok, ", value: ", sl);
   
   // Try different enum
   ok = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE, sl);
   Print("SYMBOL_TRADE_TICK_SIZE success: ", ok, ", value: ", sl);
}
//+------------------------------------------------------------------+
