# Sistema de Backup Remoto PowerShell

Sistema automatizado de backup que realiza compresión diferencial/completa con WinRAR y sincronización remota con rclone.

## 🔄 Actualizaciones Automáticas

El sistema incluye actualización automática desde GitHub sin necesidad de instalar Git.

### Actualización Manual

Para actualizar el sistema a la última versión:

```powershell
.\Update-BackupSystem.ps1
```

Con parámetros:
```powershell
# Actualizar sin confirmación
.\Update-BackupSystem.ps1 -Force

# Actualizar sin crear backup de configuración
.\Update-BackupSystem.ps1 -Force -SkipBackup
```

### Verificación Automática

El script `BackupRemoto.ps1` verifica automáticamente si hay actualizaciones disponibles al inicio de cada ejecución y muestra una notificación si hay una nueva versión.

### Archivos Protegidos

Los siguientes archivos **NO se sobrescribirán** durante la actualización:
- `BackupConfig.ps1` - Tu configuración del sistema
- `UserConfig.ps1` - Tu configuración de backups
- `TelegramConfig.ps1` - Tus credenciales de Telegram

El script creará un backup de estos archivos antes de actualizar por seguridad.

## 📁 Estructura de Archivos

### Scripts Principales
- **`BackupRemoto.ps1`** - Script principal de backup
- **`Setup-Backup.ps1`** - Configurador e instalador del sistema
- **`Send-TelegramNotification.ps1`** - Sistema de notificaciones

### Configuración
- **`BackupConfig.ps1`** - Configuración del sistema (rclone, WinRAR, rutas, etc.)
- **`UserConfig.ps1`** - Configuración específica del usuario (qué respaldar)
- **`TelegramConfig.ps1`** - Credenciales de Telegram (NO versionado)
- **`UserConfig.ps1.example`** - Plantilla de configuración de usuario
- **`TelegramConfig.ps1.example`** - Plantilla de configuración de Telegram

## 🚀 Configuración Inicial

### 1. Configurar Usuario
```powershell
# Copiar plantilla de configuración
Copy-Item "UserConfig.ps1.example" "UserConfig.ps1"

# Editar UserConfig.ps1 según sus necesidades
notepad UserConfig.ps1
```

### 2. Configurar rclone
```powershell
# Ejecutar configuración interactiva
.\Setup-Backup.ps1 -SetupRclone
```

### 3. Verificar Dependencias
```powershell
# Verificar que todo esté configurado correctamente
.\Setup-Backup.ps1 -Test
```

### 4. Instalar Tarea Programada
```powershell
# Instalar como tarea programada (requiere permisos de administrador)
.\Setup-Backup.ps1 -Install
```

## 📋 Requisitos

- **Windows PowerShell 5.1+** o **PowerShell Core 7+**
- **WinRAR** instalado en `C:\Program Files\WinRAR\`
- **rclone** configurado con un remoto válido
- **Permisos de administrador** (recomendado)

## ⚙️ Configuración de Usuario (UserConfig.ps1)

La configuración se ha separado en dos archivos para mayor flexibilidad:

### Backup de Documentos
```powershell
DocumentosEnabled = $true
DocumentosSource = @(
    "C:\Users\$env:USERNAME\Documents\*",
    "C:\Users\$env:USERNAME\Desktop\*"
)
DocumentosExclude = @("*.tmp", "*.bak")
```

### Backup de Usuarios
```powershell
UsuariosEnabled = $false  # Deshabilitado por defecto
UsuariosSource = @("C:\Users")
UsuariosExclude = @("*.pst", "*.exe")
```

### Backup de Programas
```powershell
ProgramasEnabled = $false  # Deshabilitado por defecto
ProgramasSource = @("C:\MisPrograms\*")
ProgramasExclude = @("*.exe", "*.dll")
```

## 🔄 Tipos de Backup

- **Completo**: Miércoles y Domingos (o con parámetro `-Force`)
- **Diferencial**: Resto de días (solo archivos modificados en últimos N días)

## 📋 Uso

### Ejecución Manual
```powershell
# Backup normal (según día de la semana)
.\BackupRemoto.ps1

# Forzar backup completo
.\BackupRemoto.ps1 -Force
```

### Gestión de Tareas
```powershell
# Instalar tarea programada
.\Setup-Backup.ps1 -Install

# Desinstalar tarea programada
.\Setup-Backup.ps1 -Uninstall

