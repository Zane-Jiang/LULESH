#!/bin/bash
export OMP_NUM_THREADS=60


extract_fom_metrics() {
    local csv_output="${OUT_RESULT_DIR}/fom_metrics.csv"
    
    echo "Run,FOM_z_s" > "$csv_output"
    
    for i in 1 2 3 4 5 6; do
        local log_file="${OUT_RESULT_DIR}/log_${i}"
        if [ -f "$log_file" ]; then
            local fom=$(grep -E "^FOM" "$log_file" | awk -F'=' '{print $2}' | awk '{print $1}')
            fom=${fom:-N/A}
            echo "run_${i},${fom}" >> "$csv_output"
            echo "[INFO] Run ${i}: FOM=${fom} z/s"
        fi
    done
    
    echo "[INFO] FOM metrics saved to: $csv_output"
    
    echo ""
    echo "========== FOM Summary =========="
    column -t -s',' "$csv_output"
    echo "================================="
}


REBUILD=$1
MODE=${2:-111}
if [ "$MODE" == "ratio" ]; then
    if [ -f benchmark/script/measurement/run_common_best_ratio.sh ]; then
        source benchmark/script/measurement/run_common_best_ratio.sh
    else
        echo "[WARN] benchmark/script/measurement/run_common_best_ratio.sh not found, fallback to benchmark/script/run_common.sh"
        source benchmark/script/run_common.sh
    fi
elif [ "$MODE" == "latency" ]; then
    source benchmark/script/reserve_latency_compare/run_measure_latency.sh
else
    source benchmark/script/run_common.sh
fi

pushd benchmark/LULESH
LULESH_ARGS_STR=${LULESH_ARGS_STR:-"-i 1 -s 450"}
read -r -a LULESH_ARGS_ARR <<< "${LULESH_ARGS_STR}"
if [ "$REBUILD" -eq 1 ]; then
    echo "rebuilding...."
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Debug -DMPI_CXX_COMPILER=`which mpicxx` -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS -fno-pie -no-pie" \
      -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_EXE_LINKER_FLAGS -no-pie -Wl,-no-pie " ..
    make clean && make OMP=1 
    popd
fi



run_and_analyze $MODE $(realpath ./build/lulesh2.0) "${LULESH_ARGS_ARR[@]}"
extract_fom_metrics

popd