# Pin assignments for event_system_top - hardware bring-up milestones
# (BUTTON0/BUTTON2 -> system_master_ctrl -> LEDG0 ; TX2_BT/RX2_BT -> command chain)
#
# Run from the Quartus Tcl Console (View > Utility Windows > Tcl Console)
# with the project already open, or via:
#   quartus_sh -t top_pins.tcl
#
# Pin locations confirmed against 3 independent sources: the DE0 schematic,
# the course de0_pins.tcl, and the official Terasic DE0 User Manual v1.1.
# TX2_BT/RX2_BT (the Add-On board's HC-06 Bluetooth UART channel) confirmed
# via the course de0_pins.tcl's "AddOn card placed on JP1" section - the
# command chain was moved here from TX1/RX1 (FTDI/PC debug) in Milestone 8,
# so testing can be driven from an Android Bluetooth serial terminal app.
#
# HEX0-3: the course de0_pins.tcl labels each pin as HEX<n>S[0..6], with
# [0]=g,[1]=f,[2]=e,[3]=d,[4]=c,[5]=b,[6]=a - the OPPOSITE bit order from
# this project's own HEX0-3(6 downto 0) ports, where (per
# sevenseg_controller.vhd's segment encoding) bit 6=g ... bit 0=a. So each
# bit is mapped individually below (bit 6 -> the pin labeled g, bit 0 -> the
# pin labeled a), not just copied 1:1 by index.

set_location_assignment PIN_G21 -to CLOCK_50
set_location_assignment PIN_H2  -to BUTTON0
set_location_assignment PIN_G3  -to BUTTON1
set_location_assignment PIN_F1  -to BUTTON2
set_location_assignment PIN_J1  -to LEDG0
set_location_assignment PIN_J2  -to LEDG1
set_location_assignment PIN_J3  -to LEDG2
set_location_assignment PIN_H1  -to LEDG3
set_location_assignment PIN_F2  -to LEDG4
set_location_assignment PIN_E1  -to LEDG5
set_location_assignment PIN_C1  -to LEDG6
set_location_assignment PIN_C2  -to LEDG7
set_location_assignment PIN_B2  -to LEDG8
set_location_assignment PIN_B1  -to LEDG9
set_location_assignment PIN_V7  -to TX2_BT
set_location_assignment PIN_U8  -to RX2_BT
set_location_assignment PIN_W17 -to SPEAKER
set_location_assignment PIN_D2  -to SW9

set_location_assignment PIN_F13 -to HEX0[6] ;# g
set_location_assignment PIN_F12 -to HEX0[5] ;# f
set_location_assignment PIN_G12 -to HEX0[4] ;# e
set_location_assignment PIN_H13 -to HEX0[3] ;# d
set_location_assignment PIN_H12 -to HEX0[2] ;# c
set_location_assignment PIN_F11 -to HEX0[1] ;# b
set_location_assignment PIN_E11 -to HEX0[0] ;# a

set_location_assignment PIN_A15 -to HEX1[6] ;# g
set_location_assignment PIN_E14 -to HEX1[5] ;# f
set_location_assignment PIN_B14 -to HEX1[4] ;# e
set_location_assignment PIN_A14 -to HEX1[3] ;# d
set_location_assignment PIN_C13 -to HEX1[2] ;# c
set_location_assignment PIN_B13 -to HEX1[1] ;# b
set_location_assignment PIN_A13 -to HEX1[0] ;# a

set_location_assignment PIN_F14 -to HEX2[6] ;# g
set_location_assignment PIN_B17 -to HEX2[5] ;# f
set_location_assignment PIN_A17 -to HEX2[4] ;# e
set_location_assignment PIN_E15 -to HEX2[3] ;# d
set_location_assignment PIN_B16 -to HEX2[2] ;# c
set_location_assignment PIN_A16 -to HEX2[1] ;# b
set_location_assignment PIN_D15 -to HEX2[0] ;# a

set_location_assignment PIN_G15 -to HEX3[6] ;# g
set_location_assignment PIN_D19 -to HEX3[5] ;# f
set_location_assignment PIN_C19 -to HEX3[4] ;# e
set_location_assignment PIN_B19 -to HEX3[3] ;# d
set_location_assignment PIN_A19 -to HEX3[2] ;# c
set_location_assignment PIN_F15 -to HEX3[1] ;# b
set_location_assignment PIN_B18 -to HEX3[0] ;# a

# DE0 supplies 3.3V to these I/O banks (schematic + DE0 User Manual) -
# override Quartus's generic "2.5V (default)" I/O standard to match.
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to BUTTON0
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to BUTTON1
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to BUTTON2
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG0
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG1
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG2
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG3
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG4
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG5
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG6
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG7
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG8
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDG9
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to TX2_BT
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to RX2_BT
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SPEAKER
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW9
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX0
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX1
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX2
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX3

set_global_assignment -name FAMILY "Cyclone III"
set_global_assignment -name DEVICE EP3C16F484C6

# On the DE0, unused pins default to a weak-pullup input that leaks just
# enough current through LED series resistors to glow dimly. This setting
# (identified in the course de0_pins.tcl) avoids that.
set_global_assignment -name RESERVE_ALL_UNUSED_PINS_WEAK_PULLUP "AS INPUT TRI-STATED"
