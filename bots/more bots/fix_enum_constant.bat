@echo off
echo Fixing MQL5 errors in SmcScalperHybridV20.mq5...

:: Create a temporary file with the correct enum value
powershell -Command "(Get-Content 'c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5') -replace 'SYMBOL_TRADE_STOP_LEVEL', 'SYMBOL_TRADE_STOPS_LEVEL' | Set-Content 'c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20_fixed.mq5'"

:: Replace the original file with the fixed version
copy /Y "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20_fixed.mq5" "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5"

:: Clean up temporary file
del "c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20_fixed.mq5"

echo Fixes applied successfully!
echo Changed SYMBOL_TRADE_STOP_LEVEL to SYMBOL_TRADE_STOPS_LEVEL (correct MQL5 enum)
echo Please recompile your EA to check if all errors are resolved.
pause
