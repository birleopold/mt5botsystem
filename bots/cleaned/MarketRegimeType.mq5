//+------------------------------------------------------------------+
//| Classify market regime into broader categories                   |
//+------------------------------------------------------------------+
int MarketRegimeType(int regime) {
    if(regime == 0 || regime == 1) { // TRENDING_UP or TRENDING_DOWN
        return 0; // REGIME_TRENDING
    }
    else if(regime == 7 || regime == 5) { // HIGH_VOLATILITY or BREAKOUT
        return 1; // REGIME_VOLATILE
    }
    else if(regime == 2 || regime == 3 || regime == 8) { // RANGING_NARROW, RANGING_WIDE, or LOW_VOLATILITY
        return 2; // REGIME_RANGING
    }
    else if(regime == 4) { // REVERSAL
        return 3; // REGIME_REVERSAL
    }
    else {
        return 2; // Default to ranging (REGIME_RANGING) for choppy and unknown
    }
}
