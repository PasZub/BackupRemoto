#Requires -Version 5.1
<#
.SYNOPSIS
    Script de diagnostico para notificaciones Telegram en Windows Server

.DESCRIPTION
    Prueba la conectividad y configuracion de Telegram paso a paso
#>

param(
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`n=== DIAGNOSTICO TELEGRAM PARA WINDOWS SERVER ===" -ForegroundColor Cyan
Write-Host "Fecha: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# 1. Verificar PowerShell
Write-Host "[1] Verificando version de PowerShell..." -ForegroundColor Yellow
Write-Host "    Version: $($PSVersionTable.PSVersion)" -ForegroundColor Green
Write-Host "    SO: $($PSVersionTable.OS)" -ForegroundColor Green
Write-Host ""

# 2. Verificar archivos necesarios
Write-Host "[2] Verificando archivos necesarios..." -ForegroundColor Yellow

$files = @(
    "TelegramConfig.ps1",
    "Send-TelegramNotification.ps1"
)

$allFilesOk = $true
foreach ($file in $files) {
    $filePath = Join-Path $ScriptPath $file
    if (Test-Path $filePath) {
        Write-Host "    [OK] $file encontrado" -ForegroundColor Green
    } else {
        Write-Host "    [ERROR] $file NO encontrado" -ForegroundColor Red
        $allFilesOk = $false
    }
}

if (-not $allFilesOk) {
    Write-Host "`n[ERROR] Faltan archivos necesarios. Abortando." -ForegroundColor Red
    exit 1
}
Write-Host ""

# 3. Cargar y validar configuracion
Write-Host "[3] Cargando configuracion de Telegram..." -ForegroundColor Yellow

try {
    $TelegramConfigPath = Join-Path $ScriptPath "TelegramConfig.ps1"
    $TelegramConfig = & $TelegramConfigPath
    $TELEGRAM_BOT_TOKEN = $TelegramConfig.BotToken
    $TELEGRAM_CHAT_ID = $TelegramConfig.ChatId
    
    Write-Host "    [OK] Configuracion cargada" -ForegroundColor Green
    
    # Validar credenciales
    if ([string]::IsNullOrEmpty($TELEGRAM_BOT_TOKEN) -or $TELEGRAM_BOT_TOKEN -eq "TU_BOT_TOKEN_AQUI") {
        Write-Host "    [ERROR] Bot Token no configurado correctamente" -ForegroundColor Red
        exit 1
    } else {
        $tokenPreview = $TELEGRAM_BOT_TOKEN.Substring(0, [Math]::Min(15, $TELEGRAM_BOT_TOKEN.Length)) + "..."
        Write-Host "    Bot Token: $tokenPreview" -ForegroundColor Green
    }
    
    if ([string]::IsNullOrEmpty($TELEGRAM_CHAT_ID) -or $TELEGRAM_CHAT_ID -eq "TU_CHAT_ID_AQUI") {
        Write-Host "    [ERROR] Chat ID no configurado correctamente" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "    Chat ID: $TELEGRAM_CHAT_ID" -ForegroundColor Green
    }
}
catch {
    Write-Host "    [ERROR] Error cargando configuracion: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 4. Verificar conectividad a Internet
Write-Host "[4] Verificando conectividad a Internet..." -ForegroundColor Yellow

$testHosts = @(
    @{Host = "8.8.8.8"; Port = 443; Name = "Google DNS generico"},
    @{Host = "api.telegram.org"; Port = 443; Name = "Telegram API"}
)

foreach ($test in $testHosts) {
    try {
        Write-Host "    Probando $($test.Name)..." -NoNewline
        $result = Test-NetConnection -ComputerName $test.Host -Port $test.Port -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
        if ($result) {
            Write-Host " [OK]" -ForegroundColor Green
        } else {
            Write-Host " [FALLO]" -ForegroundColor Red
        }
    }
    catch {
        Write-Host " [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host ""

# 5. Verificar configuracion SSL/TLS
Write-Host "[5] Configurando SSL/TLS..." -ForegroundColor Yellow

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [Net.ServicePointManager]::CheckCertificateRevocationList = $false
    Write-Host "    [OK] SSL/TLS configurado correctamente" -ForegroundColor Green
}
catch {
    Write-Host "    [WARN] Problema configurando SSL/TLS: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""

# 6. Probar API de Telegram con getMe
Write-Host "[6] Probando conexion con API de Telegram..." -ForegroundColor Yellow

try {
    $uri = "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getMe"
    Write-Host "    Llamando a getMe..." -NoNewline
    
    $response = Invoke-RestMethod -Uri $uri -Method Get -UseBasicParsing -ErrorAction Stop
    
    if ($response.ok) {
        Write-Host " [OK]" -ForegroundColor Green
        Write-Host "    Bot: @$($response.result.username)" -ForegroundColor Green
        Write-Host "    Nombre: $($response.result.first_name)" -ForegroundColor Green
    } else {
        Write-Host " [ERROR]" -ForegroundColor Red
        Write-Host "    Respuesta: $($response | ConvertTo-Json)" -ForegroundColor Red
    }
}
catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "    Respuesta del servidor: $responseBody" -ForegroundColor Red
        }
        catch {}
    }
}
Write-Host ""

