$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Read and replace the incorrect enum constants
$content = Get-Content $filePath
$content = $content -replace 'SYMBOL_TRADE_STOP_LEVEL', 'SYMBOL_TRADE_STOPS_LEVEL'

# Write the corrected content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Successfully fixed all SYMBOL_TRADE_STOP_LEVEL references"
Write-Host "Recompile your EA - the critical errors should now be resolved"
