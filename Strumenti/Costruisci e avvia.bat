@echo off
rem Doppio clic sul PC Windows: prova il protocollo, compila WebcamLR e la avvia.
cd /d "%~dp0\.."
rem Se nel PATH c'è prima il dotnet a 32 bit (Program Files (x86)), che non ha l'SDK, usa quello a 64 bit.
if exist "%ProgramFiles%\dotnet\dotnet.exe" set "PATH=%ProgramFiles%\dotnet;%PATH%"
rem Serve l'SDK di .NET 8 (non basta il "Runtime"): dotnet --list-sdks deve elencare una versione 8.
dotnet --list-sdks 2>nul | findstr /b "8." >nul || (
  echo.
  echo Manca .NET 8 SDK. Il "Runtime" non basta: serve l'SDK.
  echo Scaricalo da https://dotnet.microsoft.com/download/dotnet/8.0 ^(colonna SDK, Windows x64^),
  echo installalo, chiudi questa finestra e riapri il file.
  echo.
  pause
  exit /b 1
)

echo 1/2 - Test del protocollo
dotnet test Windows\WebcamLR.Protocollo.Test || goto errore
dotnet test Windows\WebcamLR.Ricevitore.Test || goto errore
dotnet test Windows\WebcamLR.Webcam.Logica.Test || goto errore

echo 2/2 - Compilo WebcamLR per Windows
rem Compila anche la webcam per le altre app (cartella Webcam accanto a WebcamLR.exe): basta il .NET SDK, niente C++.
dotnet build Windows\WebcamLR.App\WebcamLR.App.csproj -c Debug -p:Platform=x64 || goto errore

rem L'exe sta nella cartella win-x64 o direttamente sotto net8.0-windows…: dipende da come l'SDK sceglie l'architettura.
set "CARTELLA=Windows\WebcamLR.App\bin\x64\Debug\net8.0-windows10.0.19041.0"
if exist "%CARTELLA%\win-x64\WebcamLR.exe" (start "" "%CARTELLA%\win-x64\WebcamLR.exe" & exit /b 0)
if exist "%CARTELLA%\WebcamLR.exe" (start "" "%CARTELLA%\WebcamLR.exe" & exit /b 0)
echo.
echo Compilato, ma non trovo WebcamLR.exe in %CARTELLA%.
goto errore

:errore
echo.
echo Qualcosa non va: manda a Claude le righe in rosso qui sopra.
pause
exit /b 1
