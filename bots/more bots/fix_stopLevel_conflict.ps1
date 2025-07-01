$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Read the file line by line
$lines = Get-Content $filePath

# Fix the variable conflict in ValidateStopLevel function (line 3017-3020)
# The function parameter is already named stopLevel, so we need to use a different name
for ($i = 3016; $i -lt 3021; $i++) {
    if ($i -eq 3017) {
        $lines[$i] = "    double stopLevelValue = 0.0;"
    }
    elseif ($i -eq 3018) {
        $lines[$i] = "    if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue))"
    }
    elseif ($i -eq 3020) {
        $lines[$i] = "    minStopDistance = stopLevelValue;"
    }
}

# Fix the second SymbolInfoDouble call (around line 7094-7098)
for ($i = 7093; $i -lt 7099; $i++) {
    if ($i -eq 7094) {
        $lines[$i] = "    double stopLevelValue = 0.0;"
    }
    elseif ($i -eq 7095) {
        $lines[$i] = "    if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue))"
    }
    elseif ($i -eq 7097) {
        $lines[$i] = "    minStopDist = stopLevelValue;"
    }
}

# Write the modified content back to the file
$lines | Set-Content $filePath

Write-Host "Fixed stopLevel variable conflicts in SmcScalperHybridV20.mq5"
Write-Host "Changed variable name to stopLevelValue to avoid conflict with function parameter"
Write-Host "Please recompile to check if all errors are resolved."
