@echo off
REM ============================================================================
REM Script CMD para ejecutar BackupRemoto.ps1
REM Compatible con Windows Server 2012 y versiones posteriores
REM ============================================================================

setlocal

REM Cambiar al directorio donde está ubicado este script
cd /d "%~dp0"

REM Mostrar información inicial
echo.
echo ==========================================
echo   SISTEMA DE BACKUP REMOTO POWERSHELL
echo ==========================================
echo.
echo Iniciando backup desde: %~dp0
echo Fecha y hora: %date% %time%
echo.

REM Verificar que PowerShell esté disponible
powershell.exe -Command "Write-Host 'PowerShell disponible'" >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell no está disponible en este sistema
    echo.
    pause
    exit /b 1
)

REM Verificar que el script principal existe
if not exist "BackupRemoto.ps1" (
    echo ERROR: No se encontró BackupRemoto.ps1 en el directorio actual
    echo Directorio actual: %CD%
    echo.
    pause
    exit /b 1
)

echo Ejecutando backup...
echo.

REM Ejecutar el script de PowerShell con parámetros optimizados
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& '%~dp0BackupRemoto.ps1'"

REM Capturar el código de salida
set EXITCODE=%ERRORLEVEL%

echo.
echo ==========================================
if %EXITCODE%==0 (
    echo   BACKUP COMPLETADO EXITOSAMENTE
    echo ==========================================
    echo.
    echo El backup se ejecutó sin errores.
) else (
    echo   BACKUP COMPLETADO CON ERRORES
    echo ==========================================
    echo.
    echo El backup terminó con código de error: %EXITCODE%
    echo Revise los logs para más información.
)

echo.
echo Presione cualquier tecla para continuar...
pause >nul

exit /b %EXITCODE%
