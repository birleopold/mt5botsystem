$file = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Fix first occurrence
$content = Get-Content $file -Raw
$pattern1 = 'double stopLevelValue = SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL\);[\s\S]*?stopLevelValue = 5\.0;'
$replacement1 = @"
double stopLevelValue = 0.0;
if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue)) {
    Print("Error getting stop level: ", GetLastError());
    stopLevelValue = 5.0;
}
"@
$content = $content -replace $pattern1, $replacement1

# Fix second occurrence
$pattern2 = 'double stopLevelValue = SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL\);[\s\S]*?stopLevelValue = 5\.0;'
$content = $content -replace $pattern2, $replacement1

Set-Content -Path $file -Value $content

Write-Host "Fixed SymbolInfoDouble function calls by explicitly using the reference parameter overload"
Write-Host "Added proper error handling with GetLastError() for stop level validation"
Write-Host "This should resolve the compilation errors for your SMC trading bot"
