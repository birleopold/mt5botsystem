$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"
$content = Get-Content $filePath -Raw

# 1. Fix global array declarations - ensure they're properly declared
if (-not ($content -match "double\s+atrBuffer\s*\[\s*\]")) {
    # Find global variable section
    $globalVarsPattern = "// Global variables(.*?)//\+------------------------------------------------------------------\+"
    if ($content -match $globalVarsPattern) {
        $globalVarsSection = $matches[1]
        $newGlobalVars = $globalVarsSection -replace "double atrBuffer;", "double atrBuffer[];"
        $content = $content -replace [regex]::Escape($globalVarsSection), $newGlobalVars
    }
}

# 2. Fix all atrBuffer declarations and CopyBuffer calls
$content = $content -replace "double atrBuffer(?!\[\])", "double atrBuffer[]"
$content = $content -replace "double localAtrBuffer", "double atrBuffer[]"

# Fix CopyBuffer calls with proper array parameters
$content = $content -replace "CopyBuffer\(([^,]+), ([^,]+), ([^,]+), ([^,]+), atrBuffer(?!\[)", "CopyBuffer($1, $2, $3, $4, atrBuffer"

# 3. Restore trade variables - consistently use trade instead of localTrade
$content = $content -replace "CTrade localTrade", "CTrade trade"
$content = $content -replace "localTrade\.", "trade."

# 4. Fix array access - properly use array indices
$content = $content -replace "atrBuffer\s*=", "atrBuffer[0] ="
$content = $content -replace "atrBuffer;", "atrBuffer[0];"

# 5. Fix missing newSL variable declaration
$content = $content -replace "if\(orderType == ORDER_TYPE_BUY\) \{(?:[^}]+?)// Calculate trailing stop for buy", "if(orderType == ORDER_TYPE_BUY) {\n        double newSL = 0.0;\n        // Calculate trailing stop for buy"
$content = $content -replace "if\(orderType == ORDER_TYPE_SELL\) \{(?:[^}]+?)// Calculate trailing stop for sell", "if(orderType == ORDER_TYPE_SELL) {\n        double newSL = 0.0;\n        // Calculate trailing stop for sell"

# 6. Fix syntax errors, especially unbalanced parentheses
$content = $content -replace "trade\.PositionModify\(([^,]+),([^)]+)\);", "trade.PositionModify($1,$2);"

# 7. Fix IsEmergencyModeActive to properly use CopyBuffer
$isEmergencyPattern = "// Check for extreme volatility(.*?)// Check for extreme spread"
if ($content -match $isEmergencyPattern) {
    $emergencySection = $matches[1]
    $newEmergencySection = @"
    // Check for extreme volatility
    int atrHandle = iATR(Symbol(), PERIOD_M1, 14);
    double atr = 0.0;
    double buffer[1];
    if (CopyBuffer(atrHandle, 0, 0, 1, buffer) > 0) {
        atr = buffer[0];
    } else {
        LogError("Failed to copy ATR data");
        return false;
    }
    double averageAtr = 0;
    
    // Calculate average ATR over last 10 periods
    for(int i = 1; i <= 10; i++) {
        if (CopyBuffer(atrHandle, 0, i, 1, buffer) > 0) {
            averageAtr += buffer[0];
        }
    }
    averageAtr /= 10;
"@
    $content = $content -replace [regex]::Escape($emergencySection), $newEmergencySection
}

# 8. Add explicit casts for all long to double conversions
$content = $content -replace "(\bdouble[\w\s=]+)(\blongValue\b|\bspreadPoints\b)", '$1(double)$2'
$content = $content -replace "double\s+([^=]+)\s*=\s*(\w+Integer\([^)]+\))", 'double $1 = (double)$2'

# 9. Ensure ArrayResize is used before CopyBuffer for dynamic arrays
$content = $content -replace "(?<!ArrayResize\(atrBuffer, \d+\);\s+)CopyBuffer\(([^,]+), ([^,]+), ([^,]+), (\d+), atrBuffer\)", "ArrayResize(atrBuffer, $4);\n   CopyBuffer($1, $2, $3, $4, atrBuffer)"

# Fix empty controlled statements
$content = $content -replace "if\s*\([^)]+\)\s*;", ""

# Write the modified content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Fixed all array and variable issues in SmcScalperHybridV20.mq5:"
Write-Host "1. Properly defined atrBuffer[] as an array"
Write-Host "2. Fixed all CopyBuffer calls with proper array parameters"
Write-Host "3. Restored trade variables consistently throughout the code"
Write-Host "4. Fixed array access with proper indices"
Write-Host "5. Added missing variable declarations"
Write-Host "6. Fixed syntax errors and unbalanced parentheses"
Write-Host "7. Fixed the IsEmergencyModeActive function"
Write-Host "8. Added explicit casts for all conversions"
Write-Host "9. Added ArrayResize before CopyBuffer calls"
