@echo off
REM Lance la telecommande de veille automatiquement a chaque ouverture de session Windows.
REM Double-clique ce fichier une seule fois (il doit rester dans le meme dossier que serveur_veille.py).

set "SCRIPT=%~dp0serveur_veille.py"
set "CIBLE=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\veille-pc.bat"

where pythonw >nul 2>nul
if errorlevel 1 (
  echo Python est introuvable. Installe-le depuis https://www.python.org en cochant "Add python.exe to PATH".
  pause
  exit /b 1
)

> "%CIBLE%" echo @echo off
>> "%CIBLE%" echo start "" pythonw "%SCRIPT%"

echo Installe : la telecommande demarrera a chaque ouverture de session.
echo Lancement maintenant...
start "" python "%SCRIPT%"
pause
