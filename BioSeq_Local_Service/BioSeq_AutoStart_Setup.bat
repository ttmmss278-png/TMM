@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "BIOSEQ_ARG=%~1"
set "BIOSEQ_SELF=%~f0"
set "BIOSEQ_ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "BIOSEQ_DEFAULT_APP=%BIOSEQ_ROOT%\app"
set "BIOSEQ_RUNTIME=%BIOSEQ_ROOT%\runtime"
set "BIOSEQ_VENV=%BIOSEQ_RUNTIME%\venv"
set "BIOSEQ_LOGDIR=%BIOSEQ_ROOT%\logs"
set "BIOSEQ_LOG=%BIOSEQ_LOGDIR%\engine_start.log"
set "BIOSEQ_STDOUT=%BIOSEQ_LOGDIR%\engine_stdout.log"
set "BIOSEQ_STDERR=%BIOSEQ_LOGDIR%\engine_stderr.log"
set "BIOSEQ_INSTALLED=%BIOSEQ_ROOT%\BioSeq_Engine_Launcher.bat"
set "BIOSEQ_STATUS=http://127.0.0.1:8765/status"
set "BIOSEQ_APP="

echo(%BIOSEQ_ARG%| findstr /I /B /C:"bioseq://start" >nul 2>&1
if not errorlevel 1 (
    set "BIOSEQ_PROTOCOL=1"
) else (
    set "BIOSEQ_PROTOCOL=0"
    title TMM BioSeq Engine 修复与启动
)

if not exist "%BIOSEQ_ROOT%" mkdir "%BIOSEQ_ROOT%" >nul 2>&1
if not exist "%BIOSEQ_RUNTIME%" mkdir "%BIOSEQ_RUNTIME%" >nul 2>&1
if not exist "%BIOSEQ_LOGDIR%" mkdir "%BIOSEQ_LOGDIR%" >nul 2>&1

>"%BIOSEQ_LOG%" echo [%date% %time%] BioSeq repair/start
>>"%BIOSEQ_LOG%" echo Launcher: %BIOSEQ_SELF%

if "%BIOSEQ_PROTOCOL%"=="0" (
    echo =====================================================
    echo   TMM BioSeq Engine 修复与启动工具
    echo =====================================================
    echo.
)

call :check_running
if not errorlevel 1 (
    call :register_launcher
    if "%BIOSEQ_PROTOCOL%"=="0" (
        echo 已检测到 BioSeq Engine 正在运行。
        echo 未重新下载，也未重复启动。
        echo 网页启动关联已修复。
        echo.
        pause
    )
    exit /b 0
)

call :find_app
if not defined BIOSEQ_APP (
    call :download_app
    if errorlevel 1 goto :failed
)

set "BIOSEQ_SERVER=%BIOSEQ_APP%\backend\BioSeq_Server.py"
set "BIOSEQ_REQ=%BIOSEQ_APP%\backend\requirements.txt"

if not exist "%BIOSEQ_SERVER%" (
    >>"%BIOSEQ_LOG%" echo ERROR: Server missing: %BIOSEQ_SERVER%
    echo [错误] 找不到 BioSeq_Server.py：
    echo %BIOSEQ_SERVER%
    goto :failed
)

if "%BIOSEQ_PROTOCOL%"=="0" (
    echo 使用现有 BioSeq 程序：
    echo %BIOSEQ_APP%
    echo.
)

call :register_launcher
if errorlevel 1 goto :failed

call :find_python
if not defined BIOSEQ_PYBASE (
    call :install_python
)
if not defined BIOSEQ_PYBASE (
    echo [错误] 未检测到 Python 3，并且无法自动安装。
    echo 请安装 Python 3.10 或更高版本后重试。
    >>"%BIOSEQ_LOG%" echo ERROR: Python not found.
    goto :failed
)

if "%BIOSEQ_PROTOCOL%"=="0" echo [1/4] 检查 Python...
%BIOSEQ_PYBASE% --version >>"%BIOSEQ_LOG%" 2>&1
if errorlevel 1 (
    echo [错误] Python 命令无法运行：%BIOSEQ_PYBASE%
    goto :failed
)

if not exist "%BIOSEQ_VENV%\Scripts\python.exe" (
    if "%BIOSEQ_PROTOCOL%"=="0" echo [2/4] 首次创建独立 Python 环境...
    >>"%BIOSEQ_LOG%" echo Creating venv: %BIOSEQ_VENV%
    %BIOSEQ_PYBASE% -m venv "%BIOSEQ_VENV%" >>"%BIOSEQ_LOG%" 2>&1
    if errorlevel 1 (
        echo [错误] 创建 Python 虚拟环境失败。
        goto :failed
    )
) else (
    if "%BIOSEQ_PROTOCOL%"=="0" echo [2/4] 已找到独立 Python 环境。
)

set "BIOSEQ_VENVPY=%BIOSEQ_VENV%\Scripts\python.exe"

if "%BIOSEQ_PROTOCOL%"=="0" echo [3/4] 检查 Flask 依赖...
"%BIOSEQ_VENVPY%" -c "import flask, flask_cors, werkzeug" >nul 2>&1
if errorlevel 1 (
    if "%BIOSEQ_PROTOCOL%"=="0" echo 正在安装依赖，首次运行可能需要几分钟...
    >>"%BIOSEQ_LOG%" echo Installing requirements from %BIOSEQ_REQ%
    "%BIOSEQ_VENVPY%" -m pip install --disable-pip-version-check -r "%BIOSEQ_REQ%" >>"%BIOSEQ_LOG%" 2>&1
    if errorlevel 1 (
        echo [错误] Flask 依赖安装失败。
        goto :failed
    )
)

if "%BIOSEQ_PROTOCOL%"=="0" echo [4/4] 正在启动 BioSeq Engine...
>>"%BIOSEQ_LOG%" echo Starting server: %BIOSEQ_SERVER%
del /q "%BIOSEQ_STDOUT%" "%BIOSEQ_STDERR%" >nul 2>&1

set "BIOSEQ_START_PY=%BIOSEQ_VENVPY%"
set "BIOSEQ_START_SERVER=%BIOSEQ_SERVER%"
set "BIOSEQ_START_WORKDIR=%BIOSEQ_APP%"
set "BIOSEQ_START_OUT=%BIOSEQ_STDOUT%"
set "BIOSEQ_START_ERR=%BIOSEQ_STDERR%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Start-Process -FilePath $env:BIOSEQ_START_PY -ArgumentList @($env:BIOSEQ_START_SERVER) -WorkingDirectory $env:BIOSEQ_START_WORKDIR -WindowStyle Hidden -RedirectStandardOutput $env:BIOSEQ_START_OUT -RedirectStandardError $env:BIOSEQ_START_ERR" >>"%BIOSEQ_LOG%" 2>&1

if errorlevel 1 (
    echo [错误] 无法创建 BioSeq Engine 进程。
    goto :failed
)

for /L %%I in (1,1,160) do (
    call :check_running
    if not errorlevel 1 goto :started
    >nul 2>&1 ping 127.0.0.1 -n 2
)

echo [错误] BioSeq Engine 进程已调用，但端口 8765 未启动。
goto :failed

:started
>>"%BIOSEQ_LOG%" echo Engine online: %BIOSEQ_STATUS%
if "%BIOSEQ_PROTOCOL%"=="0" (
    echo.
    echo BioSeq Engine 已成功启动。
    echo 网页现在应显示“分析引擎已连接”。
    echo.
    echo 本地地址：%BIOSEQ_STATUS%
    echo 日志目录：%BIOSEQ_LOGDIR%
    echo.
    pause
)
exit /b 0

:check_running
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$r=Invoke-WebRequest -UseBasicParsing -Uri $env:BIOSEQ_STATUS -TimeoutSec 1;if($r.StatusCode -eq 200){exit 0}}catch{};exit 1" >nul 2>&1
exit /b %ERRORLEVEL%

