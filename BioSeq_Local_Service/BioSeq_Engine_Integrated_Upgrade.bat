@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "MODE_ARG=%~1"
set "SELF=%~f0"
set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "APP=%ROOT%\app"
set "FIXED=%ROOT%\BioSeq_Engine_Launcher.bat"
set "WGS_INSTALLER=%ROOT%\Install_WGS_Tools_WSL.bat"
set "LOG_DIR=%ROOT%\logs"
set "LOG=%LOG_DIR%\launcher.log"
set "STATUS_URL=http://127.0.0.1:8765/status"
set "DISTRO=Ubuntu"
set "PROTOCOL=0"

echo(%MODE_ARG%| findstr /I /B /C:"bioseq://start" >nul 2>&1
if not errorlevel 1 set "PROTOCOL=1"

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
>"%LOG%" echo [%date% %time%] TMM BioSeq integrated launcher

if "%PROTOCOL%"=="0" (
    title TMM BioSeq Engine 一体化启动器
    echo =====================================================
    echo   TMM BioSeq Engine 一体化启动器
    echo =====================================================
    echo.
)

call :ensure_app
if errorlevel 1 goto :failed

call :update_core
call :register_protocol
if errorlevel 1 goto :failed

call :ensure_wgs_tools
set "WGS_EXIT=%ERRORLEVEL%"
if "%WGS_EXIT%"=="10" exit /b 10
if "%WGS_EXIT%"=="11" exit /b 11
if not "%WGS_EXIT%"=="0" goto :failed

call :ensure_python
if errorlevel 1 goto :failed

call :engine_online
if not errorlevel 1 goto :success

if "%PROTOCOL%"=="0" echo 正在启动 BioSeq Engine...
if "%PROTOCOL%"=="1" (
    start "TMM BioSeq Engine" /min "%ComSpec%" /k call "%APP%\BioSeq_Local_Service\BioSeq_Start.bat"
) else (
    start "TMM BioSeq Engine" "%ComSpec%" /k call "%APP%\BioSeq_Local_Service\BioSeq_Start.bat"
)

for /L %%I in (1,1,150) do (
    call :engine_online
    if not errorlevel 1 goto :success
    >nul 2>&1 ping 127.0.0.1 -n 2
)

echo [错误] BioSeq Engine 未在规定时间内启动。
goto :failed

:success
if "%PROTOCOL%"=="0" (
    echo.
    echo =====================================================
    echo 启动成功
    echo =====================================================
    echo BioSeq Engine：http://127.0.0.1:8765
    echo Python、Flask、fastp、bwa、samtools、bcftools 已检查。
    echo 回到网页刷新后即可运行 WGS。
    echo.
    pause
)
exit /b 0

:ensure_app
if exist "%APP%\backend\BioSeq_Server.py" exit /b 0
if "%PROTOCOL%"=="0" echo 未发现本地 BioSeq 程序，正在下载最新版...
set "ZIP=%TEMP%\TMMBioSeq_%RANDOM%_%RANDOM%.zip"
set "EXTRACT=%TEMP%\TMMBioSeq_extract_%RANDOM%_%RANDOM%"
set "ZIP_ENV=%ZIP%"
set "EXTRACT_ENV=%EXTRACT%"
set "APP_ENV=%APP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/ttmmss278-png/TMM/archive/refs/heads/main.zip' -OutFile $env:ZIP_ENV;Expand-Archive -LiteralPath $env:ZIP_ENV -DestinationPath $env:EXTRACT_ENV -Force;$src=Get-ChildItem -LiteralPath $env:EXTRACT_ENV -Directory|Where-Object{$_.Name -like 'TMM-*'}|Select-Object -First 1;if(-not $src){throw 'TMM directory missing'};New-Item -ItemType Directory -Path $env:APP_ENV -Force|Out-Null;Copy-Item -Path (Join-Path $src.FullName '*') -Destination $env:APP_ENV -Recurse -Force" >>"%LOG%" 2>&1
set "DL_EXIT=%ERRORLEVEL%"
del /q "%ZIP%" >nul 2>&1
rmdir /s /q "%EXTRACT%" >nul 2>&1
if not "%DL_EXIT%"=="0" exit /b 1
if not exist "%APP%\backend\BioSeq_Server.py" exit /b 1
exit /b 0

:update_core
if "%PROTOCOL%"=="0" echo 正在同步核心启动和 WGS 后端文件...
set "RAW_BASE=https://raw.githubusercontent.com/ttmmss278-png/TMM/main"
call :download_file "%RAW_BASE%/backend/wgs_runner.py" "%APP%\backend\wgs_runner.py"
call :download_file "%RAW_BASE%/BioSeq_Local_Service/BioSeq_Start.bat" "%APP%\BioSeq_Local_Service\BioSeq_Start.bat"
call :download_file "%RAW_BASE%/backend/requirements.txt" "%APP%\backend\requirements.txt"
exit /b 0

:download_file
set "DL_URL=%~1"
set "DL_TARGET=%~2"
set "DL_TMP=%TEMP%\TMMBioSeq_core_%RANDOM%_%RANDOM%.tmp"
set "DL_URL_ENV=%DL_URL%"
set "DL_TARGET_ENV=%DL_TARGET%"
set "DL_TMP_ENV=%DL_TMP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{Invoke-WebRequest -UseBasicParsing -Uri $env:DL_URL_ENV -OutFile $env:DL_TMP_ENV;Copy-Item -LiteralPath $env:DL_TMP_ENV -Destination $env:DL_TARGET_ENV -Force;exit 0}catch{exit 1}" >>"%LOG%" 2>&1
del /q "%DL_TMP%" >nul 2>&1
exit /b 0

:register_protocol
if /I not "%SELF%"=="%FIXED%" copy /Y "%SELF%" "%FIXED%" >nul 2>&1
if not exist "%FIXED%" exit /b 1
set "FIXED_ENV=%FIXED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]34;$pct=[char]37;$root='HKCU:\Software\Classes\bioseq';New-Item -Path $root -Force|Out-Null;Set-Item -Path $root -Value 'URL:TMM BioSeq Engine Launcher';New-ItemProperty -Path $root -Name 'URL Protocol' -Value '' -PropertyType String -Force|Out-Null;$key=Join-Path $root 'shell\open\command';New-Item -Path $key -Force|Out-Null;$cmd=$q+$env:ComSpec+$q+' /d /c '+$q+$q+$env:FIXED_ENV+$q+' '+$q+$pct+'1'+$q+$q;Set-Item -Path $key -Value $cmd" >>"%LOG%" 2>&1
exit /b %ERRORLEVEL%

:ensure_wgs_tools
call :wgs_tools_ready
if not errorlevel 1 (
    if "%PROTOCOL%"=="0" echo WGS 工具环境已就绪。
    exit /b 0
)
if "%PROTOCOL%"=="0" (
    echo 未检测到 fastp、bwa、samtools，正在自动安装...
    echo Windows 将显示管理员授权窗口。
)
if exist "%APP%\BioSeq_Local_Service\Install_WGS_Tools_WSL.bat" copy /Y "%APP%\BioSeq_Local_Service\Install_WGS_Tools_WSL.bat" "%WGS_INSTALLER%" >nul 2>&1
if not exist "%WGS_INSTALLER%" call :download_file "https://raw.githubusercontent.com/ttmmss278-png/TMM/main/BioSeq_Local_Service/Install_WGS_Tools_WSL.bat" "%WGS_INSTALLER%"
if not exist "%WGS_INSTALLER%" exit /b 1
set "WGS_INSTALLER_ENV=%WGS_INSTALLER%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$cmd='\"\"'+$env:WGS_INSTALLER_ENV+'\" --auto\"';$p=Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',$cmd) -Verb RunAs -PassThru -Wait;exit $p.ExitCode" >>"%LOG%" 2>&1
set "INSTALL_EXIT=%ERRORLEVEL%"
if "%INSTALL_EXIT%"=="10" exit /b 10
if "%INSTALL_EXIT%"=="11" exit /b 11
if not "%INSTALL_EXIT%"=="0" exit /b 1
call :wgs_tools_ready
exit /b %ERRORLEVEL%

:wgs_tools_ready
where fastp >nul 2>&1
if not errorlevel 1 (
    where bwa >nul 2>&1
    if not errorlevel 1 (
        where samtools >nul 2>&1
        if not errorlevel 1 exit /b 0
    )
)
where wsl.exe >nul 2>&1
if errorlevel 1 exit /b 1
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\TMMBioSeq" /v WslDistro 2^>nul ^| findstr /I "WslDistro"') do set "DISTRO=%%B"
wsl.exe -d "%DISTRO%" -u root -- bash -lc "command -v fastp >/dev/null 2>&1 && command -v bwa >/dev/null 2>&1 && command -v samtools >/dev/null 2>&1 && command -v bcftools >/dev/null 2>&1" >nul 2>&1
exit /b %ERRORLEVEL%

:ensure_python
where py >nul 2>&1
if not errorlevel 1 exit /b 0
where python >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" exit /b 0
where winget >nul 2>&1
if errorlevel 1 (
    echo [错误] 未检测到 Python，且系统没有 winget。
    exit /b 1
)
if "%PROTOCOL%"=="0" echo 未检测到 Python，正在安装 Python 3.12...
winget install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements >>"%LOG%" 2>&1
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" exit /b 0
where py >nul 2>&1
exit /b %ERRORLEVEL%

:engine_online
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$r=Invoke-WebRequest -UseBasicParsing -Uri $env:STATUS_URL -TimeoutSec 1;if($r.StatusCode -eq 200){exit 0}}catch{};exit 1" >nul 2>&1
exit /b %ERRORLEVEL%

:failed
if "%PROTOCOL%"=="0" (
    echo.
    echo =====================================================
    echo 启动或安装未完成
    echo =====================================================
    echo 日志：%LOG%
    echo WGS 安装日志：%ROOT%\logs\wgs_tools_install.log
    echo.
    if exist "%LOG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG%' -Tail 30"
    echo.
    pause
)
exit /b 1
