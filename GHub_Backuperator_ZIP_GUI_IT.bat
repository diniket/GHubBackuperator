@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ==========================================================
REM  G HUB BACKUPERATOR (ZIP + GUI) - ITA
REM  - Backup ZIP in percorso scelto con finestra "Salva con nome"
REM  - Restore ZIP scelto con finestra "Apri"
REM  - Ricorda ultimo percorso (config.ini)
REM  - Richiede privilegi amministratore (ProgramData)
REM  - Pulizia WORK robusta (retry + rename + RunOnce al reboot)
REM ==========================================================

REM --- Elevazione admin se necessario ---
call :IsAdmin
if errorlevel 1 (
  call :Elevate
  exit /b
)

REM --- Cartella Download ---
call :GetDownloadsFolder
if not defined DOWNLOADS set "DOWNLOADS=%USERPROFILE%\Downloads"

REM --- Config ---
set "CONFIGDIR=%LocalAppData%\GHubBackuperator"
set "CONFIGFILE=%CONFIGDIR%\config.ini"

REM --- Default ZIP (se non c'è config) ---
set "BACKUPZIP_DEFAULT=%DOWNLOADS%\GHub_Backup.zip"

REM --- Work dirs ---
set "WORKDIR=%DOWNLOADS%\GHub_Backup_WORK"
set "RESTORETMP=%TEMP%\GHub_Backup_RESTORE_TMP"
set "question=0"

REM --- Carica config ---
call :LoadConfig

cls
echo.
echo ********************************************************************************
echo.
echo                     G HUB BACKUPERATOR (ZIP + GUI)
echo.
echo   Percorso ZIP attuale (config o default):
echo     "%BACKUPZIP%"
echo.
echo ********************************************************************************
echo.

:Ask
echo *** Vuoi [C] CREARE un backup, [R] RIPRISTINARE un backup o [E] uscire? ***
set "INPUT="
set /P "INPUT=Inserisci scelta: "
if /I "%INPUT%"=="c" goto Backup
if /I "%INPUT%"=="r" goto Restore
if /I "%INPUT%"=="e" goto DoneNoAction
if /I "%INPUT%"=="upupdowndownleftrightleftrightba" goto Contra

echo.
echo ######################################
echo     Scelta non valida. Digita C, R o E.
echo ######################################
goto Ask


:Backup
set "question=1"

echo.
echo Verrà aperta una finestra per scegliere dove salvare il backup ZIP.
echo.

call :GuiPickSaveZip
if errorlevel 1 (
  echo.
  echo Operazione annullata o errore nella finestra di salvataggio.
  pause
  goto Ask
)

call :SaveConfig
call :EnsureZipParentExists "%BACKUPZIP%"

echo.
echo ********************************************************************************
echo.
echo                    BACKUP IMPOSTAZIONI G HUB (ZIP)
echo.
echo   Output:
echo     "%BACKUPZIP%"
echo.
echo ********************************************************************************
echo.

:AskBackup
echo *** Procedere? [Y] Sì [N] No ***
set "INPUT="
set /P "INPUT=Inserisci scelta: "
if /I "%INPUT%"=="y" goto YesBackup
if /I "%INPUT%"=="n" goto DoneNoAction
if /I "%INPUT%"=="upupdowndownleftrightleftrightba" goto Contra

echo.
echo ##################################
echo     Scelta non valida. Digita Y o N.
echo ##################################
goto AskBackup

:YesBackup
echo.
echo Chiusura processi G Hub, copia file e creazione ZIP...
echo.
timeout /t 2 >nul

call :ShutdownGHub
call :RemovePreviousBackupArtifacts
call :CreateBackupToWorkDir
call :ZipWorkDir
call :CleanupWorkDirSafe

echo.
echo ********************************************************************************
echo.
echo                               OPERAZIONE COMPLETATA
echo.
echo   Backup ZIP creato in:
echo     "%BACKUPZIP%"
echo.
echo ********************************************************************************
echo.
pause
exit /b 0


:Restore
set "question=2"

echo.
echo Verrà aperta una finestra per scegliere il file ZIP da ripristinare.
echo.

call :GuiPickOpenZip
if errorlevel 1 (
  echo.
  echo Operazione annullata o errore nella finestra di selezione file.
  pause
  goto Ask
)

call :SaveConfig

echo.
echo ********************************************************************************
echo.
echo                  RIPRISTINO IMPOSTAZIONI G HUB (ZIP)
echo.
echo   File ZIP:
echo     "%BACKUPZIP%"
echo.
echo   ATTENZIONE:
echo   - Le cartelle attuali verranno ELIMINATE prima del ripristino
echo.
echo ********************************************************************************
echo.

:AskRestore
echo *** Procedere? [Y] Sì [N] No ***
set "INPUT="
set /P "INPUT=Inserisci scelta: "
if /I "%INPUT%"=="y" goto YesRestore
if /I "%INPUT%"=="n" goto DoneNoAction
if /I "%INPUT%"=="upupdowndownleftrightleftrightba" goto Contra

echo.
echo ##################################
echo     Scelta non valida. Digita Y o N.
echo ##################################
goto AskRestore

:YesRestore
echo.
echo Verifica ZIP, estrazione temporanea, chiusura G Hub, ripristino...
echo.
timeout /t 2 >nul

call :VerifyZip || goto MissingRestore
call :ExtractZipToTemp || goto MissingRestore

call :ShutdownGHub
call :DeleteCurrentSettings
call :RestoreFromExtracted
call :CleanupRestoreTemp

echo.
echo ********************************************************************************
echo.
echo                               OPERAZIONE COMPLETATA
echo.
echo ********************************************************************************
echo.
pause
exit /b 0


REM ==========================================================
REM                     CONFIG
REM ==========================================================

:LoadConfig
set "BACKUPZIP=%BACKUPZIP_DEFAULT%"
if exist "%CONFIGFILE%" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIGFILE%") do (
    if /I "%%A"=="BACKUPZIP" set "BACKUPZIP=%%B"
  )
)
exit /b 0

