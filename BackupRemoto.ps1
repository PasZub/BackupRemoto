#Requires -Version 5.1
<#
.SYNOPSIS
    Sistema de Backup Remoto PowerShell
    Replica la funcionalidad del sistema batch original

.DESCRIPTION
    Script que realiza backup diferencial/completo de documentos y usuarios,
    comprime con WinRAR y sube archivos con rclone

.PARAMETER Force
    Fuerza backup completo independientemente del día

.EXAMPLE
    .\BackupRemoto.ps1
    .\BackupRemoto.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force
)

# Configuración del entorno - Cargar desde archivos externos
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptPath "BackupConfig.ps1"
$UserConfigPath = Join-Path $ScriptPath "UserConfig.ps1"

if (Test-Path $ConfigPath) {
    $Config = & $ConfigPath
} else {
    # Configuración por defecto si no existe el archivo
    $Config = @{
        RclonePath   = "rclone.exe"
        WinRarPath   = "C:\Program Files\WinRAR\winrar.exe"
        WorkingDir   = "\Programas\Nube"
        TempDir      = "E:\send1"
        RcloneRemote = "InfoCloud"
        RcloneConfig = ""
        RcloneUploadOnly = $true
        RcloneRetryCount = 3
        RcloneBandwidth = "0"
        RcloneProgress = $true
        RcloneDeleteOlderThan = 30
        RcloneDeleteEnabled = $true
        RemotePath   = "/buffer/"
        LogEnabled   = $true
        LogPath      = "E:\send1\BackupLogs"
        LogRetentionDays = 30
    }
}

# Cargar configuración de usuario y combinar con configuración del sistema
if (Test-Path $UserConfigPath) {
    $UserConfig = & $UserConfigPath
    # Combinar configuraciones (UserConfig tiene prioridad)
    foreach ($key in $UserConfig.Keys) {
        $Config[$key] = $UserConfig[$key]
    }
    Write-Verbose "Configuración de usuario cargada desde: $UserConfigPath"
} else {
    Write-Warning "Archivo de configuración de usuario no encontrado: $UserConfigPath"
    Write-Warning "Usando configuración por defecto para backups"
    
    # Configuración por defecto de usuario si no existe el archivo
    $DefaultUserConfig = @{
        DocumentosEnabled = $false
        DocumentosSource = @()
        DocumentosExclude = @("*.tmp", "*.bak")
        UsuariosEnabled = $false
        UsuariosSource = @("C:\Users")
        UsuariosExclude = @("*.pst", "*.exe", "*.tmp")
        ProgramasEnabled = $false
        ProgramasSource = @()
        ProgramasExclude = @("*.exe", "*.tmp")
    }
    
    foreach ($key in $DefaultUserConfig.Keys) {
        $Config[$key] = $DefaultUserConfig[$key]
    }
}

# Funciones auxiliares
function Write-ColoredOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
    
    # También escribir al log si está habilitado
    if ($Config.LogEnabled) {
        Write-Log $Message
    }
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    if (-not $Config.LogEnabled) { return }
    
    try {
        # Crear directorio de logs si no existe
        if (-not (Test-Path $Config.LogPath)) {
            New-Item -ItemType Directory -Path $Config.LogPath -Force | Out-Null
        }
        
        # Generar nombre de archivo de log
        $LogFile = Join-Path $Config.LogPath "Backup_$(Get-Date -Format 'yyyyMMdd').log"
        
        # Formato del mensaje de log
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogMessage = "[$Timestamp] [$Level] $Message"
        
        # Escribir al archivo de log
        Add-Content -Path $LogFile -Value $LogMessage -Encoding UTF8
        
        # Limpiar logs antiguos
        Clear-OldLogs
    }
    catch {
        # Si falla el logging, no interrumpir el proceso principal
        Write-Warning "Error escribiendo log: $($_.Exception.Message)"
    }
}

