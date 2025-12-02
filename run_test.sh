#!/bin/bash
source benchmark/script/perf_band_monitor.sh

pushd benchmark/LULESH
REBUILD=$1
if [ $REBUILD -eq 1 ]; then
    echo "rebuilding...."
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Debug -DMPI_CXX_COMPILER=`which mpicxx` -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS -fno-pie -no-pie" \
      -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_EXE_LINKER_FLAGS -no-pie -Wl,-no-pie" ..
    make clean && make OMP=1 
    popd
fi

MODE=${2:-111}    
run_and_analyze $MODE ./build/lulesh2.0 -i 2 -s 400
popd