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

set_location_assignment PIN_G21 -to CLOCK_50
set_location_assignment PIN_H2  -to BUTTON0
set_location_assignment PIN_G3  -to BUTTON1
set_location_assignment PIN_F1  -to BUTTON2
set_location_assignment PIN_J1  -to LEDG0
set_location_assignment PIN_J2  -to LEDG1
set_location_assignment PIN_J3  -to LEDG2
set_location_assignment PIN_H1  -to LEDG3
set_location_assignment PIN_F2  -to LEDG4
set_location_assignment PIN_V7  -to TX2_BT
set_location_assignment PIN_U8  -to RX2_BT
set_location_assignment PIN_W17 -to SPEAKER

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
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to TX2_BT
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to RX2_BT
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SPEAKER

set_global_assignment -name FAMILY "Cyclone III"
set_global_assignment -name DEVICE EP3C16F484C6

# On the DE0, unused pins default to a weak-pullup input that leaks just
# enough current through LED series resistors to glow dimly. This setting
# (identified in the course de0_pins.tcl) avoids that.
set_global_assignment -name RESERVE_ALL_UNUSED_PINS_WEAK_PULLUP "AS INPUT TRI-STATED"
