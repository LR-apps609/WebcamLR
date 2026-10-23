@echo off
rem Doppio clic sul PC Windows: prova il protocollo, compila WebcamLR e la avvia.
cd /d "%~dp0\.."
where dotnet >nul 2>nul || (echo Serve .NET 8 SDK: https://dotnet.microsoft.com/download & pause & exit /b 1)

echo 1/2 - Test del protocollo
dotnet test Windows\WebcamLR.Protocollo.Test || goto errore
dotnet test Windows\WebcamLR.Ricevitore.Test || goto errore

echo 2/2 - Compilo WebcamLR per Windows
dotnet build Windows\WebcamLR.App\WebcamLR.App.csproj -c Debug -p:Platform=x64 || goto errore

start "" "Windows\WebcamLR.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\WebcamLR.exe"
exit /b 0

:errore
echo.
echo Qualcosa non va: manda a Claude le righe in rosso qui sopra.
pause
exit /b 1
