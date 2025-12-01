#Requires -Version 5.1
<#
.SYNOPSIS
    Actualiza automáticamente el sistema de backup desde GitHub

.DESCRIPTION
    Descarga la última versión del sistema de backup desde el repositorio GitHub
    sin necesidad de tener Git instalado. Usa la API de GitHub para obtener el ZIP
    de la última versión.

.PARAMETER Force
    Fuerza la actualización sin preguntar confirmación

.PARAMETER SkipBackup
    No crea backup de la configuración actual antes de actualizar

.EXAMPLE
    .\Update-BackupSystem.ps1
    .\Update-BackupSystem.ps1 -Force
    .\Update-BackupSystem.ps1 -Force -SkipBackup
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipBackup
)

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

# Información del repositorio GitHub
$GITHUB_OWNER = "PasZub"
$GITHUB_REPO = "BackupRemoto"
$GITHUB_BRANCH = "master"

# Rutas
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$TempUpdateDir = Join-Path $env:TEMP "BackupRemoto_Update_$(Get-Date -Format 'yyyyMMddHHmmss')"
$BackupConfigDir = Join-Path $ScriptPath "Config_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Archivos que NO se deben sobrescribir (configuraciones del usuario)
$ProtectedFiles = @(
    "BackupConfig.ps1",
    "UserConfig.ps1",
    "TelegramConfig.ps1"
)

# ============================================================================
# FUNCIONES
# ============================================================================

function Write-ColoredOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Get-CurrentVersion {
    $versionFile = Join-Path $ScriptPath "VERSION.txt"
    if (Test-Path $versionFile) {
        return Get-Content $versionFile -Raw -ErrorAction SilentlyContinue
    }
    return "Desconocida"
}

