// Temporary settings to disable risk management
// Copy and paste these into your EA's OnInit function to disable risk management

// Disable drawdown protection
DrawdownProtectionEnabled = false;
TradingDisabled = false;
TradingPaused = false;

// Disable daily loss limit
RiskManagementEnabled = false;
MaxDailyRiskPercent = 100.0; // Set to a very high value

// Reset any counters that might be blocking trades
ConsecutiveLosses = 0;

// Log that risk management is temporarily disabled
Print("[RISK] Risk management temporarily disabled for testing");
