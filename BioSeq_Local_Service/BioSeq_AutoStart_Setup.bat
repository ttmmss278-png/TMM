@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "ARG=%~1"
set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "MANAGER=%ROOT%\BioSeq_Engine_Manager_v132.bat"
set "TEMP_MANAGER=%TEMP%\BioSeq_Engine_Manager_v132_%RANDOM%_%RANDOM%.bat"
set "MANAGER_URL=https://raw.githubusercontent.com/ttmmss278-png/TMM/main/BioSeq_Local_Service/BioSeq_Engine_Manager_v132.bat"
set "LOG=%ROOT%\logs\autostart_download.log"
set "PROTOCOL_MODE=0"

echo(%ARG%| findstr /I /B /C:"bioseq://" >nul 2>&1
if not errorlevel 1 set "PROTOCOL_MODE=1"

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
if not exist "%ROOT%\logs" mkdir "%ROOT%\logs" >nul 2>&1
>"%LOG%" echo [%date% %time%] Downloading BioSeq manager launcher

del /q "%TEMP_MANAGER%" >nul 2>&1
set "URL_ENV=%MANAGER_URL%"
set "TEMP_ENV=%TEMP_MANAGER%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
 "Invoke-WebRequest -UseBasicParsing -Uri $env:URL_ENV -OutFile $env:TEMP_ENV" >>"%LOG%" 2>&1

if errorlevel 1 (
    where curl.exe >nul 2>&1
    if errorlevel 1 goto :download_failed
    curl.exe -L --fail --retry 3 --connect-timeout 20 -o "%TEMP_MANAGER%" "%MANAGER_URL%" >>"%LOG%" 2>&1
    if errorlevel 1 goto :download_failed
)

if not exist "%TEMP_MANAGER%" goto :download_failed
for %%F in ("%TEMP_MANAGER%") do set "DOWNLOADED_SIZE=%%~zF"
if not defined DOWNLOADED_SIZE goto :download_failed
if %DOWNLOADED_SIZE% LSS 1500 goto :download_failed
move /Y "%TEMP_MANAGER%" "%MANAGER%" >>"%LOG%" 2>&1
if errorlevel 1 goto :download_failed

if defined ARG (
    call "%MANAGER%" "%ARG%"
) else (
    call "%MANAGER%"
)
set "RC=%ERRORLEVEL%"
if "%PROTOCOL_MODE%"=="1" exit /b %RC%
if not "%RC%"=="0" (
    echo.
    echo BioSeq 管理器未成功完成，退出代码：%RC%
    echo 日志：%LOG%
    echo 按任意键关闭...
    pause >nul
)
exit /b %RC%

:download_failed
if "%PROTOCOL_MODE%"=="1" exit /b 1
echo.
echo [错误] 无法下载 BioSeq 管理器入口。
echo 日志：%LOG%
echo.
if exist "%LOG%" type "%LOG%"
echo.
echo 按任意键关闭此窗口...
pause >nul
exit /b 1
