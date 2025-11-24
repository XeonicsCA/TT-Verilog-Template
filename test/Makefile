# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = alu_pkg.sv rx_module_4b.sv decode_module_4b.sv alu_module_4b.sv tx_module_4b.sv mau_top_4b.sv
.DEFAULT_GOAL := test-top-4b

# Auto-enable Verilator waves unless explicitly disabled
VERILATOR_WAVES ?= 1
ifeq ($(SIM),verilator)
ifeq ($(VERILATOR_WAVES),1)
EXTRA_ARGS += --timing --trace --trace-structs # --trace-fst
endif
endif

# Unique run stamp
TIMESTAMP ?= $(shell date +%Y%m%d_%H%M%S)

# Ensure the per-test wave folder exists before sim starts
sim: | $(WAVES_DIR)
$(WAVES_DIR):
	@mkdir -p "$(WAVES_DIR)"

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# tests
# add additional src files as required
.PHONY: test-rx test-rx-4b test-decode test-decode-4b test-alu test-alu-4b test-tx test-tx-4b test-top test-top-4b

test-rx:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_rx \
		TOPLEVEL=rx_tb \
		VERILOG_SOURCES="./rx_module/rx_tb.sv ../src/rx_module.sv" \
		PYTHONPATH=$(PWD)/rx_module \
		WAVES_DIR=$(PWD)/rx_module/wave \
		TRACEFILE=$(WAVES_DIR)/$(TOPLEVEL)_$(TIMESTAMP).fst \
		COMPILE_ARGS='$(COMPILE_ARGS) -DVCD_PATH="\"$(PWD)/rx_module/wave/rx_module_$(TIMESTAMP).vcd\""'

test-rx-4b:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_rx_4b \
		TOPLEVEL=rx_tb_4b \
		VERILOG_SOURCES="./rx_module/rx_tb_4b.sv ../src/rx_module_4b.sv" \
		PYTHONPATH=$(PWD)/rx_module \
		WAVES_DIR=$(PWD)/rx_module/wave \
		TRACEFILE=$(WAVES_DIR)/$(TOPLEVEL)_$(TIMESTAMP).fst \
		COMPILE_ARGS='$(COMPILE_ARGS) -DVCD_PATH="\"$(PWD)/rx_module/wave/rx_module_4b_$(TIMESTAMP).vcd\""'

test-tx:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_tx \
		TOPLEVEL=tx_tb \
		VERILOG_SOURCES="./tx_module/tx_tb.sv ../src/tx_module.sv" \
		PYTHONPATH=$(PWD)/tx_module \
		WAVES_DIR=$(PWD)/tx_module/wave \
		TRACEFILE=$(WAVES_DIR)/$(TOPLEVEL)_$(TIMESTAMP).fst \
		COMPILE_ARGS='$(COMPILE_ARGS) -DVCD_PATH="\"$(PWD)/tx_module/wave/tx_module_$(TIMESTAMP).vcd\""'

test-tx-4b:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_tx_4b \
		TOPLEVEL=tx_tb_4b \
		VERILOG_SOURCES="./tx_module/tx_tb_4b.sv ../src/tx_module_4b.sv" \
		PYTHONPATH=$(PWD)/tx_module \
		WAVES_DIR=$(PWD)/tx_module/wave \
		TRACEFILE=$(WAVES_DIR)/$(TOPLEVEL)_$(TIMESTAMP).fst \
		COMPILE_ARGS='$(COMPILE_ARGS) -DVCD_PATH="\"$(PWD)/tx_module/wave/tx_module_4b_$(TIMESTAMP).vcd\""'

test-alu-4b:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_alu_4b \
		TOPLEVEL=alu_tb_4b \
		VERILOG_SOURCES="../src/alu_pkg.sv ./alu_module/alu_tb_4b.sv ../src/alu_module_4b.sv" \
		PYTHONPATH=$(PWD)/alu_module \
		WAVES_DIR=$(PWD)/alu_module/wave \
		TRACEFILE=$(WAVES_DIR)/$(TOPLEVEL)_$(TIMESTAMP).fst \
		COMPILE_ARGS='$(COMPILE_ARGS) -DVCD_PATH="\"$(PWD)/alu_module/wave/alu_module_4b$(TIMESTAMP).vcd\""'

test-decode:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_decode \
		TOPLEVEL=decode_tb \
		VERILOG_SOURCES="../src/alu_pkg.sv ./decode_module/decode_tb.sv ../src/decode_module.sv" \
		PYTHONPATH=$(PWD)/decode_module \
		WAVES_DIR=$(PWD)/decode_module/wave \
		TRACEFILE=$(WAVES_DIR)/$(TOPLEVEL)_$(TIMESTAMP).fst \
		COMPILE_ARGS='$(COMPILE_ARGS) -DVCD_PATH="\"$(PWD)/decode_module/wave/decode_module_$(TIMESTAMP).vcd\""'

test-decode-4b:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_decode_4b \
		TOPLEVEL=decode_tb_4b \
		VERILOG_SOURCES="../src/alu_pkg.sv ./decode_module/decode_tb_4b.sv ../src/decode_module_4b.sv" \
		PYTHONPATH=$(PWD)/decode_module \
		WAVES_DIR=$(PWD)/decode_module/wave \
		TRACEFILE=$(WAVES_DIR)/$(TOPLEVEL)_$(TIMESTAMP).fst \
		COMPILE_ARGS='$(COMPILE_ARGS) -DVCD_PATH="\"$(PWD)/decode_module/wave/decode_module_4b_$(TIMESTAMP).vcd\""'

test-top:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_mau_top \
		TOPLEVEL=mau_top_tb \
		VERILOG_SOURCES="./mau_top/mau_top_tb.sv ../src/mau_top.sv" \
		PYTHONPATH=$(PWD)/mau_top \
		WAVES_DIR=$(PWD)/mau_top/wave \
		TRACEFILE=$(WAVES_DIR)/$(TOPLEVEL)_$(TIMESTAMP).fst \
		COMPILE_ARGS='$(COMPILE_ARGS) -DVCD_PATH="\"$(PWD)/mau_top/wave/mau_top_$(TIMESTAMP).vcd\""'

test-top-4b:
	$(MAKE) clean
	$(MAKE) sim \
		MODULE=test_mau_top_4b \
		TOPLEVEL=mau_top_tb_4b \
		VERILOG_SOURCES="../src/alu_pkg.sv ../src/rx_module_4b.sv ../src/decode_module_4b.sv ../src/alu_module_4b.sv ../src/tx_module_4b.sv ./mau_top/mau_top_tb_4b.sv ../src/mau_top_4b.sv"\
		PYTHONPATH=$(PWD)/mau_top \
		WAVES_DIR=$(PWD)/mau_top/wave \
		TRACEFILE=$(WAVES_DIR)/$(TOPLEVEL)_$(TIMESTAMP).fst \
		COMPILE_ARGS='$(COMPILE_ARGS) -DVCD_PATH="\"$(PWD)/mau_top/wave/mau_top_4b_$(TIMESTAMP).vcd\""'

# Phony target for cleaning up
.PHONY: clean
clean::
	rm -rf sim_build* results.xml


.PHONY: all
all: test-rx-4b test-decode-4b test-alu-4b test-tx-4b test-top-4b

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
