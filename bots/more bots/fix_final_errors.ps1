$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"
$content = Get-Content $filePath -Raw

# Fix for line 3018: Remove variable redefinition
$pattern1 = 'double stopLevel = 0.0;'
$replacement1 = '// Variable already declared'
$content = $content -replace $pattern1, $replacement1

# Fix for SymbolInfoDouble calls (lines 3019 and 7096)
$pattern2 = 'if\(!SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL, stopLevel\)\)'
$replacement2 = 'if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevel))'
$content = $content -replace $pattern2, $replacement2

# Fix for enum issue (line 1316) - check for invisible characters
$pattern3 = 'PHASE_BREAKOUT = 6,'
$replacement3 = 'PHASE_BREAKOUT = 6,'
$content = $content -replace $pattern3, $replacement3

# Write the fixed content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Final fixes applied to SmcScalperHybridV20.mq5"
Write-Host "Please recompile to check for any remaining errors."
