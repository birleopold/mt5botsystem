$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Read the file content
$content = Get-Content $filePath -Raw

# Add helper functions for market data retrieval after the GetLastErrorText function
$helperFunctions = @"

//+------------------------------------------------------------------+
//| Helper functions for market data retrieval                        |
//+------------------------------------------------------------------+
// Get symbol stop level (returns in points)
long GetSymbolStopLevel() {
    long stopLevel = 0;
    if(!SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevel)) {
        Print("Error getting stop level: ", GetLastError());
        stopLevel = 5; // Default value
    }
    return stopLevel;
}

// Get current symbol point value
double GetSymbolPoint() {
    static double cachedPoint = 0;
    if(cachedPoint == 0) {
        cachedPoint = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        if(cachedPoint == 0) {
            Print("Error getting point value: ", GetLastError());
            cachedPoint = 0.00001; // Default value
        }
    }
    return cachedPoint;
}

// Get current bid price (cached for performance)
double GetCurrentBid() {
    return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}

// Get current ask price (cached for performance)
double GetCurrentAsk() {
    return SymbolInfoDouble(Symbol(), SYMBOL_ASK);
}

// Get current spread in points
long GetCurrentSpreadPoints() {
    long spreadPoints = 0;
    if(!SymbolInfoInteger(Symbol(), SYMBOL_SPREAD, spreadPoints)) {
        spreadPoints = 10; // Default if call fails
    }
    return spreadPoints;
}

// Calculate minimum stop distance in price terms
double GetMinStopDistanceInPrice() {
    long stopLevelPoints = GetSymbolStopLevel();
    double point = GetSymbolPoint();
    return (double)stopLevelPoints * point;
}

// High performance validation of stop loss levels
bool IsValidStopLossPrice(double entryPrice, double stopLossPrice, bool isBuy) {
    double minStopDistance = GetMinStopDistanceInPrice();
    double spreadPrice = (double)GetCurrentSpreadPoints() * GetSymbolPoint();
    
    if(isBuy) {
        return stopLossPrice <= entryPrice - minStopDistance - spreadPrice;
    } else {
        return stopLossPrice >= entryPrice + minStopDistance + spreadPrice;
    }
}

// Calculate optimal lot size based on risk percentage and stop distance
double CalculateOptimalLotSize(double riskPercentage, double stopDistancePoints) {
    // Prevent divide by zero
    if(stopDistancePoints <= 0) return 0.0;
    
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double riskAmount = accountBalance * riskPercentage / 100.0;
    double pointValue = tickValue / tickSize;
    
    // Calculate lot size based on risk
    double lotSize = riskAmount / (stopDistancePoints * pointValue);
    
    // Normalize to valid lot step
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    
    // Round to valid lot step
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Ensure within valid range
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    return lotSize;
}

// Emergency circuit breaker - check if trading should be halted
bool IsEmergencyModeActive() {
    // Check for extreme volatility
    double atr = iATR(Symbol(), PERIOD_M1, 14, 0);
    double averageAtr = 0;
    
    // Calculate average ATR over last 10 periods
    for(int i = 1; i <= 10; i++) {
        averageAtr += iATR(Symbol(), PERIOD_M1, 14, i);
    }
    averageAtr /= 10;
    
    // If current ATR is more than 3x the average, consider it an emergency
    if(atr > 3 * averageAtr) {
        LogError("EMERGENCY MODE ACTIVATED - Extreme volatility detected");
        return true;
    }
    
    // Check for extreme spread
    long currentSpread = GetCurrentSpreadPoints();
    if(currentSpread > 50) { // Adjust threshold as needed
        LogError("EMERGENCY MODE ACTIVATED - Extreme spread detected: " + IntegerToString(currentSpread));
        return true;
    }
    
    // Check for consecutive losses
    static int consecutiveLosses = 0;
    static bool initialized = false;
    
    if(!initialized) {
        // Count recent consecutive losses on initialization
        int totalDeals = HistoryDealsTotal();
        double lastProfit = 0;
        
        for(int i = totalDeals - 1; i >= 0; i--) {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket == 0) continue;
            
            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != Symbol()) continue;
            
            lastProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            if(lastProfit < 0) {
                consecutiveLosses++;
            } else if(lastProfit > 0) {
                break; // Stop counting at first profit
            }
        }
        
        initialized = true;
    }
    
    // Emergency stop after too many consecutive losses
    if(consecutiveLosses >= 5) { // Adjust threshold as needed
        LogError("EMERGENCY MODE ACTIVATED - Too many consecutive losses: " + IntegerToString(consecutiveLosses));
        return true;
    }
    
    return false;
}

"@

# Find position to insert (after GetLastErrorText function)
$insertPosition = $content.IndexOf("string GetLastErrorText(int error_code)")
$endOfFunction = $content.IndexOf("}", $insertPosition)
$endOfFunction = $content.IndexOf("}", $endOfFunction + 1) + 1 # Find the end of the function

# Insert helper functions after GetLastErrorText
$newContent = $content.Substring(0, $endOfFunction) + "`n" + $helperFunctions + $content.Substring($endOfFunction)

# Replace direct calls to SymbolInfoDouble with helper functions
$newContent = $newContent -replace "double point = SymbolInfoDouble\(Symbol\(\), SYMBOL_POINT\);", "double point = GetSymbolPoint();"
$newContent = $newContent -replace "SymbolInfoDouble\(Symbol\(\), SYMBOL_BID\)", "GetCurrentBid()"
$newContent = $newContent -replace "SymbolInfoDouble\(Symbol\(\), SYMBOL_ASK\)", "GetCurrentAsk()"

# Write the modified content back to the file
Set-Content -Path $filePath -Value $newContent

Write-Host "Added helper functions for improved API usage and risk management"
Write-Host "Replaced direct API calls with helper functions where appropriate"
Write-Host "Added emergency circuit breaker functionality"