:find_app
if exist "%BIOSEQ_DEFAULT_APP%\backend\BioSeq_Server.py" (
    set "BIOSEQ_APP=%BIOSEQ_DEFAULT_APP%"
    exit /b 0
)

for %%D in (
    "%USERPROFILE%\Desktop\TMM"
    "%USERPROFILE%\Desktop\TMM-main"
    "%USERPROFILE%\Downloads\TMM"
    "%USERPROFILE%\Downloads\TMM-main"
    "%USERPROFILE%\Documents\TMM"
    "%USERPROFILE%\Documents\TMM-main"
) do (
    if not defined BIOSEQ_APP if exist "%%~D\backend\BioSeq_Server.py" set "BIOSEQ_APP=%%~fD"
)

if defined BIOSEQ_APP exit /b 0

set "BIOSEQ_FIND_FILE=%TEMP%\TMMBioSeq_find_%RANDOM%.txt"
set "BIOSEQ_FIND_OUTPUT=%BIOSEQ_FIND_FILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$roots=@((Join-Path $env:USERPROFILE 'Desktop'),(Join-Path $env:USERPROFILE 'Downloads'),(Join-Path $env:USERPROFILE 'Documents'));" ^
 "$hit=$null;foreach($root in $roots){if(Test-Path $root){$hit=Get-ChildItem -LiteralPath $root -Filter 'BioSeq_Server.py' -File -Recurse -ErrorAction SilentlyContinue | Where-Object {$_.DirectoryName -like '*\backend'} | Select-Object -First 1;if($hit){break}}};" ^
 "if($hit){Split-Path -Parent (Split-Path -Parent $hit.FullName) | Set-Content -LiteralPath $env:BIOSEQ_FIND_OUTPUT -Encoding ASCII}" >nul 2>&1

