@echo off
c:
cd src
call setenv.bat
nmake
cpy c:\build
exit

