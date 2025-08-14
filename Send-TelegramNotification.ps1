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

# Configurar TLS 1.2 para evitar errores SSL/TLS con Telegram API
try {
    # Configurar protocolos de seguridad más robustos para Windows Server
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [Net.ServicePointManager]::CheckCertificateRevocationList = $false
    [Net.ServicePointManager]::MaxServicePointIdleTime = 30000
    
    if (-not $Silent) {
        Write-Verbose "Configuración de seguridad SSL/TLS aplicada para Windows Server"
    }
}
catch {
    if (-not $Silent) {
        Write-Warning "No se pudo configurar completamente SSL/TLS: $($_.Exception.Message)"
    }
}

# Configurar encoding UTF-8 para evitar problemas de caracteres
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
    if (-not $Silent) {
        Write-Verbose "No se pudo configurar encoding UTF-8"
    }
}

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
        # Asegurar codificación UTF-8 correcta para la consola
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        }
        catch {
            # Si no se puede cambiar la codificación, continuar normalmente
        }
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
    
    # Configurar TLS antes de cada llamada HTTP
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }
    catch {
        Write-Output "[WARN] No se pudo configurar TLS: $($_.Exception.Message)" "Yellow"
    }
    
    $maxRetries = 3
    $retryDelay = 2
    
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $Uri = "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
            
            $Body = @{
                chat_id = $TELEGRAM_CHAT_ID
                text = $Text
                parse_mode = "HTML"
            }
            
            if ($attempt -eq 1) {
                Write-Output "Enviando mensaje a Telegram..." "Cyan"
            } else {
                Write-Output "Reintentando envío de mensaje (intento $attempt)..." "Yellow"
            }
            
            # Usar Invoke-WebRequest en lugar de Invoke-RestMethod para mejor control de errores
            $Response = Invoke-WebRequest -Uri $Uri -Method Post -Body $Body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
            
            if ($Response.StatusCode -eq 200) {
                $JsonResponse = $Response.Content | ConvertFrom-Json
                if ($JsonResponse.ok) {
                    Write-Output "[OK] Mensaje enviado exitosamente" "Green"
                    return $true
                } else {
                    Write-Output "[ERROR] Error enviando mensaje: $($JsonResponse.description)" "Red"
                    return $false
                }
            } else {
                Write-Output "[ERROR] Error HTTP: $($Response.StatusCode)" "Red"
                if ($attempt -lt $maxRetries) {
                    Write-Output "Esperando $retryDelay segundos antes del siguiente intento..." "Gray"
                    Start-Sleep -Seconds $retryDelay
                    continue
                }
                return $false
            }
        }
        catch {
            Write-Output "[ERROR] Excepción enviando mensaje (intento $attempt): $($_.Exception.Message)" "Red"
            
            if ($attempt -lt $maxRetries) {
                Write-Output "Esperando $retryDelay segundos antes del siguiente intento..." "Gray"
                Start-Sleep -Seconds $retryDelay
            } else {
                Write-Output "[ERROR] Error después de $maxRetries intentos" "Red"
                return $false
            }
        }
    }
    
    return $false
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
    
    # Configurar TLS antes de cada llamada HTTP
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }
    catch {
        Write-Output "[WARN] No se pudo configurar TLS: $($_.Exception.Message)" "Yellow"
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
            
            # Configurar curl con opciones más robustas para Windows Server
            $curlArgs = @(
                "-X", "POST"
                "--tlsv1.2"                    # Forzar TLS 1.2
                "--ssl-no-revoke"              # Evitar verificación de revocación SSL (común en servidores)
                "--max-time", "120"            # Timeout de 2 minutos
                "--retry", "3"                 # 3 reintentos
                "--retry-delay", "5"           # 5 segundos entre reintentos
                "--show-error"                 # Mostrar errores detallados
                "--fail"                       # Fallar en códigos HTTP de error
                "-F", "chat_id=$TELEGRAM_CHAT_ID"
                "-F", "document=@`"$FilePath`""
            )
            
            # Agregar caption si existe
            if (-not [string]::IsNullOrEmpty($Caption)) {
                $curlArgs += "-F"
                $curlArgs += "caption=$Caption"
            }
            
            # Agregar URL al final
            $curlArgs += $Uri
            
            # Ejecutar curl con captura de error mejorada
            try {
                Write-Output "Ejecutando: curl $($curlArgs -join ' ')" "Gray"
                
                # Ejecutar curl y capturar tanto salida como error
                $curlOutput = & $curlPath $curlArgs 2>&1
                $curlExitCode = $LASTEXITCODE
                
                Write-Output "Codigo de salida curl: $curlExitCode" "Gray"
                
                if ($curlExitCode -eq 0) {
                    # Parsear respuesta JSON
                    try {
                        $response = $curlOutput | Where-Object { $_ -match '^\{.*\}$' } | ConvertFrom-Json
                        if ($response.ok) {
                            Write-Output "[OK] Archivo enviado exitosamente via curl" "Green"
                            return $true
                        } else {
                            Write-Output "[ERROR] Error en respuesta Telegram: $($response.description)" "Red"
                            Write-Output "Respuesta completa: $curlOutput" "Gray"
                        }
                    }
                    catch {
                        Write-Output "[WARN] Respuesta curl no JSON válido: $curlOutput" "Yellow"
                        # Si hay respuesta pero no es JSON válido, asumir éxito si no hay error HTTP
                        if ($curlOutput -notmatch "error|failed|HTTP") {
                            Write-Output "[OK] Archivo probablemente enviado (respuesta no estándar)" "Green"
                            return $true
                        }
                    }
                } else {
                    Write-Output "[ERROR] Error ejecutando curl: codigo $curlExitCode" "Red"
                    Write-Output "Salida de error curl: $curlOutput" "Red"
                    
                    # Códigos de error curl más comunes y sus significados
                    $curlErrorMessage = switch ($curlExitCode) {
                        6 { "No se pudo resolver el host (DNS)" }
                        7 { "No se pudo conectar al servidor" }
                        28 { "Timeout de operación" }
                        35 { "Error SSL/TLS - problema de handshake" }
                        51 { "Certificado SSL no válido" }
                        52 { "El servidor no respondió" }
                        56 { "Error recibiendo datos de red" }
                        60 { "Problema con certificado CA" }
                        77 { "Error SSL CA cert (path? access rights?)" }
                        default { "Error desconocido" }
                    }
                    Write-Output "Descripción del error: $curlErrorMessage" "Red"
                }
                
                # Si curl falla, intentar con método PowerShell como fallback
                Write-Output "Curl falló, intentando con método PowerShell..." "Yellow"
            }
            catch {
                Write-Output "[ERROR] Excepción ejecutando curl: $($_.Exception.Message)" "Red"
                Write-Output "Intentando con método PowerShell..." "Yellow"
            }
        }
        # Método PowerShell mejorado como fallback o método principal
        Write-Output "Usando método PowerShell nativo..." "Gray"
        
        $maxRetries = 3
        $retryDelay = 3
        
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                if ($attempt -gt 1) {
                    Write-Output "Reintentando envío de archivo (intento $attempt)..." "Yellow"
                }
                
                # Configurar protocolo de seguridad
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
                
                $uri = "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument"
                $fileName = Split-Path $FilePath -Leaf
                
                # Método simplificado usando Add-Type para formularios multipart
                Add-Type -AssemblyName System.Net.Http
                
                $httpClient = New-Object System.Net.Http.HttpClient
                $httpClient.Timeout = [TimeSpan]::FromMinutes(5)  # 5 minutos timeout
                
                try {
                    $multipartContent = New-Object System.Net.Http.MultipartFormDataContent
                    
                    # Agregar chat_id
                    $chatIdContent = New-Object System.Net.Http.StringContent($TELEGRAM_CHAT_ID)
                    $multipartContent.Add($chatIdContent, "chat_id")
                    
                    # Agregar caption si existe
                    if (-not [string]::IsNullOrEmpty($Caption)) {
                        $captionContent = New-Object System.Net.Http.StringContent($Caption)
                        $multipartContent.Add($captionContent, "caption")
                    }
                    
                    # Leer archivo y agregarlo
                    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
                    $fileContent = New-Object System.Net.Http.ByteArrayContent($fileBytes)
                    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
                    $multipartContent.Add($fileContent, "document", $fileName)
                    
                    # Enviar request
                    Write-Output "Enviando archivo usando HttpClient..." "Gray"
                    $response = $httpClient.PostAsync($uri, $multipartContent).Result
                    
                    if ($response.IsSuccessStatusCode) {
                        $responseContent = $response.Content.ReadAsStringAsync().Result
                        $jsonResponse = $responseContent | ConvertFrom-Json
                        
                        if ($jsonResponse.ok) {
                            Write-Output "[OK] Archivo enviado exitosamente via PowerShell" "Green"
                            return $true
                        } else {
                            Write-Output "[ERROR] Error en respuesta Telegram: $($jsonResponse.description)" "Red"
                        }
                    } else {
                        Write-Output "[ERROR] Error HTTP: $($response.StatusCode) - $($response.ReasonPhrase)" "Red"
                    }
                }
                finally {
                    # Limpiar recursos
                    if ($multipartContent) { $multipartContent.Dispose() }
                    if ($httpClient) { $httpClient.Dispose() }
                }
            }
            catch {
                Write-Output "[ERROR] Excepción enviando archivo (intento $attempt): $($_.Exception.Message)" "Red"
                if ($_.Exception.InnerException) {
                    Write-Output "Error interno: $($_.Exception.InnerException.Message)" "Red"
                }
                
                if ($attempt -lt $maxRetries) {
                    Write-Output "Esperando $retryDelay segundos antes del siguiente intento..." "Gray"
                    Start-Sleep -Seconds $retryDelay
                } else {
                    Write-Output "[ERROR] Error después de $maxRetries intentos con PowerShell" "Red"
                }
            }
        }
        
        return $false
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

# Diagnóstico básico de conectividad (solo si no es modo silencioso)
if (-not $Silent) {
    Write-Output "Verificando conectividad..." "Gray"
    try {
        $telegramHost = "api.telegram.org"
        $pingResult = Test-NetConnection -ComputerName $telegramHost -Port 443 -InformationLevel Quiet -ErrorAction SilentlyContinue
        if ($pingResult) {
            Write-Output "[OK] Conectividad a ${telegramHost}: disponible" "Green"
        } else {
            Write-Output "[WARN] Conectividad a ${telegramHost}: limitada o bloqueada" "Yellow"
            Write-Output "Esto puede indicar problemas de firewall, proxy o DNS" "Yellow"
        }
    }
    catch {
        Write-Output "[WARN] No se pudo verificar conectividad: $($_.Exception.Message)" "Yellow"
    }
    
    # Verificar versión de PowerShell
    Write-Output "PowerShell versión: $($PSVersionTable.PSVersion)" "Gray"
    Write-Output "SO: $($PSVersionTable.OS)" "Gray"
}

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