if exist "%BIOSEQ_FIND_FILE%" (
    set /p BIOSEQ_APP=<"%BIOSEQ_FIND_FILE%"
    del /q "%BIOSEQ_FIND_FILE%" >nul 2>&1
)
exit /b 0

:download_app
if "%BIOSEQ_PROTOCOL%"=="0" (
    echo 未发现本地 BioSeq 程序，正在从 GitHub 下载...
)
>>"%BIOSEQ_LOG%" echo Downloading TMM repository.

set "BIOSEQ_ZIP=%TEMP%\TMMBioSeq_%RANDOM%_%RANDOM%.zip"
set "BIOSEQ_EXTRACT=%TEMP%\TMMBioSeq_extract_%RANDOM%_%RANDOM%"
set "BIOSEQ_ZIP_ENV=%BIOSEQ_ZIP%"
set "BIOSEQ_EXTRACT_ENV=%BIOSEQ_EXTRACT%"
set "BIOSEQ_APP_ENV=%BIOSEQ_DEFAULT_APP%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/ttmmss278-png/TMM/archive/refs/heads/main.zip' -OutFile $env:BIOSEQ_ZIP_ENV;" ^
 "Expand-Archive -LiteralPath $env:BIOSEQ_ZIP_ENV -DestinationPath $env:BIOSEQ_EXTRACT_ENV -Force;" ^
 "$src=Get-ChildItem -LiteralPath $env:BIOSEQ_EXTRACT_ENV -Directory | Where-Object {$_.Name -like 'TMM-*'} | Select-Object -First 1;" ^
 "if(-not $src){throw 'TMM directory not found in archive'};" ^
 "New-Item -ItemType Directory -Path $env:BIOSEQ_APP_ENV -Force | Out-Null;" ^
 "Copy-Item -Path (Join-Path $src.FullName '*') -Destination $env:BIOSEQ_APP_ENV -Recurse -Force" >>"%BIOSEQ_LOG%" 2>&1

set "BIOSEQ_DOWNLOAD_EXIT=%ERRORLEVEL%"
del /q "%BIOSEQ_ZIP%" >nul 2>&1
rmdir /s /q "%BIOSEQ_EXTRACT%" >nul 2>&1

if not "%BIOSEQ_DOWNLOAD_EXIT%"=="0" (
    echo [错误] 无法下载 TMM BioSeq 程序。
    exit /b 1
)

if not exist "%BIOSEQ_DEFAULT_APP%\backend\BioSeq_Server.py" (
    echo [错误] 下载完成，但没有找到 BioSeq_Server.py。
    exit /b 1
)

