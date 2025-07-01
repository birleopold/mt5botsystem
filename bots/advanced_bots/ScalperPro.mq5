//+------------------------------------------------------------------+
//|                                                    ScalperPro.mq5|
//|         Advanced Risk-Managed Scalping EA for MetaTrader 5       |
//+------------------------------------------------------------------+
#property copyright   "Cascade AI"
#property version     "2.00" // Updated version with SMC features
#property strict

//--- Basic Inputs
input double   RiskPercent      = 1.0;      // % risk per trade
input double   MinLot           = 0.01;     // Minimum lot size
input double   MaxLot           = 10.0;     // Maximum lot size
input int      Slippage         = 3;        // Max slippage
input int      MagicNumber      = 20250426; // Unique EA ID
input int      StopLossPips     = 15;       // Initial Stop Loss (pips)
input int      TakeProfitPips   = 10;       // Initial Take Profit (pips)
input int      TrailingStart    = 5;        // Start trailing after X pips in profit
input int      TrailingStep     = 2;        // Trailing step (pips)
input int      RetraceBuffer    = 3;        // Retrace buffer for auto retrace (pips)

//--- SMC Enhancement Inputs
input bool     UseSmcFeatures   = true;     // Use Smart Money Concepts (SMC) features
input int      SwingLookback    = 20;       // Lookback bars for swing detection
input double   SmcFilterStrength = 5.0;     // Minimum SMC event strength for filtering (1-10)
input double   ExitSmcStrength  = 7.0;      // Minimum SMC event strength for early exit (1-10)
input bool     ShowVisualization = true;    // Show SMC events on chart

//--- Global Variables and Handles
int maHandle;
double maArray[];

//+------------------------------------------------------------------+
//| Smart Money Concepts (SMC) Structures                            |
//+------------------------------------------------------------------+
// Structure for swing points
struct SwingPoint {
   datetime time;      // Time of the swing point
   double   price;     // Price level of the swing point
   bool     isHigh;    // true for swing high, false for swing low
   int      strength;  // Strength/significance of the swing (1-10)
};

// Structure for Break of Structure (BOS) events
struct BosEvent {
   datetime time;      // Time of the BOS event
   double   price;     // Price at which BOS occurred
   bool     isBullish; // true for bullish BOS, false for bearish
   double   strength;  // Strength/significance of the break (1-10)
   int      swingIdx;  // Index of the broken swing point
};

// Structure for Change of Character (CHoCH) events
struct ChochEvent {
   datetime time;      // Time of the CHoCH event
   double   price;     // Price at which CHoCH occurred
   bool     isBullish; // true for bullish CHoCH, false for bearish
   double   strength;  // Strength/significance of the change (1-10)
   int      bosIdx;    // Index of the related BOS event
};

// Arrays to store SMC events
SwingPoint swingPoints[100]; // Store last 100 swing points
BosEvent bosEvents[50];      // Store last 50 BOS events
ChochEvent chochEvents[50];  // Store last 50 CHoCH events

// Counters for the arrays
int swingPointCount = 0;
int bosEventCount = 0;
int chochEventCount = 0;

//+------------------------------------------------------------------+
//| Calculate lot size based on balance and risk                     |
//+------------------------------------------------------------------+
double GetLotSize(double stopLossPips)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double lot = risk / ((stopLossPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT)) * contractSize / tickSize * tickValue);
   lot = MathMax(MinLot, MathMin(MaxLot, NormalizeDouble(lot, 2)));
   return lot;
}

