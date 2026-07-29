@echo off

title TMM BioSeq Analysis Engine

echo ==============================
echo TMM BioSeq Analysis Platform
echo ==============================

echo Checking Python environment...
python --version

if errorlevel 1 (
    echo Python not found. Please install Python 3.10+
    pause
    exit /b
)

cd /d %~dp0

python ../backend/BioSeq_Server.py

pause
