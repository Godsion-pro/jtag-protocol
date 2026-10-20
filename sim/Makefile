# sim/Makefile — Verilator builds of simulation targets (run inside WSL).
#   make -C sim rbb_tap   -> sim/obj_dir/Vrbb_tap : jtag_tap + OpenOCD remote_bitbang server (stage 1)

VERILATOR ?= verilator
RTL       := ../rtl
OBJ       := obj_dir

.PHONY: rbb_tap clean

rbb_tap: $(OBJ)/Vrbb_tap

$(OBJ)/Vrbb_tap: $(RTL)/jtag_tap.v rbb_server.h rbb_server.cpp main_tap.cpp
	$(VERILATOR) --cc --exe --build -Wall -I$(RTL) --top-module jtag_tap --prefix Vrbb_tap \
		-CFLAGS -I$(CURDIR) -Mdir $(OBJ) -o Vrbb_tap \
		$(RTL)/jtag_tap.v rbb_server.cpp main_tap.cpp

clean:
	rm -rf $(OBJ)
