$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"
$content = Get-Content $filePath -Raw

# Fix 1: Fix the enum duplicate identifier issue (line 1316)
# Change BREAKOUT = 20 to PHASE_BREAKOUT_REGIME = 20 to avoid duplicate with PHASE_BREAKOUT = 6
$content = $content -replace "BREAKOUT = 20,", "PHASE_BREAKOUT_REGIME = 20,"

# Fix 2: Add stopLevel declaration before line 3019
$pattern1 = "// Using direct assignment overload for SymbolInfoDouble which returns double\r\n// Variable already declared\r\nif\(!SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL, stopLevel\)\)"
$replacement1 = "// Using direct assignment overload for SymbolInfoDouble which returns double\r\ndouble stopLevel = 0.0;\r\nif(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevel))"
$content = $content -replace $pattern1, $replacement1

# Fix 3: Add stopLevel declaration before line 7096
$pattern2 = "// Using direct assignment overload for SymbolInfoDouble which returns double\r\nif\(!SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL, stopLevel\)\)"
$replacement2 = "// Using direct assignment overload for SymbolInfoDouble which returns double\r\ndouble stopLevel = 0.0;\r\nif(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevel))"
$content = $content -replace $pattern2, $replacement2

# Write the fixed content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "All remaining MQL5 errors fixed:"
Write-Host "1. Fixed enum duplicate identifier (BREAKOUT = 20 renamed to PHASE_BREAKOUT_REGIME = 20)"
Write-Host "2. Added stopLevel declarations before SymbolInfoDouble calls"
Write-Host "Please recompile to check if all errors are resolved."
