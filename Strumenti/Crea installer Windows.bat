@echo off
chcp 65001 >nul
setlocal
rem Doppio clic sul PC Windows: prova il codice e costruisce l'installatore «WebcamLR-Setup-<versione>.exe»
rem nella cartella Distribuzione (quello da dare agli altri o da mettere sul sito). Alla fine chiede se installarlo qui.
rem Il lavoro lo fa Windows\WebcamLR.Setup\Pacchetto.proj. Guida: Documenti\Windows - installazione e prova.md
cd /d "%~dp0\.."
call "%~dp0dotnet_windows.cmd" || goto fine_errore

echo.
echo 1/2 - Provo webcam e installatore
dotnet test Windows\WebcamLR.Webcam.Logica.Test --nologo || goto errore
dotnet test Windows\WebcamLR.Setup.Logica.Test --nologo || goto errore

echo.
echo 2/2 - Costruisco l'installatore (%PIATTAFORMA%): la prima volta ci vogliono alcuni minuti
dotnet msbuild Windows\WebcamLR.Setup\Pacchetto.proj -p:Platform=%PIATTAFORMA% -nologo -v:m || goto errore

set "SETUP="
for /f "delims=" %%f in ('dir /b /o:d "Distribuzione\WebcamLR-Setup-*.exe" 2^>nul') do set "SETUP=%%f"
if not defined SETUP (
  echo.
  echo Costruito, ma non trovo l'installatore nella cartella Distribuzione.
  goto errore
)
echo.
echo Fatto: Distribuzione\%SETUP%
echo Non è firmato: chi lo apre vede l'avviso blu di Windows, poi «Ulteriori informazioni» e «Esegui comunque».
start "" explorer "%CD%\Distribuzione"
echo.
choice /c SN /m "Lo installo adesso su questo PC"
if errorlevel 2 exit /b 0
start "" "%CD%\Distribuzione\%SETUP%"
exit /b 0

:errore
echo.
echo Qualcosa non va: manda a Claude le righe in rosso qui sopra (o una foto della finestra).
:fine_errore
pause
exit /b 1
