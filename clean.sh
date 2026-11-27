#!/usr/bin/env bash
    
for ext in CL1 CL2 CL3 CL4 CLA CLB CLC CLD CLE CLF CTL CPI MAP OBJ EXE COM SYS; do
    find src -type f -name "*.${ext}" -exec rm -v {} +
    done

rm -r build
mkdir build
#rm {IO,MSDOS}.SYS
rm out/*.img
rm out/*.vhd
tar xpf backup/tools.txz    



