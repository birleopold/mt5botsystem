//+------------------------------------------------------------------+
//|                                               TestSymbolInfo.mq5 |
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
   // Test Symbol() function
   string symbol = Symbol();
   Print("Current symbol: ", symbol);
   
   // Test SymbolInfoDouble with direct return overload
   double stopLevel1 = SymbolInfoDouble(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   Print("Stop level (direct): ", stopLevel1, ", Error: ", GetLastError());
   
   // Test SymbolInfoDouble with reference parameter overload
   double stopLevel2 = 0.0;
   bool success = SymbolInfoDouble(symbol, SYMBOL_TRADE_STOPS_LEVEL, stopLevel2);
   Print("Stop level (reference): ", stopLevel2, ", Success: ", success, ", Error: ", GetLastError());
   
   // Display results
   Print("Test completed successfully");
}
//+------------------------------------------------------------------+
