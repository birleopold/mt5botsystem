$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Read the file line by line
$lines = Get-Content $filePath

# Fix the first SymbolInfoDouble call (line 3018-3019)
$lines[3017] = "    double stopLevelValue = 0.0;"
$lines[3018] = "    if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOP_LEVEL, stopLevelValue))"
$lines[3019] = "        Print(\"Error getting stop level\");"

# Fix the second SymbolInfoDouble call (line 7095-7096)
$lines[7094] = "    double stopLevelValue = 0.0;"
$lines[7095] = "    if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOP_LEVEL, stopLevelValue))"
$lines[7096] = "        Print(\"Error getting stop level\");"

# Write the modified content back to the file
Set-Content -Path $filePath -Value $lines

Write-Host "Fixed SymbolInfoDouble function calls in SmcScalperHybridV20.mq5:"
Write-Host "1. Changed SYMBOL_TRADE_STOPS_LEVEL to SYMBOL_TRADE_STOP_LEVEL"
Write-Host "2. Fixed indentation of Print statements"
Write-Host "Please recompile to check if all errors are resolved."
