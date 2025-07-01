//+------------------------------------------------------------------+
//| SMC Hybrid Adaptive Filters Module                               |
//+------------------------------------------------------------------+
// This module adds adaptive filter functionality to the SMC Scalper Hybrid EA
// It automatically adjusts entry filters based on market conditions and performance

// Initialize adaptive filters with default settings
void InitializeAdaptiveFilters() {
    adaptiveFilters.signalQualityThreshold = MinSignalQualityToTrade; // Start with input value
    adaptiveFilters.requireMultiTimeframe = RequireMultiTimeframeConfirmation;
    adaptiveFilters.requireMomentumConfirmation = RequireMomentumConfirmation;
    adaptiveFilters.minimumBlockStrength = 3;  // Default block strength requirement
    
    // Performance tracking
    adaptiveFilters.consecutiveNoTrades = 0;
    adaptiveFilters.consecutiveLosses = 0;
    adaptiveFilters.winStreak = 0;
    adaptiveFilters.winRate = 0.5; // Start with neutral win rate
    adaptiveFilters.lastAdaptationTime = 0;
    
    // Learning rate - how quickly filters adapt (0.0-1.0)
    adaptiveFilters.adaptationRate = 0.1;
    
    // Constraints to prevent filters from becoming too loose or strict
    adaptiveFilters.minSignalQualityAllowed = 0.3;
    adaptiveFilters.maxSignalQualityAllowed = 0.8;
    
    LogInfo("[ADAPT] Adaptive filters initialized with quality threshold: " + 
           DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
}

// Update filter settings based on recent performance data
void UpdateAdaptiveFilters(bool tradeTaken, bool tradeWon, bool missedProfitableSetup) {
    // Only update filters periodically (at most once per hour)
    datetime currentTime = TimeCurrent();
    if(currentTime - adaptiveFilters.lastAdaptationTime < 3600) return;
    
    // Track consecutive metrics
    if(tradeTaken) {
        adaptiveFilters.consecutiveNoTrades = 0;
        if(tradeWon) {
            adaptiveFilters.consecutiveLosses = 0;
            adaptiveFilters.winStreak++;
        } else {
            adaptiveFilters.winStreak = 0;
            adaptiveFilters.consecutiveLosses++;
        }
    } else {
        adaptiveFilters.consecutiveNoTrades++;
    }
    
    // Gradually loosen filters if we're missing too many trades
    if(adaptiveFilters.consecutiveNoTrades > 20 || missedProfitableSetup) {
        // Reduce quality threshold to take more trades
        double adjustment = adaptiveFilters.adaptationRate * 0.1;
        adaptiveFilters.signalQualityThreshold = MathMax(
            adaptiveFilters.minSignalQualityAllowed,
            adaptiveFilters.signalQualityThreshold - adjustment
        );
        
        // After 30 consecutive no-trades, consider disabling multi-timeframe requirement
        if(adaptiveFilters.consecutiveNoTrades > 30 && adaptiveFilters.requireMultiTimeframe) {
            adaptiveFilters.requireMultiTimeframe = false;
            LogInfo("[ADAPT] Temporarily disabled multi-timeframe confirmation requirement due to lack of trades");
        }
        
        LogInfo("[ADAPT] Loosened filters due to " + IntegerToString(adaptiveFilters.consecutiveNoTrades) + 
               " missed trades. New quality threshold: " + DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
    }
    
    // Tighten filters if having consecutive losses
    if(adaptiveFilters.consecutiveLosses > 3) {
        double adjustment = adaptiveFilters.adaptationRate * 0.1 * adaptiveFilters.consecutiveLosses / 3.0;
        adaptiveFilters.signalQualityThreshold = MathMin(
            adaptiveFilters.maxSignalQualityAllowed,
            adaptiveFilters.signalQualityThreshold + adjustment
        );
        
        // After 5 consecutive losses, require all confirmations
        if(adaptiveFilters.consecutiveLosses > 5) {
            adaptiveFilters.requireMultiTimeframe = true;
            adaptiveFilters.requireMomentumConfirmation = true;
            LogInfo("[ADAPT] Enabled all confirmations due to consecutive losses");
        }
        
        LogInfo("[ADAPT] Tightened filters due to " + IntegerToString(adaptiveFilters.consecutiveLosses) + 
               " consecutive losses. New quality threshold: " + DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
    }
    
    // If winning streak, gradually optimize for more trades
    if(adaptiveFilters.winStreak > 5) {
        double adjustment = adaptiveFilters.adaptationRate * 0.05;
        adaptiveFilters.signalQualityThreshold = MathMax(
            adaptiveFilters.minSignalQualityAllowed,
            adaptiveFilters.signalQualityThreshold - adjustment
        );
        
        LogInfo("[ADAPT] Optimized filters after " + IntegerToString(adaptiveFilters.winStreak) + 
               " consecutive wins. New quality threshold: " + DoubleToString(adaptiveFilters.signalQualityThreshold, 2));
    }
    
    adaptiveFilters.lastAdaptationTime = currentTime;
}

// Get the currently adapted signal quality threshold
double GetAdaptedSignalQualityThreshold() {
    return adaptiveFilters.signalQualityThreshold;
}

// Check if multi-timeframe confirmation is required (may be dynamically adjusted)
bool IsMultiTimeframeRequired() {
    return adaptiveFilters.requireMultiTimeframe;
}

// Check if momentum confirmation is required (may be dynamically adjusted)
bool IsMomentumConfirmationRequired() {
    return adaptiveFilters.requireMomentumConfirmation;
}
