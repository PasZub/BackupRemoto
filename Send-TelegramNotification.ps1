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

# Cargar configuración del backup si existe
if (Test-Path $ConfigPath) {
    try {
        $Config = & $ConfigPath
    }
    catch {
        $Config = $null
        if (-not $Silent) {
            Write-Warning "No se pudo cargar la configuración de backup: $($_.Exception.Message)"
        }
    }
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
    $FormattedMessage = "<b>Notificacion de Backup $($Config.Usuario)</b>`n`n"
    $FormattedMessage += $Message
    $FormattedMessage += "`n`nFecha: <i>$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</i>"
    
    if (-not (Send-TelegramMessage -Text $FormattedMessage)) {
        $Success = $false
    }
}

# Enviar archivo de log específico si se especifica
if (-not [string]::IsNullOrEmpty($LogPath)) {
    if (Test-Path $LogPath) {
        $caption = "Log del Sistema de Backup`nFecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
        Write-Output "Enviando log original..." "Cyan"
        
        if (-not (Send-TelegramFile -FilePath $LogPath -Caption $caption)) {
            $Success = $false
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
