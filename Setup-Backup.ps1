#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Instalador y configurador del Sistema de Backup PowerShell

.DESCRIPTION
    Configura el entorno necesario para ejecutar el sistema de backup,
    incluyendo tareas programadas y verificacion de dependencias

.PARAMETER Install
    Instala la tarea programada

.PARAMETER Uninstall
    Desinstala la tarea programada

.PARAMETER Test
    Ejecuta pruebas de configuracion

.PARAMETER SetupRclone
    Ayuda a configurar el remote de rclone

.EXAMPLE
    .\Setup-Backup.ps1 -Test
    .\Setup-Backup.ps1 -SetupRclone
    .\Setup-Backup.ps1 -Install
    .\Setup-Backup.ps1 -Uninstall
#>

[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Test,
    [switch]$SetupRclone
)

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupScript = Join-Path $ScriptPath "BackupRemoto.ps1"
$ConfigScript = Join-Path $ScriptPath "BackupConfig.ps1"
$UserConfigScript = Join-Path $ScriptPath "UserConfig.ps1"

function Test-Dependencies {
    Write-Host "Verificando dependencias..." -ForegroundColor Cyan
    
    # Cargar configuración del sistema
    $Config = & $ConfigScript
    
    # Cargar configuración de usuario si existe
    if (Test-Path $UserConfigScript) {
        $UserConfig = & $UserConfigScript
        # Combinar configuraciones
        foreach ($key in $UserConfig.Keys) {
            $Config[$key] = $UserConfig[$key]
        }
        Write-Host "[OK] Configuración de usuario encontrada" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Archivo de configuración de usuario no encontrado: UserConfig.ps1" -ForegroundColor Yellow
        Write-Host "  Se recomienda crear UserConfig.ps1 basado en UserConfig.ps1.example" -ForegroundColor Yellow
    }
    
    $Issues = @()
    
    # Verificar WinRAR
    if (-not (Test-Path $Config.WinRarPath)) {
        $Issues += "WinRAR no encontrado en: $($Config.WinRarPath)"
    } else {
        Write-Host "[OK] WinRAR encontrado" -ForegroundColor Green
    }
    
    # Verificar rclone
    if (-not (Test-Path $Config.RclonePath)) {
        $Issues += "rclone no encontrado en: $($Config.RclonePath)"
    } else {
        Write-Host "[OK] rclone encontrado" -ForegroundColor Green
        
        # Verificar configuración de rclone
        try {
            $RcloneConfigTest = & $Config.RclonePath config show $Config.RcloneRemote 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Remote '$($Config.RcloneRemote)' configurado en rclone" -ForegroundColor Green
            } else {
                $Issues += "Remote '$($Config.RcloneRemote)' no configurado en rclone. Ejecute: rclone config"
            }
        }
        catch {
            $Issues += "Error verificando configuración de rclone: $($_.Exception.Message)"
        }
    }
    
    # Verificar directorios de origen
    foreach ($Source in $Config.DocumentosSource) {
        $CleanSource = $Source.Replace('\*', '').Replace('/*', '')
        if (-not (Test-Path $CleanSource)) {
            $Issues += "Directorio de documentos no encontrado: $CleanSource"
        } else {
            Write-Host "[OK] Directorio documentos: $CleanSource" -ForegroundColor Green
        }
    }
    
    # Verificar directorios de usuarios (múltiples fuentes)
    $UsuariosFoundCount = 0
    foreach ($UsuariosPath in $Config.UsuariosSource) {
        if (Test-Path $UsuariosPath) {
            Write-Host "[OK] Directorio usuarios: $UsuariosPath" -ForegroundColor Green
            $UsuariosFoundCount++
        } else {
            Write-Host "[WARN] Directorio usuarios no encontrado: $UsuariosPath" -ForegroundColor Yellow
        }
    }
    
    if ($UsuariosFoundCount -eq 0) {
        Write-Host "[WARN] Ninguna fuente de usuarios encontrada" -ForegroundColor Yellow
        Write-Host "  Se usara C:\Users\ como alternativa" -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Fuentes de usuarios encontradas: $UsuariosFoundCount de $($Config.UsuariosSource.Count)" -ForegroundColor Green
    }
    
    # Verificar directorio temporal
    if (-not (Test-Path $Config.TempDir)) {
        try {
            New-Item -ItemType Directory -Path $Config.TempDir -Force | Out-Null
            Write-Host "[OK] Directorio temporal creado: $($Config.TempDir)" -ForegroundColor Green
        }
        catch {
            $Issues += "No se puede crear directorio temporal: $($Config.TempDir)"
        }
    } else {
        Write-Host "[OK] Directorio temporal: $($Config.TempDir)" -ForegroundColor Green
    }
    
    return $Issues
}

