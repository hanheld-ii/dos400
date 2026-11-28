@echo off
c:
cd \src\bios
call ..\setenv.bat
masm -Mx -t -I..\inc msdisk.asm,msdisk.TST,c:\build\msdisk.lst,NUL > c:\build\chk.log
masm -Mx -t -I..\inc msinit.asm,msinit.TST,c:\build\msinit.lst,NUL > c:\build\chk2.log
masm -Mx -t -I..\inc msbio2.asm,msbio2.TST,c:\build\msbio2.lst,NUL > c:\build\chk3.log
del msdisk.TST
del msinit.TST
del msbio2.TST
exit