function Clear-OldLogs {
    try {
        if ((Test-Path $Config.LogPath) -and $Config.LogRetentionDays -gt 0) {
            $CutoffDate = (Get-Date).AddDays(-$Config.LogRetentionDays)
            Get-ChildItem -Path $Config.LogPath -Filter "*.log" | 
                Where-Object { $_.LastWriteTime -lt $CutoffDate } | 
                Remove-Item -Force
        }
    }
    catch {
        Write-Warning "Error limpiando logs antiguos: $($_.Exception.Message)"
    }
}
B
function Initialize-Environment {
    Write-ColoredOutput "Inicializando entorno de backup..." "Cyan"
    
    # Cambiar al directorio de trabajo
    if (Test-Path $Config.WorkingDir) {
        Set-Location $Config.WorkingDir
    }
    
    # Crear directorio temporal
    if (-not (Test-Path $Config.TempDir)) {
        New-Item -ItemType Directory -Path $Config.TempDir -Force | Out-Null
        Write-ColoredOutput "Directorio temporal creado: $($Config.TempDir)" "Green"
    }
    
    # Calcular fechas y tipo de backup
    $script:FechaActual = Get-Date -Format "yyyyMMdd"
    $script:DiaSemanaNombre = (Get-Date).DayOfWeek
    $script:DiaSemanaNumero = [int](Get-Date).DayOfWeek
    
    # Determinar tipo de backup (0=Completo, 1=Diferencial)
    if ($Force -or $script:DiaSemanaNombre -eq "Wednesday" -or $script:DiaSemanaNombre -eq "Sunday") {
        $script:TipoDiferencial = 0
        $script:TipoBackup = "COMPLETO"
    } else {
        $script:TipoDiferencial = 1
        $script:TipoBackup = "DIFERENCIAL"
    }
    
    $script:DiasAtras = $script:DiaSemanaNumero
    
    Write-ColoredOutput "Fecha: $script:FechaActual | Día: $script:DiaSemanaNombre | Tipo: $script:TipoBackup" "Yellow"
}

