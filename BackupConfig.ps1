# Configuración del Sistema de Backup PowerShell
# Archivo: BackupConfig.ps1

@{
    # Rutas de aplicaciones
    RclonePath   = ".\rclone.exe"
    WinRarPath   = "C:\Program Files\WinRAR\winrar.exe"
    
    # Directorios
    WorkingDir   = "\Programas\BackupRemoto"
    TempDir      = "D:\send1"

    # Configuración de servidor remoto - rclone
    RcloneRemote = "InfoCloud"  # Nombre del remote configurado en rclone
    RcloneConfig = ""  # Ruta al archivo de configuración de rclone
    
    # Configuración de rclone
    RcloneUploadOnly = $true      # Solo subir archivos, no sincronizar
    RcloneRetryCount = 3          # Número de reintentos en caso de error
    RcloneBandwidth = "0"         # Límite de ancho de banda (0 = sin límite)
    RcloneProgress = $true        # Mostrar progreso de transferencia
    RcloneTransfers = 2
    RcloneCheckers = 16
    RcloneBufferSize = "32M"
    RcloneMultiThreadCutoff = "250M"
    RcloneMultiThreadStreams = 4
    RcloneTimeout = "5m"
    RcloneContimeout = "60s"
    RcloneLowLevelRetries = 10
    RcloneUseServerModtime = $true
    
    # Limpieza automática del servidor
    RcloneDeleteOlderThan = 30    # Días para borrar archivos antiguos del servidor
    RcloneDeleteEnabled = $true   # Habilitar limpieza automática
    
    # Configuración de logging
    LogEnabled = $true
    LogPath = ".\BackupLogs"  # Logs dentro del TempDir para sincronización
    LogRetentionDays = 30
}
