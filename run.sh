#!/bin/bash
source benchmark/script/run_common.sh
export OMP_NUM_THREADS=60
pushd benchmark/LULESH
REBUILD=$1
if [ $REBUILD -eq 1 ]; then
    echo "rebuilding...."
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Debug -DMPI_CXX_COMPILER=`which mpicxx` -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS -fno-pie -no-pie" \
      -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_EXE_LINKER_FLAGS -no-pie -Wl,-no-pie " ..
    make clean && make OMP=1 
    popd
fi

MODE=${2:-111}    
# Must use absolute path for the program when using addr2line in analysis
run_and_analyze $MODE $(realpath ./build/lulesh2.0) -i 3 -s 400
popd