set "BIOSEQ_APP=%BIOSEQ_DEFAULT_APP%"
exit /b 0

:find_python
set "BIOSEQ_PYBASE="

where py >nul 2>&1
if not errorlevel 1 (
    py -3 --version >nul 2>&1
    if not errorlevel 1 set "BIOSEQ_PYBASE=py -3"
)

if not defined BIOSEQ_PYBASE (
    where python >nul 2>&1
    if not errorlevel 1 (
        python --version >nul 2>&1
        if not errorlevel 1 set "BIOSEQ_PYBASE=python"
    )
)

if not defined BIOSEQ_PYBASE (
    for %%P in (
        "%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
        "%ProgramFiles%\Python313\python.exe"
        "%ProgramFiles%\Python312\python.exe"
        "%ProgramFiles%\Python311\python.exe"
    ) do (
        if not defined BIOSEQ_PYBASE if exist "%%~P" set "BIOSEQ_PYBASE=%%~P"
    )
)
exit /b 0

:install_python
where winget >nul 2>&1
if errorlevel 1 exit /b 1

if "%BIOSEQ_PROTOCOL%"=="0" (
    echo 未检测到 Python，正在使用 winget 安装 Python 3.12...
)
>>"%BIOSEQ_LOG%" echo Installing Python 3.12 with winget.

winget install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements >>"%BIOSEQ_LOG%" 2>&1

if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    set "BIOSEQ_PYBASE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
)
exit /b 0

:register_launcher
if /I not "%BIOSEQ_SELF%"=="%BIOSEQ_INSTALLED%" (
    copy /Y "%BIOSEQ_SELF%" "%BIOSEQ_INSTALLED%" >nul 2>&1
    if errorlevel 1 (
        echo [错误] 无法安装网页启动器。
        exit /b 1
    )
)

set "BIOSEQ_PROTOCOL_LAUNCHER=%BIOSEQ_INSTALLED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$q=[char]34;$pct=[char]37;" ^
 "$root='HKCU:\Software\Classes\bioseq';" ^
 "New-Item -Path $root -Force | Out-Null;" ^
 "Set-Item -Path $root -Value 'URL:TMM BioSeq Engine Launcher';" ^
 "New-ItemProperty -Path $root -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null;" ^
 "$cmdKey=Join-Path $root 'shell\open\command';New-Item -Path $cmdKey -Force | Out-Null;" ^
 "$cmd=$q+$env:ComSpec+$q+' /d /c '+$q+$q+$env:BIOSEQ_PROTOCOL_LAUNCHER+$q+' '+$q+$pct+'1'+$q+$q;" ^
 "Set-Item -Path $cmdKey -Value $cmd;" ^
 "$cfg='HKCU:\Software\TMMBioSeq';New-Item -Path $cfg -Force | Out-Null;" ^
 "Set-ItemProperty -Path $cfg -Name 'LauncherBat' -Value $env:BIOSEQ_PROTOCOL_LAUNCHER;" ^
 "if($env:BIOSEQ_APP){Set-ItemProperty -Path $cfg -Name 'AppDir' -Value $env:BIOSEQ_APP}" >>"%BIOSEQ_LOG%" 2>&1

exit /b %ERRORLEVEL%

:failed
>>"%BIOSEQ_LOG%" echo Startup failed.
if "%BIOSEQ_PROTOCOL%"=="0" (
    echo.
    echo 启动失败。下面是诊断信息：
    echo -----------------------------------------------------
    if exist "%BIOSEQ_LOG%" type "%BIOSEQ_LOG%"
    if exist "%BIOSEQ_STDERR%" (
        echo.
        echo Python 后端错误：
        type "%BIOSEQ_STDERR%"
    )
    if exist "%BIOSEQ_STDOUT%" (
        echo.
        echo Python 后端输出：
        type "%BIOSEQ_STDOUT%"
    )
    echo -----------------------------------------------------
    echo.
    echo 日志目录：
    echo %BIOSEQ_LOGDIR%
    echo.
    pause
)
exit /b 1
