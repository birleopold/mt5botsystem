@echo off
echo Fixing MQL5 errors in SmcScalperHybridV20.mq5...

:: Create a temporary file for the first fix
type "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5" > temp1.mq5

:: Fix line 3017-3020 (first stopLevel error)
powershell -Command "(Get-Content temp1.mq5) -replace '// Variable already declared', 'double stopLevel = 0.0;' | Set-Content temp2.mq5"

:: Fix line 7094-7098 (second stopLevel error)
powershell -Command "(Get-Content temp2.mq5) -replace '// Variable already declared', 'double stopLevel = 0.0;' | Set-Content temp3.mq5"

:: Replace the original file with the fixed version
copy /Y temp3.mq5 "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

:: Clean up temporary files
del temp1.mq5
del temp2.mq5
del temp3.mq5

echo Fixes applied successfully!
echo Please recompile your EA to check if all errors are resolved.
pause
