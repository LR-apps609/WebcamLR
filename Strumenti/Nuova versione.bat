@echo off
chcp 65001 >nul
rem Doppio clic sul PC Windows (oppure: "Strumenti\Nuova versione.bat" 1.1).
rem Cambia la versione di WebcamLR in Strumenti\Versione.xcconfig, l'unica fonte per Mac, iPhone, Windows e Android,
rem e fa salire di uno il numero di build. Con Invio senza scrivere niente sale solo il numero di build.
cd /d "%~dp0\.."
set "NUOVA=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$f='Strumenti\Versione.xcconfig'; $t=[IO.File]::ReadAllText($f);" ^
  "$v=[regex]::Match($t,'(?m)^\s*MARKETING_VERSION\s*=\s*(\S+)\s*$').Groups[1].Value;" ^
  "$b=[regex]::Match($t,'(?m)^\s*CURRENT_PROJECT_VERSION\s*=\s*(\d+)\s*$').Groups[1].Value;" ^
  "if(-not $v -or -not $b){ Write-Host 'Non leggo versione e numero di build in' $f; exit 1 }" ^
  "Write-Host ('Versione attuale: '+$v+' (build '+$b+')');" ^
  "$n=$env:NUOVA; if(-not $n){ $n=Read-Host ('Nuova versione (per esempio 1.1 o 1.0.1; Invio = resta '+$v+')') }; if(-not $n){ $n=$v };" ^
  "if($n -notmatch '^\d+\.\d+(\.\d+)?$'){ Write-Host ($n+' non va bene: scrivi due o tre numeri separati da punti, come 1.1 o 1.0.1.'); exit 1 }" ^
  "$nb=[int]$b+1;" ^
  "$t=[regex]::Replace($t,'(?m)^(\s*MARKETING_VERSION\s*=\s*)\S+',('${1}'+$n));" ^
  "$t=[regex]::Replace($t,'(?m)^(\s*CURRENT_PROJECT_VERSION\s*=\s*)\d+',('${1}'+$nb));" ^
  "[IO.File]::WriteAllText($f,$t,(New-Object Text.UTF8Encoding $false));" ^
  "Write-Host ('Fatto: WebcamLR '+$n+' (build '+$nb+'). Ricordati di fare il commit di '+$f+'.')"
if errorlevel 1 (
  echo.
  echo La versione non è cambiata.
)
if "%~1"=="" pause
