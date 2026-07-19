vsim work.tb_event_table_manager
add wave clk
add wave auto_release_req
add wave auto_release_instance_id
add wave release_req
add wave release_done
add wave table_used
add wave table_changed
add wave alloc_done
run -all