:SaveConfig
if not exist "%CONFIGDIR%" mkdir "%CONFIGDIR%" >nul 2>&1
(
  echo BACKUPZIP=%BACKUPZIP%
) > "%CONFIGFILE%"
exit /b 0

:EnsureZipParentExists
set "ZIPPATH=%~1"
for %%D in ("%ZIPPATH%") do set "ZIPDIR=%%~dpD"
if not exist "%ZIPDIR%" mkdir "%ZIPDIR%" >nul 2>&1
exit /b 0


REM ==========================================================
REM                     GUI PICKERS (STA + Try/Catch)
REM ==========================================================

:GuiPickSaveZip
REM Ritorna errorlevel 1 se annullato o errore; altrimenti setta BACKUPZIP
set "PICKED="

for /f "usebackq delims=" %%P in (`
  powershell -NoProfile -STA -ExecutionPolicy Bypass -Command ^
  "Try { " ^
  "  Add-Type -AssemblyName System.Windows.Forms | Out-Null; " ^
  "  $dlg = New-Object System.Windows.Forms.SaveFileDialog; " ^
  "  $dlg.Filter = 'Zip (*.zip)|*.zip'; " ^
  "  $dlg.Title = 'Scegli dove salvare il backup ZIP'; " ^
  "  $dlg.OverwritePrompt = $true; " ^
  "  $dlg.AddExtension = $true; " ^
  "  $dlg.DefaultExt = 'zip'; " ^
  "  $dlg.FileName = [System.IO.Path]::GetFileName('%BACKUPZIP%'); " ^
  "  $initDir = [System.IO.Path]::GetDirectoryName('%BACKUPZIP%'); " ^
  "  if ([string]::IsNullOrWhiteSpace($initDir) -or -not (Test-Path $initDir)) { $initDir = [Environment]::GetFolderPath('MyDocuments') } " ^
  "  $dlg.InitialDirectory = $initDir; " ^
  "  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dlg.FileName } else { 'CANCEL' } " ^
  "} Catch { 'ERROR:' + $_.Exception.Message }"
`) do set "PICKED=%%P"

if not defined PICKED exit /b 1
if /I "%PICKED%"=="CANCEL" exit /b 1
echo %PICKED% | findstr /b /i "ERROR:" >nul && (
  echo.
  echo [ERRORE GUI] %PICKED%
  exit /b 1
)

