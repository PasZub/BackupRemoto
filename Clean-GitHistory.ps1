<#
.SYNOPSIS
    Script para eliminar credenciales sensibles del historial de Git

.DESCRIPTION
    Este script usa git filter-branch para reescribir el historial y eliminar
    las credenciales de Telegram que fueron expuestas en commits anteriores.
    
    IMPORTANTE: Este script reescribe el historial de Git. Todos los que tengan
    clones del repositorio necesitarán hacer un fresh clone después de ejecutar esto.

.NOTES
    Usar con precaución. Hará un backup automático antes de proceder.
#>

Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "  LIMPIEZA DE CREDENCIALES DEL HISTORIAL DE GIT" -ForegroundColor Yellow
Write-Host "============================================================`n" -ForegroundColor Yellow

Write-Host "[ADVERTENCIA] Este script reescribirá el historial de Git" -ForegroundColor Red
Write-Host "Esto significa que:" -ForegroundColor Yellow
Write-Host "  • Se cambiarán todos los hashes de commits" -ForegroundColor Gray
Write-Host "  • Necesitarás hacer force push a GitHub" -ForegroundColor Gray
Write-Host "  • Otros clones del repo necesitarán re-clonarse" -ForegroundColor Gray
Write-Host "`n¿Deseas continuar? (S/N): " -ForegroundColor Cyan -NoNewline
$response = Read-Host

if ($response -ne "S" -and $response -ne "s") {
    Write-Host "Operación cancelada" -ForegroundColor Yellow
    exit 0
}

Write-Host "`n[1/5] Creando backup del repositorio..." -ForegroundColor Cyan
$backupPath = "D:\desarrollos\BackupRemoto_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item -Path "D:\desarrollos\BackupRemoto" -Destination $backupPath -Recurse -Force
Write-Host "[OK] Backup creado en: $backupPath" -ForegroundColor Green

Write-Host "`n[2/5] Verificando que no haya cambios sin commitear..." -ForegroundColor Cyan
$status = git status --porcelain
if ($status) {
    Write-Host "[ERROR] Hay cambios sin commitear. Por favor, commitea o descarta los cambios primero." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Repositorio limpio" -ForegroundColor Green

Write-Host "`n[3/5] Reescribiendo historial para eliminar credenciales..." -ForegroundColor Cyan
Write-Host "Esto puede tomar varios minutos..." -ForegroundColor Gray

# Crear un script de filtro para reemplazar las credenciales
$filterScript = @'
# Reemplazar las credenciales expuestas en Send-TelegramNotification.ps1
if [ "$GIT_COMMIT" != "PLACEHOLDER" ]; then
    sed -i 's/1734951853:AAG0yCbVnErlYSk_gTAO-RsffqTvShHeviw/TU_BOT_TOKEN_AQUI/g' Send-TelegramNotification.ps1 2>/dev/null || true
    sed -i 's/-1001575024278/TU_CHAT_ID_AQUI/g' Send-TelegramNotification.ps1 2>/dev/null || true
fi
'@

# Alternativa: Usar git filter-branch con sed en PowerShell
Write-Host "Ejecutando filter-branch..." -ForegroundColor Gray

# Método más simple: usar --tree-filter con PowerShell
git filter-branch --force --tree-filter "
    if (Test-Path 'Send-TelegramNotification.ps1') {
        (Get-Content 'Send-TelegramNotification.ps1' -Raw) -replace '1734951853:AAG0yCbVnErlYSk_gTAO-RsffqTvShHeviw', 'TU_BOT_TOKEN_AQUI' -replace '-1001575024278', 'TU_CHAT_ID_AQUI' | Set-Content 'Send-TelegramNotification.ps1' -NoNewline
    }
" --tag-name-filter cat -- --all

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Falló la reescritura del historial" -ForegroundColor Red
    Write-Host "Puedes restaurar desde el backup en: $backupPath" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] Historial reescrito exitosamente" -ForegroundColor Green

Write-Host "`n[4/5] Limpiando referencias antiguas..." -ForegroundColor Cyan
git for-each-ref --format="%(refname)" refs/original/ | ForEach-Object { git update-ref -d $_ }
git reflog expire --expire=now --all
git gc --prune=now --aggressive

Write-Host "[OK] Limpieza completada" -ForegroundColor Green

Write-Host "`n[5/5] Verificando resultado..." -ForegroundColor Cyan
$credentialsFound = git log --all --full-history -p -S "1734951853:AAG0yCbVnErlYSk_gTAO" -- Send-TelegramNotification.ps1

if ($credentialsFound) {
    Write-Host "[WARN] Aún se encontraron rastros de credenciales en el historial" -ForegroundColor Yellow
    Write-Host "Revisa manualmente o considera usar BFG Repo-Cleaner" -ForegroundColor Yellow
} else {
    Write-Host "[OK] No se encontraron credenciales en el historial" -ForegroundColor Green
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  LIMPIEZA COMPLETADA" -ForegroundColor Green
Write-Host "============================================================`n" -ForegroundColor Green

Write-Host "SIGUIENTE PASO:" -ForegroundColor Cyan
Write-Host "Para aplicar los cambios al repositorio remoto, ejecuta:" -ForegroundColor White
Write-Host "`n  git push origin --force --all" -ForegroundColor Yellow
Write-Host "  git push origin --force --tags`n" -ForegroundColor Yellow

Write-Host "[IMPORTANTE] Después del force push:" -ForegroundColor Red
Write-Host "  • Todos los colaboradores deberán clonar nuevamente el repo" -ForegroundColor Gray
Write-Host "  • No uses 'git pull', usa 'git clone' para obtener el repo limpio" -ForegroundColor Gray

Write-Host "`nBackup del repositorio original guardado en:" -ForegroundColor Cyan
Write-Host "  $backupPath`n" -ForegroundColor Gray