# 7. Enviar mensaje de prueba
Write-Host "[7] Enviando mensaje de prueba..." -ForegroundColor Yellow

try {
    $nl = [char]10
    $testMessage = "[TEST] Prueba de notificacion desde Windows Server${nl}Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    $uri = "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    $body = @{
        chat_id = $TELEGRAM_CHAT_ID
        text = $testMessage
    } | ConvertTo-Json -Compress
    
    Write-Host "    Enviando mensaje..." -NoNewline
    
    $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json; charset=utf-8" -UseBasicParsing -ErrorAction Stop
    
    if ($response.ok) {
        Write-Host " [OK]" -ForegroundColor Green
        Write-Host "    Message ID: $($response.result.message_id)" -ForegroundColor Green
    } else {
        Write-Host " [ERROR]" -ForegroundColor Red
        Write-Host "    Respuesta: $($response | ConvertTo-Json)" -ForegroundColor Red
    }
}
catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "    Respuesta del servidor: $responseBody" -ForegroundColor Red
        }
        catch {}
    }
}
Write-Host ""

# 8. Verificar disponibilidad de curl
Write-Host "[8] Verificando curl.exe..." -ForegroundColor Yellow

$curlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if ($curlPath) {
    Write-Host "    [OK] curl.exe encontrado en: $curlPath" -ForegroundColor Green
    try {
        $curlVersion = & curl.exe --version 2>&1 | Select-Object -First 1
        Write-Host "    Version: $curlVersion" -ForegroundColor Green
    }
    catch {}
} else {
    Write-Host "    [WARN] curl.exe no encontrado - no es critico" -ForegroundColor Yellow
}
Write-Host ""

# 9. Probar script completo de notificacion
Write-Host "[9] Probando script completo Send-TelegramNotification.ps1..." -ForegroundColor Yellow

try {
    $notificationScript = Join-Path $ScriptPath "Send-TelegramNotification.ps1"
    $testMsg = "[TEST] Mensaje de prueba completo desde $env:COMPUTERNAME"
    
    Write-Host "    Ejecutando script en modo silencioso..." -ForegroundColor Gray
    $output = & $notificationScript -Message $testMsg -Silent 2>&1
    
    # Mostrar solo errores criticos
    $errors = $output | Where-Object { $_ -match '\[ERROR\]' }
    if ($errors) {
        $errors | ForEach-Object {
            Write-Host "    $_" -ForegroundColor Red
        }
    }
    
    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
        Write-Host "    [OK] Script ejecutado correctamente - Mensaje enviado" -ForegroundColor Green
    } else {
        Write-Host "    [ERROR] Script termino con codigo: $LASTEXITCODE" -ForegroundColor Red
    }
}
catch {
    Write-Host "    [ERROR] Error ejecutando script: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "=== DIAGNOSTICO COMPLETADO ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Si todos los tests pasaron correctamente, las notificaciones deberian funcionar." -ForegroundColor Green
Write-Host "Si algun test fallo, revisa el error especifico y la configuracion correspondiente." -ForegroundColor Yellow
Write-Host ""
