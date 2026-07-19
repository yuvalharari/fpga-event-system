vsim work.tb_priority_scheduler
add wave clk
add wave reschedule
add wave active_valid
add wave active_index
add wave start_pulse
add wave timeout_pulse
add wave dut/duration_count
add wave dut/timed_out_latched
run -all
