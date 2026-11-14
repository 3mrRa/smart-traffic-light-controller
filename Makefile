IVERILOG ?= iverilog
VVP      ?= vvp
FLAGS    := -g2012 -Wall
BUILD    := build

RTL      := rtl/traffic_ctrl.v rtl/traffic_ctrl_ref.v
TB       := tb/traffic_checker.v tb/traffic_ctrl_tb.v
TOP_SRC  := rtl/traffic_ctrl.v rtl/traffic_top.v tb/traffic_checker.v tb/traffic_top_tb.v

SEED     ?= 1
CYCLES   ?= 20000

.PHONY: all test sim top seeds wave synth clean

all: test

test: sim top

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/traffic_sim: $(RTL) $(TB) | $(BUILD)
	$(IVERILOG) $(FLAGS) -o $@ $(RTL) $(TB)

$(BUILD)/top_sim: $(TOP_SRC) | $(BUILD)
	$(IVERILOG) $(FLAGS) -o $@ $(TOP_SRC)

# Main regression (writes build/traffic_ctrl.vcd)
sim: $(BUILD)/traffic_sim
	cd $(BUILD) && $(VVP) -n traffic_sim +seed=$(SEED) +cycles=$(CYCLES)

# Board wrapper smoke test
top: $(BUILD)/top_sim
	cd $(BUILD) && $(VVP) -n top_sim

# Several random seeds, longer runs
seeds: $(BUILD)/traffic_sim
	@for s in 1 7 42 1234 99991; do \
	  echo "== seed $$s"; \
	  (cd $(BUILD) && $(VVP) -n traffic_sim +novcd +seed=$$s +cycles=50000) | grep -E "^(PASS|FAIL)" || exit 1; \
	done

wave: sim
	gtkwave $(BUILD)/traffic_ctrl.vcd

# Generic synthesis check with Yosys
synth:
	yosys -q -p "read_verilog rtl/traffic_ctrl.v rtl/traffic_top.v; synth -top traffic_top; stat"

clean:
	rm -rf $(BUILD)
