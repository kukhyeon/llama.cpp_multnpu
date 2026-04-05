#!/bin/sh
# run_npu_infer.sh - NPU inference only
# Run from: /data/local/tmp/llama.cpp

# screen brightness control
echo 0 > /sys/class/backlight/panel0-backlight/brightness

freq_from_idx() {
    idx=$1
    shift
    i=0
    for freq in "$@"; do
        if [ "$i" -eq "$idx" ]; then
            echo "$freq"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

# ---- S25 freq tables (kHz), index is 0-based ----
S25_CPU0_FREQS="384000 556800 748800 960000 1152000 1363200 1555200 1785600 1996800 2227200 2400000 2745600 2918400 3072000 3321600 3532800"
S25_CPU6_FREQS="1017600 1209600 1401600 1689600 1958400 2246400 2438400 2649600 2841600 3072000 3283200 3513600 3840000 4089600 4281600 4473600"
S25_DDR_FREQS="547000 1353000 1555000 1708000 2092000 2736000 3187000 3686000 4224000 4761000"

# ---- User-tunable indices (0-based) ----
CLK0_IDX=15
CLK6_IDX=15
DDR_IDX=9

# ---- Resolve kHz from indices ----
CLK0=$(freq_from_idx "$CLK0_IDX" $S25_CPU0_FREQS) || { echo "[error] invalid CLK0_IDX=$CLK0_IDX"; exit 1; }
CLK6=$(freq_from_idx "$CLK6_IDX" $S25_CPU6_FREQS) || { echo "[error] invalid CLK6_IDX=$CLK6_IDX"; exit 1; }
DDR_BOOST=$(freq_from_idx "$DDR_IDX" $S25_DDR_FREQS) || { echo "[error] invalid DDR_IDX=$DDR_IDX"; exit 1; }

# CPU Governor: performance
echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo performance > /sys/devices/system/cpu/cpufreq/policy6/scaling_governor
echo "CPU Governor (policy0): $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
echo "CPU Governor (policy6): $(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_governor)"
sleep 3


chmod 644 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
echo $CLK0 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
chmod 444 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
chmod 644 /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
echo $CLK0 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
chmod 444 /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq

chmod 644 /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq
echo $CLK6 > /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq
chmod 444 /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq
chmod 644 /sys/devices/system/cpu/cpufreq/policy6/scaling_min_freq
echo $CLK6 > /sys/devices/system/cpu/cpufreq/policy6/scaling_min_freq
chmod 444 /sys/devices/system/cpu/cpufreq/policy6/scaling_min_freq

chmod 644 /sys/devices/system/cpu/bus_dcvs/DDR/boost_freq
echo $DDR_BOOST > /sys/devices/system/cpu/bus_dcvs/DDR/boost_freq
chmod 444 /sys/devices/system/cpu/bus_dcvs/DDR/boost_freq

echo "[setup] DDR boost_freq: $(su -c 'cat /sys/devices/system/cpu/bus_dcvs/DDR/boost_freq' 2>/dev/null)"

echo "[setup] CPU gov: $(su -c 'cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor' 2>/dev/null) / $(su -c 'cat /sys/devices/system/cpu/cpufreq/policy6/scaling_governor' 2>/dev/null)"
    sleep 2

setenforce 0 && \
    export LD_LIBRARY_PATH=/data/local/tmp/llama.cpp/lib && \
    export ADSP_LIBRARY_PATH=/data/local/tmp/llama.cpp/lib && \
    export GGML_HEXAGON_HOSTBUF=1 && \
    export IGNITE_CSV_OP_BREAKDOWN=1 && \
    cd /data/local/tmp/llama.cpp && \
    taskset fe ./bin/llama-ignite-npu \
        -m /data/local/tmp/gguf/qwen-3-1.7b-q4_k_m.gguf \
        -t 6 -tb 6 -i -cnv -ub 512 -b 512 -fa off \
        --json-path data/qwen3_prefill_64_20.json \
	--strict on \
	--strict-limit 128 \
        --output-dir output \
        --temp 0 \
        --top-k 1 \
        -c 1024 \
        --device HTP0
# ---- Restore CPU freq (index 기반) ----
RST_CLK0_MAX=$(freq_from_idx 15 $S25_CPU0_FREQS)
RST_CLK0_MIN=$(freq_from_idx 0  $S25_CPU0_FREQS)
RST_CLK6_MAX=$(freq_from_idx 15 $S25_CPU6_FREQS)
RST_CLK6_MIN=$(freq_from_idx 0  $S25_CPU6_FREQS)
RST_DDR=$(freq_from_idx 0 $S25_DDR_FREQS)

chmod 644 /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
echo $RST_CLK0_MAX > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
chmod 644 /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
echo $RST_CLK0_MIN > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq

chmod 644 /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq
echo $RST_CLK6_MAX > /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq
chmod 644 /sys/devices/system/cpu/cpufreq/policy6/scaling_min_freq
echo $RST_CLK6_MIN > /sys/devices/system/cpu/cpufreq/policy6/scaling_min_freq

chmod 644 /sys/devices/system/cpu/bus_dcvs/DDR/boost_freq
echo $RST_DDR > /sys/devices/system/cpu/bus_dcvs/DDR/boost_freq

# ---- Screen on ----
echo 1023 > /sys/class/backlight/panel0-backlight/brightness
echo "[restore] screen on"

# CPU Governor reset: walt
echo walt > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo walt > /sys/devices/system/cpu/cpufreq/policy6/scaling_governor
echo "CPU Governor reset (policy0): $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
echo "CPU Governor reset (policy6): $(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_governor)"

echo "[inference] done."
