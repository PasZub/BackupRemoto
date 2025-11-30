#Requires -Version 5.1
<#
.SYNOPSIS
    Sistema de Backup Remoto PowerShell
    Replica la funcionalidad del sistema batch original

.DESCRIPTION
    Script que realiza backup diferencial/completo de documentos y usuarios,
    comprime con WinRAR y su        # Preparar parámetros de WinRAR
        $WinRarArgs = @("A", "-r")  # Removemos -inul para poder capturar salida

        # Agregar partición de archivos de 2GB
        $WinRarArgs += "-v2g"
        Write-ColoredOutput "Configuración: Partición de archivos en 2GB" "Gray"
        
        # Parámetros para evitar diálogos y continuar automáticamente
        $WinRarArgs += "-y"      # Responder "Sí" a todas las preguntas
        $WinRarArgs += "-o+"     # Sobrescribir archivos existentes
        $WinRarArgs += "-ilog"   # Escribir nombres de archivos a log
        $WinRarArgs += "-ierr"   # Enviar todos los mensajes a stderrcon rclone

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

# Verificar que existan los archivos de configuración requeridos
$ConfigurationErrors = @()

if (-not (Test-Path $ConfigPath)) {
    $ConfigurationErrors += "Archivo de configuración del sistema no encontrado: $ConfigPath"
}

if (-not (Test-Path $UserConfigPath)) {
    $ConfigurationErrors += "Archivo de configuración de usuario no encontrado: $UserConfigPath"
}

# Si hay errores de configuración, mostrar y salir
if ($ConfigurationErrors.Count -gt 0) {
    Write-Host "`n[ERROR CRÍTICO] Configuración incompleta del sistema de backup" -ForegroundColor Red
    Write-Host "=" * 70 -ForegroundColor Red
    Write-Host "`nNo se encontraron los siguientes archivos de configuración requeridos:`n" -ForegroundColor Yellow
    
    foreach ($error in $ConfigurationErrors) {
        Write-Host "  ❌ $error" -ForegroundColor Red
    }
    
    Write-Host "`n[SOLUCIÓN]" -ForegroundColor Cyan
    Write-Host "Por favor, cree los archivos de configuración necesarios:" -ForegroundColor White
    Write-Host "  1. BackupConfig.ps1 - Configuración del sistema (rutas, rclone, etc.)" -ForegroundColor Gray
    Write-Host "  2. UserConfig.ps1 - Configuración del usuario (backups a realizar)" -ForegroundColor Gray
    Write-Host "`nPuede usar los archivos de ejemplo como plantilla." -ForegroundColor Gray
    Write-Host "=" * 70 -ForegroundColor Red
    
    exit 2
}

