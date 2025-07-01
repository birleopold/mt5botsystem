$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Read the file content
$content = Get-Content $filePath -Raw

# Fix for line 3017-3020 (first SymbolInfoDouble call)
$pattern1 = "// Using direct assignment overload for SymbolInfoDouble which returns double\r\n    // Variable already declared\r\nif\(!SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL, stopLevel\)\)\r\n   Print\(""Error getting stop level""\);\r\nminStopDistance = stopLevel;"
$replacement1 = "// Using direct assignment overload for SymbolInfoDouble which returns double\r\n    double stopLevel = 0.0;\r\n    if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevel))\r\n        Print(\"Error getting stop level\");\r\n    minStopDistance = stopLevel;"
$content = $content -replace [regex]::Escape($pattern1), $replacement1

# Fix for line 7094-7098 (second SymbolInfoDouble call)
$pattern2 = "// Using direct assignment overload for SymbolInfoDouble which returns double\r\n    // Variable already declared\r\nif\(!SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL, stopLevel\)\)\r\n   Print\(""Error getting stop level""\);\r\nminStopDist = stopLevel;"
$replacement2 = "// Using direct assignment overload for SymbolInfoDouble which returns double\r\n    double stopLevel = 0.0;\r\n    if(!SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevel))\r\n        Print(\"Error getting stop level\");\r\n    minStopDist = stopLevel;"
$content = $content -replace [regex]::Escape($pattern2), $replacement2

# Write the fixed content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Fixed stopLevel errors in SmcScalperHybridV20.mq5"
Write-Host "Added proper variable declarations before SymbolInfoDouble calls"
Write-Host "Please recompile to check if all errors are resolved."
