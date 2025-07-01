$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Read the file line by line
$lines = Get-Content $filePath

# Fix the first SymbolInfoDouble call (line 3018-3019)
for ($i = 3017; $i -lt 3021; $i++) {
    if ($i -eq 3018) {
        $lines[$i] = "    if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue)) {"
    }
    elseif ($i -eq 3019) {
        $lines[$i] = "        Print(\"Error getting stop level\");"
    }
    elseif ($i -eq 3020) {
        $lines[$i] = "    }"
    }
}

# Add a new line for the assignment
$newLines = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    $newLines += $lines[$i]
    if ($i -eq 3020) {
        $newLines += "    minStopDistance = stopLevelValue;"
    }
}

# Fix the second SymbolInfoDouble call (around line 7095-7097)
for ($i = 0; $i -lt $newLines.Count; $i++) {
    if ($i -ge 7094 && $i -le 7098) {
        if ($i -eq 7095) {
            $newLines[$i] = "    if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue)) {"
        }
        elseif ($i -eq 7096) {
            $newLines[$i] = "        Print(\"Error getting stop level\");"
        }
        elseif ($i -eq 7097) {
            $newLines[$i] = "    }"
        }
        elseif ($i -eq 7098) {
            $newLines[$i] = "    minStopDist = stopLevelValue;"
        }
    }
}

# Write the modified content back to the file
$newLines | Set-Content $filePath

Write-Host "Fixed SymbolInfoDouble function calls in SmcScalperHybridV20.mq5"
Write-Host "Added proper formatting and braces to function calls"
Write-Host "Please recompile to check if all errors are resolved."
