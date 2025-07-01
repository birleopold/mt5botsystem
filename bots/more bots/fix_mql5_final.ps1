$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

# Read the file line by line
$lines = Get-Content $filePath

# Find and fix the first stopLevel error (around line 3017-3020)
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "// Variable already declared" -and $i -lt 3100 -and $i -gt 3000) {
        $lines[$i] = "    double stopLevel = 0.0;"
        Write-Host "Fixed first stopLevel declaration at line $i"
        break
    }
}

# Find and fix the second stopLevel error (around line 7094-7098)
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "// Variable already declared" -and $i -lt 7100 -and $i -gt 7000) {
        $lines[$i] = "    double stopLevel = 0.0;"
        Write-Host "Fixed second stopLevel declaration at line $i"
        break
    }
}

# Write the modified content back to the file
$lines | Set-Content $filePath

Write-Host "Fixes applied to SmcScalperHybridV20.mq5"
Write-Host "Please recompile to check if all errors are resolved."
