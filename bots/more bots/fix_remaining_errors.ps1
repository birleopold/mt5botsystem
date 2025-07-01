$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"
$content = Get-Content $filePath -Raw

# Fix 1: Check for the '6' - identifier expected error at line 1316
# This could be due to an invisible character or syntax issue
# Let's look at the PHASE_BREAKOUT = 6 line and ensure it has proper formatting
$content = $content -replace "PHASE_BREAKOUT(\s*)=(\s*)6,", "PHASE_BREAKOUT = 6,"

# Fix 2: Fix the variable already defined error at line 3018
# Replace the redefinition with just an assignment to the existing variable
$content = $content -replace "double stopLevel = 0.0;\r\nif\(!SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL, stopLevel\)\)", "if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevel))"

# Fix 3: Fix the remaining SymbolInfoDouble overload errors
# Ensure proper parameter types and error handling
$content = $content -replace "minStopDistance = SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL\);", "if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, minStopDistance)) { minStopDistance = 0.0; Print(\"Error getting stop level\"); }"
$content = $content -replace "minStopDist = SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL\);", "if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, minStopDist)) { minStopDist = 0.0; Print(\"Error getting stop level\"); }"

# Write the fixed content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Additional fixes applied to SmcScalperHybridV20.mq5"
Write-Host "The following changes were made:"
Write-Host "1. Fixed potential formatting issue with PHASE_BREAKOUT = 6"
Write-Host "2. Removed duplicate variable declaration for stopLevel"
Write-Host "3. Fixed remaining SymbolInfoDouble overload errors"
Write-Host "Please recompile and check for any remaining errors."
