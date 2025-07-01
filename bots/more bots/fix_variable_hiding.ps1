$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"
$content = Get-Content $filePath

# 1. Fix variable hiding for atrBuffer
$content = $content -replace '\bdouble atrBuffer\b(?!\s*=\s*\{)', 'double localAtrBuffer'
$content = $content -replace '\bint atrBuffer\b(?!\s*=\s*\{)', 'int localAtrBuffer'

# 2. Fix variable hiding for trade (careful to not break CTrade instances)
$content = $content -replace '(?<!CTrade\s)trade\b(?=\s*=)', 'localTrade'
$content = $content -replace '(?<=CTrade\s)trade(?=;)', 'localTrade'

# 3. Fix variable hiding for lastTradeExecTime
$content = $content -replace '\bdatetime lastTradeExecTime\b', 'datetime localLastTradeExecTime'

# 4. Add explicit type casting for long to double conversions
$content = $content -replace '(\bdouble\b[^=]*=\s*)(\blongValue\b|\bspreadPoints\b)', '$1(double)$2'

# Write the modified content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Fixed variable hiding warnings and added explicit type casts"
Write-Host "Please recompile your EA to check for remaining warnings"