//+------------------------------------------------------------------+
//| Entry logic with SMC enhancements for better scalping            |
//+------------------------------------------------------------------+
bool BuySignal()
{
   // Get price data
   double closePrice[1];
   if(CopyClose(_Symbol, _Period, 0, 1, closePrice) <= 0) return false;
   
   // Get basic MA data
   double maBuf[];
   ArraySetAsSeries(maBuf, true);
   if(CopyBuffer(maHandle, 0, 0, 3, maBuf) <= 0) return false;
   
   // Basic signal - price above EMA
   bool basicSignal = (closePrice[0] > maBuf[0]);
   
   // If SMC features aren't enabled, return basic signal
   if(!UseSmcFeatures) return basicSignal;
   
   // SMC-enhanced logic for scalpers
   datetime currentTime = TimeCurrent();
   datetime recentTime = currentTime - 10 * PeriodSeconds(_Period); // Last 10 bars
   
   // If we have a basic signal, check if SMC confirms
   if(basicSignal) {
      // Look for confirming bullish SMC events
      for(int i = 0; i < bosEventCount; i++) {
         if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime && bosEvents[i].strength >= SmcFilterStrength) {
            Print("[SMC] Enhanced BUY signal confirmed by bullish BOS");
            return true; // Strong confirmation
         }
      }
      
      for(int i = 0; i < chochEventCount; i++) {
         if(chochEvents[i].isBullish && chochEvents[i].time >= recentTime && chochEvents[i].strength >= SmcFilterStrength) {
            Print("[SMC] Enhanced BUY signal confirmed by bullish CHoCH");
            return true; // Even stronger confirmation
         }
      }
      
      // Check for opposing bearish SMC events
      double bearishStrength = 0;
      
      for(int i = 0; i < bosEventCount; i++) {
         if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
            bearishStrength += bosEvents[i].strength;
         }
      }
      
      for(int i = 0; i < chochEventCount; i++) {
         if(!chochEvents[i].isBullish && chochEvents[i].time >= recentTime) {
            bearishStrength += chochEvents[i].strength * 1.5; // CHoCH gets higher weight
         }
      }
      
      // Reject signal if opposing SMC events are strong
      if(bearishStrength > SmcFilterStrength * 1.5) {
         Print("[SMC] Rejecting BUY signal due to strong bearish structure");
         return false;
      }
      
      // If no strong SMC events either way, use basic signal
      return basicSignal;
   }
   else {
      // No basic signal, but check if SMC events are strong enough on their own
      for(int i = 0; i < chochEventCount; i++) {
         if(chochEvents[i].isBullish && chochEvents[i].time >= recentTime && chochEvents[i].strength >= 8.0) {
            Print("[SMC] Generating BUY signal based on very strong bullish CHoCH alone");
            return true; // Very strong CHoCH can generate signal without MA
         }
      }
   }
   
   return false;
}

