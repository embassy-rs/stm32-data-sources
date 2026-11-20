#!/usr/bin/env bash

set -e
cd $(dirname $0)

die() { echo "$*" 1>&2; exit 1; }

require() {
    for i in "$@"; do
        command -v "$i" &>/dev/null || die "Missing the command line tool '$i'"
    done
}

CMD=$1
shift

CMSIS_FAMILIES="c0 f0 f1 f2 f3 f4 f7 g0 g4 h5 h7 h7rs l0 l1 l4 l5 n6 u0 u3 u5 wb wb0 wba wl wl3"
DFP_FAMILIES="c5 g5 h7p"

copy_device_headers() {
    local src_dir=$1
    local dst_dir=$2
    for h in "$src_dir"/*.h; do
        [ -f "$h" ] || continue
        local base=$(basename "$h")
        case "$base" in
            system_*.h|partition_*.h|RTE_Components.h|mmu_*.h|*_ca7.h) continue ;;
            stm32wl3xx.h) ;; # actual device header for STM32WL30/31/33
            stm32??x.h|stm32???x.h|stm32??xx.h|stm32???xx.h|stm32????xx.h) continue ;; # family umbrella headers
            stm32wb0[0-9].h)
                # STM32WB0x headers omit the `xx` suffix upstream; normalize to stm32wb0?xx.h.
                base="${base%.h}xx.h"
                ;;
        esac
        cp "$h" "$dst_dir/$base"
        # Fix known upstream typos/omissions in CMSIS device headers.
        sed -i \
            -e 's/\(#define[[:space:]]\+OCTOSPI_CR_FTIE_Msk[[:space:]]\+XSPI_CR_FTIE_Msk\))/\1 /' \
            -e 's/RRM_CBIAS0_HW_TRIM_OUT _HW_CBIAS_/RRM_CBIAS0_HW_TRIM_OUT_HW_CBIAS_/g' \
            "$dst_dir/$base"
        case "$base" in
            stm32f030*.h|stm32f070*.h)
                if ! grep -q '#define[[:space:]]\+UID_BASE\b' "$dst_dir/$base"; then
                    sed -i '/#define[[:space:]]\+FLASHSIZE_BASE\b/a #define UID_BASE              0x1FFFF7ACUL       /*!< Unique device ID register base address */' "$dst_dir/$base"
                fi
                ;;
        esac
    done
}

case "$CMD" in
    download-all)
        ./d download-mcufinder
        ./d download-svd
        ./d download-headers
        ./d download-dfp
        ./d download-cubedb
        ./d download-cubeprogdb
    ;;
    download-mcufinder)
        require wget
        mkdir -p mcufinder
        wget http://stmcufinder.com/API/getFiles.php -O mcufinder/files.json
        wget http://stmcufinder.com/API/getMCUsForMCUFinderPC.php -O mcufinder/mcus.json
    ;;
    download-pdf)
        require jq wget
        jq -r .Files[].URL < mcufinder/files.json | wget -P pdf/ -N -i -
    ;;
    download-svd)
        require git svd
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
        require git
        rm -rf headers
        mkdir -p headers ./git

        for f in $CMSIS_FAMILIES; do
            rm -rf ./git/cmsis-device-$f
            git clone --depth 1 https://github.com/STMicroelectronics/cmsis-device-$f ./git/cmsis-device-$f
            copy_device_headers "./git/cmsis-device-$f/Include" headers
        done

        # STM32MP1 has no standalone cmsis-device-mp1 repo; pull CM4 headers from STM32CubeMP1.
        rm -rf ./git/STM32CubeMP1
        git clone --depth 1 --filter=blob:none --sparse https://github.com/STMicroelectronics/STM32CubeMP1 ./git/STM32CubeMP1
        git -C ./git/STM32CubeMP1 sparse-checkout set Drivers/CMSIS/Device/ST/STM32MP1xx/Include
        copy_device_headers "./git/STM32CubeMP1/Drivers/CMSIS/Device/ST/STM32MP1xx/Include" headers

        # DFP families also ship CMSIS device headers.
        for f in $DFP_FAMILIES; do
            rm -rf ./git/stm32${f}xx-dfp
            git clone --depth 1 https://github.com/STMicroelectronics/stm32${f}xx-dfp ./git/stm32${f}xx-dfp
            copy_device_headers "./git/stm32${f}xx-dfp/Include" headers
        done
    ;;
    download-dfp)
        require git
        mkdir -p cubeprogdb2 headers svd ./git
        for f in $DFP_FAMILIES; do
            local_repo=./git/stm32${f}xx-dfp
            rm -rf "$local_repo"
            git clone --depth 1 https://github.com/STMicroelectronics/stm32${f}xx-dfp "$local_repo"

            rm -rf cubeprogdb2/stm32${f}
            mkdir -p cubeprogdb2/stm32${f}
            cp -r "$local_repo/Descriptors" cubeprogdb2/stm32${f}/
            cp "$local_repo"/*.pdsc cubeprogdb2/stm32${f}/
            cp "$local_repo/Descriptors/peripheral_configuration_mapping.json" cubeprogdb2/stm32${f}/
            rm -f cubeprogdb2/stm32${f}/Descriptors/peripheral_configuration_mapping.json
            cp "$local_repo/LICENSE.md" cubeprogdb2/LICENSE.md

            copy_device_headers "$local_repo/Include" headers

            for s in "$local_repo"/SVD/*.svd; do
                [ -f "$s" ] || continue
                base=$(basename "$s" | tr '[:upper:]' '[:lower:]')
                cp "$s" "svd/$base"
            done
        done
    ;;
    download-cubedb)
        require git
        rm -rf cubedb
        git clone --depth 1 https://github.com/embassy-rs/stm32cube-database.git cubedb
    ;;
    download-cubeprogdb)
        require git
        rm -rf cubeprogdb
        git clone --depth 1 https://github.com/embassy-rs/stm32cubeprog-database.git cubeprogdb
    ;;
    *)
        echo "unknown command"
    ;;
esac
