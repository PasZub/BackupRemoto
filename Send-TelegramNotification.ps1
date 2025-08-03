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

# Cargar assemblies necesarios para conversion PDF
Add-Type -AssemblyName System.Web

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

function Convert-LogToHtml {
    param([string]$LogPath, [string]$OutputPath)
    
    try {
        Write-Output "Convirtiendo log a HTML..." "Cyan"
        
        # Leer contenido del log
        $logContent = Get-Content -Path $LogPath -Encoding UTF8
        $fileName = Split-Path $LogPath -Leaf
        
        # Crear HTML optimizado para lectura
        $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Log del Sistema de Backup</title>
    <style>
        body { 
            font-family: 'Courier New', monospace; 
            font-size: 11px; 
            line-height: 1.3;
            margin: 20px;
            background-color: #f8f9fa;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header { 
            font-size: 18px; 
            font-weight: bold; 
            margin-bottom: 20px;
            text-align: center;
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 15px;
        }
        .info { 
            background-color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px; 
            font-size: 12px;
            color: #34495e;
        }
        .log-content { 
            background-color: #2c3e50;
            color: #ecf0f1;
            padding: 20px;
            border-radius: 5px;
            overflow-x: auto;
            white-space: pre-wrap;
            word-wrap: break-word;
            font-family: 'Courier New', monospace;
            font-size: 11px;
            line-height: 1.4;
        }
        .line { 
            margin: 2px 0; 
            padding: 1px 0;
        }
        .line:hover {
            background-color: rgba(52, 152, 219, 0.2);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">Log del Sistema de Backup</div>
        <div class="info">
            <strong>Archivo:</strong> $fileName<br>
            <strong>Fecha de conversion:</strong> $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')<br>
            <strong>Total de lineas:</strong> $($logContent.Count)
        </div>
        <div class="log-content">
"@
        
        # Agregar contenido del log linea por linea
        foreach ($line in $logContent) {
            $escapedLine = [System.Web.HttpUtility]::HtmlEncode($line)
            $htmlContent += "<div class=`"line`">$escapedLine</div>`n"
        }
        
        $htmlContent += @"
        </div>
    </div>
</body>
</html>
"@
        
        # Guardar HTML
        $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8
        
        if (Test-Path $OutputPath) {
            $htmlSize = (Get-Item $OutputPath).Length
            Write-Output "[OK] HTML creado: $(Split-Path $OutputPath -Leaf) ($([math]::Round($htmlSize/1KB, 1))KB)" "Green"
            return $true
        } else {
            Write-Output "[ERROR] No se pudo crear el HTML" "Red"
            return $false
        }
    }
    catch {
        Write-Output "[ERROR] Error convirtiendo a HTML: $($_.Exception.Message)" "Red"
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
            
            # Crear formulario multipart manualmente pero mas simple
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
    # Intentar convertir a HTML
    $htmlPath = $LogPath -replace '\.log$', '.html'
    $fileToSend = $LogPath
    $caption = "Log del Sistema de Backup`nFecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
    
    if (Convert-LogToHtml -LogPath $LogPath -OutputPath $htmlPath) {
        if (Test-Path $htmlPath) {
            $fileToSend = $htmlPath
            $caption = "Log del Sistema de Backup (HTML)`nFecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
            Write-Output "Enviando como HTML..." "Green"
        } else {
            Write-Output "Enviando log original..." "Yellow"
        }
    } else {
        Write-Output "Enviando log original..." "Yellow"
    }
    
    if (-not (Send-TelegramFile -FilePath $fileToSend -Caption $caption)) {
        $Success = $false
    }
    
    # Limpiar archivos temporales
    if ($fileToSend -ne $LogPath -and (Test-Path $fileToSend)) {
        Remove-Item $fileToSend -ErrorAction SilentlyContinue
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
