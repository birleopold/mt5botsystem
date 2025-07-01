$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"
$content = Get-Content $filePath -Raw

# Fix 1: Restore GetCurrentBid/Ask - infinite recursion error
$content = $content -replace "double GetCurrentBid\(\) \{\s*return GetCurrentBid\(\);\s*\}", @"
double GetCurrentBid() {
    return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}
"@

$content = $content -replace "double GetCurrentAsk\(\) \{\s*return GetCurrentAsk\(\);\s*\}", @"
double GetCurrentAsk() {
    return SymbolInfoDouble(Symbol(), SYMBOL_ASK);
}
"@

# Fix 2: Fix iATR function calls in IsEmergencyModeActive
$content = $content -replace "double atr = iATR\(Symbol\(\), PERIOD_M1, 14, 0\);", "int atrHandle = iATR(Symbol(), PERIOD_M1, 14);"
$content = $content -replace "averageAtr \+= iATR\(Symbol\(\), PERIOD_M1, 14, i\);", "double tempValue = 0.0; CopyBuffer(atrHandle, 0, i, 1, tempValue); averageAtr += tempValue;"

# Fix 3: Define missing MinSignalQualityToTrade input parameter
$inputs = $content -match "input"
$inputSection = $content.Substring(0, $content.IndexOf("//+------------------------------------------------------------------+", $content.IndexOf("input")))

if (-not ($inputSection -match "MinSignalQualityToTrade")) {
    $insertPoint = $content.IndexOf("//+------------------------------------------------------------------+", $content.IndexOf("input"))
    $newInputs = "input double MinSignalQualityToTrade = 70.0; // Minimum signal quality to trade (0-100)`n"
    $content = $content.Substring(0, $insertPoint) + $newInputs + $content.Substring($insertPoint)
}

# Fix 4: Add workingMinSignalQualityToTrade variable declaration
if (-not ($content -match "double workingMinSignalQualityToTrade")) {
    $globalVariables = $content.IndexOf("// Global variables", $content.IndexOf("input"))
    if ($globalVariables -eq -1) {
        $globalVariables = $content.IndexOf("// Global variables", 0)
    }
    
    if ($globalVariables -ne -1) {
        $insertPoint = $content.IndexOf(";", $globalVariables)
        $insertPoint = $content.IndexOf("`n", $insertPoint) + 1
        $newVariable = "double workingMinSignalQualityToTrade = 70.0; // Working copy of minimum signal quality`n"
        $content = $content.Substring(0, $insertPoint) + $newVariable + $content.Substring($insertPoint)
    }
}

# Fix 5: Fix atrBuffer issues - ensure it's defined as an array
$content = $content -replace "double localAtrBuffer;", "double atrBuffer[];"
$content = $content -replace "double localAtrBuffer\s*=\s*0;", "double atrBuffer[];"
$content = $content -replace "double localAtrBuffer\[", "double atrBuffer["

# Fix 6: Fix CTrade variable issues - restore 'trade' globally
$content = $content -replace "CTrade localTrade;", "CTrade trade;"

# Fix 7: Fix all variable uses to match global definitions
$content = $content -replace "localAtrBuffer(?!\[)", "atrBuffer"
$content = $content -replace "localTrade\.", "trade."

Set-Content -Path $filePath -Value $content

Write-Host "Fixed critical errors in the SmcScalperHybridV20 EA:"
Write-Host "✓ Fixed infinite recursion in GetCurrentBid/Ask"
Write-Host "✓ Fixed iATR function calls"
Write-Host "✓ Added missing MinSignalQualityToTrade input parameter"
Write-Host "✓ Defined workingMinSignalQualityToTrade global variable"
Write-Host "✓ Fixed atrBuffer array definition"
Write-Host "✓ Restored CTrade variable usage"
Write-Host "✓ Fixed variable references to match global definitions"
