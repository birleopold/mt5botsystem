$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"
$content = Get-Content $filePath -Raw

# Fix 1: Correct the GetCurrentBid/Ask methods (they were causing infinite recursion)
$content = $content -replace "double GetCurrentBid\(\) \{[\s\S]*?return GetCurrentBid\(\);[\s\S]*?\}", @"
double GetCurrentBid() {
    return SymbolInfoDouble(Symbol(), SYMBOL_BID);
}
"@

$content = $content -replace "double GetCurrentAsk\(\) \{[\s\S]*?return GetCurrentAsk\(\);[\s\S]*?\}", @"
double GetCurrentAsk() {
    return SymbolInfoDouble(Symbol(), SYMBOL_ASK);
}
"@

# Fix 2: Restore original variable names and fix variable hiding issues
$content = $content -replace "double localAtrBuffer", "double atrBuffer[]"
$content = $content -replace "CTrade localTrade", "CTrade trade"
$content = $content -replace "datetime localLastTradeExecTime", "datetime lastTradeExecTime"

# Fix 3: Fix iATR function calls (parameter count issues)
$content = $content -replace "double atr = iATR\(Symbol\(\), PERIOD_M1, 14, 0\);", @"
int atrHandle = iATR(Symbol(), PERIOD_M1, 14);
double atr = 0.0;
if (CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0) {
    LogError("Failed to copy ATR data");
    return false;
}
"@

$content = $content -replace "averageAtr \+= iATR\(Symbol\(\), PERIOD_M1, 14, i\);", @"
double tempBuffer[1];
if (CopyBuffer(atrHandle, 0, i, 1, tempBuffer) > 0) {
    averageAtr += tempBuffer[0];
}
"@

# Fix 4: Add MinSignalQualityToTrade input parameter
if (-not ($content -match "input\s+double\s+MinSignalQualityToTrade")) {
    $insertPoint = $content.IndexOf("//+------------------------------------------------------------------+", $content.IndexOf("input"))
    if ($insertPoint -gt 0) {
        $newParam = "`ninput double MinSignalQualityToTrade = 70.0; // Minimum signal quality to trade (0-100)`n"
        $content = $content.Substring(0, $insertPoint) + $newParam + $content.Substring($insertPoint)
    }
}

# Fix 5: Add workingMinSignalQualityToTrade variable if needed
if (-not ($content -match "double\s+workingMinSignalQualityToTrade")) {
    $insertPoint = $content.IndexOf("//+------------------------------------------------------------------+", $content.IndexOf("// Global variables"))
    if ($insertPoint -gt 0) {
        $newVar = "double workingMinSignalQualityToTrade = 70.0; // Working copy of minimum signal quality`n`n"
        $content = $content.Substring(0, $insertPoint) + $newVar + $content.Substring($insertPoint)
    }
}

# Fix 6: Fix explicit casts for long to double conversions
$content = $content -replace "(\bdouble[\w\s=]+)(\blongValue\b|\bspreadPoints\b)", '$1(double)$2'

# Write the modified content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Fixed critical errors in the SmcScalperHybridV20 EA:"
Write-Host "- Fixed infinite recursion in GetCurrentBid/Ask"
Write-Host "- Fixed iATR function calls"
Write-Host "- Added missing MinSignalQualityToTrade input parameter"
Write-Host "- Added workingMinSignalQualityToTrade global variable"
Write-Host "- Fixed array definitions and variable naming"
Write-Host "- Added proper type casting for long to double conversions"