function Test-InternetConnection {
    try {
        $null = Test-NetConnection -ComputerName "api.github.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-LatestReleaseInfo {
    try {
        Write-ColoredOutput "Consultando última versión en GitHub..." "Cyan"
        
        # Configurar TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        
        # URL de la API de GitHub para obtener la última release
        $apiUrl = "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest"
        
        # Intentar obtener la última release
        try {
            $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop -UseBasicParsing
            return @{
                Version = $response.tag_name
                ZipUrl = $response.zipball_url
                PublishedAt = $response.published_at
                IsRelease = $true
            }
        }
        catch {
            # Si no hay releases, usar el branch directamente
            Write-ColoredOutput "No hay releases publicadas, usando branch $GITHUB_BRANCH" "Yellow"
            $zipUrl = "https://github.com/$GITHUB_OWNER/$GITHUB_REPO/archive/refs/heads/$GITHUB_BRANCH.zip"
            
            # Obtener el último commit del branch
            try {
                $commitsUrl = "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/commits/$GITHUB_BRANCH"
                $commitInfo = Invoke-RestMethod -Uri $commitsUrl -Method Get -ErrorAction Stop -UseBasicParsing
                
                return @{
                    Version = if ($commitInfo.sha) { $commitInfo.sha.Substring(0, 7) } else { "latest" }
                    ZipUrl = $zipUrl
                    PublishedAt = if ($commitInfo.commit.author.date) { $commitInfo.commit.author.date } else { Get-Date }
                    IsRelease = $false
                }
            }
            catch {
                # Si falla todo, usar valores por defecto
                Write-ColoredOutput "Usando valores por defecto" "Yellow"
                return @{
                    Version = "master-latest"
                    ZipUrl = $zipUrl
                    PublishedAt = Get-Date
                    IsRelease = $false
                }
            }
        }
    }
    catch {
        Write-ColoredOutput "[ERROR] No se pudo consultar GitHub: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Backup-Configuration {
    if ($SkipBackup) {
        Write-ColoredOutput "Omitiendo backup de configuración (parámetro -SkipBackup)" "Yellow"
        return $true
    }
    
    try {
        Write-ColoredOutput "Creando backup de archivos de configuración..." "Cyan"
        
        # Crear directorio de backup
        New-Item -ItemType Directory -Path $BackupConfigDir -Force | Out-Null
        
        $backedUpCount = 0
        foreach ($file in $ProtectedFiles) {
            $sourcePath = Join-Path $ScriptPath $file
            if (Test-Path $sourcePath) {
                $destPath = Join-Path $BackupConfigDir $file
                Copy-Item -Path $sourcePath -Destination $destPath -Force
                Write-ColoredOutput "  Backup creado: $file" "Green"
                $backedUpCount++
            }
        }
        
        if ($backedUpCount -gt 0) {
            Write-ColoredOutput "[OK] Backup de configuración creado en: $BackupConfigDir" "Green"
            return $true
        } else {
            Write-ColoredOutput "[WARN] No se encontraron archivos de configuración para respaldar" "Yellow"
            return $true
        }
    }
    catch {
        Write-ColoredOutput "[ERROR] Error creando backup: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Download-UpdatePackage {
    param([string]$ZipUrl)
    
    try {
        Write-ColoredOutput "Descargando actualización desde GitHub..." "Cyan"
        
        # Crear directorio temporal
        New-Item -ItemType Directory -Path $TempUpdateDir -Force | Out-Null
        
        $zipFile = Join-Path $TempUpdateDir "update.zip"
        
        # Configurar TLS
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Descargar el archivo ZIP
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell-BackupSystem-Updater")
        
        Write-ColoredOutput "Descargando archivo..." "Gray"
        $webClient.DownloadFile($ZipUrl, $zipFile)
        $webClient.Dispose()
        
        if (Test-Path $zipFile) {
            $fileSize = (Get-Item $zipFile).Length / 1MB
            Write-ColoredOutput "[OK] Descarga completada: $([math]::Round($fileSize, 2)) MB" "Green"
            return $zipFile
        } else {
            Write-ColoredOutput "[ERROR] No se pudo descargar el archivo" "Red"
            return $null
        }
    }
    catch {
        Write-ColoredOutput "[ERROR] Error descargando actualización: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Extract-UpdatePackage {
    param([string]$ZipFile)
    
    try {
        Write-ColoredOutput "Extrayendo archivos..." "Cyan"
        
        # Extraer el ZIP
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extractPath = Join-Path $TempUpdateDir "extracted"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFile, $extractPath)
        
        # GitHub crea una carpeta con el nombre del repo, encontrarla
        $repoFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
        
        if ($repoFolder) {
            Write-ColoredOutput "[OK] Archivos extraídos correctamente" "Green"
            return $repoFolder.FullName
        } else {
            Write-ColoredOutput "[ERROR] No se encontró la carpeta del repositorio" "Red"
            return $null
        }
    }
    catch {
        Write-ColoredOutput "[ERROR] Error extrayendo archivos: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Install-Update {
    param([string]$SourcePath)
    
    try {
        Write-ColoredOutput "Instalando actualización..." "Cyan"
        
        # Obtener todos los archivos del paquete de actualización
        $files = Get-ChildItem -Path $SourcePath -File -Recurse
        $updatedCount = 0
        $skippedCount = 0
        
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($SourcePath.Length + 1)
            $destPath = Join-Path $ScriptPath $relativePath
            $fileName = Split-Path $relativePath -Leaf
            
            # Verificar si es un archivo protegido
            if ($ProtectedFiles -contains $fileName) {
                Write-ColoredOutput "  Omitido (protegido): $relativePath" "Yellow"
                $skippedCount++
                continue
            }
            
            # Crear directorio destino si no existe
            $destDir = Split-Path $destPath -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            # Copiar archivo
            Copy-Item -Path $file.FullName -Destination $destPath -Force
            Write-ColoredOutput "  Actualizado: $relativePath" "Green"
            $updatedCount++
        }
        
        Write-ColoredOutput "`n[OK] Actualización completada:" "Green"
        Write-ColoredOutput "  • Archivos actualizados: $updatedCount" "White"
        Write-ColoredOutput "  • Archivos protegidos: $skippedCount" "White"
        
        return $true
    }
    catch {
        Write-ColoredOutput "[ERROR] Error instalando actualización: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Cleanup-TempFiles {
    try {
        if (Test-Path $TempUpdateDir) {
            Remove-Item -Path $TempUpdateDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColoredOutput "Archivos temporales eliminados" "Gray"
        }
    }
    catch {
        Write-ColoredOutput "[WARN] No se pudieron eliminar archivos temporales: $TempUpdateDir" "Yellow"
    }
}

function Save-VersionInfo {
    param([string]$Version)
    
    try {
        $versionFile = Join-Path $ScriptPath "VERSION.txt"
        "Versión: $Version`nActualizado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $versionFile -Encoding UTF8 -Force
    }
    catch {
        Write-ColoredOutput "[WARN] No se pudo guardar información de versión" "Yellow"
    }
}

# ============================================================================
# SCRIPT PRINCIPAL
# ============================================================================

function Main {
    Write-ColoredOutput "`n========================================================" "Cyan"
    Write-ColoredOutput "  ACTUALIZACION AUTOMATICA - SISTEMA DE BACKUP" "Cyan"
    Write-ColoredOutput "========================================================`n" "Cyan"
    
    # Verificar conexión a Internet
    Write-ColoredOutput "Verificando conexión a Internet..." "Cyan"
    if (-not (Test-InternetConnection)) {
        Write-ColoredOutput "[ERROR] No hay conexión a Internet o no se puede acceder a GitHub" "Red"
        exit 1
    }
    Write-ColoredOutput "[OK] Conexión disponible" "Green"
    
    # Obtener versión actual
    $currentVersion = Get-CurrentVersion
    Write-ColoredOutput "Versión actual: $currentVersion" "White"
    
    # Consultar última versión disponible
    $releaseInfo = Get-LatestReleaseInfo
    if (-not $releaseInfo) {
        Write-ColoredOutput "[ERROR] No se pudo obtener información de la última versión" "Red"
        exit 1
    }
    
    Write-ColoredOutput "Última versión disponible: $($releaseInfo.Version)" "White"
    Write-ColoredOutput "Fecha de publicación: $($releaseInfo.PublishedAt)" "Gray"
    
    # Verificar si hay actualización disponible
    if ($currentVersion -eq $releaseInfo.Version -and -not $Force) {
        Write-ColoredOutput "`n[OK] Ya tienes la última versión instalada" "Green"
        exit 0
    }
    
    # Confirmar actualización
    if (-not $Force) {
        Write-ColoredOutput "`n¿Deseas actualizar el sistema de backup? (S/N): " "Yellow" -NoNewline
        $response = Read-Host
        if ($response -ne "S" -and $response -ne "s") {
            Write-ColoredOutput "Actualización cancelada por el usuario" "Yellow"
            exit 0
        }
    }
    
    Write-ColoredOutput "`nIniciando proceso de actualización..." "Cyan"
    
    try {
        # 1. Backup de configuración
        if (-not (Backup-Configuration)) {
            Write-ColoredOutput "[ERROR] No se pudo crear backup de configuración" "Red"
            if (-not $Force) {
                Write-ColoredOutput "¿Deseas continuar sin backup? (S/N): " "Yellow" -NoNewline
                $response = Read-Host
                if ($response -ne "S" -and $response -ne "s") {
                    exit 1
                }
            }
        }
        
        # 2. Descargar actualización
        $zipFile = Download-UpdatePackage -ZipUrl $releaseInfo.ZipUrl
        if (-not $zipFile) {
            Write-ColoredOutput "[ERROR] No se pudo descargar la actualización" "Red"
            exit 1
        }
        
        # 3. Extraer archivos
        $extractedPath = Extract-UpdatePackage -ZipFile $zipFile
        if (-not $extractedPath) {
            Write-ColoredOutput "[ERROR] No se pudo extraer la actualización" "Red"
            Cleanup-TempFiles
            exit 1
        }
        
        # 4. Instalar actualización
        if (-not (Install-Update -SourcePath $extractedPath)) {
            Write-ColoredOutput "[ERROR] No se pudo instalar la actualización" "Red"
            Cleanup-TempFiles
            exit 1
        }
        
        # 5. Guardar información de versión
        Save-VersionInfo -Version $releaseInfo.Version
        
        # 6. Limpiar archivos temporales
        Cleanup-TempFiles
        
        # Mensaje final
        Write-ColoredOutput "`n========================================================" "Green"
        Write-ColoredOutput "  ACTUALIZACION COMPLETADA EXITOSAMENTE" "Green"
        Write-ColoredOutput "========================================================`n" "Green"
        Write-ColoredOutput "Versión instalada: $($releaseInfo.Version)" "White"
        
        if (Test-Path $BackupConfigDir) {
            Write-ColoredOutput "`nBackup de configuración guardado en:" "Cyan"
            Write-ColoredOutput "  $BackupConfigDir" "Gray"
        }
        
        exit 0
    }
    catch {
        Write-ColoredOutput "`n[ERROR CRÍTICO] Error durante la actualización: $($_.Exception.Message)" "Red"
        Cleanup-TempFiles
        exit 1
    }
}

# Ejecutar script principal
Main
