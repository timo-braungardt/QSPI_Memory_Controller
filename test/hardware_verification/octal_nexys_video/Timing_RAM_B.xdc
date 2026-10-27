##############################################################################
# psram_timing.xdc
# Timing constraints for the OctalSPI controller (OctalSPI.v) talking to the
# AP Memory APS12808L-3OBMx OPI Xccela PSRAM (datasheet Rev 1.5, -7 grade).
#
# Add this file next to the Nexys Video board XDC. That file must create
# sys_clk_pin (100 MHz on port clk) and keeps the pin locations / IOSTANDARDs.
# If Vivado reports "clock sys_clk_pin not found", set this file to
# PROCESSING_ORDER = LATE.
#
# How the interface behaves (from OctalSPI.v):
#   * Bus clock = sys_clk / 2 = 50 MHz, from a negedge FF (bus_clock_p2_reg).
#     It toggles on sys_clk FALLING edges.
#   * Write: data/DM/CE# launch on sys_clk RISING edges, the PSRAM samples on
#     both bus clock edges -> data is centre-aligned (about 5 ns each side).
#   * Read: the PSRAM drives DQ edge-aligned to its own output strobe. The
#     controller ignores DQS and samples DQ with sys_clk.
##############################################################################


##############################################################################
# 1. Parameters
##############################################################################

# --- PSRAM datasheet (Tables 28 / 29, -7 grade) [ns] ---
set psram_tDS        1.1   ;# DQ/DM setup to CLK edge (write)
set psram_tDH        1.1   ;# DQ/DM hold from CLK edge (write)
set psram_tCSP       2.5   ;# CE# setup to CLK rising edge
set psram_tCHD       2.5   ;# CE# hold from CLK falling edge
set psram_tDQSCK_min 2.0   ;# CLK edge -> DQS edge (read)
set psram_tDQSCK_max 5.5
set psram_tDQSQ      0.6   ;# DQS -> DQ skew (read)

# --- Board delays between FPGA pin and PSRAM ball [ns] ---
# TODO: replace with your real values (rule of thumb: ~0.17 ns per inch of trace,
# add the FMC connector / cable / breakout board). Min and max cover tolerance.
set pcb_clk_min 0.92   ;# FPGA o_spi_bus_clock -> PSRAM CLK
set pcb_clk_max 0.99
set pcb_dq_min  0.44   ;# DQ / DM / CE# traces (same length assumed both ways)
set pcb_dq_max  0.69


##############################################################################
# 2. Bus clock (forwarded clock)
##############################################################################

# The register that drives o_spi_bus_clock. Check in the synthesized design:
#   llength [get_cells -hier -filter {NAME =~ *SPI_Transmitter/bus_clock_p2_reg_reg}]  -> must be 1

# Divide-by-2, rising edge on the sys_clk FALLING edge:
# sys_clk edges: 1=rise, 2=fall, 3=rise, 4=fall, 5=rise, 6=fall
# bus clock rises on edge 2, falls on edge 4, rises again on edge 6.
create_generated_clock -name bus_clk -source [get_pins -of_objects [get_cells -hier -filter {NAME =~ *SPI_Transmitter/bus_clock_p2_reg_reg}] -filter {REF_PIN_NAME == C}] -divide_by 2 [get_ports o_spi_bus_clock]


##############################################################################
# 3. Keep the pad registers in the IOBs for stable, short pin delays
#    (Vivado warns for every register it cannot pack)
##############################################################################
#set_property IOB TRUE [get_ports {io_spi_b_data[*]}]
#set_property IOB TRUE [get_ports io_spi_b_data_strobe]
#set_property IOB TRUE [get_ports o_spi_b_chipselect_neg]


##############################################################################
# 4. Write path: FPGA -> PSRAM (DQ, DM on io_spi_b_data_strobe, CE#)
#    The PSRAM samples DQ/DM on BOTH clock edges (DDR), so constrain both.
#    max = setup requirement + data trace (max) - clock trace (min)
#    min = data trace (min) - clock trace (max) - hold requirement
##############################################################################
set out_max [expr {$psram_tDS + $pcb_dq_max - $pcb_clk_min}]
set out_min [expr {$pcb_dq_min - $pcb_clk_max - $psram_tDH}]

set dq_out_ports [get_ports {io_spi_b_data[*] io_spi_b_data_strobe}]

set_output_delay -clock bus_clk -max $out_max $dq_out_ports
set_output_delay -clock bus_clk -min $out_min $dq_out_ports
set_output_delay -clock bus_clk -clock_fall -max $out_max -add_delay $dq_out_ports
set_output_delay -clock bus_clk -clock_fall -min $out_min -add_delay $dq_out_ports

# CE#: setup to the rising edge (tCSP), hold from the falling edge (tCHD)
set ce_max [expr {$psram_tCSP + $pcb_dq_max - $pcb_clk_min}]
set ce_min [expr {$pcb_dq_min - $pcb_clk_max - $psram_tCHD}]

set_output_delay -clock bus_clk -max $ce_max [get_ports o_spi_b_chipselect_neg]
set_output_delay -clock bus_clk -clock_fall -min $ce_min -add_delay [get_ports o_spi_b_chipselect_neg]


##############################################################################
# 5. Read path: PSRAM -> FPGA (DQ)
#    DQ is edge-aligned to the PSRAM output strobe, which follows its CLK by
#    tDQSCK (2..5.5 ns). DQ settles tDQSQ after the strobe edge.
#    Rev 1.5 of the datasheet has no output hold (tQH), so DQ is assumed to
#    start changing as early as tDQSQ before the strobe edge.
#    Round trip = clock trace (FPGA -> PSRAM) + data trace (PSRAM -> FPGA).
#    The delay from sys_clk to the pin (FF clk->Q + OBUF) is added by Vivado
#    automatically as latency of the generated clock.
##############################################################################
set in_max [expr {$psram_tDQSCK_max + $psram_tDQSQ + $pcb_clk_max + $pcb_dq_max}]
set in_min [expr {$psram_tDQSCK_min - $psram_tDQSQ + $pcb_clk_min + $pcb_dq_min}]

set dq_in_ports [get_ports {io_spi_b_data[*]}]

set_input_delay -clock bus_clk -max $in_max $dq_in_ports
set_input_delay -clock bus_clk -min $in_min $dq_in_ports
set_input_delay -clock bus_clk -clock_fall -max $in_max -add_delay $dq_in_ports
set_input_delay -clock bus_clk -clock_fall -min $in_min -add_delay $dq_in_ports

# The read data needs more than one sys_clk cycle to come back (clock to pin,
# tDQSCK, trace, input buffer), so DQ launched by a bus clock edge is captured
# by the SECOND following sys_clk rising edge instead of the first one.
# Setup only: new data arrives every cycle, so the hold check must NOT be moved.
# Verify with report_timing; use 3 if the data arrives later than ~2 cycles.
#set_multicycle_path 2 -setup -from [get_clocks bus_clk] -to [get_clocks sys_clk_pin]


##############################################################################
# 6. Paths that are intentionally not timed
##############################################################################

# DQS is not used for read capture (only sampled into a debug register).
# Remove this line if you start using DQS in the controller.
set_false_path -from [get_ports io_spi_b_data_strobe]

# RESET# is static, the PSRAM has no differential clock.
set_false_path -to [get_ports {o_spi_reset_neg o_spi_bus_clock_neg}]