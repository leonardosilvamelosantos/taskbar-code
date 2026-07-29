@echo off
REM Ponto de entrada tolerante a duplo-clique: roda install.ps1 mesmo sob a
REM Execution Policy padrao (Restricted), sem exigir que quem executa saiba
REM da flag -ExecutionPolicy Bypass.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
