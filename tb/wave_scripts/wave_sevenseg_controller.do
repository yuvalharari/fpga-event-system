vsim work.tb_sevenseg_controller
add wave clk
add wave active_valid
add wave event_start_pulse
add wave sw9
add wave active_priority
add wave active_instance_id
add wave dut/seconds_left
add wave -radix binary hex0
add wave -radix binary hex1
add wave -radix binary hex2
add wave -radix binary hex3
run -all