set "BACKUPZIP=%PICKED%"
exit /b 0


:GuiPickOpenZip
REM Ritorna errorlevel 1 se annullato o errore; altrimenti setta BACKUPZIP
set "PICKED="

for /f "usebackq delims=" %%P in (`
  powershell -NoProfile -STA -ExecutionPolicy Bypass -Command ^
  "Try { " ^
  "  Add-Type -AssemblyName System.Windows.Forms | Out-Null; " ^
  "  $dlg = New-Object System.Windows.Forms.OpenFileDialog; " ^
  "  $dlg.Filter = 'Zip (*.zip)|*.zip'; " ^
  "  $dlg.Title = 'Seleziona il file ZIP di backup da ripristinare'; " ^
  "  $dlg.Multiselect = $false; " ^
  "  $initDir = [System.IO.Path]::GetDirectoryName('%BACKUPZIP%'); " ^
  "  if ([string]::IsNullOrWhiteSpace($initDir) -or -not (Test-Path $initDir)) { $initDir = [Environment]::GetFolderPath('MyDocuments') } " ^
  "  $dlg.InitialDirectory = $initDir; " ^
  "  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dlg.FileName } else { 'CANCEL' } " ^
  "} Catch { 'ERROR:' + $_.Exception.Message }"
`) do set "PICKED=%%P"

if not defined PICKED exit /b 1
if /I "%PICKED%"=="CANCEL" exit /b 1
echo %PICKED% | findstr /b /i "ERROR:" >nul && (
  echo.
  echo [ERRORE GUI] %PICKED%
  exit /b 1
)

set "BACKUPZIP=%PICKED%"
exit /b 0


REM ==========================================================
REM                     CORE ROUTINES
REM ==========================================================

:IsAdmin
fsutil dirty query %SystemDrive% >nul 2>&1
if errorlevel 1 (exit /b 1) else (exit /b 0)

:Elevate
set "vbs=%temp%\_ghub_elevate.vbs"
(
  echo Set UAC = CreateObject^("Shell.Application"^)
  echo UAC.ShellExecute "%~f0", "", "", "runas", 1
) > "%vbs%"
cscript //nologo "%vbs%" >nul 2>&1
del /f /q "%vbs%" >nul 2>&1
exit /b 0

:GetDownloadsFolder
set "DOWNLOADS="
for /f "usebackq tokens=2,*" %%A in (`reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v "{374DE290-123F-4565-9164-39C4925E467B}" 2^>nul`) do (
  set "DOWNLOADS=%%B"
)
exit /b 0


:ShutdownGHub
call :KillIfRunning "lghub.exe"
call :KillIfRunning "lghub_agent.exe"
call :KillIfRunning "lghub_system_tray.exe"
exit /b 0

:KillIfRunning
set "PROC=%~1"
tasklist /fi "imagename eq %PROC%" 2>nul | find /I "%PROC%" >nul
if not errorlevel 1 taskkill /f /im "%PROC%" >nul 2>&1
exit /b 0


:RemovePreviousBackupArtifacts
if exist "%BACKUPZIP%" del /f /q "%BACKUPZIP%" >nul 2>&1
if exist "%WORKDIR%" (
  attrib -r -s -h "%WORKDIR%" /s /d >nul 2>&1
  rmdir /s /q "%WORKDIR%" >nul 2>&1
)
exit /b 0


:CreateBackupToWorkDir
mkdir "%WORKDIR%" >nul 2>&1
xcopy "%LocalAppData%\LGHUB\" "%WORKDIR%\AppData\Local\LGHUB\" /E /H /I /K /Y /Q >nul
xcopy "%AppData%\G HUB\" "%WORKDIR%\AppData\Roaming\G HUB\" /E /H /I /K /Y /Q >nul
xcopy "%AppData%\lghub\" "%WORKDIR%\AppData\Roaming\lghub\" /E /H /I /K /Y /Q >nul
xcopy "%ProgramData%\LGHUB\" "%WORKDIR%\ProgramData\LGHUB\" /E /H /I /K /Y /Q >nul
exit /b 0


