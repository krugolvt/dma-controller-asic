#!/usr/bin/env bash
# Lint + regression for the DMA controller.
#   Icarus Verilog : existing directed FIFO testbenches (4-state)
#   Verilator      : lint, clock-gating directed test with SVA
#   UVM testbenches: need a UVM-capable simulator; run if UVM_HOME is set.
set -u
cd "$(dirname "$0")"

BUILD=sim_build
mkdir -p "$BUILD"

RTL="rtl/dma_top.sv rtl/icg_cell.sv rtl/pulse_sync.sv axi4_lite.sv
     async_fifo.sv dma_fsm_wr.sv dma_fsm_rd.sv"

results=()
fails=0

record() {  # name status
    results+=("$(printf '%-24s %s' "$1" "$2")")
    case "$2" in PASS|SKIP*) ;; *) fails=$((fails + 1)) ;; esac
}

# A test passes if it ran, printed the expected marker, and printed no failures.
check_log() {  # name log pass_marker [fail_regex]
    local fail_re=${4:-'FAIL|ERROR|Assertion failed'}
    if grep -q "$3" "$2" && ! grep -qiE "$fail_re" "$2"; then
        record "$1" PASS
    else
        record "$1" FAIL
        sed 's/^/    /' "$2"
    fi
}

echo "== Verilator lint (dma_top, -Wall)"
if verilator --lint-only -Wall lint/verilator.vlt --top-module dma_top $RTL \
        > "$BUILD/lint.log" 2>&1; then
    record lint PASS
else
    record lint FAIL
    cat "$BUILD/lint.log"
fi

run_iverilog() {  # name top files...
    local name=$1 top=$2; shift 2
    echo "== Icarus: $name"
    if iverilog -g2012 -s "$top" -o "$BUILD/$name.vvp" "$@" > "$BUILD/$name.log" 2>&1; then
        (cd "$BUILD" && vvp -n "$name.vvp") >> "$BUILD/$name.log" 2>&1
        check_log "$name" "$BUILD/$name.log" PASS
    else
        record "$name" FAIL
        cat "$BUILD/$name.log"
    fi
}

run_iverilog sync_fifo_tb  sync_fifo_tb  sync_fifo.sv  sync_fifo_tb.sv
run_iverilog async_fifo_tb async_fifo_tb async_fifo.sv async_fifo_tb.sv
# 4-state functional run of the gating test. Icarus can't parse the concurrent
# SVA, so -DSYNTHESIS compiles them out; the Verilator run below checks them.
run_iverilog dma_cg_tb_icarus dma_cg_tb -DSYNTHESIS tb/dma_cg_tb.sv $RTL

echo "== Verilator: dma_cg_tb (clock gating + SVA)"
if verilator --binary --timing --assert -Wno-fatal -Wno-lint -Wno-style \
        --top-module dma_cg_tb --Mdir "$BUILD/dma_cg_tb" -o sim \
        tb/dma_cg_tb.sv $RTL > "$BUILD/dma_cg_tb.build.log" 2>&1; then
    "$BUILD/dma_cg_tb/sim" > "$BUILD/dma_cg_tb.log" 2>&1
    check_log dma_cg_tb "$BUILD/dma_cg_tb.log" "TEST PASSED"
    sed -n "/Gated-cycle report/,/idle time/p" "$BUILD/dma_cg_tb.log"
else
    record dma_cg_tb FAIL
    cat "$BUILD/dma_cg_tb.build.log"
fi

if [ -n "${UVM_HOME:-}" ]; then
    run_uvm() {  # name top files...
        local name=$1 top=$2; shift 2
        echo "== Verilator+UVM: $name"
        if verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
                +incdir+"$UVM_HOME/src" "$UVM_HOME/src/uvm_pkg.sv" \
                --top-module "$top" --Mdir "$BUILD/$name" -o sim \
                "$@" > "$BUILD/$name.build.log" 2>&1; then
            "$BUILD/$name/sim" > "$BUILD/$name.log" 2>&1
            check_log "$name" "$BUILD/$name.log" "UVM_ERROR : *0" \
                'UVM_(ERROR|FATAL) : *[1-9]|%Error'
        else
            record "$name" FAIL
            tail -30 "$BUILD/$name.build.log"
        fi
    }
    run_uvm async_fifo_UVM_tb async_fifo_uvm_tb async_fifo.sv async_fifo_UVM_tb.sv
    run_uvm axi4_uvm_tb       dma_axi_uvm_tb    axi4_lite.sv  axi4_uvm_tb.sv
else
    record async_fifo_UVM_tb "SKIP (set UVM_HOME)"
    record axi4_uvm_tb       "SKIP (set UVM_HOME)"
fi

echo
echo "== Summary"
printf '  %s\n' "${results[@]}"
[ "$fails" -eq 0 ]
