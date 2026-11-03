<#
.SYNOPSIS
    MammothRevive - Скрипт базовой и тонкой оптимизации Windows 10 для слабых ПК.
.PARAMETER Profile
    Calculator - RAM <= 4 GB, HDD (максимальная разгрузка)
    Ofisnik    - RAM 5-6 GB (сбалансированная настройка)
    Bodry      - RAM >= 7 GB (базовая очистка)
.PARAMETER DryRun
    Тестовый запуск без внесения изменений.
#>
param(
    [ValidateSet('Calculator','Ofisnik','Bodry')]
    [string]$Profile = 'Ofisnik',
    [switch]$DryRun
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Step($msg) { Write-Host " [*] $msg..." -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "     [OK] $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "     [SKIP] $msg" -ForegroundColor Yellow }

function Set-RegDword($Path, $Name, $Value) {
    if ($DryRun) { Write-Skip "reg: $Path\$Name = $Value"; return }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-RegString($Path, $Name, $Value) {
    if ($DryRun) { Write-Skip "reg(str): $Path\$Name = $Value"; return }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Set-SvcState($Name, $StartupType) {
    if ($DryRun) { Write-Skip "svc: $Name -> $StartupType"; return }
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Skip "svc: $Name не найден"; return }
    Set-Service -Name $Name -StartupType $StartupType -ErrorAction SilentlyContinue
    if ($StartupType -eq 'Disabled') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
}

function Remove-JunkApp($Name) {
    if ($DryRun) { Write-Skip "app: $Name"; return }
    Get-AppxPackage -AllUsers -Name $Name -ErrorAction SilentlyContinue |
        Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $Name } |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
}

function Disable-Task($FullPath) {
    if ($DryRun) { Write-Skip "task: $FullPath"; return }
    $parent = Split-Path $FullPath -Parent
    if (-not $parent.EndsWith('\')) { $parent += '\' }
    $name = Split-Path $FullPath -Leaf
    Get-ScheduledTask -TaskPath $parent -TaskName $name -ErrorAction SilentlyContinue |
        Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
}

function Remove-RegKey($Path) {
    if ($DryRun) { Write-Skip "reg-del: $Path"; return }
    Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Детект диска с резервным определением ---
$diskType = (Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object -First 1).MediaType
if (-not $diskType -or $diskType -eq 'Unspecified') {
    $drive = Get-CimInstance Win32_DiskDrive | Select-Object -First 1
    if ($drive.Model -match 'SSD|NVMe') { $diskType = 'SSD' } else { $diskType = 'HDD' }
}

$rusProfile = switch ($Profile) {
    'Calculator' { 'Максимальный' }
    'Ofisnik'    { 'Сбалансированный' }
    'Bodry'      { 'Базовый' }
}

Write-Host ""
Write-Host "--- MammothRevive Clean: профиль=$rusProfile, диск=$diskType, DryRun=$DryRun ---" -ForegroundColor Magenta
Write-Host ""

# ==========================================================
# БЛОК 1. Общие безопасные твики фоновой активности
# ==========================================================

Write-Step "Отключаю телеметрию и диагностические трекеры"
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
Set-SvcState 'DiagTrack' 'Disabled'
Set-SvcState 'dmwappushservice' 'Disabled'

Write-Step "Отключаю рекламные модули и установку промо-приложений"
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1

Write-Step "Отключаю P2P-раздачу обновлений (Delivery Optimization)"
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0

Write-Step "Ограничиваю фоновые процессы Microsoft Edge"
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0

Write-Step "Отключаю автозапуск OneDrive"
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
if (-not $DryRun) {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive' -ErrorAction SilentlyContinue
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Step "Отключаю неиспользуемые службы Xbox"
foreach ($svc in 'XboxGipSvc','XblAuthManager','XblGameSave','XboxNetApiSvc') {
    Set-SvcState $svc 'Disabled'
}

Write-Step "Отключаю GameDVR и игровой оверлей"
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0

Write-Step "Отключаю голосовой помощник Cortana"
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0

Write-Step "Отключаю фоновую активность приложений"
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1

Write-Step "Отключаю подсказки и баннеры рекомендаций"
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0

# ==========================================================
# БЛОК 2. Деинсталляция неиспользуемых встроенных UWP пакетов
# ==========================================================

Write-Step "Удаляю предустановленные рекламные UWP-пакеты (Магазин, Фото и Калькулятор остаются)"
$junk = @(
    'Microsoft.BingNews','Microsoft.BingWeather',
    'Microsoft.GetHelp','Microsoft.Getstarted',
    'Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.SkypeApp','Microsoft.WindowsFeedbackHub',
    'Microsoft.XboxApp','Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.YourPhone',
    'Microsoft.ZuneMusic','Microsoft.ZuneVideo',
    'Microsoft.MixedReality.Portal','Microsoft.3DViewer',
    'Microsoft.OneConnect','Microsoft.People',
    'Microsoft.Print3D','Microsoft.Wallet',
    'Microsoft.BingSearch',
    'Microsoft.OutlookForWindows',
    'Microsoft.Windows.DevHome',
    'Microsoft.Office.OneNote',
    'Microsoft.MicrosoftStickyNotes',
    'Microsoft.WindowsMaps',
    'Microsoft.WindowsSoundRecorder',
    'Microsoft.WindowsAlarms',
    'Microsoft.549981C3F5F10'
)
foreach ($app in $junk) { Remove-JunkApp $app }

# ==========================================================
# БЛОК 3. Очистка временных файлов
# ==========================================================

Write-Step "Очищаю пользовательские и системные Temp-директории"
if (-not $DryRun) {
    Remove-Item "$env:USERPROFILE\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
} else {
    Write-Skip "temp files cleanup"
}

# ==========================================================
# БЛОК 4. Специфика профилей
# ==========================================================

if ($Profile -in 'Calculator','Ofisnik') {
    Write-Step "Отключаю гибернацию (освобождение дискового пространства)"
    if (-not $DryRun) { powercfg /h off } else { Write-Skip "powercfg /h off" }

    Write-Step "Активирую план максимальной производительности (выжимаем максимум из ЦП)"
    if (-not $DryRun) { powercfg /setactive SCHEME_MIN } else { Write-Skip "powercfg /setactive SCHEME_MIN" }
}

if ($Profile -eq 'Calculator') {
    Write-Step "Оптимизирую Windows Search (перевод в режим Manual для сохранения поиска)"
    Set-SvcState 'WSearch' 'Manual'
}

# ==========================================================
# БЛОК 5. Управление службой SysMain (Superfetch)
# ==========================================================

Write-Step "Конфигурация SysMain для типа диска: $diskType"
if ($diskType -eq 'HDD') {
    if ($Profile -eq 'Calculator') {
        Set-SvcState 'SysMain' 'Disabled'
        if (-not $DryRun) { Write-Ok "SysMain отключен (предотвращение 100% загрузки медленного HDD)" }
        else              { Write-Skip "SysMain будет отключен" }
    } else {
        Set-SvcState 'SysMain' 'Automatic'
        if (-not $DryRun) { Write-Ok "SysMain оставлен в режиме Automatic" }
        else              { Write-Skip "SysMain будет включен" }
    }
} elseif ($diskType -eq 'SSD') {
    Set-SvcState 'SysMain' 'Disabled'
    if (-not $DryRun) { Write-Ok "SysMain отключен (не требуется на SSD)" }
    else              { Write-Skip "SysMain будет отключен" }
} else {
    Write-Skip "Тип диска не определен достоверно, служба SysMain не затронута"
}

# ==========================================================
# БЛОК 6. Приватность, задачи и неиспользуемые службы
# ==========================================================

Write-Step "Настраиваю политики приватности и отклик меню"
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'PublishUserActivities' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'UploadUserActivities' 0
Set-RegDword 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
Set-RegDword 'HKCU:\Software\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'DisableWebSearch' 1
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'ConnectedSearchUseWeb' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowSearchToUseLocation' 0
Set-RegString 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0'

Write-Step "Отключаю задачи сбора данных в планировщике заданий"
$tasks = @(
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
)
foreach ($t in $tasks) { Disable-Task $t }

Write-Step "Отключаю устаревшие и неиспользуемые службы"
foreach ($svc in 'Fax','RetailDemo','RemoteRegistry','MapsBroker','WMPNetworkSvc','WerSvc','wisvc') {
    Set-SvcState $svc 'Disabled'
}

Write-Step "Деактивирую фоновый апдейтер OneDrive"
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
if (-not $DryRun) {
    Get-ScheduledTask -TaskName 'OneDrive Standalone Updater' -ErrorAction SilentlyContinue |
        Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
}

# ==========================================================
# БЛОК 7. Тонкая настройка оболочки Проводника (Explorer)
# ==========================================================

Write-Step "Оптимизирую панель задач"
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'ShowCortanaButton' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowPeopleButton' 0

Write-Step "Включаю значок 'Этот компьютер' на рабочем столе"
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel' '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' 0

Write-Step "Настраиваю Проводник (открытие 'Этот компьютер', удаление каталога 'Объемные объекты')"
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
Remove-RegKey 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}'

Write-Step "Отключаю спонсорский контент экрана блокировки"
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
Set-RegDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0

Write-Host ""
Write-Host "[✓] Этап Clean.ps1 успешно завершен" -ForegroundColor Green