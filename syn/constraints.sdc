# syn/constraints.sdc — stage 1 (kh_jtag_top = jtag_tap only). Values from CLAUDE.md §4.
# Units follow gsclib045 Liberty: time ns, capacitance pF.
# Stage 1 has no clk / rst_n ports, so the clk clock, its clock group and the rst_n false path
# from CLAUDE.md §4 are added in stage 3.

create_clock -name tck -period 20.0 [get_ports tck]                 ;# 50 MHz starting point

# Host drives TMS/TDI on the TCK falling edge (IEEE 1149.1-2013 6.1.2.1 NOTE 1) -> budget = half period - 4 ns
set_input_delay  -clock tck -clock_fall 4.0 [get_ports {tms tdi}]   ;# decisions.md D-002

# TDO/tdo_oe launched by negedge flops, captured by the host on the next rising edge -> half-period path
set_output_delay -clock tck 4.0 [get_ports {tdo tdo_oe}]

# Asynchronous TRST*: release only with TCK stopped or TMS = 1 (decisions.md D-001)
set_false_path -from [get_ports trst_n]

set_load 0.01 [all_outputs]                                         ;# 0.01 pF = 10 fF
