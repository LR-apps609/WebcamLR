@echo off
chcp 65001 >nul
setlocal
rem Doppio clic sul PC Windows: prova il codice, compila WebcamLR e la avvia.
rem «Costruisci e avvia.bat veloce» (da una finestra del Prompt dei comandi) salta le prove.
rem Guida passo passo: Documenti\Windows - installazione e prova.md
cd /d "%~dp0\.."
call "%~dp0dotnet_windows.cmd" || goto fine_errore

if /i "%~1"=="veloce" goto compila
echo.
echo 1/3 - Provo protocollo, ricevitore, webcam, installatore ed effetti
dotnet test Windows\WebcamLR.Protocollo.Test --nologo || goto errore
dotnet test Windows\WebcamLR.Ricevitore.Test --nologo || goto errore
dotnet test Windows\WebcamLR.Webcam.Logica.Test --nologo || goto errore
dotnet test Windows\WebcamLR.Setup.Logica.Test --nologo || goto errore
dotnet test Windows\WebcamLR.Effetti.Test --nologo || goto errore

:compila
echo.
echo 2/3 - Compilo WebcamLR per Windows (%PIATTAFORMA%)
rem Una WebcamLR ancora aperta (anche solo con l'icona accanto all'orologio) blocca i file da sovrascrivere,
rem e la copia nuova passerebbe l'apertura a quella vecchia: si chiude prima di compilare.
tasklist /fi "imagename eq WebcamLR.exe" 2>nul | find /i "WebcamLR.exe" >nul && (
  echo Chiudo la WebcamLR ancora aperta...
  taskkill /im WebcamLR.exe /f >nul 2>&1
  timeout /t 2 /nobreak >nul
)
rem Compila anche la webcam per le altre app (cartella Webcam accanto a WebcamLR.exe): basta il .NET SDK, niente C++.
rem Dentro ci sono la sorgente per Windows 11 e il filtro DirectShow per Windows 10, anche a 32 bit (Webcam\x86).
rem La piattaforma (x64 o ARM64) la sceglie dotnet_windows.cmd dal PC: il progetto ne ricava il RuntimeIdentifier.
dotnet build Windows\WebcamLR.App\WebcamLR.App.csproj -c Debug -p:Platform=%PIATTAFORMA% --nologo || goto errore

rem L'exe e la cartella Webcam stanno sempre nella cartella del RuntimeIdentifier (win-x64 o win-arm64).
set "CARTELLA=Windows\WebcamLR.App\bin\%PIATTAFORMA%\Debug\net8.0-windows10.0.19041.0\%RID%"
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

echo.
echo 3/3 - Avvio WebcamLR
rem /D: l'app parte dalla sua cartella, come con un doppio clic sull'exe.
start "" /D "%CD%\%CARTELLA%" "%CD%\%CARTELLA%\WebcamLR.exe"
echo Fatto. La webcam per le altre app si installa dalla scheda «Webcam per le altre app».
timeout /t 5 >nul
exit /b 0

:errore
echo.
echo Qualcosa non va: manda a Claude le righe in rosso qui sopra (o una foto della finestra).
:fine_errore
pause
exit /b 1