function Invoke-WinRarCompress {
    param(
        [string]$ArchiveName,
        [string[]]$IncludeFiles,
        [string[]]$ExcludeExtensions,
        [int]$Diferencial
    )
    
    Write-ColoredOutput "Comprimiendo: $ArchiveName" "Magenta"
    
    # Verificar si existen archivos para procesar
    $FilesFound = $false
    foreach ($IncludePath in $IncludeFiles) {
        $CleanPath = $IncludePath.Replace('\*', '').Replace('/*', '')
        Write-ColoredOutput "Verificando ruta: $CleanPath" "Cyan"
        
        if (Test-Path $CleanPath) {
            $FilesCount = (Get-ChildItem -Path $CleanPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
            Write-ColoredOutput "Archivos encontrados en $CleanPath`: $FilesCount" "Cyan"
            if ($FilesCount -gt 0) {
                $FilesFound = $true
            }
        } else {
            Write-ColoredOutput "[WARN] Ruta no existe: $CleanPath" "Yellow"
        }
    }
    
    if (-not $FilesFound) {
        Write-ColoredOutput "[ERROR] No se encontraron archivos en ninguna de las rutas especificadas" "Red"
        return 10  # Simular el código de error de WinRAR "No files to add"
    }
    
    # Crear archivos temporales para inclusiones y exclusiones
    $IncludeFile = "$env:TEMP\incluir_$(Get-Random).txt"
    $ExcludeFile = "$env:TEMP\excluir_$(Get-Random).txt"
    
    try {
        # Escribir archivos de inclusión
        $IncludeFiles | Out-File -FilePath $IncludeFile -Encoding ASCII
        
        # Escribir archivos de exclusión
        $ExcludeExtensions | Out-File -FilePath $ExcludeFile -Encoding ASCII
        
        # Debug: mostrar contenido de archivos temporales
        Write-Log "Contenido del archivo de inclusión ($IncludeFile):" "INFO"
        Get-Content $IncludeFile | ForEach-Object { Write-Log "  Include: $_" "INFO" }
        
        Write-Log "Contenido del archivo de exclusión ($ExcludeFile):" "INFO"
        Get-Content $ExcludeFile | ForEach-Object { Write-Log "  Exclude: $_" "INFO" }
        
        # Preparar parámetros de WinRAR
        $WinRarArgs = @("A", "-r", "-inul")
        
        # Agregar parámetros incrementales si es diferencial
        if ($Diferencial -eq 1) {
            $WinRarArgs += "-tnco$($script:DiasAtras)d"
            $WinRarArgs += "-tnmo$($script:DiasAtras)d"
            Write-ColoredOutput "Modo diferencial: últimos $($script:DiasAtras) días" "Gray"
        } else {
            Write-ColoredOutput "Modo completo: todos los archivos" "Gray"
        }
        
        # Agregar exclusiones y archivo
        $WinRarArgs += "-x@$ExcludeFile"
        $WinRarArgs += $ArchiveName
        $WinRarArgs += "@$IncludeFile"
        
        # Ejecutar WinRAR
        Write-ColoredOutput "Ejecutando: $($Config.WinRarPath) $($WinRarArgs -join ' ')" "Gray"
        
        if (Test-Path $Config.WinRarPath) {
            $Process = Start-Process -FilePath $Config.WinRarPath -ArgumentList $WinRarArgs -Wait -PassThru -NoNewWindow
            
            if ($Process.ExitCode -eq 0) {
                Write-ColoredOutput "[OK] Compresión exitosa: $ArchiveName" "Green"
                return 0
            } else {
                $ErrorMessage = switch ($Process.ExitCode) {
                    1 { "Advertencias no fatales" }
                    2 { "Error fatal" }
                    3 { "CRC error en los datos" }
                    4 { "Error de bloqueo" }
                    5 { "Error de escritura" }
                    6 { "Error de apertura de archivo" }
                    7 { "Error de usuario" }
                    8 { "Error de memoria" }
                    9 { "Error de creación de archivo" }
                    10 { "No hay archivos que añadir al archivo" }
                    11 { "Parámetros incorrectos" }
                    255 { "Break/Ctrl+C presionado" }
                    default { "Error desconocido" }
                }
                Write-ColoredOutput "[ERROR] Error en compresión: Código $($Process.ExitCode) - $ErrorMessage" "Red"
                return 1
            }
        } else {
            Write-ColoredOutput "[ERROR] WinRAR no encontrado en: $($Config.WinRarPath)" "Red"
            return 1
        }
    }
    finally {
        # Limpiar archivos temporales
        Remove-Item -Path $IncludeFile -ErrorAction SilentlyContinue
        Remove-Item -Path $ExcludeFile -ErrorAction SilentlyContinue
    }
}

function Invoke-BackupTask {
    param(
        [string]$TaskName,
        [string]$DestinationPath, 
        [int]$Diferencial,
        [string[]]$SourcePaths,
        [string[]]$ExcludeExtensions,
        [switch]$ProcessUserDirectories
    )
    
    Write-ColoredOutput "`n=== BACKUP $($TaskName.ToUpper()) ===" "Yellow"
    
    $ArchiveName = Join-Path $DestinationPath "$TaskName`_$script:FechaActual.rar"
    $IncludeFiles = @()
    
    if ($ProcessUserDirectories) {
        # Lógica especial para directorios de usuarios
        $TotalUsers = 0
        
        foreach ($UsersPath in $SourcePaths) {
            Write-ColoredOutput "Procesando fuente: $UsersPath" "Cyan"
            
            if (Test-Path $UsersPath) {
                try {
                    $UserDirs = Get-ChildItem -Path $UsersPath -Directory -ErrorAction Stop
                    
                    foreach ($UserDir in $UserDirs) {
                        $UserPath = $UserDir.FullName
                        
                        # Agregar subdirectorios estándar de usuario
                        $UserSubDirs = @("Desktop", "Documents", "Downloads")
                        
                        foreach ($SubDir in $UserSubDirs) {
                            $FullPath = Join-Path $UserPath $SubDir
                            if (Test-Path $FullPath) {
                                $IncludeFiles += "$FullPath\*"
                                Write-Log "Agregado: $FullPath" "INFO"
                            }
                        }
                    }
                    
                    $TotalUsers += $UserDirs.Count
                    Write-ColoredOutput "  [OK] Usuarios encontrados: $($UserDirs.Count)" "Green"
                }
                catch {
                    Write-ColoredOutput "  [ERROR] Error accediendo a $UsersPath`: $($_.Exception.Message)" "Red"
                }
            } else {
                Write-ColoredOutput "  [WARN] Fuente no encontrada: $UsersPath" "Yellow"
            }
        }
        
        # Si no se encontraron usuarios en ninguna fuente, usar ubicación por defecto
        if ($IncludeFiles.Count -eq 0) {
            Write-ColoredOutput "[WARN] No se encontraron usuarios en las fuentes configuradas" "Yellow"
            Write-ColoredOutput "  Usando ubicación por defecto: C:\Users\" "Yellow"
            
            $IncludeFiles += "C:\Users\*\Desktop\*"
            $IncludeFiles += "C:\Users\*\Documents\*"
            $IncludeFiles += "C:\Users\*\Downloads\*"
        }
        
        Write-ColoredOutput "Total de usuarios procesados: $TotalUsers" "Cyan"
        Write-ColoredOutput "Total de rutas incluidas: $($IncludeFiles.Count)" "Cyan"
    } else {
        # Lógica estándar para archivos/directorios normales
        $IncludeFiles = $SourcePaths
    }
    
    $Result = Invoke-WinRarCompress -ArchiveName $ArchiveName -IncludeFiles $IncludeFiles -ExcludeExtensions $ExcludeExtensions -Diferencial $Diferencial
    
    if ($Result -eq 0) {
        Write-Log "Backup de $TaskName completado exitosamente: $ArchiveName" "SUCCESS"
    } else {
        Write-Log "Error en backup de $TaskName`: $ArchiveName" "ERROR"
    }
    
    return $Result
}

function Backup-Documentos {
    param([string]$DestinationPath, [int]$Diferencial)
    
    return Invoke-BackupTask -TaskName "Documentos" -DestinationPath $DestinationPath -Diferencial $Diferencial -SourcePaths $Config.DocumentosSource -ExcludeExtensions $Config.DocumentosExclude
}

function Backup-Usuarios {
    param([string]$DestinationPath, [int]$Diferencial)
    
    return Invoke-BackupTask -TaskName "Usuarios" -DestinationPath $DestinationPath -Diferencial $Diferencial -SourcePaths $Config.UsuariosSource -ExcludeExtensions $Config.UsuariosExclude -ProcessUserDirectories
}

function Backup-Programas {
    param([string]$DestinationPath, [int]$Diferencial)
    
    return Invoke-BackupTask -TaskName "Programas" -DestinationPath $DestinationPath -Diferencial $Diferencial -SourcePaths $Config.ProgramasSource -ExcludeExtensions $Config.ProgramasExclude
}

function Sync-ToRclone {
    param([string]$LocalPath)
    
    Write-ColoredOutput "`n=== SINCRONIZACIÓN RCLONE ===" "Yellow"
    
    if (-not (Test-Path $Config.RclonePath)) {
        Write-ColoredOutput "[ERROR] rclone no encontrado en: $($Config.RclonePath)" "Red"
        return $false
    }
    
    if ([string]::IsNullOrEmpty($LocalPath)) {
        Write-ColoredOutput "[ERROR] Ruta local no especificada" "Red"
        return $false
    }
    
    try {
        # Verificar que el directorio local existe
        if (-not (Test-Path $LocalPath)) {
            Write-ColoredOutput "[ERROR] Directorio local no existe: $LocalPath" "Red"
            return $false
        }
        
        # Construir argumentos para rclone copy (solo subir, no sincronizar)
        $RcloneArgs = @(
            "copy",
            $LocalPath,
            "$($Config.RcloneRemote):$($Config.RemotePath)",
            "--retries", $Config.RcloneRetryCount.ToString()
        )
        
        # Agregar progreso si está habilitado
        if ($Config.RcloneProgress) {
            $RcloneArgs += "--progress"
        }
        
        # Agregar límite de ancho de banda si está configurado
        if ($Config.RcloneBandwidth -ne "0") {
            $RcloneArgs += "--bwlimit"
            $RcloneArgs += $Config.RcloneBandwidth
        }
        
        # Agregar configuración personalizada si existe
        if ($Config.RcloneConfig -and (Test-Path $Config.RcloneConfig)) {
            $RcloneArgs += "--config"
            $RcloneArgs += $Config.RcloneConfig
        }
        
        Write-ColoredOutput "Subiendo archivos a: $($Config.RcloneRemote):$($Config.RemotePath)" "Cyan"
        Write-Log "Directorio local: $LocalPath" "INFO"
        
        $Process = Start-Process -FilePath $Config.RclonePath -ArgumentList $RcloneArgs -Wait -PassThru -NoNewWindow
        
        if ($Process.ExitCode -eq 0) {
            Write-ColoredOutput "[OK] Subida exitosa" "Green"
            
            # Limpiar archivos antiguos del servidor si está habilitado
            if ($Config.RcloneDeleteEnabled) {
                Clear-OldFilesFromServer
            }
            
            return 0
        } else {
            Write-ColoredOutput "[ERROR] Error en subida: Código $($Process.ExitCode)" "Red"
            return 1
        }
    }
    catch {
        Write-ColoredOutput "[ERROR] Error ejecutando rclone: $($_.Exception.Message)" "Red"
        return 1
    }
}

function Clear-OldFilesFromServer {
    Write-ColoredOutput "`n=== LIMPIEZA DEL SERVIDOR ===" "Yellow"
    
    try {
        # Construir argumentos para rclone delete
        $DeleteArgs = @(
            "delete",
            "$($Config.RcloneRemote):$($Config.RemotePath)",
            "--min-age", "$($Config.RcloneDeleteOlderThan)d"
        )
        
        # Agregar configuración personalizada si existe
        if ($Config.RcloneConfig -and (Test-Path $Config.RcloneConfig)) {
            $DeleteArgs += "--config"
            $DeleteArgs += $Config.RcloneConfig
        }
        
        Write-ColoredOutput "Eliminando archivos mayores a $($Config.RcloneDeleteOlderThan) días del servidor" "Cyan"
        
        $Process = Start-Process -FilePath $Config.RclonePath -ArgumentList $DeleteArgs -Wait -PassThru -NoNewWindow
        
        if ($Process.ExitCode -eq 0) {
            Write-ColoredOutput "[OK] Limpieza del servidor completada" "Green"
            Write-Log "Limpieza de archivos antiguos del servidor exitosa" "SUCCESS"
        } else {
            Write-ColoredOutput "[WARN] Error en limpieza del servidor: Código $($Process.ExitCode)" "Yellow"
            Write-Log "Advertencia en limpieza del servidor: Código $($Process.ExitCode)" "WARN"
        }
    }
    catch {
        Write-ColoredOutput "[WARN] Error en limpieza del servidor: $($_.Exception.Message)" "Yellow"
        Write-Log "Advertencia en limpieza del servidor: $($_.Exception.Message)" "WARN"
    }
}

function Clear-TempFiles {
    param([string]$TempPath)
    
    Write-ColoredOutput "`n=== LIMPIEZA ===" "Yellow"
    Write-Log "Iniciando limpieza de archivos temporales" "INFO"
    
    try {
        # Eliminar archivos con fecha del día (pero NO la carpeta de logs)
        $FilesToDelete = Get-ChildItem -Path $TempPath -Filter "*$script:FechaActual*" -ErrorAction SilentlyContinue | 
                        Where-Object { $_.Name -notlike "*BackupLogs*" }
        
        foreach ($File in $FilesToDelete) {
            Remove-Item -Path $File.FullName -Force
            Write-ColoredOutput "Eliminado: $($File.Name)" "Gray"
            Write-Log "Archivo eliminado: $($File.Name)" "INFO"
        }
        
        # Eliminar archivos de sincronización (pero NO dentro de la carpeta de logs)
        $SyncFiles = Get-ChildItem -Path $TempPath -Filter "*.sync*" -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notlike "*BackupLogs*" }
        
        foreach ($File in $SyncFiles) {
            Remove-Item -Path $File.FullName -Force
            Write-ColoredOutput "Eliminado: $($File.Name)" "Gray"
            Write-Log "Archivo sync eliminado: $($File.Name)" "INFO"
        }
        
        Write-ColoredOutput "[OK] Limpieza completada (logs preservados)" "Green"
        Write-Log "Limpieza de archivos temporales completada. Logs preservados en: $($Config.LogPath)" "SUCCESS"
    }
    catch {
        Write-ColoredOutput "[WARN] Error en limpieza: $($_.Exception.Message)" "Yellow"
        Write-Log "Error durante limpieza: $($_.Exception.Message)" "ERROR"
    }
}

