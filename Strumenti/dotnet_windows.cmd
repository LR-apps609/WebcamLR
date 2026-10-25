@echo off
rem Preparazione comune degli script di Windows («Costruisci e avvia.bat», «Crea installer Windows.bat»): non va aperto da solo.
rem Dopo «call» ERRORLEVEL vale 0 se è tutto pronto, e ci sono PIATTAFORMA (x64 o ARM64) e RID (win-x64 o win-arm64).

set "DOTNET_CLI_TELEMETRY_OPTOUT=1"
set "DOTNET_NOLOGO=1"
set "DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1"

rem L'architettura del PC, anche se questa finestra fosse a 32 bit (allora PROCESSOR_ARCHITECTURE dice x86).
set "PIATTAFORMA=x64"
set "RID=win-x64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
  set "PIATTAFORMA=ARM64"
  set "RID=win-arm64"
)
if /i "%PROCESSOR_ARCHITEW6432%"=="ARM64" (
  set "PIATTAFORMA=ARM64"
  set "RID=win-arm64"
)

rem Il dotnet a 64 bit, sempre. Se nel PATH c'è prima quello a 32 bit («Program Files (x86)», senza SDK),
rem i comandi dicono che l'SDK manca anche quando c'è. ProgramW6432 è «C:\Program Files» anche da una finestra a 32 bit.
set "CARTELLA_DOTNET=%ProgramW6432%\dotnet"
if not defined ProgramW6432 set "CARTELLA_DOTNET=%ProgramFiles%\dotnet"
if not exist "%CARTELLA_DOTNET%\dotnet.exe" goto manca_sdk
set "PATH=%CARTELLA_DOTNET%;%PATH%"

rem Serve l'SDK di .NET 8 (il «Runtime» non basta): dotnet --list-sdks deve elencare una versione 8.
dotnet --list-sdks 2>nul | findstr /b "8." >nul || goto manca_sdk
exit /b 0

:manca_sdk
echo.
echo Manca .NET 8 SDK a 64 bit. Il "Runtime" non basta: serve l'SDK.
echo  1. Apri https://dotnet.microsoft.com/download/dotnet/8.0
echo  2. Nella colonna "SDK", riga "Windows", scegli "x64" (su un PC ARM: "Arm64") e installalo.
echo  3. Chiudi questa finestra e riapri lo script.
echo.
exit /b 1