# Verificar configuración
.\Setup-Backup.ps1 -Test
```

## 📋 Notificaciones Telegram

El sistema incluye notificaciones automáticas via Telegram:

- ✅ **Backup exitoso**: Resumen con estadísticas
- ❌ **Backup con errores**: Resumen + archivo de log adjunto
- 🆘 **Error crítico**: Detalles del error + log

### Configuración de Telegram

1. **Crear archivo de configuración:**
   ```powershell
   # Copiar plantilla
   Copy-Item "TelegramConfig.ps1.example" "TelegramConfig.ps1"
   
   # Editar con tus credenciales
   notepad TelegramConfig.ps1
   ```

2. **Obtener credenciales:**
   - **Bot Token**: Hablar con [@BotFather](https://t.me/BotFather) en Telegram y crear un nuevo bot
   - **Chat ID**: Enviar un mensaje al bot y visitar `https://api.telegram.org/bot<TU_BOT_TOKEN>/getUpdates`

3. **Configurar:**
   ```powershell
   # TelegramConfig.ps1
   return @{
       BotToken = "1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
       ChatId = "-1001234567890"  # Para grupos empieza con -100
   }
   ```

⚠️ **IMPORTANTE**: El archivo `TelegramConfig.ps1` NO se sube a GitHub por seguridad (está en .gitignore)

## 🗂️ Estructura de Archivos de Salida

```
TempDir/
├── Documentos_YYYYMMDD.rar    # Backup de documentos
├── Usuarios_YYYYMMDD.rar      # Backup de perfiles de usuario
├── Programas_YYYYMMDD.rar     # Backup de programas (si está habilitado)
└── BackupLogs/
    └── Backup_YYYYMMDD.log    # Log del día
```

## 🔧 Configuración Avanzada

### Parámetros de rclone (BackupConfig.ps1)
```powershell
RcloneTransfers = 4           # Transferencias paralelas
RcloneCheckers = 8            # Verificadores paralelos
RcloneBandwidth = "0"         # Límite de ancho de banda
RcloneDeleteOlderThan = 30    # Días para auto-limpiar servidor
```

### Logging
```powershell
LogEnabled = $true
LogPath = ".\BackupLogs"
LogRetentionDays = 30
```

## 🔄 Flujo de Trabajo

1. **Inicialización** - Carga configuración y determina tipo de backup
2. **Compresión** - Crea archivos RAR con WinRAR
3. **Sincronización** - Sube archivos con rclone
4. **Limpieza** - Elimina archivos temporales y antiguos del servidor
5. **Notificación** - Envía resumen por Telegram

## 📝 Archivos de Log

- **Formato**: `Backup_YYYYMMDD.log`
- **Contenido**: Timestamps, niveles de log, operaciones detalladas
- **Retención**: Configurable (30 días por defecto)
- **Conversión**: Automática a HTML para notificaciones

## � Solución de Problemas

### Verificar Estado
```powershell
.\Setup-Backup.ps1 -Test
```

### Logs Detallados
- Revisar archivo `BackupLogs\Backup_YYYYMMDD.log`
- Verificar notificaciones de Telegram

### Errores Comunes
- **WinRAR no encontrado**: Verificar ruta en `BackupConfig.ps1`
- **rclone no configurado**: Ejecutar `.\Setup-Backup.ps1 -SetupRclone`
- **Sin archivos para comprimir**: Verificar rutas en `UserConfig.ps1`

## 🏗️ Arquitectura Separada

- **Sistema**: Configuración técnica (rclone, WinRAR, logging)
- **Usuario**: Configuración de contenido (qué respaldar)
- **Flexibilidad**: Fácil personalización sin tocar archivos del sistema

## 🆚 Mejoras vs Sistema Original

### ✅ Nuevas Funcionalidades
- **rclone** en lugar de NextCloud (mayor compatibilidad)
- **Notificaciones Telegram** automáticas
- **Configuración separada** para mejor mantenimiento
- **Auto-limpieza** de archivos antiguos del servidor

### 🔄 Funcionalidad Mantenida
- Mismo algoritmo de backup diferencial/completo
- Compatibilidad con WinRAR
- Logging detallado con rotación
- Tarea programada automatizada

## 📞 Soporte

Para problemas o mejoras, revisar los logs en `E:\send1\BackupLogs\` y verificar la configuración con `.\Setup-Backup.ps1 -Test`.
