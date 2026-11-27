# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = project.v dt_spi.v dt_core.v dt_delay_line.v

ifeq ($(POSTSIM),yes)

# Post-layout simulation with SDF back-annotation (run locally, see 设计说明.md).
# First run postsim_prep.py to make an Icarus-compatible cell library and SDF, then:
#   make POSTSIM=yes NETLIST=<final/pnl/*.pnl.v> CELL_LIB=<patched lib> SDF=<patched sdf>
SIM_BUILD				= sim_build/postsim
CELL_LIB        ?= $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
GATES            = yes
export GATES
export POSTSIM
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DPOSTSIM
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DUNIT_DELAY=\#0
COMPILE_ARGS    += -gspecify
COMPILE_ARGS    += -DSDF_FILE=\"$(SDF)\"
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(CELL_LIB)
VERILOG_SOURCES += $(NETLIST)

else ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
# behavioural models (with placeholder delays) of the sky130 cells used in src/
VERILOG_SOURCES += $(PWD)/sim_cells.v

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

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
