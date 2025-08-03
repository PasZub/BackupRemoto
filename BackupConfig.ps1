# Configuración del Sistema de Backup PowerShell
# Archivo: BackupConfig.ps1

@{
    # Rutas de aplicaciones
    RclonePath   = ".\rclone.exe"
    WinRarPath   = "C:\Program Files\WinRAR\winrar.exe"
    
    # Directorios
    WorkingDir   = "\Programas\Nube"
    TempDir      = "D:\send1"

    # Configuración de servidor remoto - rclone
    RcloneRemote = "InfoCloud"  # Nombre del remote configurado en rclone
    RcloneConfig = ".rclone.conf"  # Ruta al archivo de configuración de rclone
    
    # Configuración de rclone
    RcloneUploadOnly = $true      # Solo subir archivos, no sincronizar
    RcloneRetryCount = 3          # Número de reintentos en caso de error
    RcloneTransfers = 4           # Número de transferencias paralelas
    RcloneCheckers = 8            # Número de verificadores paralelos
    RcloneBandwidth = "0"         # Límite de ancho de banda (0 = sin límite)
    RcloneProgress = $true        # Mostrar progreso de transferencia
    
    # Configuración de ruta remota
    RemotePath   = "/buffer/"     # Ruta en el servidor remoto
    
    # Limpieza automática del servidor
    RcloneDeleteOlderThan = 30    # Días para borrar archivos antiguos del servidor
    RcloneDeleteEnabled = $true   # Habilitar limpieza automática
    
    # Configuración de logging
    LogEnabled = $true
    LogPath = ".\BackupLogs"  # Logs dentro del TempDir para sincronización
    LogRetentionDays = 30
}
