@echo off
chcp 65001 >nul
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
rem Una WebcamLR ancora aperta (anche solo con l'icona accanto all'orologio) blocca i file da sovrascrivere,
rem e la copia nuova passerebbe l'apertura a quella vecchia: si chiude prima di compilare.
tasklist /fi "imagename eq WebcamLR.exe" 2>nul | find /i "WebcamLR.exe" >nul && (
  echo Chiudo la WebcamLR ancora aperta...
  taskkill /im WebcamLR.exe /f >nul 2>&1
  timeout /t 2 /nobreak >nul
)
rem Compila anche la webcam per le altre app (cartella Webcam accanto a WebcamLR.exe): basta il .NET SDK, niente C++.
rem Dentro ci sono la sorgente per Windows 11 e il filtro DirectShow per Windows 10, anche a 32 bit (Webcam\x86).
rem Su un PC ARM64 sostituisci x64 con ARM64 qui e win-x64 con win-arm64 sotto.
dotnet build Windows\WebcamLR.App\WebcamLR.App.csproj -c Debug -p:Platform=x64 || goto errore

rem Il progetto fissa il RuntimeIdentifier dalla piattaforma: l'exe e la cartella Webcam stanno sempre in win-x64.
set "CARTELLA=Windows\WebcamLR.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64"
if not exist "%CARTELLA%\WebcamLR.exe" (
  echo.
  echo Compilato, ma non trovo WebcamLR.exe in %CARTELLA%.
  goto errore
)
if not exist "%CARTELLA%\Webcam\WebcamLR.Webcam.Installa.exe" (
  echo.
  echo Attenzione: manca la cartella Webcam accanto a WebcamLR.exe. L'app parte, ma la webcam per le altre app non si installa.
)
if not exist "%CARTELLA%\Webcam\x86\WebcamLR.Webcam.DirectShow.comhost.dll" (
  echo.
  echo Attenzione: manca il filtro DirectShow a 32 bit ^(Webcam\x86^). Su Windows 10 la webcam funziona solo nelle app a 64 bit.
)
rem /D: l'app parte dalla sua cartella, come con un doppio clic sull'exe.
start "" /D "%CD%\%CARTELLA%" "%CD%\%CARTELLA%\WebcamLR.exe"
exit /b 0

:errore
echo.
echo Qualcosa non va: manda a Claude le righe in rosso qui sopra.
pause
exit /b 1
