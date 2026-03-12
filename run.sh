#!/bin/bash
export OMP_NUM_THREADS=120

# Extract FOM metrics from log files and save to CSV
extract_fom_metrics() {
    local csv_output="${result_dir}/fom_metrics.csv"
    
    echo "Run,FOM_z_s" > "$csv_output"
    
    for i in 1 2 3 4; do
        local log_file="${OUT_RESULT_DIR}/log_${i}"
        if [ -f "$log_file" ]; then
            local fom=$(grep -E "^FOM" "$log_file" | awk -F'=' '{print $2}' | awk '{print $1}')
            fom=${fom:-N/A}
            
            echo "run_${i},${fom}" >> "$csv_output"
            echo "[INFO] Run ${i}: FOM=${fom} z/s"
        else
            echo "[WARN] Log file not found: $log_file"
        fi
    done
    
    echo "[INFO] FOM metrics saved to: $csv_output"
    
    echo ""
    echo "========== FOM Summary =========="
    column -t -s',' "$csv_output"
    echo "================================="
}

# Extract FOM from ratio benchmark logs and generate plot (supports dual mode)
extract_ratio_fom_and_plot() {
    local output_dir="$1"
    local fom_csv="${output_dir}/fom_ratio_results.csv"
    local plot_data="${output_dir}/fom_plot_data.dat"
    local plot_output="${output_dir}/fom_ratio_plot.png"
    
    echo "ratio,node0_weight,node1_weight,mode,run_index,fom" > "$fom_csv"
    
    # Extract FOM from each ratio subdirectory
    for ratio_dir in "${output_dir}"/*/; do
        if [ -d "$ratio_dir" ]; then
            local dir_name=$(basename "$ratio_dir")
            # Skip non-ratio directories
            [[ "$dir_name" != *"to"* ]] && continue
            
            # Convert directory name to ratio (e.g., 10to1 -> 10:1)
            local ratio=$(echo "$dir_name" | sed 's/to/:/')
            
            local node0_weight="${ratio%%:*}"
            local node1_weight="${ratio##*:}"
            
            # Check if we have mode subdirectories (native/cxlmalloc)
            if [ -d "${ratio_dir}native" ] || [ -d "${ratio_dir}cxlmalloc" ]; then
                # Dual mode structure
                for mode in "native" "cxlmalloc"; do
                    local mode_dir="${ratio_dir}${mode}"
                    if [ -d "$mode_dir" ]; then
                        for log_file in "${mode_dir}/"log_*.log; do
                            if [ -f "$log_file" ]; then
                                local log_basename=$(basename "$log_file" .log)
                                local run_index=$(echo "$log_basename" | sed 's/log_//')
                                
                                local fom=$(grep -E "^FOM" "$log_file" | awk -F'=' '{print $2}' | awk '{print $1}')
                                fom=${fom:-0}
                                
                                echo "${ratio},${node0_weight},${node1_weight},${mode},${run_index},${fom}" >> "$fom_csv"
                            fi
                        done
                    fi
                done
            else
                # Single mode structure (backward compatibility)
                for log_file in "${ratio_dir}"log_*.log; do
                    if [ -f "$log_file" ]; then
                        local log_basename=$(basename "$log_file" .log)
                        local run_index=$(echo "$log_basename" | sed 's/log_//')
                        
                        local fom=$(grep -E "^FOM" "$log_file" | awk -F'=' '{print $2}' | awk '{print $1}')
                        fom=${fom:-0}
                        
                        echo "${ratio},${node0_weight},${node1_weight},native,${run_index},${fom}" >> "$fom_csv"
                    fi
                done
            fi
        fi
    done
    
    echo "[INFO] FOM results saved to: $fom_csv"
    echo "[DEBUG] CSV content:"
    
    # Generate plot data with average FOM per ratio and mode
    echo "# ratio_label native_fom cxlmalloc_fom" > "$plot_data"
    awk -F, 'NR>1 {
        ratio=$1
        mode=$4
        fom=$6
        key=ratio "_" mode
        sum[key] += fom
        count[key]++
        ratios[ratio] = 1
    }
    END {
        n = asorti(ratios, sorted_ratios)
        for (i=1; i<=n; i++) {
            r = sorted_ratios[i]
            native_key = r "_native"
            cxl_key = r "_cxlmalloc"
            native_avg = (count[native_key] > 0) ? sum[native_key] / count[native_key] : 0
            cxl_avg = (count[cxl_key] > 0) ? sum[cxl_key] / count[cxl_key] : 0
            printf "%s %.4f %.4f\n", r, native_avg, cxl_avg
        }
    }' "$fom_csv" >> "$plot_data"
    
    # Generate plot using gnuplot or Python
    if command -v gnuplot &> /dev/null; then
        gnuplot <<-EOF
            set terminal pngcairo enhanced font 'Arial,12' size 1200,600
            set output '${plot_output}'
            set title 'FOM vs Interleave Ratio'
            set xlabel 'Interleave Ratio (Node0:Node1)'
            set ylabel 'FOM (z/s)'
            set grid
            set style data linespoints
            set pointsize 1.5
            set xtics rotate by -45
            set key top right
            plot '${plot_data}' using 0:2:xtic(1) with linespoints pt 7 ps 1.5 lw 2 lc rgb '#0066cc' title 'Native', \
                 '${plot_data}' using 0:3:xtic(1) with linespoints pt 9 ps 1.5 lw 2 lc rgb '#cc3300' title 'CXLMalloc'
EOF
        echo "[INFO] Plot saved to: $plot_output"
    else
        # Use external Python script
        python3 ${PCXL_ROOT}/benchmark/script/plot_fom_ratio.py "$plot_data" "$plot_output"
    fi
    
    # Print summary table
    echo ""
    echo "========== FOM vs Ratio Summary =========="
    echo "Ratio        Native      CXLMalloc"
    awk 'NR>1 {printf "%-12s %-11s %s\n", $1, $2, $3}' "$plot_data"
    echo "=========================================="
}

# Run best ratio benchmark for LULESH
run_best_ratio_benchmark() {
    local output_dir="${1:-result/ratio_benchmark}"
    
    echo "[INFO] Running best ratio benchmark with both modes..."
    echo "[INFO] Output directory: $output_dir"
    
    find_best_ratio_with_modes "$output_dir" $(realpath ./build/lulesh2.0) -i 2 -s 450
    
    # Extract FOM and generate plot
    echo "[INFO] Extracting FOM metrics and generating plot..."
    extract_ratio_fom_and_plot "$output_dir"
}

# Extract FOM metrics from combine benchmark logs
extract_combine_fom_metrics() {
    local csv_output="${OUT_RESULT_DIR}/fom_combine_metrics.csv"
    
    echo "Run,NumaBalance,FOM_z_s" > "$csv_output"
    
    for mode in "off" "on"; do
        local log_file="${OUT_RESULT_DIR}/log_numabalance_${mode}.log"
        if [ -f "$log_file" ]; then
            local fom=$(grep -E "^FOM" "$log_file" | awk -F'=' '{print $2}' | awk '{print $1}')
            fom=${fom:-N/A}
            
            echo "numabal_${mode},${mode},${fom}" >> "$csv_output"
            echo "[INFO] NumaBalance ${mode}: FOM=${fom} z/s"
        else
            echo "[WARN] Log file not found: $log_file"
        fi
    done
    
    echo "[INFO] FOM metrics saved to: $csv_output"
    
    echo ""
    echo "========== Combine FOM Summary =========="
    column -t -s',' "$csv_output"
    echo "========================================="
}

REBUILD=$1
MODE=${2:-111}
if [ "$MODE" == "ratio" ]; then
    source benchmark/script/run_common_best_ratio.sh
elif [ "$MODE" == "latency" ]; then
    source benchmark/script/run_measure_latency.sh
elif [ "$MODE" == "combine" ]; then
    source benchmark/script/run_combine.sh
elif [ "$MODE" == "vis_miss" ]; then
    source benchmark/script/run_measure_miss.sh
else
    source benchmark/script/run_common.sh
fi

pushd benchmark/LULESH
if [ $REBUILD -eq 1 ]; then
    echo "rebuilding...."
    pushd build
    cmake -DCMAKE_BUILD_TYPE=Debug -DMPI_CXX_COMPILER=`which mpicxx` -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS -fno-pie -no-pie" \
      -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_EXE_LINKER_FLAGS -no-pie -Wl,-no-pie " ..
    make clean && make OMP=1 
    popd
fi


if [ "$MODE" == "ratio" ]; then
    OBJ_BANDWIDTH_RANK="${OUT_RESULT_DIR}/obj_bandwidth_rank.csv"
    export CXL_MALLOC_OBJ_RANK_RESULT="$(pwd)/${OBJ_BANDWIDTH_RANK}"
    RATIO_OUTPUT_DIR="${3:-result/ratio_benchmark}"
    run_best_ratio_benchmark "$RATIO_OUTPUT_DIR"
elif [ "$MODE" == "latency" ]; then
    run_and_measure_latency $(realpath ./build/lulesh2.0) -i 2 -s 500
elif [ "$MODE" == "vis_miss" ]; then
    run_and_analyze_vis_miss $(realpath ./build/lulesh2.0) -i 2 -s 500
elif [ "$MODE" == "combine" ]; then
    run_combine $(realpath ./build/lulesh2.0) -i 2 -s 500
    
    # Extract FOM metrics after combine runs complete
    echo "[INFO] Extracting FOM metrics from combine log files..."
    extract_combine_fom_metrics
else
    # Must use absolute path for the program when using addr2line in analysis
    run_and_analyze $MODE $(realpath ./build/lulesh2.0) -i 2 -s 500

    # Extract FOM metrics after all runs complete
    echo "[INFO] Extracting FOM metrics from log files..."
    extract_fom_metrics
fi
popd