#Requires -Version 5.1
<#
.SYNOPSIS
    Envia notificaciones y archivos de logs por Telegram

.DESCRIPTION
    Script para enviar mensajes de texto y archivos de logs del sistema de backup
    a traves de un bot de Telegram

.PARAMETER Message
    Mensaje de texto a enviar

.PARAMETER LogPath
    Ruta al archivo de log a enviar

.PARAMETER Silent
    Ejecuta sin mostrar salida en consola

.EXAMPLE
    .\Send-TelegramNotification.ps1 -Message "Backup completado exitosamente"
    .\Send-TelegramNotification.ps1 -LogPath ".\BackupLogs\backup_20250802.log"
    .\Send-TelegramNotification.ps1 -Message "Error en backup" -LogPath ".\BackupLogs\backup_20250802.log"
#>

[CmdletBinding()]
param(
    [string]$Message,
    [string]$LogPath,
    [switch]$Silent
)

# ============================================================================
# CONFIGURACIÓN - MODIFICAR ESTAS VARIABLES CON TUS DATOS
# ============================================================================

# Token del bot de Telegram (obtenerlo de @BotFather)
$TELEGRAM_BOT_TOKEN = "1734951853:AAG0yCbVnErlYSk_gTAO-RsffqTvShHeviw"

# Chat ID donde enviar los mensajes (puede ser chat personal o grupo)
$TELEGRAM_CHAT_ID = "-1001575024278"

# ============================================================================
# NO MODIFICAR EL CÓDIGO A PARTIR DE AQUÍ
# ============================================================================

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptPath "BackupConfig.ps1"
$UserConfigPath = Join-Path $ScriptPath "UserConfig.ps1"

# Cargar configuración del sistema
if (Test-Path $ConfigPath) {
    try {
        $Config = & $ConfigPath
    }
    catch {
        $Config = @{}
        if (-not $Silent) {
            Write-Warning "No se pudo cargar la configuración del sistema: $($_.Exception.Message)"
        }
    }
} else {
    $Config = @{}
    if (-not $Silent) {
        Write-Warning "Archivo de configuración del sistema no encontrado: $ConfigPath"
    }
}

# Cargar configuración de usuario y combinar
if (Test-Path $UserConfigPath) {
    try {
        $UserConfig = & $UserConfigPath
        # Combinar configuraciones (UserConfig tiene prioridad)
        foreach ($key in $UserConfig.Keys) {
            $Config[$key] = $UserConfig[$key]
        }
        if (-not $Silent) {
            Write-Verbose "Configuración de usuario cargada desde: $UserConfigPath"
        }
    }
    catch {
        if (-not $Silent) {
            Write-Warning "No se pudo cargar la configuración de usuario: $($_.Exception.Message)"
        }
    }
} else {
    if (-not $Silent) {
        Write-Warning "Archivo de configuración de usuario no encontrado: $UserConfigPath"
    }
}

# Asegurar que existe la propiedad Usuario para retrocompatibilidad
if (-not $Config.ContainsKey('Usuario') -or [string]::IsNullOrEmpty($Config.Usuario)) {
    $Config['Usuario'] = $env:USERNAME
}

