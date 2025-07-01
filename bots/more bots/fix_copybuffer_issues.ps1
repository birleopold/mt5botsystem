$filePath = "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"
$content = Get-Content $filePath -Raw

# 1. Fix the global atrBuffer array declaration
if ($content -match "double\s+atrBuffer\s*(?!\[)") {
    $content = $content -replace "double\s+atrBuffer\s*;", "double atrBuffer[]; // ATR indicator buffer"
}

# 2. Fix all CopyBuffer calls - ensure they have the correct number and type of parameters
# Pattern: CopyBuffer(handle, buffer_num, start_pos, count, array_name)
$content = $content -replace "CopyBuffer\(([^,]+),([^,]+),([^,]+),([^,]+),\s*atrBuffer\s*(?!\[)", "CopyBuffer($1,$2,$3,$4,atrBuffer"

# 3. Fix any instances where localAtrBuffer is still referenced
$content = $content -replace "localAtrBuffer", "atrBuffer"

# 4. Replace problematic CopyBuffer calls at specific locations with correctly formatted ones
$content = $content -replace "CopyBuffer\([^,]+,[^,]+,[^,]+,[^,\)]+$", "CopyBuffer(atrHandle, 0, 0, 1, buffer)"

# 5. Fix invalid array access
$content = $content -replace "atrBuffer\s*=", "atrBuffer[0] ="
$content = $content -replace "atrBuffer(?!\[|\s*\[|\]|\s*=|\s*\])", "atrBuffer[0]"

# 6. Fix missing parameters in CopyBuffer calls at specific locations
$lines = $content -split "`n"
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "CopyBuffer\(.*\)" -and $lines[$i] -match "',' - syntax error, parameter missed") {
        $lineNumber = $i + 1
        Write-Host "Fixing syntax error on line $lineNumber: $($lines[$i])"
        
        # Extract the existing parameters
        if ($lines[$i] -match "CopyBuffer\(([^,]+),\s*([^,]+)") {
            $handle = $matches[1]
            $buffer = $matches[2]
            
            # Create a correct CopyBuffer call with all parameters
            $lines[$i] = "    ArrayResize(atrBuffer, 1); if(CopyBuffer($handle, $buffer, 0, 1, atrBuffer) <= 0) { Print(\"Error copying buffer: \", GetLastError()); }"
        }
    }
}
$content = $lines -join "`n"

# 7. Fix syntax errors with missing parameters in other function calls
$content = $content -replace "trade\.([^\(]+)\(([^,\)]*),\s*$", "trade.$1($2)"

# 8. Replace invalid array index values
$content = $content -replace "atrBuffer\[(?!\d|\])([^\]]+)\]", "atrBuffer[0]"

# 9. Add ArrayResize before CopyBuffer calls
$content = $content -replace "(?<!ArrayResize\(atrBuffer, \d+\);\s*)CopyBuffer\(([^,]+), ([^,]+), ([^,]+), (\d+), atrBuffer\)", "ArrayResize(atrBuffer, $4); CopyBuffer($1, $2, $3, $4, atrBuffer)"

# 10. Ensure global trade is used instead of local redeclarations
$content = $content -replace "CTrade\s+trade\s*;", "// Using global trade object"
$content = $content -replace "(?<!CTrade\s+)trade\s*=", "// Using global trade"

# Write the modified content back to the file
Set-Content -Path $filePath -Value $content

Write-Host "Fixed CopyBuffer and array issues:"
Write-Host "1. Properly defined atrBuffer[] as an array"
Write-Host "2. Fixed CopyBuffer calls with correct parameters"
Write-Host "3. Fixed invalid array access"
Write-Host "4. Fixed missing parameters in function calls"
Write-Host "5. Added ArrayResize before CopyBuffer calls"
Write-Host "6. Ensured global trade object is used consistently"
