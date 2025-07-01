$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Read the file content as an array of lines
$lines = Get-Content $filePath

# Fix the first error at line 3020
# Replace problematic code with manually typed, syntactically perfect code
$lines[3017] = "    // Manual declaration and initialization"
$lines[3018] = "    double stopLevelValue = 0.0;"
$lines[3019] = "    bool stopLevelSuccess = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue);"
$lines[3020] = "    if(!stopLevelSuccess) {"
$lines[3021] = "        Print(\"Error getting stop level: \", GetLastError());"
$lines[3022] = "        stopLevelValue = 5.0; // Default value if call fails"
$lines[3023] = "    }"

# Find the second error location (around line 7099)
# First find the start of that block by searching for a pattern
$secondBlockStart = -1
for ($i = 7090; $i < 7110; $i++) {
    if ($lines[$i] -match "double stopLevelValue") {
        $secondBlockStart = $i
        break
    }
}

if ($secondBlockStart -ne -1) {
    # Fix the second error block
    $lines[$secondBlockStart] = "    // Manual declaration and initialization"
    $lines[$secondBlockStart + 1] = "    double stopLevelValue = 0.0;"
    $lines[$secondBlockStart + 2] = "    bool stopLevelSuccess = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue);"
    $lines[$secondBlockStart + 3] = "    if(!stopLevelSuccess) {"
    $lines[$secondBlockStart + 4] = "        Print(\"Error getting stop level: \", GetLastError());"
    $lines[$secondBlockStart + 5] = "        stopLevelValue = 5.0; // Default value if call fails"
    $lines[$secondBlockStart + 6] = "    }"
}

# Write the modified content back to the file
Set-Content -Path $filePath -Value $lines

# Output summary
Write-Host "Surgical fix applied to SmcScalperHybridV20.mq5"
Write-Host "- Fixed first SymbolInfoDouble call (line 3020)"
if ($secondBlockStart -ne -1) {
    Write-Host "- Fixed second SymbolInfoDouble call (around line 7099)"
} else {
    Write-Host "- Could not locate second error block - manual fix required"
}
Write-Host "The code now uses a temporary variable to store the function result to avoid ambiguity"
Write-Host "Please recompile your EA to check if errors are resolved"