function Write-Output {
    param([string]$Message, [string]$Color = "White")
    if (-not $Silent) {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Send-TelegramMessage {
    param([string]$Text)
    
    if ([string]::IsNullOrEmpty($TELEGRAM_BOT_TOKEN) -or $TELEGRAM_BOT_TOKEN -eq "TU_BOT_TOKEN_AQUI") {
        Write-Output "[ERROR] Token de Telegram no configurado" "Red"
        return $false
    }
    
    if ([string]::IsNullOrEmpty($TELEGRAM_CHAT_ID) -or $TELEGRAM_CHAT_ID -eq "TU_CHAT_ID_AQUI") {
        Write-Output "[ERROR] Chat ID de Telegram no configurado" "Red"
        return $false
    }
    
    try {
        $Uri = "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
        
        $Body = @{
            chat_id = $TELEGRAM_CHAT_ID
            text = $Text
            parse_mode = "HTML"
        }
        
        Write-Output "Enviando mensaje a Telegram..." "Cyan"
        
        $Response = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body -ContentType "application/x-www-form-urlencoded"
        
        if ($Response.ok) {
            Write-Output "[OK] Mensaje enviado exitosamente" "Green"
            return $true
        } else {
            Write-Output "[ERROR] Error enviando mensaje: $($Response.description)" "Red"
            return $false
        }
    }
    catch {
        Write-Output "[ERROR] Excepción enviando mensaje: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Send-TelegramFile {
    param([string]$FilePath, [string]$Caption = "")
    
    if ([string]::IsNullOrEmpty($TELEGRAM_BOT_TOKEN) -or $TELEGRAM_BOT_TOKEN -eq "TU_BOT_TOKEN_AQUI") {
        Write-Output "[ERROR] Token de Telegram no configurado" "Red"
        return $false
    }
    
    if ([string]::IsNullOrEmpty($TELEGRAM_CHAT_ID) -or $TELEGRAM_CHAT_ID -eq "TU_CHAT_ID_AQUI") {
        Write-Output "[ERROR] Chat ID de Telegram no configurado" "Red"
        return $false
    }
    
    if (-not (Test-Path $FilePath)) {
        Write-Output "[ERROR] Archivo no encontrado: $FilePath" "Red"
        return $false
    }
    
    try {
        # Verificar tamano del archivo (limite de Telegram: 50MB)
        $FileSize = (Get-Item $FilePath).Length
        $MaxSize = 50MB
        
        if ($FileSize -gt $MaxSize) {
            Write-Output "[ERROR] Archivo demasiado grande: $([math]::Round($FileSize/1MB, 2))MB (maximo: 50MB)" "Red"
            return $false
        }
        
        Write-Output "Enviando archivo a Telegram: $(Split-Path $FilePath -Leaf)" "Cyan"
        Write-Output "Tamano: $([math]::Round($FileSize/1KB, 2))KB" "Gray"
        
        # Usar metodo alternativo con curl si esta disponible
        $curlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
        if ($curlPath) {
            Write-Output "Usando curl para envio..." "Gray"
            
            $Uri = "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument"
            $fileName = Split-Path $FilePath -Leaf
            
            # Construir argumentos para curl
            $curlArgs = @(
                "-X", "POST",
                "-F", "chat_id=$TELEGRAM_CHAT_ID",
                "-F", "document=@`"$FilePath`""
            )
            
            if (-not [string]::IsNullOrEmpty($Caption)) {
                $curlArgs += "-F"
                $curlArgs += "caption=$Caption"
            }
            
            $curlArgs += $Uri
            
            # Ejecutar curl
            $result = & $curlPath $curlArgs 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                $response = $result | ConvertFrom-Json
                if ($response.ok) {
                    Write-Output "[OK] Archivo enviado exitosamente" "Green"
                    return $true
                } else {
                    Write-Output "[ERROR] Error enviando archivo: $($response.description)" "Red"
                    return $false
                }
            } else {
                Write-Output "[ERROR] Error ejecutando curl: codigo $LASTEXITCODE" "Red"
                return $false
            }
        } else {
            # Fallback: usar metodo PowerShell nativo simplificado
            Write-Output "Usando metodo PowerShell nativo..." "Gray"
            
            # Crear formulario multipart manualmente
            $boundary = [System.Guid]::NewGuid().ToString()
            $LF = "`r`n"
            
            # Leer archivo
            $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
            $fileName = Split-Path $FilePath -Leaf
            
            # Construir body multipart
            $bodyParts = @()
            
            # chat_id
            $bodyParts += "--$boundary"
            $bodyParts += "Content-Disposition: form-data; name=`"chat_id`""
            $bodyParts += ""
            $bodyParts += $TELEGRAM_CHAT_ID
            
            # caption (opcional)
            if (-not [string]::IsNullOrEmpty($Caption)) {
                $bodyParts += "--$boundary"
                $bodyParts += "Content-Disposition: form-data; name=`"caption`""
                $bodyParts += ""
                $bodyParts += $Caption
            }
            
            # document header
            $bodyParts += "--$boundary"
            $bodyParts += "Content-Disposition: form-data; name=`"document`"; filename=`"$fileName`""
            $bodyParts += "Content-Type: application/octet-stream"
            $bodyParts += ""
            
            # Convertir header a bytes
            $headerText = ($bodyParts -join $LF) + $LF
            $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerText)
            
            # Footer
            $footerText = $LF + "--$boundary--" + $LF
            $footerBytes = [System.Text.Encoding]::UTF8.GetBytes($footerText)
            
            # Combinar todo
            $bodyBytes = $headerBytes + $fileBytes + $footerBytes
            
            # Enviar
            $Uri = "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument"
            $headers = @{
                "Content-Type" = "multipart/form-data; boundary=$boundary"
            }
            
            $Response = Invoke-RestMethod -Uri $Uri -Method Post -Body $bodyBytes -Headers $headers
            
            if ($Response.ok) {
                Write-Output "[OK] Archivo enviado exitosamente" "Green"
                return $true
            } else {
                Write-Output "[ERROR] Error enviando archivo: $($Response.description)" "Red"
                return $false
            }
        }
    }
    catch {
        Write-Output "[ERROR] Excepcion enviando archivo: $($_.Exception.Message)" "Red"
        return $false
    }
}

# ============================================================================
# SCRIPT PRINCIPAL
# ============================================================================

Write-Output "`n=== NOTIFICACION TELEGRAM ===" "Yellow"

$Success = $true

# Enviar mensaje personalizado si se especifica
if (-not [string]::IsNullOrEmpty($Message)) {
    # Construir encabezado con información del sistema
    $systemInfo = ""
    if ($Config.ContainsKey('Usuario') -and -not [string]::IsNullOrEmpty($Config.Usuario)) {
        $systemInfo = "Usuario: $($Config.Usuario)"
    } else {
        $systemInfo = "Sistema: $env:COMPUTERNAME"
    }
    
    # Agregar información del directorio temporal si está disponible
    if ($Config.ContainsKey('TempDir') -and -not [string]::IsNullOrEmpty($Config.TempDir)) {
        $systemInfo += "`nDirectorio: $($Config.TempDir)"
    }
    
    # Agregar información del servidor remoto si está disponible
    if ($Config.ContainsKey('RcloneRemote') -and -not [string]::IsNullOrEmpty($Config.RcloneRemote)) {
        $systemInfo += "`nServidor: $($Config.RcloneRemote)"
    }
    
    $FormattedMessage = "<b>NOTIFICACION DE BACKUP</b>`n"
    $FormattedMessage += "========================================`n"
    $FormattedMessage += "$systemInfo`n`n"
    $FormattedMessage += $Message
    $FormattedMessage += "`n`nFecha: <i>$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</i>"
    
    if (-not (Send-TelegramMessage -Text $FormattedMessage)) {
        $Success = $false
    }
}

# Enviar archivo de log específico si se especifica
if (-not [string]::IsNullOrEmpty($LogPath)) {
    if (Test-Path $LogPath) {
        # Crear caption más informativo
        $logFileName = Split-Path $LogPath -Leaf
        $systemName = if ($Config.ContainsKey('Usuario') -and -not [string]::IsNullOrEmpty($Config.Usuario)) { 
            $Config.Usuario 
        } else { 
            $env:COMPUTERNAME 
        }
        
        $caption = "LOG DEL SISTEMA DE BACKUP`n"
        $caption += "========================================`n"
        $caption += "Sistema: $systemName`n"
        $caption += "Archivo: $logFileName`n"
        $caption += "Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
        
        Write-Output "Preparando log para envío..." "Cyan"
        
        # Crear copia temporal del log para evitar problemas de archivo en uso
        $tempLogPath = $null
        $maxRetries = 3
        $retryCount = 0
        $copySuccess = $false
        
        while ($retryCount -lt $maxRetries -and -not $copySuccess) {
            try {
                # Generar nombre único para el archivo temporal
                $tempFileName = "TelegramLog_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(Get-Random -Maximum 9999).log"
                $tempLogPath = Join-Path $env:TEMP $tempFileName
                
                Write-Output "Creando copia temporal: $tempFileName" "Gray"
                
                # Intentar copiar el archivo con diferentes métodos
                if ($retryCount -eq 0) {
                    # Método 1: Copy-Item estándar
                    Copy-Item -Path $LogPath -Destination $tempLogPath -Force
                } elseif ($retryCount -eq 1) {
                    # Método 2: Leer contenido y escribir a nuevo archivo
                    $logContent = Get-Content -Path $LogPath -Raw -ErrorAction Stop
                    $logContent | Out-File -FilePath $tempLogPath -Encoding UTF8 -Force
                } else {
                    # Método 3: Usar robocopy para archivos bloqueados
                    $sourceDir = Split-Path $LogPath -Parent
                    $sourceFile = Split-Path $LogPath -Leaf
                    $tempDir = Split-Path $tempLogPath -Parent
                    
                    $robocopyResult = robocopy.exe $sourceDir $tempDir $sourceFile /R:1 /W:1 /NP /NDL /NJH /NJS
                    
                    if (Test-Path $tempLogPath) {
                        # Renombrar el archivo copiado por robocopy
                        $robocopyFile = Join-Path $tempDir $sourceFile
                        if (Test-Path $robocopyFile -and $robocopyFile -ne $tempLogPath) {
                            Move-Item $robocopyFile $tempLogPath -Force
                        }
                    }
                }
                
                # Verificar que la copia se creó correctamente
                if (Test-Path $tempLogPath) {
                    $originalSize = (Get-Item $LogPath).Length
                    $tempSize = (Get-Item $tempLogPath).Length
                    
                    if ($tempSize -gt 0) {
                        Write-Output "[OK] Copia temporal creada: $([math]::Round($tempSize/1KB, 1))KB" "Green"
                        $copySuccess = $true
                    } else {
                        Write-Output "[WARN] Copia temporal vacía, reintentando..." "Yellow"
                        Remove-Item $tempLogPath -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Output "[WARN] No se pudo crear copia temporal, reintentando..." "Yellow"
                }
            }
            catch {
                Write-Output "[WARN] Error creando copia temporal (intento $($retryCount + 1)): $($_.Exception.Message)" "Yellow"
                if ($tempLogPath -and (Test-Path $tempLogPath)) {
                    Remove-Item $tempLogPath -Force -ErrorAction SilentlyContinue
                }
            }
            
            if (-not $copySuccess) {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Output "Esperando 2 segundos antes del siguiente intento..." "Gray"
                    Start-Sleep -Seconds 2
                }
            }
        }
        
        # Intentar enviar el archivo
        if ($copySuccess -and $tempLogPath -and (Test-Path $tempLogPath)) {
            Write-Output "Enviando copia temporal del log..." "Cyan"
            
            if (-not (Send-TelegramFile -FilePath $tempLogPath -Caption $caption)) {
                $Success = $false
            }
            
            # Limpiar archivo temporal
            try {
                Remove-Item $tempLogPath -Force -ErrorAction SilentlyContinue
                Write-Output "Copia temporal eliminada" "Gray"
            }
            catch {
                Write-Output "[WARN] No se pudo eliminar copia temporal: $tempLogPath" "Yellow"
            }
        } else {
            Write-Output "[ERROR] No se pudo crear copia temporal del log después de $maxRetries intentos" "Red"
            
            # Como último recurso, intentar enviar el archivo original
            Write-Output "Intentando enviar archivo original como último recurso..." "Yellow"
            
            try {
                if (-not (Send-TelegramFile -FilePath $LogPath -Caption $caption)) {
                    $Success = $false
                    Write-Output "[ERROR] Tampoco se pudo enviar el archivo original" "Red"
                }
            }
            catch {
                Write-Output "[ERROR] Error enviando archivo original: $($_.Exception.Message)" "Red"
                $Success = $false
            }
        }
    } else {
        Write-Output "[ERROR] Archivo de log no encontrado: $LogPath" "Red"
        $Success = $false
    }
}

# Mostrar resultado final
if ($Success) {
    Write-Output "`n[OK] Notificacion completada exitosamente" "Green"
    exit 0
} else {
    Write-Output "`n[ERROR] Errores durante el envio de notificacion" "Red"
    exit 1
}
