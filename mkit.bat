@echo off
c:
cd src
call setenv.bat
nmake
cpy c:\build
rem call c:\src\mkboot.bat
exit

