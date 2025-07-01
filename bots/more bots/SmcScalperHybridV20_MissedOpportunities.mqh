//+------------------------------------------------------------------+
//| SMC Hybrid Missed Opportunity Tracker                             |
//+------------------------------------------------------------------+
// This module tracks potential trading opportunities that were filtered out
// Helps with strategy optimization by showing what you might be missing

// Constants for missed opportunities tracking
#define MAX_MISSED_OPPORTUNITIES 50

// Record a missed trading opportunity with all relevant details
void RecordMissedOpportunity(int signal, double price, string reason, double quality) {
    if(signal == 0) return; // Don't record if there was no valid signal
    
    // Record the missed opportunity in our circular buffer
    missedOpportunities[missedOpportunityIndex].time = TimeCurrent();
    missedOpportunities[missedOpportunityIndex].signal = signal;
    missedOpportunities[missedOpportunityIndex].price = price;
    missedOpportunities[missedOpportunityIndex].filterReason = reason;
    missedOpportunities[missedOpportunityIndex].marketRegime = (int)currentRegime;
    missedOpportunities[missedOpportunityIndex].signalQuality = quality;
    missedOpportunities[missedOpportunityIndex].potentialProfit = 0; // Will calculate when updated
    missedOpportunities[missedOpportunityIndex].wouldHaveWon = false; // Default until we know outcome
    
    // Log the missed opportunity
    string direction = signal > 0 ? "BUY" : "SELL";
    LogInfo("[MISSED] " + direction + " opportunity at " + DoubleToString(price, _Digits) + 
           " filtered due to: " + reason + " (quality: " + DoubleToString(quality, 2) + ")");
    
    // Increment the index in our circular buffer and counter
    missedOpportunityIndex = (missedOpportunityIndex + 1) % MAX_MISSED_OPPORTUNITIES;
    missedOpportunityCount = MathMin(missedOpportunityCount + 1, MAX_MISSED_OPPORTUNITIES);
}

// Update all tracked missed opportunities with outcome information
void UpdateMissedOpportunities() {
    double atr = GetATR(Symbol(), PERIOD_CURRENT, 14, 0);
    if(atr <= 0) return; // Skip if no valid ATR
    
    double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    
    for(int i = 0; i < missedOpportunityCount; i++) {
        // Skip already processed entries or very recent ones (less than 1 hour old)
        if(missedOpportunities[i].potentialProfit != 0) continue;
        
        datetime entryTime = missedOpportunities[i].time;
        datetime currentTime = TimeCurrent();
        
        // Only evaluate missed opportunities that are at least 1 hour old but less than 24 hours
        if(currentTime - entryTime < 3600 || currentTime - entryTime > 86400) continue;
        
        int signal = missedOpportunities[i].signal;
        double entryPrice = missedOpportunities[i].price;
        
        // Calculate hypothetical SL and TP levels (similar to actual trade logic)
        double stopLoss = signal > 0 ?
            entryPrice - (SL_ATR_Mult * atr) :
            entryPrice + (SL_ATR_Mult * atr);
            
        double takeProfit = signal > 0 ?
            entryPrice + (TP_ATR_Mult * atr) :
            entryPrice - (TP_ATR_Mult * atr);
        
        bool hitTakeProfit = false;
        bool hitStopLoss = false;
        double maxFavorableMove = 0;
        double maxAdverseMove = 0;
        
        // Get price data since opportunity was missed
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        int bars = (int)((currentTime - entryTime) / PeriodSeconds()) + 10; // Add buffer
        int copied = CopyRates(Symbol(), PERIOD_CURRENT, 0, bars, rates);
        
        if(copied > 0) {
            // Find the bar closest to our entry time
            int startBar = 0;
            for(int j = 0; j < copied; j++) {
                if(rates[j].time <= entryTime) {
                    startBar = j;
                    break;
                }
            }
            
            // Analyze price movement after entry time
            for(int j = startBar; j >= 0; j--) {
                if(signal > 0) { // Buy signal
                    // Check if TP would have been hit
                    if(rates[j].high >= takeProfit) hitTakeProfit = true;
                    
                    // Check if SL would have been hit
                    if(rates[j].low <= stopLoss) hitStopLoss = true;
                    
                    // Track max favorable/adverse moves
                    maxFavorableMove = MathMax(maxFavorableMove, rates[j].high - entryPrice);
                    maxAdverseMove = MathMax(maxAdverseMove, entryPrice - rates[j].low);
                }
                else { // Sell signal
                    // Check if TP would have been hit
                    if(rates[j].low <= takeProfit) hitTakeProfit = true;
                    
                    // Check if SL would have been hit
                    if(rates[j].high >= stopLoss) hitStopLoss = true;
                    
                    // Track max favorable/adverse moves
                    maxFavorableMove = MathMax(maxFavorableMove, entryPrice - rates[j].low);
                    maxAdverseMove = MathMax(maxAdverseMove, rates[j].high - entryPrice);
                }
                
                // If either TP or SL was hit, we know the outcome
                if(hitTakeProfit || hitStopLoss) break;
            }
            
            // Calculate potential profit/loss
            double potentialPips = 0;
            
            if(hitTakeProfit) {
                // Would have hit take profit
                potentialPips = signal > 0 ? 
                    (takeProfit - entryPrice) / Point() : 
                    (entryPrice - takeProfit) / Point();
                missedOpportunities[i].wouldHaveWon = true;
            }
            else if(hitStopLoss) {
                // Would have hit stop loss
                potentialPips = signal > 0 ? 
                    (stopLoss - entryPrice) / Point() : 
                    (entryPrice - stopLoss) / Point();
                missedOpportunities[i].wouldHaveWon = false;
            }
            else {
                // Neither hit yet, calculate current profit/loss
                double currentPrice = signal > 0 ? currentBid : currentAsk;
                potentialPips = signal > 0 ? 
                    (currentPrice - entryPrice) / Point() :
                    (entryPrice - currentPrice) / Point();
                missedOpportunities[i].wouldHaveWon = potentialPips > 0;
            }
            
            // Store the result
            missedOpportunities[i].potentialProfit = potentialPips;
            
            // Log significant missed winners (would have been profitable)
            if(missedOpportunities[i].wouldHaveWon && potentialPips > 20.0) {
                LogInfo("[MISSED-WINNER] The " + (signal > 0 ? "BUY" : "SELL") + 
                       " opportunity filtered on " + TimeToString(entryTime) + 
                       " would have yielded " + DoubleToString(potentialPips, 1) + 
                       " pips! Filtered due to: " + missedOpportunities[i].filterReason);
                       
                // Signal that we missed a profitable setup for adaptive filters
                if(potentialPips > 50.0) {
                    UpdateAdaptiveFilters(false, false, true);
                }
            }
        }
    }
}

