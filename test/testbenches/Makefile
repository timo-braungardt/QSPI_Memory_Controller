SRC_PATH=./memory_model_test
TESTBENCH_NAME?=caching_tb_write

all: simulate

sv_compile:
	xvlog -sv $(SRC_PATH)/*

prepare_mem:
	cp ../memory_models/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en/s25hl512tRel/s25hl512tOTP.mem .

elaborate: sv_compile prepare_mem
	xelab -debug typical -top $(TESTBENCH_NAME) -snapshot $(TESTBENCH_NAME)_snapshot

simulate: elaborate
	xsim $(TESTBENCH_NAME)_snapshot -R 

simulate_dump: elaborate
	xsim $(TESTBENCH_NAME)_snapshot -tclbatch Makefile_cfg_xsim.tcl
	xsim --gui $(TESTBENCH_NAME)_snapshot.wdb


clean:
	find . -type f ! -name 'Makefile*' -execdir rm {} +
	rm -rf xsim.dir