function Show-Summary {
    param([hashtable]$Results)
    
    $Separator = "=" * 30
    Write-ColoredOutput "`n$Separator" "Cyan"
    Write-ColoredOutput "RESUMEN DEL BACKUP" "Cyan"
    Write-ColoredOutput "$Separator" "Cyan"
    Write-ColoredOutput "Fecha: $script:FechaActual" "White"
    Write-ColoredOutput "Tipo: $script:TipoBackup" "White"
    Write-ColoredOutput "Destino: $($Config.TempDir)" "White"
    Write-ColoredOutput ""
    
    foreach ($Task in $Results.Keys) {
        $Result = $Results[$Task]
        
        if ($Result -eq "DESHABILITADO") {
            $Status = "[SKIP] DESHABILITADO"
            $Color = "Yellow"
        } elseif ($Result -eq 0) {
            $Status = "[OK] EXITOSO"
            $Color = "Green"
        } elseif ($Result -eq 1) {
            $Status = "[ERROR] FALLIDO"
            $Color = "Red"
        } else {
            # Manejar otros tipos de valores
            $Status = "[UNKNOWN] $Result"
            $Color = "Gray"
        }
        Write-ColoredOutput "$Task`: $Status" $Color
    }
    
    Write-ColoredOutput "`n$Separator" "Cyan"
}