:ZipWorkDir
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Try { Compress-Archive -Path '%WORKDIR%\*' -DestinationPath '%BACKUPZIP%' -Force -ErrorAction Stop; exit 0 } Catch { Write-Host $_; exit 1 }"
if errorlevel 1 (
  echo.
  echo ERRORE: creazione ZIP fallita.
  pause
  exit /b 1
)
exit /b 0


:CleanupWorkDirSafe
timeout /t 2 >nul
rmdir /s /q "%WORKDIR%" >nul 2>&1
if not exist "%WORKDIR%" exit /b 0

attrib -r -s -h "%WORKDIR%" /s /d >nul 2>&1
rmdir /s /q "%WORKDIR%" >nul 2>&1
if not exist "%WORKDIR%" exit /b 0

set "RENAMED=%DOWNLOADS%\GHub_Backup_WORK_OLD_%RANDOM%%RANDOM%"
ren "%WORKDIR%" "%~nxRENAMED%" >nul 2>&1
if exist "%RENAMED%" (
  set "WORKDIR=%RENAMED%"
  rmdir /s /q "%WORKDIR%" >nul 2>&1
  if not exist "%WORKDIR%" exit /b 0
)

set "CMDDEL=cmd.exe /c rmdir /s /q ""%WORKDIR%"""
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce" ^
 /v "GHubBackupWorkCleanup" /t REG_SZ /d "%CMDDEL%" /f >nul 2>&1

exit /b 0


:VerifyZip
if not exist "%BACKUPZIP%" exit /b 1
exit /b 0


:ExtractZipToTemp
if exist "%RESTORETMP%" (
  attrib -r -s -h "%RESTORETMP%" /s /d >nul 2>&1
  rmdir /s /q "%RESTORETMP%" >nul 2>&1
)
mkdir "%RESTORETMP%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Try { Expand-Archive -Path '%BACKUPZIP%' -DestinationPath '%RESTORETMP%' -Force -ErrorAction Stop; exit 0 } Catch { Write-Host $_; exit 1 }"
if errorlevel 1 exit /b 1

if not exist "%RESTORETMP%\ProgramData\LGHUB\" exit /b 1
if not exist "%RESTORETMP%\AppData\Local\LGHUB\" exit /b 1
if not exist "%RESTORETMP%\AppData\Roaming\lghub\" exit /b 1
if not exist "%RESTORETMP%\AppData\Roaming\G HUB\" exit /b 1
exit /b 0


:DeleteCurrentSettings
rmdir /s /q "%LocalAppData%\LGHUB\" >nul 2>&1
rmdir /s /q "%AppData%\lghub\" >nul 2>&1
rmdir /s /q "%AppData%\G HUB\" >nul 2>&1
rmdir /s /q "%ProgramData%\LGHUB\" >nul 2>&1
exit /b 0


:RestoreFromExtracted
xcopy "%RESTORETMP%\AppData\Local\LGHUB\" "%LocalAppData%\LGHUB\" /E /H /I /K /Y /Q >nul
xcopy "%RESTORETMP%\AppData\Roaming\lghub\" "%AppData%\lghub\" /E /H /I /K /Y /Q >nul
xcopy "%RESTORETMP%\AppData\Roaming\G HUB\" "%AppData%\G HUB\" /E /H /I /K /Y /Q >nul
xcopy "%RESTORETMP%\ProgramData\LGHUB\" "%ProgramData%\LGHUB\" /E /H /I /K /Y /Q >nul
exit /b 0


:CleanupRestoreTemp
if exist "%RESTORETMP%" (
  attrib -r -s -h "%RESTORETMP%" /s /d >nul 2>&1
  rmdir /s /q "%RESTORETMP%" >nul 2>&1
)
exit /b 0


:MissingRestore
echo.
echo ********************************************************************************
echo.
echo   Backup ZIP non trovato / incompleto oppure estrazione fallita.
echo   Ripristino annullato.
echo.
echo ********************************************************************************
echo.
pause
exit /b 1


:DoneNoAction
echo.
echo Nessuna operazione eseguita. Uscita.
pause
exit /b 0


:Contra
echo.
echo Codice segreto rilevato. Premio: assolutamente niente.
echo.
if "%question%"=="0" goto Ask
if "%question%"=="1" goto AskBackup
if "%question%"=="2" goto AskRestore
goto Ask
