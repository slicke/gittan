@echo off
rem The gittan command of Gittan's installer (dist\windows\gittan.iss), in
rem {app}\bin, which the installer's PATH task adds to the PATH.
rem gittan [folder | file] opens it in Gittan, the current folder by default.
if not "%~1"=="" goto args
start "" "%~dp0..\Gittan.exe" "%CD%"
goto :eof
:args
start "" "%~dp0..\Gittan.exe" %*