# Cargar configuración del sistema
try {
    $Config = & $ConfigPath
    Write-Verbose "Configuración del sistema cargada desde: $ConfigPath"
}
catch {
    Write-Host "`n[ERROR] Error al cargar configuración del sistema: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

# Cargar configuración de usuario y combinar con configuración del sistema
try {
    $UserConfig = & $UserConfigPath
    # Combinar configuraciones (UserConfig tiene prioridad)
    foreach ($key in $UserConfig.Keys) {
        $Config[$key] = $UserConfig[$key]
    }
    Write-Verbose "Configuración de usuario cargada desde: $UserConfigPath"
}
catch {
    Write-Host "`n[ERROR] Error al cargar configuración de usuario: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

# Validar configuración de días para backup completo
if (-not $Config.ContainsKey('BackupCompletoDias') -or $Config.BackupCompletoDias.Count -eq 0) {
    Write-Warning "Configuración de días para backup completo no definida. Usando valores por defecto (Domingo)"
    $Config.BackupCompletoDias = @(0)
} else {
    # Validar que los días están en rango válido (0-6)
    $diasValidos = $Config.BackupCompletoDias | Where-Object { $_ -ge 0 -and $_ -le 6 }
    if ($diasValidos.Count -ne $Config.BackupCompletoDias.Count) {
        Write-Warning "Algunos días configurados no son válidos (deben estar entre 0-6). Usando valores válidos solamente"
        $Config.BackupCompletoDias = $diasValidos
    }
}

# Funciones auxiliares
function Write-ColoredOutput {
    param(
        [string]$Message, 
        [string]$Color = "White",
        [switch]$NoLog  # Parámetro para evitar logging automático
    )
    Write-Host $Message -ForegroundColor $Color
    
    # Solo escribir al log si está habilitado y NoLog no está activado
    if ($Config.LogEnabled -and -not $NoLog) {
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
    
    # Determinar tipo de backup usando configuración personalizable
    # Verificar si el día actual está en la lista de días para backup completo
    $EsDiaBackupCompleto = $Config.BackupCompletoDias -contains $script:DiaSemanaNumero
    
    if ($Force -or $EsDiaBackupCompleto) {
        $script:TipoDiferencial = 0
        $script:TipoBackup = "COMPLETO"
        $razonBackup = if ($Force) { "forzado por parámetro" } else { "día configurado para backup completo" }
        Write-ColoredOutput "Backup completo ($razonBackup)" "Cyan"
    } else {
        $script:TipoDiferencial = 1
        $script:TipoBackup = "DIFERENCIAL"
        Write-ColoredOutput "Backup diferencial (día no configurado para backup completo)" "Cyan"
    }
    
    $script:DiasAtras = $script:DiaSemanaNumero
    
    # Mostrar configuración de días
    $diasNombres = @("Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado")
    $diasConfigurados = $Config.BackupCompletoDias | ForEach-Object { $diasNombres[$_] }
    Write-ColoredOutput "Días configurados para backup completo: $($diasConfigurados -join ', ')" "Gray"
    
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
        $WinRarArgs = @("A", "-r")  # Removemos -inul para poder capturar salida

        # Agregar partición de archivos de 2GB
        $WinRarArgs += "-v2g"
        Write-ColoredOutput "Configuración: Partición de archivos en 2GB" "Gray"
        
        # Parámetros para evitar diálogos y continuar automáticamente
        $WinRarArgs += "-y"      # Responder "Sí" a todas las preguntas
        $WinRarArgs += "-o+"     # Sobrescribir archivos existentes
        $WinRarArgs += "-ilog"   # Escribir nombres de archivos a log
        $WinRarArgs += "-ierr"   # Enviar todos los mensajes a stderr

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
        
        # Ejecutar WinRAR con captura de salida
        Write-ColoredOutput "Ejecutando: $($Config.WinRarPath) $($WinRarArgs -join ' ')" "Gray"
        Write-Log "Iniciando compresión WinRAR: $($WinRarArgs -join ' ')" "INFO"
        
        if (Test-Path $Config.WinRarPath) {
            # Crear archivos temporales para capturar la salida de WinRAR
            $TempOutputFile = "$env:TEMP\winrar_output_$(Get-Random).txt"
            $TempErrorFile = "$env:TEMP\winrar_error_$(Get-Random).txt"
            
            try {
                # Ejecutar WinRAR (ya incluye -ierr y -y para evitar diálogos)
                $Process = Start-Process -FilePath $Config.WinRarPath -ArgumentList $WinRarArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput $TempOutputFile -RedirectStandardError $TempErrorFile
                
                # Leer y analizar la salida estándar de WinRAR
                if (Test-Path $TempOutputFile) {
                    $WinRarOutput = Get-Content $TempOutputFile -ErrorAction SilentlyContinue
                    $WarningCount = 0
                    $ErrorCount = 0
                    $LockedFileCount = 0
                    
                    foreach ($line in $WinRarOutput) {
                        # Capturar errores y advertencias
                        if ($line -match "WARNING:|ERROR:|Cannot|Failed|Access denied|Sharing violation|locked|in use|Skipping") {
                            if ($line -match "ERROR:|Cannot|Failed|Access denied") {
                                $ErrorCount++
                                Write-Log "[WINRAR ERROR] $line" "ERROR"
                            } else {
                                $WarningCount++
                                Write-Log "[WINRAR WARNING] $line" "WARNING"
                            }
                        }
                        # Capturar mensajes específicos de archivos bloqueados
                        if ($line -match "File .* is locked|File .* is being used|Cannot open") {
                            $LockedFileCount++
                            Write-Log "[WINRAR FILE LOCKED] $line" "WARNING"
                        }
                        # Solo loggear información de progreso si es necesario (reducir spam)
                        if ($line -match "Adding|Compressing" -and $line -notmatch "^\.\.\.$") {
                            Write-Log "[WINRAR PROGRESS] $line" "INFO"
                        }
                    }
                    
                    # Resumen de problemas encontrados
                    if ($ErrorCount -gt 0 -or $WarningCount -gt 0 -or $LockedFileCount -gt 0) {
                        Write-ColoredOutput "[WARN] Problemas en compresión: $ErrorCount errores, $WarningCount advertencias, $LockedFileCount archivos bloqueados" "Yellow" -NoLog
                        Write-Log "Resumen WinRAR: $ErrorCount errores, $WarningCount advertencias, $LockedFileCount archivos bloqueados" "WARNING"
                    }
                }
                
                # Leer y analizar la salida de error de WinRAR
                if (Test-Path $TempErrorFile) {
                    $WinRarErrors = Get-Content $TempErrorFile -ErrorAction SilentlyContinue
                    $CriticalErrorCount = 0
                    foreach ($line in $WinRarErrors) {
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            $CriticalErrorCount++
                            Write-Log "[WINRAR CRITICAL ERROR] $line" "ERROR"
                        }
                    }
                    if ($CriticalErrorCount -gt 0) {
                        Write-ColoredOutput "[ERROR] WinRAR reportó $CriticalErrorCount errores críticos" "Red" -NoLog
                        Write-Log "WinRAR reportó $CriticalErrorCount errores críticos" "ERROR"
                    }
                }
                
                # Log adicional con información del proceso
                Write-Log "WinRAR terminó con código de salida: $($Process.ExitCode)" "INFO"
                
                # Evaluar resultado según código de salida
                if ($Process.ExitCode -eq 0) {
                    Write-ColoredOutput "[OK] Compresión exitosa: $ArchiveName" "Green" -NoLog
                    Write-Log "Compresión WinRAR completada exitosamente" "SUCCESS"
                    return 0
                } elseif ($Process.ExitCode -eq 1) {
                    Write-ColoredOutput "[OK] Compresión completada con advertencias: $ArchiveName" "Yellow" -NoLog
                    Write-Log "Compresión WinRAR completada con advertencias (algunos archivos omitidos)" "WARNING"
                    return 0  # Consideramos éxito con advertencias
                } else {
                    $ErrorMessage = switch ($Process.ExitCode) {
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
                    Write-ColoredOutput "[ERROR] Error en compresión: Código $($Process.ExitCode) - $ErrorMessage" "Red" -NoLog
                    Write-Log "Error en compresión WinRAR: Código $($Process.ExitCode) - $ErrorMessage" "ERROR"
                    return 1
                }
            }
            finally {
                # Limpiar archivos temporales de salida
                Remove-Item -Path $TempOutputFile -ErrorAction SilentlyContinue
                Remove-Item -Path $TempErrorFile -ErrorAction SilentlyContinue
            }
        } else {
            Write-ColoredOutput "[ERROR] WinRAR no encontrado en: $($Config.WinRarPath)" "Red" -NoLog
            Write-Log "WinRAR no encontrado en la ruta: $($Config.WinRarPath)" "ERROR"
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
            "$($Config.RcloneRemote):$($Config.RemotePath)"
        )
        
        # Optimizaciones de rendimiento
        if ($Config.RcloneTransfers) {
            $RcloneArgs += "--transfers=$($Config.RcloneTransfers)"
        }
        
        if ($Config.RcloneCheckers) {
            $RcloneArgs += "--checkers=$($Config.RcloneCheckers)"
        }
        
        if ($Config.RcloneBufferSize) {
            $RcloneArgs += "--buffer-size=$($Config.RcloneBufferSize)"
        }
        
        if ($Config.RcloneMultiThreadCutoff) {
            $RcloneArgs += "--multi-thread-cutoff=$($Config.RcloneMultiThreadCutoff)"
        }
        
        if ($Config.RcloneMultiThreadStreams) {
            $RcloneArgs += "--multi-thread-streams=$($Config.RcloneMultiThreadStreams)"
        }
        
        if ($Config.RcloneTimeout) {
            $RcloneArgs += "--timeout=$($Config.RcloneTimeout)"
        }
        
        if ($Config.RcloneContimeout) {
            $RcloneArgs += "--contimeout=$($Config.RcloneContimeout)"
        }
        
        if ($Config.RcloneLowLevelRetries) {
            $RcloneArgs += "--low-level-retries=$($Config.RcloneLowLevelRetries)"
        }
        
        if ($Config.RcloneUseServerModtime) {
            $RcloneArgs += "--use-server-modtime"
        }
        
        # Optimizaciones adicionales de velocidad
        $RcloneArgs += "--fast-list"           # Lista archivos en paralelo
        $RcloneArgs += "--ignore-checksum"     # No verificar checksum (más rápido)
        $RcloneArgs += "--no-traverse"         # No recorrer directorio destino
        $RcloneArgs += "--disable=move"        # Deshabilitar operaciones move
        
        # Agregar reintentos
        if ($Config.RcloneRetryCount) {
            $RcloneArgs += "--retries=$($Config.RcloneRetryCount)"
        }
        
        # Agregar progreso si está habilitado
        if ($Config.RcloneProgress) {
            $RcloneArgs += "--progress"
        }
        
        # Agregar límite de ancho de banda si está configurado
        if ($Config.RcloneBandwidth -ne "0") {
            $RcloneArgs += "--bwlimit=$($Config.RcloneBandwidth)"
        }
        
        # Agregar configuración personalizada si existe
        if ($Config.RcloneConfig -and (Test-Path $Config.RcloneConfig)) {
            $RcloneArgs += "--config=$($Config.RcloneConfig)"
        }
        
        Write-ColoredOutput "Subiendo archivos a: $($Config.RcloneRemote):$($Config.RemotePath)" "Cyan"
        Write-ColoredOutput "Optimizaciones: $($Config.RcloneTransfers) transferencias, $($Config.RcloneCheckers) verificadores" "Gray"
        Write-ColoredOutput "Buffer: $($Config.RcloneBufferSize), Multi-thread: >$($Config.RcloneMultiThreadCutoff)" "Gray"
        Write-Log "Directorio local: $LocalPath" "INFO"
        Write-Log "Argumentos rclone: $($RcloneArgs -join ' ')" "INFO"
        
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
        
        # Agregar optimizaciones para operaciones de limpieza
        if ($Config.RcloneCheckers) {
            $DeleteArgs += "--checkers=$($Config.RcloneCheckers)"
        }
        
        if ($Config.RcloneTimeout) {
            $DeleteArgs += "--timeout=$($Config.RcloneTimeout)"
        }
        
        if ($Config.RcloneContimeout) {
            $DeleteArgs += "--contimeout=$($Config.RcloneContimeout)"
        }
        
        if ($Config.RcloneLowLevelRetries) {
            $DeleteArgs += "--low-level-retries=$($Config.RcloneLowLevelRetries)"
        }
        
        # Optimizaciones adicionales para listado
        $DeleteArgs += "--fast-list"           # Lista archivos en paralelo
        
        # Agregar configuración personalizada si existe
        if ($Config.RcloneConfig -and (Test-Path $Config.RcloneConfig)) {
            $DeleteArgs += "--config=$($Config.RcloneConfig)"
        }
        
        Write-ColoredOutput "Eliminando archivos mayores a $($Config.RcloneDeleteOlderThan) días del servidor" "Cyan"
        Write-Log "Argumentos rclone delete: $($DeleteArgs -join ' ')" "INFO"
        
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
    
    # Obtener nombre del cliente desde configuración
    $cliente = if ($Config.ContainsKey('Usuario') -and -not [string]::IsNullOrEmpty($Config.Usuario)) {
        $Config.Usuario
    } else {
        $env:COMPUTERNAME
    }
    
    # Construir mensaje según el modelo especificado
    $Summary = "Cliente: $cliente - Informe`n"
    $Summary += "---------------------`n"
    $Summary += "Fecha: $script:FechaActual`n"
    $Summary += "Tipo: $script:TipoBackup`n"
    $Summary += "Completado: $(Get-Date -Format 'HH:mm:ss')`n`n"
    
    $Summary += "RESULTADOS:`n"
    $Summary += "---------------------`n"
    
    # Ordenar resultados para mantener consistencia
    $orderedTasks = @("Backup Programas", "Backup Documentos", "Backup Usuarios", "Sincronización rclone")
    
    foreach ($Task in $orderedTasks) {
        if ($Results.ContainsKey($Task)) {
            $Result = $Results[$Task]
            
            if ($Result -eq "DESHABILITADO") {
                $Status = "[SKIP] DESHABILITADO"
            } elseif ($Result -eq 0) {
                $Status = "[OK] EXITOSO"
            } elseif ($Result -eq 1) {
                $Status = "[ERROR] FALLIDO"
            } else {
                $Status = "[?] DESCONOCIDO"
            }
            
            $Summary += "• $Task`: $Status`n"
        }
    }
    
    return $Summary
}

function Check-ForUpdates {
    try {
        # Configuración del repositorio
        $GITHUB_OWNER = "PasZub"
        $GITHUB_REPO = "BackupRemoto"
        
        # Verificar si hay conexión a Internet (rápido, sin bloquear)
        $canConnect = Test-NetConnection -ComputerName "api.github.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        
        if (-not $canConnect) {
            return  # Sin conexión, continuar sin verificar
        }
        
        # Obtener versión actual
        $versionFile = Join-Path $ScriptPath "VERSION.txt"
        $currentVersion = if (Test-Path $versionFile) {
            (Get-Content $versionFile -Raw -ErrorAction SilentlyContinue) -replace '.*Versión:\s*(\S+).*', '$1'
        } else {
            "Desconocida"
        }
        
        # Consultar última versión (timeout corto)
        $apiUrl = "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest"
        
        try {
            # Timeout de 3 segundos para no retrasar el backup
            $request = [System.Net.WebRequest]::Create($apiUrl)
            $request.Timeout = 3000
            $request.UserAgent = "PowerShell-BackupSystem"
            
            $response = $request.GetResponse()
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $content = $reader.ReadToEnd()
            $reader.Close()
            $response.Close()
            
            $releaseInfo = $content | ConvertFrom-Json
            $latestVersion = $releaseInfo.tag_name
            
            if ($currentVersion -ne $latestVersion) {
                Write-ColoredOutput "`n[ACTUALIZACIÓN DISPONIBLE] Nueva versión: $latestVersion (actual: $currentVersion)" "Yellow"
                Write-ColoredOutput "Ejecuta '.\Update-BackupSystem.ps1' para actualizar" "Yellow"
                Write-Log "Actualización disponible: $latestVersion (actual: $currentVersion)" "INFO"
            }
        }
        catch {
            # Silenciosamente ignorar errores de verificación
        }
    }
    catch {
        # Silenciosamente ignorar errores de verificación
    }
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
            $Message = "[OK] BACKUP COMPLETADO EXITOSAMENTE`n`n"
            $Message += Get-BackupSummaryText -Results $Results
            $Icon = "[OK]"
        } else {
            $Message = "[ERROR] BACKUP COMPLETADO CON ERRORES`n`n"
            $Message += Get-BackupSummaryText -Results $Results
            $Message += "`nRevise el archivo de log adjunto para mas detalles."
            $Icon = "[ERROR]"
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
    
    # Verificar si hay actualizaciones disponibles (no bloquea el backup)
    Check-ForUpdates
    
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

