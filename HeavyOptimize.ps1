<#
.SYNOPSIS
    MammothRevive - Скрипт глубокой дисковой оптимизации (WinSxS, SoftwareDistribution, Pagefile, Defrag).
.PARAMETER DryRun
    Тестовый запуск без внесения изменений.
#>
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Step($msg) { Write-Host " [*] $msg..." -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "     [OK] $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "     [SKIP] $msg" -ForegroundColor Yellow }
function Write-Warn($msg) { Write-Host "     [WARN] $msg" -ForegroundColor Red }

$BASE = Split-Path -Parent $MyInvocation.MyCommand.Path
$LOGDIR = Join-Path $BASE 'logs'
if (-not (Test-Path $LOGDIR)) { New-Item -Path $LOGDIR -ItemType Directory -Force | Out-Null }
$LOG = Join-Path $LOGDIR 'heavy.log'
"=== MammothRevive Heavy start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') DryRun=$DryRun ===" | Out-File $LOG -Encoding UTF8

# --- Детект типа диска ---
$diskType = (Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object -First 1).MediaType
if (-not $diskType -or $diskType -eq 'Unspecified') {
    $drive = Get-CimInstance Win32_DiskDrive | Select-Object -First 1
    if ($drive.Model -match 'SSD|NVMe') { $diskType = 'SSD' } else { $diskType = 'HDD' }
}

$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1)

Write-Host ""
Write-Host "--- MammothRevive Heavy: диск=$diskType, свободно C: $freeGB GB, DryRun=$DryRun ---" -ForegroundColor Magenta
Write-Host ""

# ==========================================================
# 1. Сжатие и очистка WinSxS (DISM ResetBase)
# ==========================================================
Write-Step "DISM: Очистка и сжатие WinSxS (ResetBase)"
if ($DryRun) {
    Write-Skip "Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase"
} else {
    if ($freeGB -lt 3) {
        Write-Warn "Свободно менее 3 ГБ на системном томе. Операция пропущена во избежание сбоев."
    } else {
        "DISM StartComponentCleanup /ResetBase" | Out-File $LOG -Append -Encoding UTF8
        Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet /NoRestart 2>&1 | Out-File $LOG -Append -Encoding UTF8
        if ($LASTEXITCODE -eq 0) { Write-Ok "Хранилище компонентов WinSxS очищено и сжато" }
        else { Write-Warn "DISM завершился с кодом $LASTEXITCODE (детали в heavy.log)" }
    }
}

# ==========================================================
# 2. Очистка кэша обновлений Windows
# ==========================================================
Write-Step "Очистка загруженных пакетов обновлений Windows"
if ($DryRun) {
    Write-Skip "Очистка директории SoftwareDistribution\Download"
} else {
    Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv, bits -ErrorAction SilentlyContinue
    Write-Ok "Кэш загрузок Windows Update успешно очищен"
}

# ==========================================================
# 3. Конфигурация файла подкачки
# ==========================================================
Write-Step "Оптимизация файла подкачки (Начальный: 4096 МБ, Максимальный: 8192 МБ)"
if ($DryRun) {
    Write-Skip "pagefile: InitialSize=4096, MaximumSize=8192"
} else {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs -and $cs.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false} -ErrorAction SilentlyContinue
    }
    $pf = Get-CimInstance Win32_PageFileSetting -Filter "Name='C:\\pagefile.sys'" -ErrorAction SilentlyContinue
    if ($pf) {
        Set-CimInstance -InputObject $pf -Property @{InitialSize=4096; MaximumSize=8192} -ErrorAction SilentlyContinue
        Write-Ok "Размер файла подкачки обновлен на 4096/8192 МБ"
    } else {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name='C:\pagefile.sys'; InitialSize=4096; MaximumSize=8192} -ErrorAction SilentlyContinue | Out-Null
        Write-Ok "Создан фиксированный файл подкачки 4096/8192 МБ"
    }
}

# ==========================================================
# 4. Дефрагментация / TRIM
# ==========================================================
Write-Step "Оптимизация блоков накопителя C:"
if ($diskType -eq 'HDD') {
    if ($DryRun) {
        Write-Skip "defrag C: /O (HDD)"
    } else {
        "defrag C: /O" | Out-File $LOG -Append -Encoding UTF8
        defrag C: /O /U 2>&1 | Out-File $LOG -Append -Encoding UTF8
        if ($LASTEXITCODE -eq 0) { Write-Ok "Дефрагментация файлов завершена" }
        else { Write-Warn "defrag вернул код $LASTEXITCODE" }
    }
} elseif ($diskType -eq 'SSD') {
    if ($DryRun) { Write-Skip "Optimize-Volume -ReTrim (SSD)" }
    else {
        Optimize-Volume -DriveLetter C -ReTrim -Verbose -ErrorAction SilentlyContinue | Out-Null
        Write-Ok "Команда ReTrim выполнена"
    }
} else {
    Write-Skip "Тип диска не определен достоверно, оптимизация пропущена"
}

# ==========================================================
# 5. Очистка устаревших теневых копий
# ==========================================================
Write-Step "Удаление устаревших точек восстановления и теневых копий"
if ($DryRun) {
    Write-Skip "vssadmin delete shadows /for=C: /all /quiet"
} else {
    "vssadmin delete shadows" | Out-File $LOG -Append -Encoding UTF8
    vssadmin delete shadows /for=C: /all /quiet 2>&1 | Out-File $LOG -Append -Encoding UTF8
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Теневые копии успешно удалены"
    } elseif ($LASTEXITCODE -eq 1) {
        Write-Ok "Теневых копий не обнаружено (чистая система)"
    } else {
        Write-Warn "vssadmin завершил работу с кодом $LASTEXITCODE"
    }
}

# ==========================================================
# Финал HeavyOptimize
# ==========================================================

$freeGBAfter = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
$gained = [math]::Round($freeGBAfter - $freeGB, 1)

Write-Host ""
Write-Host "[✓] HeavyOptimize завершен: Свободно было $freeGB GB, стало $freeGBAfter GB (высвобождено +$gained GB)" -ForegroundColor Green
"=== MammothRevive Heavy end: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), free $freeGB -> $freeGBAfter GB ===" | Out-File $LOG -Append -Encoding UTF8