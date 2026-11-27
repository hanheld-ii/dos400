@echo off
rem tell dosbox-x to set the correct version
ver set 4 00
rem mount our build dir as a:, create disk images
mount a ./build
imgmake out/dos4boot12.img -t fd_1200
imgmake out/dos4boot144.img -t fd_1440
imgmake out/dos4hd.vhd -t vhd -size 40

rem mount images, transfer system, transfer dos
imgmount e out/dos4hd.vhd
a:
sys e:
mkdir e:\dos4
xcopy *.* e:\dos4
copy command.com e:\
rem imgmount -u e
imgmount b out/dos4boot12.img
sys b:
xcopy e:\dos4\*.* b:\
rem copy command.com b:\
imgmount -u b
imgmount b out/dos4boot144.img
sys b:
xcopy e:\dos4\*.* b:\
rem copy command.com b:\
imgmount -u b 
imgmount -u e

