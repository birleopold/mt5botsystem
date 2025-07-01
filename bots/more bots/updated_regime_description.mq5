//+------------------------------------------------------------------+
//| Convert market regime enum to descriptive string                 |
//+------------------------------------------------------------------+
string GetRegimeDescription(ENUM_MARKET_REGIME regime)
{
   switch(regime) {
      case REGIME_UNKNOWN: return "Unknown";
      case REGIME_NORMAL: return "Normal";
      case REGIME_TRENDING: return "Trending";
      case REGIME_TRENDING_BULL: return "Trending Bullish";
      case REGIME_TRENDING_BEAR: return "Trending Bearish";
      case REGIME_RANGING: return "Ranging";
      case REGIME_CHOPPY: return "Choppy";
      case REGIME_VOLATILE: return "Volatile";
      case REGIME_BREAKOUT: return "Breakout";
      case REGIME_STRONG_TREND: return "Strong Trend";
      case REGIME_MIXED: return "Mixed";
      case REGIME_REVERSAL: return "Reversal";
      default: return "Unknown";
   }
}
