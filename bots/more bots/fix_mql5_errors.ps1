$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"
$content = Get-Content $filePath -Raw

# Fix the SYMBOL_TRADE_STOP_LEVEL errors (replace with SYMBOL_TRADE_STOPS_LEVEL)
$content = $content -replace "SYMBOL_TRADE_STOP_LEVEL", "SYMBOL_TRADE_STOPS_LEVEL"

# Fix any duplicate variable declarations (if needed)
# This part might be more complex depending on context, but this addresses the most critical errors

# Write the fixed content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Fixes applied to SmcScalperHybridV20.mq5"
Write-Host "The following changes were made:"
Write-Host "1. Changed SYMBOL_TRADE_STOP_LEVEL to SYMBOL_TRADE_STOPS_LEVEL"
Write-Host "Please recompile and check for any remaining errors."
