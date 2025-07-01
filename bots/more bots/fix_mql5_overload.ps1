$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Read the file content
$content = Get-Content $filePath -Raw

# Fix first SymbolInfoDouble call (around line 3019)
$firstPattern = @"
    // Get minimum stop distance from broker
    double stopLevelValue = 0.0;
    if\(!SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue\)\) {
        Print\("Error getting stop level"\);
        stopLevelValue = 5.0; // Default value if call fails
    }
"@

$firstReplacement = @"
    // Get minimum stop distance from broker using direct value retrieval
    double stopLevelValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    if(stopLevelValue == 0 && GetLastError() != 0) {
        Print("Error getting stop level: ", GetLastError());
        stopLevelValue = 5.0; // Default value if call fails
    }
"@

# Fix second SymbolInfoDouble call (around line 7098)
$secondPattern = @"
    // Get minimum stop distance from broker
    double stopLevelValue = 0.0;
    if\(!SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue\)\) {
        Print\("Error getting stop level"\);
        stopLevelValue = 5.0; // Default value if call fails
    }
"@

$secondReplacement = @"
    // Get minimum stop distance from broker using direct value retrieval
    double stopLevelValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    if(stopLevelValue == 0 && GetLastError() != 0) {
        Print("Error getting stop level: ", GetLastError());
        stopLevelValue = 5.0; // Default value if call fails
    }
"@

# Apply replacements
$content = $content -replace [regex]::Escape($firstPattern), $firstReplacement
$content = $content -replace [regex]::Escape($secondPattern), $secondReplacement

# Write the modified content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Fixed SymbolInfoDouble calls by switching to direct value retrieval method"
Write-Host "Please recompile your EA to check if errors are resolved"