function Get-BackupSummaryText {
    param([hashtable]$Results)
    
    $Summary = "📋 RESUMEN DEL BACKUP`n"
    $Summary += "═════════════════════`n"
    $Summary += "📅 Fecha: $script:FechaActual`n"
    $Summary += "🔄 Tipo: $script:TipoBackup`n"
    $Summary += "📂 Destino: $($Config.TempDir)`n"
    $Summary += "🕒 Completado: $(Get-Date -Format 'HH:mm:ss')`n`n"
    
    $Summary += "📊 RESULTADOS:`n"
    $Summary += "─────────────────────`n"
    
    $SuccessCount = 0
    $ErrorCount = 0
    $SkippedCount = 0
    
    foreach ($Task in $Results.Keys) {
        $Result = $Results[$Task]
        
        if ($Result -eq "DESHABILITADO") {
            $Status = "⏭️ DESHABILITADO"
            $SkippedCount++
        } elseif ($Result -eq 0) {
            $Status = "✅ EXITOSO"
            $SuccessCount++
        } elseif ($Result -eq 1) {
            $Status = "❌ FALLIDO"
            $ErrorCount++
        } else {
            $Status = "❔ DESCONOCIDO"
        }
        
        $Summary += "• $Task`: $Status`n"
    }
    
    $Summary += "`n📈 ESTADÍSTICAS:`n"
    $Summary += "──────────────────`n"
    $Summary += "✅ Exitosas: $SuccessCount`n"
    $Summary += "❌ Fallidas: $ErrorCount`n"
    $Summary += "⏭️ Omitidas: $SkippedCount`n"
    
    return $Summary
}

