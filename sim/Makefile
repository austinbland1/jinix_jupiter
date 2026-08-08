#=============================================================================
#  sim/Makefile — Deterministic smoke test for jupiter_core (Milestone 1A)
#
#  Simulator: Icarus Verilog (iverilog + vvp) only for this milestone.
#  The previous Verilator fallback has been removed because the SystemVerilog
#  testbench uses timed constructs that have not been verified with Verilator.
#
#  All paths are relative to sim/ because this Makefile lives in sim/.
#=============================================================================

SRCS = ../rtl/jupiter_core.sv \
       jupiter_core_tb.sv

.PHONY: test clean

#--- Default rule — compile + run with Icarus ----------------------------
test:
	iverilog -g2012 -o jupiter_core.vvp $(SRCS)
	vvp -n jupiter_core.vvp

#--- Cleanup ----------------------------------------------------------
clean:
	rm -f jupiter_core.vvp
