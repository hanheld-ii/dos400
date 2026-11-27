@echo off
rem tell dosbox-x to set the correct version
ver set 4 00
rem mount our build dir as a:, create disk images
mount a ./build
imgmake dos4boot12.img -t fd_1200
imgmake dos4boot144.img -t fd_1440
imgmake dos4hd.vhd -t vhd -size 33

rem mount images, transfer system, transfer dos
imgmount e dos4hd.vhd
a:
sys e:
mkdir e:\dos4
xcopy *.* e:\dos4
copy command.com e:\
rem imgmount -u e
imgmount b dos4boot12.img
sys b:
xcopy e:\dos4\*.* b:\
rem copy command.com b:\
imgmount -u b
imgmount b dos4boot144.img
sys b:
xcopy e:\dos4\*.* b:\
rem copy command.com b:\
imgmount -u b 
imgmount -u e

