# Configuración de Usuario - Sistema de Backup PowerShell
# Archivo: UserConfig.ps1
# Este archivo contiene la configuración específica del usuario

@{
    # Nombre usuario
    Usuario      = "pascual" 
    # Configuración de ruta remota
    RemotePath   = "/buffer/"

    # Configuración de días para backup completo
    # Días de la semana para backup completo (0=Domingo, 1=Lunes, 2=Martes, 3=Miércoles, 4=Jueves, 5=Viernes, 6=Sábado)
    BackupCompletoDias = @(0,3)  # Solo domingo por defecto

    # Configuración de backup
    # Documentos (habilitar/deshabilitar backup)
    DocumentosEnabled = $true
    DocumentosSource = @(
        "D:\pc_pascual_20250602\user_pascual\Nextcloud\Documentos\*"
    )
    
    # Extensiones excluidas para documentos
    DocumentosExclude = @(
        "*.acc"
    )

    # Usuarios (habilitar/deshabilitar backup)
    UsuariosEnabled = $false
    # Fuentes de usuarios (colección para múltiples ubicaciones)
    UsuariosSource = @(
        "C:\users"      # Ubicación principal
        # "C:\Users"    # Ubicación alternativa (comentada)
        # "D:\profiles" # Ubicación adicional futura (comentada)
    )
    
    # Extensiones excluidas para usuarios
    UsuariosExclude = @(
        "*.pst",
        "*.acc", 
        "*.exe"
    )
    
    # Programas (deshabilitado por defecto, como en el original)
    ProgramasEnabled = $false
    ProgramasSource = @(
        "C:\Program Files (x86)\iVMS-4200 Site\*",
        "C:\Program Files (x86)\Tryton-5.0\*",
        "C:\Nube\*",
        "e:\clinicas\*",
        "e:\denuncia\*",
        "e:\programas\*",
        "e:\remesas\*",
        "e:\sanatori\*",
        "c:\*.tps",
        "C:\LibFactu_elec_AS\*"
    )
    
    # Extensiones excluidas para programas
    ProgramasExclude = @(
        "*.acc",
        "ivms4200_config_*.zip"
    )
}
