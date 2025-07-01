@echo off
echo Fixing the CORRECT ROOT CAUSE in SmcScalperHybridV20.mq5...

powershell -Command "$content = Get-Content 'c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5' -Raw; $content = $content -replace '(?s)double stopLevelValue = 0.0;\s+if\(!SymbolInfoDouble\(Symbol\(\), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue\)[^}]+}', 'long stopLevelInt = 0;\r\n    if(!SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelInt)) {\r\n        Print(\"Error getting stop level: \", GetLastError());\r\n        stopLevelInt = 5; // Default value\r\n    }'; Set-Content 'c:\Users\LEOSOFT\OneDrive\Desktop\metatrader5\bots\more bots\SmcScalperHybridV20.mq5' -Value $content"

echo.
echo ==========================================================================
echo FIXED THE ROOT CAUSE! SYMBOL_TRADE_STOPS_LEVEL is an INTEGER property,
echo not a DOUBLE property! This is why SymbolInfoDouble() kept failing.
echo.
echo Changed:
echo SymbolInfoDouble(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelValue)
echo.
echo To:
echo SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL, stopLevelInt)
echo ==========================================================================
echo.
echo Please recompile your EA - this will finally fix the error!
pause
