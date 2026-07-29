@echo off
setlocal EnableExtensions
chcp 65001 >nul

title TMM BioSeq Analysis Engine

set "SERVICE_DIR=%~dp0"
for %%I in ("%SERVICE_DIR%..") do set "PROJECT_DIR=%%~fI"
set "SERVER=%PROJECT_DIR%\backend\BioSeq_Server.py"
set "REQ=%PROJECT_DIR%\backend\requirements.txt"
set "RUNTIME_DIR=%LOCALAPPDATA%\TMMBioSeq\runtime"
set "VENV_DIR=%RUNTIME_DIR%\venv"
set "LOG_DIR=%LOCALAPPDATA%\TMMBioSeq\logs"
set "LOG_FILE=%LOG_DIR%\engine_start.log"

if not exist "%RUNTIME_DIR%" mkdir "%RUNTIME_DIR%" >nul 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

>"%LOG_FILE%" echo [%date% %time%] TMM BioSeq Engine startup
>>"%LOG_FILE%" echo Project: %PROJECT_DIR%
>>"%LOG_FILE%" echo Server: %SERVER%

echo ========================================
echo TMM BioSeq Analysis Platform
echo Local engine: http://127.0.0.1:8765
echo Log: %LOG_FILE%
echo ========================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$r=Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8765/status' -TimeoutSec 1;if($r.StatusCode -eq 200){exit 0}}catch{};exit 1" >nul 2>&1
if not errorlevel 1 (
    echo BioSeq Engine 已经在运行。
    >>"%LOG_FILE%" echo Engine already running.
    exit /b 0
)

if not exist "%SERVER%" (
    echo [错误] 找不到后端文件：
    echo %SERVER%
    >>"%LOG_FILE%" echo ERROR: Server file not found.
    pause
    exit /b 2
)

set "PY_CMD="
where py >nul 2>&1
if not errorlevel 1 set "PY_CMD=py -3"

if not defined PY_CMD (
    where python >nul 2>&1
    if not errorlevel 1 set "PY_CMD=python"
)

if not defined PY_CMD (
    for %%P in (
        "%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
        "%ProgramFiles%\Python313\python.exe"
        "%ProgramFiles%\Python312\python.exe"
        "%ProgramFiles%\Python311\python.exe"
    ) do if not defined PY_CMD if exist "%%~P" set "PY_CMD=%%~P"
)

if not defined PY_CMD (
    echo [错误] 未检测到 Python 3。
    echo 请安装 Python 3.10 或更高版本，并勾选 Add Python to PATH。
    >>"%LOG_FILE%" echo ERROR: Python 3 not found.
    pause
    exit /b 3
)

echo [1/4] 检测 Python...
%PY_CMD% --version
%PY_CMD% --version >>"%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [错误] Python 无法正常运行。
    >>"%LOG_FILE%" echo ERROR: Python command failed: %PY_CMD%
    pause
    exit /b 3
)

if not exist "%VENV_DIR%\Scripts\python.exe" (
    echo [2/4] 首次创建独立 Python 环境...
    >>"%LOG_FILE%" echo Creating virtual environment.
    %PY_CMD% -m venv "%VENV_DIR%" >>"%LOG_FILE%" 2>&1
    if errorlevel 1 (
        echo [错误] 无法创建 Python 虚拟环境。
        echo 请查看日志：%LOG_FILE%
        pause
        exit /b 4
    )
) else (
    echo [2/4] 已找到独立 Python 环境。
)

set "VENV_PY=%VENV_DIR%\Scripts\python.exe"

echo [3/4] 检查 BioSeq Python 依赖...
"%VENV_PY%" -c "import flask, flask_cors, werkzeug" >nul 2>&1
if errorlevel 1 (
    echo 正在安装 Flask 依赖，首次运行可能需要几分钟...
    >>"%LOG_FILE%" echo Installing Python dependencies.
    "%VENV_PY%" -m pip install --disable-pip-version-check -r "%REQ%" >>"%LOG_FILE%" 2>&1
    if errorlevel 1 (
        echo [错误] Python 依赖安装失败。
        echo 请查看日志：%LOG_FILE%
        pause
        exit /b 5
    )
)

echo [4/4] 启动 BioSeq Engine...
echo 保持此窗口开启，关闭窗口会停止分析引擎。
echo.
>>"%LOG_FILE%" echo Starting server.

cd /d "%PROJECT_DIR%"
"%VENV_PY%" "%SERVER%" 1>>"%LOG_FILE%" 2>>&1
set "SERVER_EXIT=%ERRORLEVEL%"

echo.
echo BioSeq Engine 已停止，退出代码：%SERVER_EXIT%
echo 日志：%LOG_FILE%
>>"%LOG_FILE%" echo Server stopped with exit code %SERVER_EXIT%.
pause
exit /b %SERVER_EXIT%