// Generate a statistical report on missed opportunities
string GenerateMissedOpportunitiesReport() {
    int totalMissed = 0;
    int totalWinners = 0;
    int totalLosers = 0;
    double totalPips = 0;
    
    // Count opportunities with outcomes
    for(int i = 0; i < missedOpportunityCount; i++) {
        if(missedOpportunities[i].potentialProfit != 0) {
            totalMissed++;
            
            if(missedOpportunities[i].wouldHaveWon) {
                totalWinners++;
                totalPips += MathAbs(missedOpportunities[i].potentialProfit);
            } else {
                totalLosers++;
                totalPips -= MathAbs(missedOpportunities[i].potentialProfit);
            }
        }
    }
    
    // Generate report
    string report = "=== MISSED OPPORTUNITIES REPORT ===\n";
    report += "Total tracked: " + IntegerToString(missedOpportunityCount) + "\n";
    report += "With outcomes: " + IntegerToString(totalMissed) + "\n";
    
    if(totalMissed > 0) {
        double winRate = totalWinners * 100.0 / totalMissed;
        report += "Potential winners: " + IntegerToString(totalWinners) + 
                 " (" + DoubleToString(winRate, 1) + "%)\n";
        report += "Potential losers: " + IntegerToString(totalLosers) + 
                 " (" + DoubleToString(100.0 - winRate, 1) + "%)\n";
        report += "Net pips: " + DoubleToString(totalPips, 1) + "\n";
        
        // Analyze reasons for filtering
        int reasonCounts[5] = {0,0,0,0,0};
        string reasonLabels[5] = {"Quality", "Regime", "Confirmation", "Cooldown", "Other"};
        
        for(int i = 0; i < missedOpportunityCount; i++) {
            string reason = missedOpportunities[i].filterReason;
            if(StringFind(reason, "quality") >= 0) reasonCounts[0]++;
            else if(StringFind(reason, "regime") >= 0) reasonCounts[1]++;
            else if(StringFind(reason, "confirmation") >= 0) reasonCounts[2]++;
            else if(StringFind(reason, "cooldown") >= 0) reasonCounts[3]++;
            else reasonCounts[4]++;
        }
        
        report += "\nFiltered by:\n";
        for(int i = 0; i < 5; i++) {
            report += reasonLabels[i] + ": " + IntegerToString(reasonCounts[i]) + "\n";
        }
    }
    
    return report;
}

// Draw missed opportunities on chart for visual analysis
void DrawMissedOpportunities() {
    // Clear previous drawings
    ObjectsDeleteAll(0, "MissedOpp_");
    
    // Only draw the most recent 20 opportunities
    int count = MathMin(20, missedOpportunityCount);
    
    for(int i = 0; i < count; i++) {
        // Only draw ones with outcome data
        if(missedOpportunities[i].potentialProfit == 0) continue;
        
        string name = "MissedOpp_" + IntegerToString(i);
        datetime time = missedOpportunities[i].time;
        double price = missedOpportunities[i].price;
        color arrowColor = missedOpportunities[i].wouldHaveWon ? clrLimeGreen : clrRed;
        
        // Create an arrow showing the missed opportunity
        if(missedOpportunities[i].signal > 0) {
            // Buy arrow (up)
            ObjectCreate(0, name, OBJ_ARROW_UP, 0, time, price - 20 * Point());
        } else {
            // Sell arrow (down)
            ObjectCreate(0, name, OBJ_ARROW_DOWN, 0, time, price + 20 * Point());
        }
        
        ObjectSetInteger(0, name, OBJPROP_COLOR, arrowColor);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
        
        // Add label with information
        string labelName = "MissedOpp_Label_" + IntegerToString(i);
        string labelText = (missedOpportunities[i].signal > 0 ? "BUY" : "SELL") + 
                          " " + DoubleToString(MathAbs(missedOpportunities[i].potentialProfit), 1) + "p";
        
        ObjectCreate(0, labelName, OBJ_TEXT, 0, time, price + (missedOpportunities[i].signal > 0 ? -40 : 40) * Point());
        ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
        ObjectSetInteger(0, labelName, OBJPROP_COLOR, arrowColor);
        ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
    }
}