function Send-BackupNotification {
    param(
        [bool]$Success,
        [hashtable]$Results,
        [string]$LogFilePath = ""
    )
    
    Write-ColoredOutput "`n=== ENVIANDO NOTIFICACION TELEGRAM ===" "Cyan"
    Write-Log "Iniciando envío de notificación de Telegram" "INFO"
    
    # Verificar si existe el script de notificación
    $NotificationScript = Join-Path $ScriptPath "Send-TelegramNotification.ps1"
    
    if (-not (Test-Path $NotificationScript)) {
        Write-ColoredOutput "[WARN] Script de notificación no encontrado: $NotificationScript" "Yellow"
        Write-Log "Script de notificación no encontrado: $NotificationScript" "WARNING"
        return
    }
    
    try {
        # Crear mensaje según el resultado
        if ($Success) {
            $Message = "🎉 BACKUP COMPLETADO EXITOSAMENTE`n`n"
            $Message += Get-BackupSummaryText -Results $Results
            $Icon = "✅"
        } else {
            $Message = "⚠️ BACKUP COMPLETADO CON ERRORES`n`n"
            $Message += Get-BackupSummaryText -Results $Results
            $Message += "`n🔍 Revise el archivo de log adjunto para más detalles."
            $Icon = "❌"
        }
        
        Write-ColoredOutput "Enviando notificación: $Icon Backup $(if($Success){'exitoso'}else{'con errores'})" "Cyan"
        Write-Log "Enviando notificación de backup $(if($Success){'exitoso'}else{'con errores'})" "INFO"
        
        # Ejecutar script de notificación
        Write-Log "Ejecutando script de notificación de Telegram" "INFO"
        
        # Crear archivo temporal para el mensaje (para evitar problemas con caracteres especiales)
        $TempMessageFile = Join-Path $env:TEMP "backup_message_$(Get-Random).txt"
        $Message | Out-File -FilePath $TempMessageFile -Encoding UTF8
        
        try {
            # Preparar argumentos de forma más segura
            $ProcessArgs = @(
                "-ExecutionPolicy", "Bypass", 
                "-File", "`"$NotificationScript`"",
                "-Message", "`"$Message`""
            )
            
            # Si hay errores y existe el log del día, adjuntarlo
            if (-not $Success -and (Test-Path $LogFilePath)) {
                $ProcessArgs += "-LogPath"
                $ProcessArgs += "`"$LogFilePath`""
                Write-ColoredOutput "Adjuntando log del día: $(Split-Path $LogFilePath -Leaf)" "Gray"
                Write-Log "Adjuntando archivo de log: $LogFilePath" "INFO"
            }
            
            Write-Log "Argumentos del proceso: $($ProcessArgs -join ' ')" "INFO"
            
            $NotificationProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $ProcessArgs -Wait -PassThru -NoNewWindow
            
            if ($NotificationProcess.ExitCode -eq 0) {
                Write-ColoredOutput "[OK] Notificación enviada exitosamente" "Green"
                Write-Log "Notificación de Telegram enviada exitosamente" "SUCCESS"
            } else {
                Write-ColoredOutput "[WARN] Error enviando notificación: Código $($NotificationProcess.ExitCode)" "Yellow"
                Write-Log "Error enviando notificación de Telegram: Código $($NotificationProcess.ExitCode)" "WARNING"
            }
        }
        finally {
            # Limpiar archivo temporal
            if (Test-Path $TempMessageFile) {
                Remove-Item $TempMessageFile -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-ColoredOutput "[WARN] Error enviando notificación: $($_.Exception.Message)" "Yellow"
        Write-Log "Error enviando notificación de Telegram: $($_.Exception.Message)" "WARNING"
    }
}

# SCRIPT PRINCIPAL
function Main {
    $ErrorActionPreference = "Continue"
    
    Write-ColoredOutput "[INICIO] INICIANDO BACKUP REMOTO POWERSHELL" "Cyan"
    Write-ColoredOutput "Timestamp: $(Get-Date)" "Gray"
    Write-Log "========== INICIO DE SESIÓN DE BACKUP ==========" "INFO"
    Write-Log "Script iniciado: $(Get-Date)" "INFO"
    Write-Log "Parámetros: Force=$Force" "INFO"
    
    # Verificar permisos de administrador
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-ColoredOutput "[WARN] Se recomienda ejecutar como Administrador para acceso completo" "Yellow"
        Write-Log "Ejecutándose sin permisos de administrador" "WARNING"
    }
    
    try {
        # Inicializar entorno
        Initialize-Environment
        
        # Resultados del proceso
        $Results = @{}
        
        # Realizar backups
        Write-Log "Iniciando proceso de backup - Tipo: $script:TipoBackup" "INFO"
        
        # Backup Documentos (si está habilitado)
        if ($Config.DocumentosEnabled) {
            $Results["Backup Documentos"] = Backup-Documentos -DestinationPath $Config.TempDir -Diferencial $script:TipoDiferencial
        } else {
            Write-ColoredOutput "Backup Documentos DESHABILITADO" "Yellow"
            Write-Log "Backup Documentos deshabilitado en configuración" "INFO"
            $Results["Backup Documentos"] = "DESHABILITADO"
        }
        
        # Backup Usuarios (si está habilitado)
        if ($Config.UsuariosEnabled) {
            $Results["Backup Usuarios"] = Backup-Usuarios -DestinationPath $Config.TempDir -Diferencial $script:TipoDiferencial
        } else {
            Write-ColoredOutput "Backup Usuarios DESHABILITADO" "Yellow"
            Write-Log "Backup Usuarios deshabilitado en configuración" "INFO"
            $Results["Backup Usuarios"] = "DESHABILITADO"
        }
        
        # Backup Programas (si está habilitado)
        if ($Config.ProgramasEnabled) {
            $Results["Backup Programas"] = Backup-Programas -DestinationPath $Config.TempDir -Diferencial $script:TipoDiferencial
        } else {
            Write-ColoredOutput "Backup Programas DESHABILITADO" "Yellow"
            Write-Log "Backup Programas deshabilitado en configuración" "INFO"
            $Results["Backup Programas"] = "DESHABILITADO"
        }
        
        # Subir archivos con rclone
        $Results["Sincronización rclone"] = Sync-ToRclone -LocalPath "$($Config.TempDir)/"
        
        # Limpiar archivos temporales (pero NO los logs que están dentro del TempDir)
        Clear-TempFiles -TempPath $Config.TempDir
        
        # Mostrar resumen
        Show-Summary -Results $Results
        
        # Obtener ruta del log del día para notificaciones
        $TodayLogFile = Join-Path $Config.LogPath "Backup_$script:FechaActual.log"
        
        # Determinar código de salida (ignorar tareas deshabilitadas)
        $FailedTasks = $Results.Values | Where-Object { $_ -eq 1 }
        if ($FailedTasks.Count -gt 0) {
            Write-ColoredOutput "`n[WARN] BACKUP COMPLETADO CON ERRORES" "Yellow"
            Write-Log "Backup completado con errores. Tareas fallidas: $($FailedTasks.Count)" "WARNING"
            Write-Log "========== FIN DE SESIÓN CON ERRORES ==========" "WARNING"
            
            # Enviar notificación de error con log adjunto
            Send-BackupNotification -Success $false -Results $Results -LogFilePath $TodayLogFile
            
            exit 1
        } else {
            Write-ColoredOutput "`n[OK] BACKUP COMPLETADO EXITOSAMENTE" "Green"
            Write-Log "Backup completado exitosamente" "SUCCESS"
            Write-Log "========== FIN DE SESIÓN EXITOSA ==========" "SUCCESS"
            
            # Enviar notificación de éxito
            Send-BackupNotification -Success $true -Results $Results
            
            exit 0
        }
    }
    catch {
        Write-ColoredOutput "`n[ERROR] ERROR CRÍTICO: $($_.Exception.Message)" "Red"
        Write-ColoredOutput $_.ScriptStackTrace "Red"
        Write-Log "ERROR CRÍTICO: $($_.Exception.Message)" "CRITICAL"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "CRITICAL"
        Write-Log "========== FIN DE SESIÓN CON ERROR CRÍTICO ==========" "CRITICAL"
        
        # Enviar notificación de error crítico con log adjunto
        $TodayLogFile = Join-Path $Config.LogPath "Backup_$script:FechaActual.log"
        $CriticalResults = @{
            "Error Crítico" = 1
            "Mensaje" = $_.Exception.Message
        }
        
        Send-BackupNotification -Success $false -Results $CriticalResults -LogFilePath $TodayLogFile
        
        exit 2
    }
}

# Ejecutar script principal
Main

