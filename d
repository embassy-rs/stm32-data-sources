#!/usr/bin/env bash

set -e
cd $(dirname $0)

die() { echo "$*" 1>&2; exit 1; }

for i in jq wget svd git; do
    command -v "$i" &>/dev/null || die "Missing the command line tool '$i'"
done

CMD=$1
shift

case "$CMD" in
    download-all)
        ./d download-mcufinder
        ./d download-svd
        ./d download-headers
        ./d download-cubedb
        ./d download-cubeprogdb
    ;;
    download-mcufinder)
        mkdir -p mcufinder
        wget http://stmcufinder.com/API/getFiles.php -O mcufinder/files.json
        wget http://stmcufinder.com/API/getMCUsForMCUFinderPC.php -O mcufinder/mcus.json	
    ;;
    download-pdf)
	    jq -r .Files[].URL < mcufinder/files.json  | wget -P pdf/ -N -i -
    ;;
    download-svd)
    	rm -rf ./git/stm32-rs
        git clone --depth 1 https://github.com/stm32-rs/stm32-rs.git ./git/stm32-rs
        (cd ./git/stm32-rs; make svdformat)
        mkdir -p svd
        for f in ./git/stm32-rs/svd/*.formatted; do
            base=$(basename $f | cut -f 1 -d .)
            cp $f svd/$base.svd
        done
    ;;
    download-headers)
        for f in F0 F1 F2 F3 F4 F7 H7 L0 L1 L4 L5 G0 G4 WB WL; do
            rm -rf ./git/STM32Cube$f
            git clone --depth 1 https://github.com/STMicroelectronics/STM32Cube$f git/STM32Cube$f
        done
        rm -rf headers
        mkdir -p headers
        cp git/STM32Cube*/Drivers/CMSIS/Device/ST/STM32*/Include/*.h headers
        rm headers/stm32??xx.h
        rm headers/system_*.h
        rm headers/partition_*.h
    ;;
    download-cubedb)
        rm -rf cubedb
        git clone --depth 1 https://github.com/embassy-rs/stm32cube-database.git cubedb
    ;;
    download-cubeprogdb)
        rm -rf cubeprogdb
        git clone --depth 1 https://github.com/embassy-rs/stm32cubeprog-database.git cubeprogdb
    ;;
    *)
        echo "unknown command"
    ;;
esac
