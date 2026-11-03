@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: ============================================================
:: Автоматический запрос прав администратора (UAC)
:: ============================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "BASE=%~dp0"
cd /d "%BASE%"

title MammothRevive v1.0 • Windows 10 Optimization Suite ^| by @afigenys

if not exist "%BASE%Clean.ps1" (
    echo [ERROR] Скрипт Clean.ps1 не найден в директории: %BASE%
    pause
    exit /b 1
)

if not exist "%BASE%logs" mkdir "%BASE%logs"

cls
echo ============================================================
echo   MammothRevive v1.0 • Комплексная оптимизация Windows 10
echo   Специально для слабых и устаревших ПК ^| by @afigenys
echo ============================================================
echo.

:: ============================================================
:: ЭТАП 0. Сбор "до"
:: ============================================================
echo [*] ЭТАП 0/3: Анализ аппаратной конфигурации...
echo.

for /f "delims=" %%a in ('powershell -NoProfile -Command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)"') do set "RAM=%%a"
if not defined RAM set "RAM=8"

for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "$d=(Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object -First 1).MediaType; if(-not $d -or $d -eq 'Unspecified'){$m=(Get-CimInstance Win32_DiskDrive | Select-Object -First 1).Model; if($m -match 'SSD|NVMe'){$d='SSD'}else{$d='HDD'}}; $d"`) do set "DISK=%%a"
if not defined DISK set "DISK=Unknown"

for /f "delims=" %%a in ('powershell -NoProfile -Command "[math]::Round((Get-PSDrive C).Free/1GB,1)"') do set "FREE_BEFORE=%%a"

echo    Объем ОЗУ   : %RAM% GB
echo    Тип диска   : %DISK%
echo    Свободно на C: %FREE_BEFORE% GB
echo.

powershell -NoProfile -Command "Get-Service DiagTrack, dmwappushservice, WSearch, SysMain, wuauserv, XboxGipSvc, XblAuthManager, XblGameSave, XboxNetApiSvc, Fax, RemoteRegistry, MapsBroker, WMPNetworkSvc, WerSvc | Select-Object Name, Status, StartType | Format-Table -AutoSize | Out-File '%BASE%logs\before_services.txt'"

:: ============================================================
:: Выбор профиля
:: ============================================================
if %RAM% LEQ 4 (
    set "PROFILE=Calculator"
    set "RUS_NAME=Максимальный (RAM до 4 GB / HDD)"
) else if %RAM% LEQ 6 (
    set "PROFILE=Ofisnik"
    set "RUS_NAME=Сбалансированный (RAM 5-6 GB)"
) else (
    set "PROFILE=Bodry"
    set "RUS_NAME=Базовый (RAM от 7 GB)"
)

echo ------------------------------------------------------------
echo  Выбранный профиль: %RUS_NAME%
echo ------------------------------------------------------------
echo.
echo  ВНИМАНИЕ: Процесс займет от 25 до 60 минут
echo  (сжатие компонентов WinSxS и дефрагментация файлов на HDD).
echo  Не закрывайте это окно до завершения всех процедур.
echo.
echo  Нажмите любую клавишу для запуска оптимизации...
pause >nul

:: ============================================================
:: ЭТАП 1. Clean.ps1
:: ============================================================
echo.
echo ============================================================
echo  ЭТАП 1/3: Очистка системы, служб и фоновых компонентов
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%Clean.ps1" -Profile %PROFILE%
set "CLEAN_RESULT=%errorlevel%"
if %CLEAN_RESULT% neq 0 (
    echo [WARN] Clean.ps1 завершился с кодом %CLEAN_RESULT%. Продолжаем.
)

:: ============================================================
:: ЭТАП 2. HeavyOptimize.ps1
:: ============================================================
echo.
echo ============================================================
echo  ЭТАП 2/3: Глубокая дисковая оптимизация (WinSxS, Pagefile, Defrag)
echo ============================================================
echo.

if exist "%BASE%HeavyOptimize.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%HeavyOptimize.ps1"
    set "HEAVY_RESULT=%errorlevel%"
    if !HEAVY_RESULT! neq 0 (
        echo [WARN] HeavyOptimize.ps1 завершился с кодом !HEAVY_RESULT!. Продолжаем.
    )
) else (
    echo [SKIP] HeavyOptimize.ps1 не найден - пропускаем.
)

:: ============================================================
:: ЭТАП 3. Сбор "после" + отчёт
:: ============================================================
echo.
echo ============================================================
echo  ЭТАП 3/3: Верификация состояния системы
echo ============================================================
echo.

for /f "delims=" %%a in ('powershell -NoProfile -Command "[math]::Round((Get-PSDrive C).Free/1GB,1)"') do set "FREE_AFTER=%%a"

powershell -NoProfile -Command "Get-Service DiagTrack, dmwappushservice, WSearch, SysMain, wuauserv, XboxGipSvc, XblAuthManager, XblGameSave, XboxNetApiSvc, Fax, RemoteRegistry, MapsBroker, WMPNetworkSvc, WerSvc | Select-Object Name, Status, StartType | Format-Table -AutoSize | Out-File '%BASE%logs\after_services.txt'"

echo    Свободное место на C: %FREE_BEFORE% GB  -^>  %FREE_AFTER% GB
echo.
echo    Состояние критических служб:
powershell -NoProfile -Command "$wu = Get-Service wuauserv; $sm = Get-Service SysMain; $ws = Get-Service WSearch; Write-Host ('    wuauserv : ' + $wu.Status + ' / ' + $wu.StartType); Write-Host ('    SysMain  : ' + $sm.Status + ' / ' + $sm.StartType); Write-Host ('    WSearch  : ' + $ws.Status + ' / ' + $ws.StartType)"

echo.
echo    Проверка базовых UWP (Store/Calc/Photos):
powershell -NoProfile -Command "foreach ($n in 'Microsoft.WindowsStore','Microsoft.WindowsCalculator','Microsoft.Windows.Photos') { $p = Get-AppxPackage $n; if ($p) { Write-Host ('    OK: ' + $n) } else { Write-Host ('    MISSING: ' + $n) } }"

echo.
echo    Анализ устройств и драйверов:
powershell -NoProfile -Command "$err = @(Get-PnpDevice -Status Error -ErrorAction SilentlyContinue); if ($err.Count -eq 0) { Write-Host '    OK: Устройств с ошибками драйверов не обнаружено' } else { Write-Host ('    WARN: Обнаружено устройств с ошибками: ' + $err.Count) }"

echo.
echo ============================================================
echo  [✓] ОПТИМИЗАЦИЯ СИСТЕМЫ УСПЕШНО ЗАВЕРШЕНА!
echo  Подробные отчеты сохранены в папке: %BASE%logs
echo ============================================================
echo.

:: ============================================================
:: Перезагрузка
:: ============================================================
set /p REBOOT="Перезагрузить систему для применения всех изменений? (Y/N): "
if /i "%REBOOT%"=="Y" (
    echo Перезагрузка через 10 секунд... (Ctrl+C для отмены)
    shutdown /r /t 10 /c "MammothRevive: Применение настроек оптимизации"
) else (
    echo Перезагрузка отложена пользователем. Не забудьте перезагрузить систему вручную.
    pause
)

endlocal