function Install-ScheduledTask {
    Write-Host "Instalando tarea programada..." -ForegroundColor Cyan
    
    $TaskName = "BackupRemoto-PowerShell"
    $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    
    Write-Host "Usuario para la tarea: $CurrentUser" -ForegroundColor Cyan
    
    # Eliminar tarea existente si existe
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Tarea existente eliminada" -ForegroundColor Yellow
    }
    
    # Crear acción
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$BackupScript`""
    
    # Crear trigger (diario a las 23:00)
    $Trigger = New-ScheduledTaskTrigger -Daily -At "23:00"
    
    # Configuración principal - Usar el usuario actual
    $Principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Highest
    
    # Configuración de la tarea
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    
    # Registrar tarea
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Description "Sistema de Backup Remoto PowerShell - Ejecuta backup automatico diario con usuario $CurrentUser"
    
    Write-Host "[OK] Tarea programada instalada: $TaskName" -ForegroundColor Green
    Write-Host "  Usuario: $CurrentUser" -ForegroundColor Gray
    Write-Host "  Programada para ejecutarse diariamente a las 23:00" -ForegroundColor Gray
}

function Uninstall-ScheduledTask {
    Write-Host "Desinstalando tarea programada..." -ForegroundColor Cyan
    
    $TaskName = "BackupRemoto-PowerShell"
    
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[OK] Tarea eliminada: $TaskName" -ForegroundColor Green
    } else {
        Write-Host "No se encontro la tarea: $TaskName" -ForegroundColor Yellow
    }
}

function Setup-RcloneRemote {
    Write-Host "Configurando remote de rclone..." -ForegroundColor Cyan
    
    $Config = & $ConfigScript
    
    Write-Host @"

=== CONFIGURACIÓN DE RCLONE ===

Para configurar el remote '$($Config.RcloneRemote)', ejecute:

1. rclone config
2. Seleccione 'n' para nuevo remote
3. Nombre del remote: $($Config.RcloneRemote)
4. Seleccione el tipo de storage apropiado para su servidor
5. Complete la configuración según su proveedor

"@ -ForegroundColor Yellow
    
    $Response = Read-Host "¿Desea abrir la configuración de rclone ahora? (s/n)"
    if ($Response -eq 's' -or $Response -eq 'S') {
        & $Config.RclonePath config
    }
}

function Show-Usage {
    Write-Host @"

=== SISTEMA DE BACKUP REMOTO POWERSHELL ===

INSTALACIÓN:
1. Instalar rclone desde: https://rclone.org/downloads/
2. Ejecutar como Administrador: .\Setup-Backup.ps1 -Test
3. Si falta configuración de rclone: .\Setup-Backup.ps1 -SetupRclone
4. Si las pruebas son exitosas: .\Setup-Backup.ps1 -Install

EJECUCIÓN MANUAL:
   .\BackupRemoto.ps1          # Backup normal (diferencial/completo según día)
   .\BackupRemoto.ps1 -Force   # Forzar backup completo

CONFIGURACIÓN:
   Editar BackupConfig.ps1 para personalizar rutas y configuraciones
   Remote de rclone debe llamarse: backupremoto

DESINSTALACIÓN:
   .\Setup-Backup.ps1 -Uninstall

"@ -ForegroundColor White
}

# Script principal
if ($Test) {
    $Issues = Test-Dependencies
    
    if ($Issues.Count -eq 0) {
        Write-Host "`n[OK] TODAS LAS VERIFICACIONES PASARON" -ForegroundColor Green
        Write-Host "El sistema esta listo para usar" -ForegroundColor Green
    } else {
        Write-Host "`n[ERROR] SE ENCONTRARON PROBLEMAS:" -ForegroundColor Red
        foreach ($Issue in $Issues) {
            Write-Host "  - $Issue" -ForegroundColor Red
        }
        Write-Host "`nCorrige estos problemas antes de continuar" -ForegroundColor Yellow
    }
}
elseif ($Install) {
    $Issues = Test-Dependencies
    
    if ($Issues.Count -eq 0) {
        Install-ScheduledTask
        Write-Host "`n[OK] INSTALACION COMPLETADA" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] No se puede instalar. Hay problemas de configuracion:" -ForegroundColor Red
        foreach ($Issue in $Issues) {
            Write-Host "  - $Issue" -ForegroundColor Red
        }
    }
}
elseif ($SetupRclone) {
    Setup-RcloneRemote
}
elseif ($Uninstall) {
    Uninstall-ScheduledTask
}
else {
    Show-Usage
}