bool SellSignal()
{
   // Get price data
   double closePrice[1];
   if(CopyClose(_Symbol, _Period, 0, 1, closePrice) <= 0) return false;
   
   // Get basic MA data
   double maBuf[];
   ArraySetAsSeries(maBuf, true);
   if(CopyBuffer(maHandle, 0, 0, 3, maBuf) <= 0) return false;
   
   // Basic signal - price below EMA
   bool basicSignal = (closePrice[0] < maBuf[0]);
   
   // If SMC features aren't enabled, return basic signal
   if(!UseSmcFeatures) return basicSignal;
   
   // SMC-enhanced logic for scalpers
   datetime currentTime = TimeCurrent();
   datetime recentTime = currentTime - 10 * PeriodSeconds(_Period); // Last 10 bars
   
   // If we have a basic signal, check if SMC confirms
   if(basicSignal) {
      // Look for confirming bearish SMC events
      for(int i = 0; i < bosEventCount; i++) {
         if(!bosEvents[i].isBullish && bosEvents[i].time >= recentTime && bosEvents[i].strength >= SmcFilterStrength) {
            Print("[SMC] Enhanced SELL signal confirmed by bearish BOS");
            return true; // Strong confirmation
         }
      }
      
      for(int i = 0; i < chochEventCount; i++) {
         if(!chochEvents[i].isBullish && chochEvents[i].time >= recentTime && chochEvents[i].strength >= SmcFilterStrength) {
            Print("[SMC] Enhanced SELL signal confirmed by bearish CHoCH");
            return true; // Even stronger confirmation
         }
      }
      
      // Check for opposing bullish SMC events
      double bullishStrength = 0;
      
      for(int i = 0; i < bosEventCount; i++) {
         if(bosEvents[i].isBullish && bosEvents[i].time >= recentTime) {
            bullishStrength += bosEvents[i].strength;
         }
      }
      
      for(int i = 0; i < chochEventCount; i++) {
         if(chochEvents[i].isBullish && chochEvents[i].time >= recentTime) {
            bullishStrength += chochEvents[i].strength * 1.5; // CHoCH gets higher weight
         }
      }
      
      // Reject signal if opposing SMC events are strong
      if(bullishStrength > SmcFilterStrength * 1.5) {
         Print("[SMC] Rejecting SELL signal due to strong bullish structure");
         return false;
      }
      
      // If no strong SMC events either way, use basic signal
      return basicSignal;
   }
   else {
      // No basic signal, but check if SMC events are strong enough on their own
      for(int i = 0; i < chochEventCount; i++) {
         if(!chochEvents[i].isBullish && chochEvents[i].time >= recentTime && chochEvents[i].strength >= 8.0) {
            Print("[SMC] Generating SELL signal based on very strong bearish CHoCH alone");
            return true; // Very strong CHoCH can generate signal without MA
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Place order with SL/TP                                           |
//+------------------------------------------------------------------+
void OpenTrade(int type)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? price - StopLossPips * _Point : price + StopLossPips * _Point;
   double tp = (type == ORDER_TYPE_BUY) ? price + TakeProfitPips * _Point : price - TakeProfitPips * _Point;
   double lot = GetLotSize(StopLossPips);
   
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   
   req.action = (ENUM_TRADE_REQUEST_ACTIONS)TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = (ENUM_ORDER_TYPE)type;
   req.price = price;
   req.sl = NormalizeDouble(sl, _Digits);
   req.tp = NormalizeDouble(tp, _Digits);
   req.deviation = Slippage;
   req.magic = MagicNumber;
   req.type_filling = ORDER_FILLING_IOC;
   
   bool result = OrderSend(req, res);
   if(result) {
      Print("[SMC] Trade executed successfully: ", EnumToString((ENUM_ORDER_TYPE)type), ", Lot: ", DoubleToString(lot, 2));
   } else {
      Print("[SMC] Trade execution failed. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Trailing stop and TP retrace management                          |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      int type = (int)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPips = (type == POSITION_TYPE_BUY) ? (price - openPrice)/_Point : (openPrice - price)/_Point;
      // Trailing stop
      if(profitPips > TrailingStart)
      {
         double newSL = (type == POSITION_TYPE_BUY) ? price - TrailingStep * _Point : price + TrailingStep * _Point;
         // Only move SL forward
         if((type == POSITION_TYPE_BUY && newSL > sl) || (type == POSITION_TYPE_SELL && newSL < sl))
         {
            MqlTradeRequest req;
            MqlTradeResult res;
            ZeroMemory(req);
            ZeroMemory(res);
            
            req.action = (ENUM_TRADE_REQUEST_ACTIONS)1; // TRADE_ACTION_SLTP is 1
            req.position = ticket;
            req.sl = NormalizeDouble(newSL, _Digits);
            req.tp = tp; // unchanged
            
            bool result = OrderSend(req, res);
            if(result) {
               Print("[INFO] Trailing stop updated");
            } else {
               Print("[ERROR] Failed to update trailing stop. Error: ", GetLastError());
            }
         }
      }
      // Auto retrace TP: if price keeps moving in favor, move TP further
      if(profitPips > TakeProfitPips + RetraceBuffer)
      {
         double newTP = (type == POSITION_TYPE_BUY) ? price + RetraceBuffer * _Point : price - RetraceBuffer * _Point;
         if((type == POSITION_TYPE_BUY && newTP > tp) || (type == POSITION_TYPE_SELL && newTP < tp))
         {
            MqlTradeRequest req;
            MqlTradeResult res;
            ZeroMemory(req);
            ZeroMemory(res);
            
            req.action = (ENUM_TRADE_REQUEST_ACTIONS)1; // TRADE_ACTION_SLTP is 1
            req.position = ticket;
            req.sl = sl; // unchanged
            req.tp = NormalizeDouble(newTP, _Digits);
            
            bool result = OrderSend(req, res);
            if(result) {
               Print("[INFO] Take profit updated");
            } else {
               Print("[ERROR] Failed to update take profit. Error: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Swing Points Function - SMC Enhancement                    |
//+------------------------------------------------------------------+
void DetectSwingPoints()
{
   if(!UseSmcFeatures) return;
   
   // Look back several bars to detect swing points
   const int lookback = SwingLookback;
   
   // Arrays for price data
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   // Get high and low prices
   if(CopyHigh(_Symbol, _Period, 0, lookback + 4, high) <= 0) return;
   if(CopyLow(_Symbol, _Period, 0, lookback + 4, low) <= 0) return;
   
   // Detect swing high
   for(int i = 2; i < lookback - 2; i++) {
      // Swing high condition: middle bar higher than surrounding bars
      if(high[i] > high[i-1] && high[i] > high[i-2] && 
         high[i] > high[i+1] && high[i] > high[i+2]) {
         
         // Check if we already have this swing point (avoid duplicates)
         bool isDuplicate = false;
         for(int j = 0; j < swingPointCount; j++) {
            if(MathAbs(swingPoints[j].price - high[i]) < 10 * _Point) {
               isDuplicate = true;
               break;
            }
         }
         
         if(!isDuplicate) {
            // Make space in array if needed
            if(swingPointCount >= ArraySize(swingPoints)) {
               // Shift array to remove oldest
               for(int j = 0; j < ArraySize(swingPoints) - 1; j++) {
                  swingPoints[j] = swingPoints[j+1];
               }
               swingPointCount--;
            }
            
            // Calculate strength (1-10 scale) based on surrounding bars
            double leftDelta = high[i] - MathMax(high[i-1], high[i-2]);
            double rightDelta = high[i] - MathMax(high[i+1], high[i+2]);
            int strength = (int)MathMin(10, MathMax(1, (leftDelta + rightDelta) / (20 * _Point)));
            
            // Add new swing high
            swingPoints[swingPointCount].time = iTime(_Symbol, _Period, i);
            swingPoints[swingPointCount].price = high[i];
            swingPoints[swingPointCount].isHigh = true;
            swingPoints[swingPointCount].strength = strength;
            swingPointCount++;
            
            if(ShowVisualization) {
               // Optional visualization code for chart
               string objName = "SwingHigh_" + IntegerToString((long)iTime(_Symbol, _Period, i));
               ObjectCreate(0, objName, OBJ_ARROW_DOWN, 0, iTime(_Symbol, _Period, i), high[i] + 15 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            }
         }
      }
      
      // Swing low condition: middle bar lower than surrounding bars
      if(low[i] < low[i-1] && low[i] < low[i-2] && 
         low[i] < low[i+1] && low[i] < low[i+2]) {
         
         // Check if we already have this swing point (avoid duplicates)
         bool isDuplicate = false;
         for(int j = 0; j < swingPointCount; j++) {
            if(MathAbs(swingPoints[j].price - low[i]) < 10 * _Point) {
               isDuplicate = true;
               break;
            }
         }
         
         if(!isDuplicate) {
            // Make space in array if needed
            if(swingPointCount >= ArraySize(swingPoints)) {
               // Shift array to remove oldest
               for(int j = 0; j < ArraySize(swingPoints) - 1; j++) {
                  swingPoints[j] = swingPoints[j+1];
               }
               swingPointCount--;
            }
            
            // Calculate strength (1-10 scale) based on surrounding bars
            double leftDelta = MathMin(low[i-1], low[i-2]) - low[i];
            double rightDelta = MathMin(low[i+1], low[i+2]) - low[i];
            int strength = (int)MathMin(10, MathMax(1, (leftDelta + rightDelta) / (20 * _Point)));
            
            // Add new swing low
            swingPoints[swingPointCount].time = iTime(_Symbol, _Period, i);
            swingPoints[swingPointCount].price = low[i];
            swingPoints[swingPointCount].isHigh = false;
            swingPoints[swingPointCount].strength = strength;
            swingPointCount++;
            
            if(ShowVisualization) {
               // Optional visualization code for chart
               string objName = "SwingLow_" + IntegerToString((long)iTime(_Symbol, _Period, i));
               ObjectCreate(0, objName, OBJ_ARROW_UP, 0, iTime(_Symbol, _Period, i), low[i] - 15 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrGreen);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Break of Structure (BOS) Function                         |
//+------------------------------------------------------------------+
void DetectBreakOfStructure()
{
   if(!UseSmcFeatures) return;
   if(swingPointCount < 3) return;
   
   // Get current price data
   double close = iClose(_Symbol, _Period, 1);
   datetime currentTime = iTime(_Symbol, _Period, 1);
   
   // Scalper-specific: Look for recent breaks that could lead to quick scalps
   for(int i = 0; i < swingPointCount; i++) {
      // For scalping, focus on very recent swing points (last 25 bars max)
      if(currentTime - swingPoints[i].time > 25 * PeriodSeconds(_Period)) continue;
      
      // Check for bullish BOS (break above a swing high)
      if(swingPoints[i].isHigh && close > swingPoints[i].price) {
         // Verify this is a new BOS
         bool isNewBOS = true;
         for(int j = 0; j < bosEventCount; j++) {
            if(bosEvents[j].swingIdx == i || MathAbs(bosEvents[j].price - swingPoints[i].price) < 5 * _Point) {
               isNewBOS = false;
               break;
            }
         }
         
         if(isNewBOS) {
            // Make space in array if needed
            if(bosEventCount >= ArraySize(bosEvents)) {
               // Shift array
               for(int j = 0; j < ArraySize(bosEvents) - 1; j++) {
                  bosEvents[j] = bosEvents[j+1];
               }
               bosEventCount--;
            }
            
            // Calculate break strength (key for scalping decisions)
            double breakDistance = close - swingPoints[i].price;
            double strength = MathMin(10.0, MathMax(1.0, breakDistance / (5 * _Point))); // Stronger for scalping
            
            // Add the BOS event
            bosEvents[bosEventCount].time = currentTime;
            bosEvents[bosEventCount].price = close;
            bosEvents[bosEventCount].isBullish = true;
            bosEvents[bosEventCount].strength = strength;
            bosEvents[bosEventCount].swingIdx = i;
            bosEventCount++;
            
            Print("[SMC] Bullish BOS detected at price ", close, " strength: ", DoubleToString(strength, 1));
            
            if(ShowVisualization) {
               // Visual marker for bullish BOS
               string objName = "BullBOS_" + IntegerToString((long)currentTime);
               ObjectCreate(0, objName, OBJ_ARROW, 0, currentTime, close - 20 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 233); // Up arrow
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrBlue);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            }
         }
      }
      
      // Check for bearish BOS (break below a swing low)
      if(!swingPoints[i].isHigh && close < swingPoints[i].price) {
         // Verify this is a new BOS
         bool isNewBOS = true;
         for(int j = 0; j < bosEventCount; j++) {
            if(bosEvents[j].swingIdx == i || MathAbs(bosEvents[j].price - swingPoints[i].price) < 5 * _Point) {
               isNewBOS = false;
               break;
            }
         }
         
         if(isNewBOS) {
            // Make space in array if needed
            if(bosEventCount >= ArraySize(bosEvents)) {
               // Shift array
               for(int j = 0; j < ArraySize(bosEvents) - 1; j++) {
                  bosEvents[j] = bosEvents[j+1];
               }
               bosEventCount--;
            }
            
            // Calculate break strength
            double breakDistance = swingPoints[i].price - close;
            double strength = MathMin(10.0, MathMax(1.0, breakDistance / (5 * _Point))); // Stronger for scalping
            
            // Add the BOS event
            bosEvents[bosEventCount].time = currentTime;
            bosEvents[bosEventCount].price = close;
            bosEvents[bosEventCount].isBullish = false;
            bosEvents[bosEventCount].strength = strength;
            bosEvents[bosEventCount].swingIdx = i;
            bosEventCount++;
            
            Print("[SMC] Bearish BOS detected at price ", close, " strength: ", DoubleToString(strength, 1));
            
            if(ShowVisualization) {
               // Visual marker for bearish BOS
               string objName = "BearBOS_" + IntegerToString((long)currentTime);
               ObjectCreate(0, objName, OBJ_ARROW, 0, currentTime, close + 20 * _Point);
               ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 234); // Down arrow
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrMagenta);
               ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Change of Character (CHoCH) Function                      |
//+------------------------------------------------------------------+
void DetectChangeOfCharacter()
{
   if(!UseSmcFeatures) return;
   if(bosEventCount < 1 || swingPointCount < 3) return;
   
   double close = iClose(_Symbol, _Period, 1);
   datetime currentTime = iTime(_Symbol, _Period, 1);
   
   // For scalping: Focus on very recent BOS events
   for(int i = 0; i < bosEventCount; i++) {
      // Only consider very recent BOS events (within last 15 bars)
      if(currentTime - bosEvents[i].time > 15 * PeriodSeconds(_Period)) continue;
      
      // For bullish BOS, look for a higher low (CHoCH)
      if(bosEvents[i].isBullish) {
         for(int j = 0; j < swingPointCount; j++) {
            if(!swingPoints[j].isHigh && // It's a low
               swingPoints[j].time > bosEvents[i].time && // Occurred after BOS
               close > swingPoints[j].price && // Price now above the swing low
               swingPoints[j].price > swingPoints[bosEvents[i].swingIdx].price) { // Higher low
               
               // Check if this is a new CHoCH
               bool isNewCHoCH = true;
               for(int k = 0; k < chochEventCount; k++) {
                  if(chochEvents[k].bosIdx == i) {
                     isNewCHoCH = false;
                     break;
                  }
               }
               
               if(isNewCHoCH) {
                  // Make space in array if needed
                  if(chochEventCount >= ArraySize(chochEvents)) {
                     for(int k = 0; k < ArraySize(chochEvents) - 1; k++) {
                        chochEvents[k] = chochEvents[k+1];
                     }
                     chochEventCount--;
                  }
                  
                  // Calculate strength - for scalping, we want stronger values
                  double chochStrength = MathMin(10.0, bosEvents[i].strength * 1.2);
                  
                  // Add the CHoCH event
                  chochEvents[chochEventCount].time = currentTime;
                  chochEvents[chochEventCount].price = close;
                  chochEvents[chochEventCount].isBullish = true;
                  chochEvents[chochEventCount].strength = chochStrength;
                  chochEvents[chochEventCount].bosIdx = i;
                  chochEventCount++;
                  
                  Print("[SMC] Bullish CHoCH detected at price ", close, " strength: ", DoubleToString(chochStrength, 1));
                  
                  if(ShowVisualization) {
                     string objName = "BullCHoCH_" + IntegerToString((long)currentTime);
                     ObjectCreate(0, objName, OBJ_TEXT, 0, currentTime, close - 25 * _Point);
                     ObjectSetString(0, objName, OBJPROP_TEXT, "CHoCH");
                     ObjectSetInteger(0, objName, OBJPROP_COLOR, clrBlue);
                     ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
                  }
                  break;
               }
            }
         }
      }
      
      // For bearish BOS, look for a lower high (CHoCH)
      if(!bosEvents[i].isBullish) {
         for(int j = 0; j < swingPointCount; j++) {
            if(swingPoints[j].isHigh && // It's a high
               swingPoints[j].time > bosEvents[i].time && // Occurred after BOS
               close < swingPoints[j].price && // Price now below the swing high
               swingPoints[j].price < swingPoints[bosEvents[i].swingIdx].price) { // Lower high
               
               // Check if this is a new CHoCH
               bool isNewCHoCH = true;
               for(int k = 0; k < chochEventCount; k++) {
                  if(chochEvents[k].bosIdx == i) {
                     isNewCHoCH = false;
                     break;
                  }
               }
               
               if(isNewCHoCH) {
                  // Make space in array if needed
                  if(chochEventCount >= ArraySize(chochEvents)) {
                     for(int k = 0; k < ArraySize(chochEvents) - 1; k++) {
                        chochEvents[k] = chochEvents[k+1];
                     }
                     chochEventCount--;
                  }
                  
                  // Calculate strength
                  double chochStrength = MathMin(10.0, bosEvents[i].strength * 1.2);
                  
                  // Add the CHoCH event
                  chochEvents[chochEventCount].time = currentTime;
                  chochEvents[chochEventCount].price = close;
                  chochEvents[chochEventCount].isBullish = false;
                  chochEvents[chochEventCount].strength = chochStrength;
                  chochEvents[chochEventCount].bosIdx = i;
                  chochEventCount++;
                  
                  Print("[SMC] Bearish CHoCH detected at price ", close, " strength: ", DoubleToString(chochStrength, 1));
                  
                  if(ShowVisualization) {
                     string objName = "BearCHoCH_" + IntegerToString((long)currentTime);
                     ObjectCreate(0, objName, OBJ_TEXT, 0, currentTime, close + 25 * _Point);
                     ObjectSetString(0, objName, OBJPROP_TEXT, "CHoCH");
                     ObjectSetInteger(0, objName, OBJPROP_COLOR, clrMagenta);
                     ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
                  }
                  break;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("ScalperPro EA with SMC features initialized.");
   // Initialize MA indicator handle for basic signals
   maHandle = iMA(_Symbol, _Period, 10, 0, MODE_EMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE) {
      Print("Error creating MA indicator handle");
      return INIT_FAILED;
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up MA indicator handle
   if(maHandle != INVALID_HANDLE) IndicatorRelease(maHandle);
   
   // Clean up visual objects if they exist
   if(ShowVisualization) {
      ObjectsDeleteAll(0, "SwingHigh_");
      ObjectsDeleteAll(0, "SwingLow_");
      ObjectsDeleteAll(0, "BullBOS_");
      ObjectsDeleteAll(0, "BearBOS_");
      ObjectsDeleteAll(0, "BullCHoCH_");
      ObjectsDeleteAll(0, "BearCHoCH_");
   }
}

//+------------------------------------------------------------------+
//| Check for early exit conditions based on SMC events               |
//+------------------------------------------------------------------+
void CheckSmcExitConditions()
{
   if(!UseSmcFeatures) return;
   
   // Check for opposing SMC events that might warrant an early exit
   bool shouldExit = false;
   string exitReason = "";
   datetime recentTime = TimeCurrent() - 5 * PeriodSeconds(_Period); // Last 5 bars
   
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      int type = (int)PositionGetInteger(POSITION_TYPE);
      
      // For BUY positions, check for strong bearish signals
      if(type == POSITION_TYPE_BUY) {
         // Check for bearish BOS with significant strength
         for(int j=0; j<bosEventCount; j++) {
            if(!bosEvents[j].isBullish && bosEvents[j].time >= recentTime && bosEvents[j].strength >= ExitSmcStrength) {
               shouldExit = true;
               exitReason = "Strong bearish BOS";
               break;
            }
         }
         
         // Check for bearish CHoCH - even more significant
         if(!shouldExit) {
            for(int j=0; j<chochEventCount; j++) {
               if(!chochEvents[j].isBullish && chochEvents[j].time >= recentTime && chochEvents[j].strength >= ExitSmcStrength * 0.8) {
                  shouldExit = true;
                  exitReason = "Bearish CHoCH";
                  break;
               }
            }
         }
      }
      // For SELL positions, check for strong bullish signals
      else if(type == POSITION_TYPE_SELL) {
         // Check for bullish BOS with significant strength
         for(int j=0; j<bosEventCount; j++) {
            if(bosEvents[j].isBullish && bosEvents[j].time >= recentTime && bosEvents[j].strength >= ExitSmcStrength) {
               shouldExit = true;
               exitReason = "Strong bullish BOS";
               break;
            }
         }
         
         // Check for bullish CHoCH - even more significant
         if(!shouldExit) {
            for(int j=0; j<chochEventCount; j++) {
               if(chochEvents[j].isBullish && chochEvents[j].time >= recentTime && chochEvents[j].strength >= ExitSmcStrength * 0.8) {
                  shouldExit = true;
                  exitReason = "Bullish CHoCH";
                  break;
               }
            }
         }
      }
      
      // Execute early exit if conditions are met
      if(shouldExit) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         MqlTradeRequest req;
         MqlTradeResult res;
         ZeroMemory(req);
         ZeroMemory(res);
         req.action = (ENUM_TRADE_REQUEST_ACTIONS)TRADE_ACTION_DEAL;
         req.position = ticket;
         req.symbol = _Symbol;
         req.volume = PositionGetDouble(POSITION_VOLUME);
         req.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         req.deviation = Slippage;
         req.magic = MagicNumber;
         
         bool result = OrderSend(req, res);
         if(result) {
            Print("[SMC] Early exit: ", exitReason, ". Profit: ", DoubleToString(profit, 2));
         } else {
            Print("[SMC] Failed to execute early exit. Error: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Enhanced trailing stop with SMC considerations                    |
//+------------------------------------------------------------------+
void ManagePositionsWithSmc()
{
   if(!UseSmcFeatures) {
      ManagePositions(); // Use standard position management
      return;
   }
   
   datetime recentTime = TimeCurrent() - 5 * PeriodSeconds(_Period);
   
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      int type = (int)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPips = (type == POSITION_TYPE_BUY) ? (price - openPrice)/_Point : (openPrice - price)/_Point;
      
      // Adjust trailing parameters based on SMC events
      int trailingStart = TrailingStart;
      int trailingStep = TrailingStep;
      int retraceBufferAdjusted = RetraceBuffer;
      
      // For BUY positions
      if(type == POSITION_TYPE_BUY) {
         bool hasConfirmingBullish = false;
         
         // Look for confirming bullish SMC events
         for(int j=0; j<bosEventCount; j++) {
            if(bosEvents[j].isBullish && bosEvents[j].time >= recentTime && bosEvents[j].strength >= SmcFilterStrength) {
               hasConfirmingBullish = true;
               // If we have confirming bullish structure, we can be more aggressive with trail
               trailingStart = (int)MathMax(1, TrailingStart * 0.7); // Start trailing earlier
               trailingStep = (int)MathMax(1, TrailingStep * 0.8);   // Tighter trailing
               break;
            }
         }
         
         // CHoCH is an even stronger confirmation
         for(int j=0; j<chochEventCount; j++) {
            if(chochEvents[j].isBullish && chochEvents[j].time >= recentTime && chochEvents[j].strength >= SmcFilterStrength) {
               hasConfirmingBullish = true;
               // If we have confirming bullish CHoCH, be very aggressive with trail
               trailingStart = (int)MathMax(1, TrailingStart * 0.5); // Start trailing much earlier
               trailingStep = (int)MathMax(1, TrailingStep * 0.6);   // Much tighter trailing
               retraceBufferAdjusted = (int)MathMax(1, RetraceBuffer * 0.7); // More aggressive TP adjustment
               break;
            }
         }
      }
      // For SELL positions
      else if(type == POSITION_TYPE_SELL) {
         bool hasConfirmingBearish = false;
         
         // Look for confirming bearish SMC events
         for(int j=0; j<bosEventCount; j++) {
            if(!bosEvents[j].isBullish && bosEvents[j].time >= recentTime && bosEvents[j].strength >= SmcFilterStrength) {
               hasConfirmingBearish = true;
               // If we have confirming bearish structure, we can be more aggressive with trail
               trailingStart = (int)MathMax(1, TrailingStart * 0.7); // Start trailing earlier
               trailingStep = (int)MathMax(1, TrailingStep * 0.8);   // Tighter trailing
               break;
            }
         }
         
         // CHoCH is an even stronger confirmation
         for(int j=0; j<chochEventCount; j++) {
            if(!chochEvents[j].isBullish && chochEvents[j].time >= recentTime && chochEvents[j].strength >= SmcFilterStrength) {
               hasConfirmingBearish = true;
               // If we have confirming bearish CHoCH, be very aggressive with trail
               trailingStart = (int)MathMax(1, TrailingStart * 0.5); // Start trailing much earlier
               trailingStep = (int)MathMax(1, TrailingStep * 0.6);   // Much tighter trailing
               retraceBufferAdjusted = (int)MathMax(1, RetraceBuffer * 0.7); // More aggressive TP adjustment
               break;
            }
         }
      }
      
      // Trailing stop with SMC-adjusted parameters
      if(profitPips > trailingStart)
      {
         double newSL = (type == POSITION_TYPE_BUY) ? price - trailingStep * _Point : price + trailingStep * _Point;
         // Only move SL forward
         if((type == POSITION_TYPE_BUY && newSL > sl) || (type == POSITION_TYPE_SELL && newSL < sl))
         {
            MqlTradeRequest req;
            MqlTradeResult res;
            ZeroMemory(req);
            ZeroMemory(res);
            
            req.action = (ENUM_TRADE_REQUEST_ACTIONS)1; // TRADE_ACTION_SLTP is 1
            req.position = ticket;
            req.sl = NormalizeDouble(newSL, _Digits);
            req.tp = tp; // unchanged
            
            bool result = OrderSend(req, res);
            if(result) {
               Print("[SMC] Trailing stop adjusted with SMC factors");
            } else {
               Print("[SMC] Failed to adjust trailing stop. Error: ", GetLastError());
            }
         }
      }
      
      // Auto retrace TP with SMC-adjusted parameters
      if(profitPips > TakeProfitPips + retraceBufferAdjusted)
      {
         double newTP = (type == POSITION_TYPE_BUY) ? price + retraceBufferAdjusted * _Point : price - retraceBufferAdjusted * _Point;
         if((type == POSITION_TYPE_BUY && newTP > tp) || (type == POSITION_TYPE_SELL && newTP < tp))
         {
            MqlTradeRequest req;
            MqlTradeResult res;
            ZeroMemory(req);
            ZeroMemory(res);
            
            req.action = (ENUM_TRADE_REQUEST_ACTIONS)1; // TRADE_ACTION_SLTP is 1
            req.position = ticket;
            req.sl = sl; // unchanged
            req.tp = NormalizeDouble(newTP, _Digits);
            
            bool result = OrderSend(req, res);
            if(result) {
               Print("[SMC] Take profit adjusted with SMC factors");
            } else {
               Print("[SMC] Failed to adjust take profit. Error: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Process only on new bars for SMC detection
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, _Period, 0);
   bool newBar = (lastBar != currentBar);
   
   if(newBar) {
      lastBar = currentBar;
      
      // Run SMC detection on new bars
      if(UseSmcFeatures) {
         DetectSwingPoints();
         DetectBreakOfStructure();
         DetectChangeOfCharacter();
      }
   }
   
   // Use either standard or SMC-enhanced position management
   if(UseSmcFeatures) {
      ManagePositionsWithSmc();
      CheckSmcExitConditions();
   } else {
      ManagePositions();
   }
   
   // Only one trade at a time per direction
   bool hasBuy = false, hasSell = false;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY) hasBuy = true;
      if(posType == POSITION_TYPE_SELL) hasSell = true;
   }
   
   // Check for entry signals and execute trades
   if(!hasBuy && BuySignal())
      OpenTrade(ORDER_TYPE_BUY);
   if(!hasSell && SellSignal())
      OpenTrade(ORDER_TYPE_SELL);
}
//+------------------------------------------------------------------+
