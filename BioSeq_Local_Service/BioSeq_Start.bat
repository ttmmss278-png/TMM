@echo off
setlocal
title TMM BioSeq Analysis Engine
cd /d %~dp0

echo ========================================
echo TMM BioSeq Analysis Platform
echo Local engine: http://127.0.0.1:8765
echo ========================================

echo [1/3] Checking Python environment...
python --version
if errorlevel 1 (
    echo.
    echo Python was not found. Please install Python 3.10 or later and enable Add Python to PATH.
    pause
    exit /b 1
)

echo [2/3] Checking Python packages...
python -c "import flask, flask_cors, werkzeug" >nul 2>nul
if errorlevel 1 (
    echo Installing Flask dependencies...
    python -m pip install -r "..\backend\requirements.txt"
    if errorlevel 1 (
        echo Dependency installation failed. Check the network and Python permissions.
        pause
        exit /b 1
    )
)

echo [3/3] Starting BioSeq Engine...
echo Keep this window open while using the GitHub Pages workbench.
echo.
python "..\backend\BioSeq_Server.py"

echo.
echo BioSeq Engine stopped.
pause
endlocal