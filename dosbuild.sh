#!/bin/bash

# create the directory 'out' if it doesn't exist:
if [ ! -d "out" ]; then
    [ -e "out" ] || [ -L "out" ] && rm -f "out"
        mkdir "out"
	fi

# the directory 'backup' is intentionally ignored by git
dosbox-x -conf backup/mkdos.conf

