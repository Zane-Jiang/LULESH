#!/bin/bash
#!/bin/bash
export PCXL_ROOT=/home/jz/PCXL
# export CC=${PCXL_ROOT}/llvm-project/build/bin/clang
# export CXX=${PCXL_ROOT}/llvm-project/build/bin/clang++
# export LD_LIBRARY_PATH=${PCXL_ROOT}/lib/:$LD_LIBRARY_PATH


function enable_hmalloc_env() {
    export HMALLOC_JEMALLOC=1
    export HMALLOC_NODEMASK=4
    export HMALLOC_MPOL_MODE=2
}

function disable_hmalloc_env() {
    unset HMALLOC_JEMALLOC
    unset HMALLOC_NODEMASK
    unset HMALLOC_MPOL_MODE
} 


get_sysinfo()
{
  uname -a
  echo "--------------------------"
  sudo numactl --hardware
  echo "--------------------------"
  lscpu
  echo "--------------------------"
  cat /proc/cpuinfo
  echo "--------------------------"
  cat /proc/meminfo
}

disable_thp()
{
  echo "never" | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null 2>&1
}

disable_numa_balancing()
{
  echo 0 | sudo tee /proc/sys/kernel/numa_balancing >/dev/null 2>&1
}

disable_ksm()
{
  echo 0 | sudo tee /sys/kernel/mm/ksm/run >/dev/null 2>&1
}

disable_turbo()
{
  echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null 2>&1
}

disable_nmi_watchdog()
{
  echo 0 | sudo tee /proc/sys/kernel/nmi_watchdog >/dev/null 2>&1
}

flush_fs_caches()
{
  echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1
  sleep 5
}

disable_ht()
{
  echo off | sudo tee /sys/devices/system/cpu/smt/control >/dev/null 2>&1
}

bring_all_cpus_online()
{
  echo 1 | sudo tee /sys/devices/system/cpu/cpu*/online >/dev/null 2>&1
}

set_performance_mode()
{
  for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance | sudo tee $governor >/dev/null 2>&1
  done
}

check_pmqos()
{
  local pmqospid=$(ps -ef | grep pmqos | grep -v grep | grep -v sudo | awk '{print $2}')
  set_performance_mode
  [[ -n "$pmqospid" ]] && return
  sudo nohup ${TOPDIR}/pmqos >/dev/null 2>&1 &
  sleep 3
  pmqospid=$(ps -ef | grep pmqos | grep -v grep | grep -v sudo | awk '{print $2}')
  if [[ -z "$pmqospid" ]]; then
    echo "==> Error: failed to start pmqos!!!!"
    exit
  fi
}

configure_cxl_exp_cores()
{
  echo 1 | sudo tee /sys/devices/system/cpu/cpu*/online >/dev/null 2>&1
  echo 0 | sudo tee /sys/devices/system/node/node1/cpu*/online >/dev/null 2>&1
}

disable_va_aslr()
{
  echo 0 | sudo tee /proc/sys/kernel/randomize_va_space >/dev/null 2>&1
}

disable_swap()
{
  sudo swapoff -a
}

check_cxl_conf()
{
  disable_nmi_watchdog
  disable_va_aslr
  disable_ksm
  disable_numa_balancing
  disable_thp
  disable_ht
  disable_turbo
  disable_swap
#   check_pmqos
  configure_cxl_exp_cores
}

check_conf()
{
  disable_nmi_watchdog
  disable_va_aslr
  disable_ksm
  disable_numa_balancing
  disable_thp
  disable_ht
  disable_turbo
#   check_pmqos
  disable_swap
}

MEMSYS="/sys/devices/system/memory"
START=16
END=32
offline_mem(){
    for ((blk=$START; blk<=$END; blk++)); do
        path="$MEMSYS/memory${blk}"
        online_file="$path/online"

        if [ ! -d "$path" ]; then
            echo "[WARN] memory${blk} not exists, skip"
            continue
        fi

        state=$(cat "$online_file")

        echo 0 > "$online_file" 2>/dev/null && \
            echo "[OK] offline memory${blk} " || \
            echo "[FAIL] offline memory${blk} (maybe used)"
done
}

online_mem(){
    for ((blk=$START; blk<=$END; blk++)); do
        path="$MEMSYS/memory${blk}"
        online_file="$path/online"

        if [ ! -d "$path" ]; then
            echo "[WARN] memory${blk} not exists, skip"
            continue
        fi

        state=$(cat "$online_file")

        echo 1 > "$online_file" 2>/dev/null && \
            echo "[OK] online memory${blk} " || \
            echo "[FAIL] online memory${blk} (maybe )"
    done
}




## main function===============
cd benchmark/LULESH
if [ $# -eq 1 ]; then
    make clean && make -j$(nproc) OMP=1
fi

# enable_hmalloc_env
check_cxl_conf
check_conf
flush_fs_caches
# offline_mem


export OMP_NUM_THREADS=64
/usr/bin/time -v  numactl --cpunodebind=0 ./build/lulesh2.0 -i 50 -s 620 
# online_mem