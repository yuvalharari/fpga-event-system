----------------------------------------------------------------
-- event_system_top : top-level entity for the DE0 board.       --
--                                                               --
-- Grows incrementally as more blocks come online (spec section --
-- 23 work plan).                                                --
--                                                               --
-- Milestone 1: BUTTON0/BUTTON2 control the SYSTEM_ON/SYSTEM_OFF --
-- master state, shown live on LEDG0 (spec section 24 acceptance --
-- criteria: "BUTTON0/BUTTON1/BUTTON2 are implemented and         --
-- tested").                                                      --
--                                                               --
-- Milestone 2 (superseded): TX1/RX1 wired to uart_tx/uart_rx     --
-- with a temporary echo test, to confirm the real UART link      --
-- works against a PC terminal.                                  --
--                                                               --
-- Milestone 3: the temporary echo test is replaced by the real  --
-- command chain - uart_rx -> RX sync_fifo -> line_receiver ->   --
-- text_command_parser -> command_dispatcher -> response_builder --
-- -> response_sender -> uart_tx - proving a real ASCII command   --
-- (e.g. "EVT,01,03") gets a real ACK/NACK response back over the --
-- same UART link (spec section 23, days 4-6 target: "STATUS     --
-- ו-ACK/NACK בסיסי דרך בלוטוס'").                                 --
--                                                               --
-- Milestone 4: event_table_manager wired in - EVT commands now  --
-- get a REAL instance_id from a real allocation, instead of      --
-- command_dispatcher's old source_id placeholder. Adds the       --
-- NACK,UNKNOWN_EVENT / NACK,TABLE_FULL response paths (spec      --
-- section 16, error codes 03/04).                                --
--                                                               --
-- Milestone 5: ACK commands now go through a real slot release   --
-- (event_table_manager's release_req/release_done, the spec's    --
-- ack_manager role) instead of blindly echoing instance_id -     --
-- the table actually empties out as instances get acknowledged.  --
-- Adds NACK,UNKNOWN_INSTANCE (project-defined, not in the spec's --
-- error table) for an ACK naming an instance that isn't          --
-- currently occupying any slot.                                  --
--                                                               --
-- Milestone 6: BUTTON1 full_reset wired in (spec section 14.2.1) --
-- - a debounced BUTTON1 pulse clears the entire event table in   --
-- one clock, without touching SYSTEM_ON/OFF or the instance_id   --
-- counter.                                                        --
--                                                               --
-- Milestone 7 (superseded by Milestone 10): priority_scheduler     --
-- wired in (spec section 8.2/23 days 10-12 target: "הדגמת מתזמן   --
-- מבוססת-LED בלבד"). event_table_manager's table_changed drives    --
-- its reschedule input directly (guaranteed-fresh table data, see  --
-- event_table_manager's header). The original LEDG1=active/        --
-- LEDG2-4=binary-index demo was replaced by the chase animation    --
-- in Milestone 10.                                                 --
--                                                               --
-- Milestone 8: switched the command-chain UART from TX1/RX1 (the --
-- Add-On's PC/FTDI debug channel) to TX2_BT/RX2_BT (the Add-On's --
-- HC-06 Bluetooth channel) - same uart_rx/uart_tx, same 9600     --
-- baud default, just different physical pins, so testing can be  --
-- driven from an Android Bluetooth serial terminal app instead   --
-- of comsh. No RTL logic changed, only the pin-facing port names --
-- and top_pins.tcl. (iOS was ruled out - HC-06 is Bluetooth       --
-- Classic/SPP, which iOS does not expose to third-party apps      --
-- without MFi certification.)                                    --
--                                                               --
-- Milestone 9: buzzer_controller wired in (project's own reduced --
-- design, NOT the spec's per-event-type BUZZER_PATTERN opcode -   --
-- see project memory "final product vision"). Exactly two        --
-- triggers, both a short beep: system_enable's rising edge, and   --
-- table_not_empty's rising edge (the first event entering an      --
-- otherwise-empty event_table_manager table). table_not_empty is --
-- just an OR-reduction of event_table_manager's table_used.       --
--                                                               --
-- Milestone 10: led_pattern_controller wired in, replacing the   --
-- Milestone 7 binary-index LED demo. LEDG1-LEDG9 (LEDG0 stays     --
-- SYSTEM_ON) now show a chase/marquee animation that runs         --
-- whenever priority_scheduler has an active event, with speed      --
-- scaling by that event's priority (project's own reduced design, --
-- NOT the spec's LED0-7 meaning table - see project memory        --
-- "final product vision"). active_priority is looked up from       --
-- event_table_manager's table_priority using the scheduler's       --
-- active_index.                                                    --
--                                                               --
-- Milestone 11: active-duration timeout wired in (project-specific --
-- addition, see priority_scheduler's own header for the full        --
-- reasoning). Every active event now gets a fixed 5-second budget    --
-- (active_duration_cycles=250,000,000 @ 50MHz) before                --
-- priority_scheduler's timeout_pulse auto-releases it from           --
-- event_table_manager via the NEW, independent auto_release_req/     --
-- auto_release_instance_id path (deliberately not the manual         --
-- release_req/ACK path, to avoid confusing command_dispatcher's      --
-- own ACK handshake). table_changed then naturally brings the        --
-- scheduler back around to the next queued event, or idle if none    --
-- remain - no other logic needed to change.                          --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;
use work.event_system_pkg.all ;

entity event_system_top is
   port ( CLOCK_50 : in  std_logic ;
          BUTTON0  : in  std_logic ; -- active-low, System ON
          BUTTON1  : in  std_logic ; -- active-low, full event-table reset
          BUTTON2  : in  std_logic ; -- active-low, System OFF
          LEDG0    : out std_logic ; -- lit when SYSTEM_ON
          LEDG1    : out std_logic ; -- chase animation, positions 0-8
          LEDG2    : out std_logic ;
          LEDG3    : out std_logic ;
          LEDG4    : out std_logic ;
          LEDG5    : out std_logic ;
          LEDG6    : out std_logic ;
          LEDG7    : out std_logic ;
          LEDG8    : out std_logic ;
          LEDG9    : out std_logic ;
          RX2_BT   : in  std_logic ; -- Add-On board HC-06 Bluetooth UART, FPGA receive
          TX2_BT   : out std_logic ; -- Add-On board HC-06 Bluetooth UART, FPGA transmit
          SPEAKER  : out std_logic ) ; -- Add-On board passive piezo buzzer
end event_system_top ;

architecture arc_event_system_top of event_system_top is

   component reset_controller
      generic ( hold_cycles : positive := 16 ) ;
      port ( clk    : in  std_logic ;
             resetN : out std_logic ) ;
   end component ;

   component button_pulse
      generic ( clk_freq           : integer := 50_000_000 ;
                max_bounce_time_ms : integer := 10          ) ;
      port ( resetN   : in  std_logic ;
             clk      : in  std_logic ;
             button_n : in  std_logic ;
             pulse    : out std_logic ) ;
   end component ;

   component system_master_ctrl
      port ( resetN          : in  std_logic ;
             clk             : in  std_logic ;
             button0_pulse_i : in  std_logic ;
             button2_pulse_i : in  std_logic ;
             system_enable_o : out std_logic ) ;
   end component ;

   component uart_rx
      generic ( clk_hz    : integer := 50_000_000 ;
                baud_rate : integer := 9600        ) ;
      port ( resetN     : in  std_logic                     ;
             clk        : in  std_logic                     ;
             rx         : in  std_logic                     ;
             read_dout  : in  std_logic                     ;
             data_valid : out std_logic                     ;
             dout       : out std_logic_vector(7 downto 0)  ;
             dout_ready : out std_logic                      ) ;
   end component ;

   component uart_tx
      generic ( clk_hz    : integer := 50_000_000 ;
                baud_rate : integer := 9600        ) ;
      port ( resetN    : in  std_logic                    ;
             clk       : in  std_logic                    ;
             din       : in  std_logic_vector(7 downto 0) ;
             write_din : in  std_logic                    ;
             tx        : out std_logic                    ;
             tx_ready  : out std_logic                    ) ;
   end component ;

   component sync_fifo
      generic ( data_width : positive := 8  ;
                depth      : positive := 16 ) ;
      port ( resetN   : in  std_logic                               ;
             clk      : in  std_logic                               ;
             wr_en    : in  std_logic                               ;
             wr_data  : in  std_logic_vector(data_width-1 downto 0) ;
             rd_en    : in  std_logic                               ;
             rd_data  : out std_logic_vector(data_width-1 downto 0) ;
             full     : out std_logic                               ;
             empty    : out std_logic                               ;
             overflow : out std_logic                               ) ;
   end component ;

   component line_receiver
      generic ( max_line_length : positive := 32 ) ;
      port ( resetN       : in  std_logic                                      ;
             clk          : in  std_logic                                      ;
             fifo_empty   : in  std_logic                                      ;
             fifo_rd_data : in  std_logic_vector(7 downto 0)                   ;
             fifo_rd_en   : out std_logic                                      ;
             line_data    : out std_logic_vector(max_line_length*8-1 downto 0) ;
             line_length  : out std_logic_vector(7 downto 0)                   ;
             line_ready   : out std_logic                                      ;
             line_error   : out std_logic                                       ) ;
   end component ;

   component text_command_parser
      generic ( max_line_length : positive := 32 ) ;
      port ( resetN      : in  std_logic                                      ;
             clk         : in  std_logic                                      ;
             line_data   : in  std_logic_vector(max_line_length*8-1 downto 0) ;
             line_length : in  std_logic_vector(7 downto 0)                   ;
             line_ready  : in  std_logic                                      ;
             cmd_valid   : out std_logic                    ;
             cmd_is_evt  : out std_logic                    ;
             cmd_is_ack  : out std_logic                    ;
             event_type  : out std_logic_vector(7 downto 0) ;
             source_id   : out std_logic_vector(7 downto 0) ;
             instance_id : out std_logic_vector(7 downto 0) ;
             cmd_error      : out std_logic                    ;
             cmd_error_code : out std_logic_vector(7 downto 0) ) ;
   end component ;

   component command_dispatcher
      port ( resetN      : in  std_logic                    ;
             clk         : in  std_logic                    ;
             cmd_valid      : in  std_logic                    ;
             cmd_is_evt     : in  std_logic                    ;
             cmd_is_ack     : in  std_logic                    ;
             event_type     : in  std_logic_vector(7 downto 0) ;
             source_id      : in  std_logic_vector(7 downto 0) ;
             instance_id    : in  std_logic_vector(7 downto 0) ;
             cmd_error      : in  std_logic                    ;
             cmd_error_code : in  std_logic_vector(7 downto 0) ;
             alloc_req          : out std_logic                    ;
             alloc_event_type   : out std_logic_vector(7 downto 0) ;
             alloc_source_id    : out std_logic_vector(7 downto 0) ;
             alloc_done         : in  std_logic                    ;
             alloc_ok           : in  std_logic                    ;
             alloc_unknown_type : in  std_logic                    ;
             alloc_instance_id  : in  std_logic_vector(7 downto 0) ;
             release_req          : out std_logic                    ;
             release_instance_id  : out std_logic_vector(7 downto 0) ;
             release_done         : in  std_logic                    ;
             release_ok           : in  std_logic                    ;
             build_ack               : out std_logic                    ;
             build_nack_bad_format   : out std_logic                    ;
             build_nack_unknown      : out std_logic                    ;
             build_nack_unknown_evt  : out std_logic                    ;
             build_nack_table_full   : out std_logic                    ;
             build_nack_unknown_inst : out std_logic                    ;
             param_byte              : out std_logic_vector(7 downto 0) ) ;
   end component ;

   component event_table_manager
      generic ( event_slots : positive := 8 ) ;
      port ( resetN             : in  std_logic                    ;
             clk                : in  std_logic                    ;
             full_reset         : in  std_logic                    ;
             alloc_req          : in  std_logic                    ;
             event_type         : in  std_logic_vector(7 downto 0) ;
             source_id          : in  std_logic_vector(7 downto 0) ;
             alloc_done         : out std_logic                    ;
             alloc_ok           : out std_logic                    ;
             alloc_unknown_type : out std_logic                    ;
             alloc_instance_id  : out std_logic_vector(7 downto 0) ;
             alloc_priority     : out std_logic_vector(2 downto 0) ;
             alloc_requires_ack : out std_logic                    ;
             release_req         : in  std_logic                    ;
             release_instance_id : in  std_logic_vector(7 downto 0) ;
             release_done        : out std_logic                    ;
             release_ok          : out std_logic                    ;
             auto_release_req         : in  std_logic                    ;
             auto_release_instance_id : in  std_logic_vector(7 downto 0) ;
             table_used         : out std_logic_vector(0 to event_slots - 1)         ;
             table_priority     : out priority_array_t(0 to event_slots - 1)         ;
             table_instance_id  : out instance_id_array_t(0 to event_slots - 1)      ;
             table_changed      : out std_logic                                       ) ;
   end component ;

   component priority_scheduler
      generic ( event_slots            : positive := 8           ;
                preempt_threshold      : natural  := 7           ;
                active_duration_cycles : positive := 250_000_000 ) ;
      port ( resetN         : in  std_logic                                     ;
             clk            : in  std_logic                                     ;
             reschedule     : in  std_logic                                     ;
             table_used        : in  std_logic_vector(0 to event_slots - 1)     ;
             table_priority    : in  priority_array_t(0 to event_slots - 1)     ;
             table_instance_id : in  instance_id_array_t(0 to event_slots - 1)  ;
             active_valid   : out std_logic                                     ;
             active_index   : out integer range 0 to event_slots - 1            ;
             start_pulse    : out std_logic                                     ;
             preempt_pulse  : out std_logic                                     ;
             timeout_pulse  : out std_logic                                      ) ;
   end component ;

   component buzzer_controller
      generic ( clk_hz           : integer  := 50_000_000 ;
                beep_duration_cs : positive := 20          ;
                beep_freq_hz     : positive := 2000         ) ;
      port ( resetN          : in  std_logic ;
             clk             : in  std_logic ;
             system_enable   : in  std_logic ;
             table_not_empty : in  std_logic ;
             buzzer_out      : out std_logic ) ;
   end component ;

   component led_pattern_controller
      generic ( num_leds    : positive := 9         ;
                base_cycles : positive := 25_000_000 ) ;
      port ( resetN          : in  std_logic ;
             clk             : in  std_logic ;
             active_valid    : in  std_logic ;
             active_priority : in  std_logic_vector(2 downto 0) ;
             leds            : out std_logic_vector(num_leds - 1 downto 0) ) ;
   end component ;

   component response_builder
      generic ( max_response_length : positive := 32 ) ;
      port ( resetN                 : in  std_logic                                          ;
             clk                    : in  std_logic                                          ;
             build_ack              : in  std_logic                                          ;
             build_nack_bad_format  : in  std_logic                                          ;
             build_nack_unknown     : in  std_logic                                          ;
             build_nack_unknown_evt : in  std_logic                                          ;
             build_nack_table_full  : in  std_logic                                          ;
             build_nack_unknown_inst: in  std_logic                                          ;
             param_byte             : in  std_logic_vector(7 downto 0)                       ;
             resp_data              : out std_logic_vector(max_response_length*8-1 downto 0) ;
             resp_length            : out std_logic_vector(7 downto 0)                       ;
             resp_ready             : out std_logic                                          ) ;
   end component ;

   component response_sender
      generic ( max_response_length : positive := 32 ) ;
      port ( resetN       : in  std_logic                                          ;
             clk          : in  std_logic                                          ;
             resp_data    : in  std_logic_vector(max_response_length*8-1 downto 0) ;
             resp_length  : in  std_logic_vector(7 downto 0)                       ;
             resp_ready   : in  std_logic                                          ;
             tx_din       : out std_logic_vector(7 downto 0)                       ;
             tx_write_din : out std_logic                                          ;
             tx_ready     : in  std_logic                                          ) ;
   end component ;

   signal resetN         : std_logic ;
   signal button0_pulse  : std_logic ;
   signal button1_pulse  : std_logic ;
   signal button2_pulse  : std_logic ;
   signal system_enable  : std_logic ;

   signal rx_dout        : std_logic_vector(7 downto 0) ;
   signal rx_data_valid  : std_logic ;
   signal tx_din         : std_logic_vector(7 downto 0) ;
   signal tx_write_din   : std_logic ;
   signal tx_ready       : std_logic ;

   signal rx_fifo_rd_en   : std_logic ;
   signal rx_fifo_rd_data : std_logic_vector(7 downto 0) ;
   signal rx_fifo_empty   : std_logic ;
   signal rx_fifo_full    : std_logic ;
   signal rx_fifo_overflow: std_logic ;

   signal line_data   : std_logic_vector(32*8-1 downto 0) ;
   signal line_length : std_logic_vector(7 downto 0) ;
   signal line_ready  : std_logic ;
   signal line_error  : std_logic ;

   signal cmd_valid      : std_logic ;
   signal cmd_is_evt     : std_logic ;
   signal cmd_is_ack     : std_logic ;
   signal event_type     : std_logic_vector(7 downto 0) ;
   signal source_id      : std_logic_vector(7 downto 0) ;
   signal instance_id    : std_logic_vector(7 downto 0) ;
   signal cmd_error      : std_logic ;
   signal cmd_error_code : std_logic_vector(7 downto 0) ;

   signal alloc_req          : std_logic ;
   signal alloc_event_type   : std_logic_vector(7 downto 0) ;
   signal alloc_source_id    : std_logic_vector(7 downto 0) ;
   signal alloc_done         : std_logic ;
   signal alloc_ok           : std_logic ;
   signal alloc_unknown_type : std_logic ;
   signal alloc_instance_id  : std_logic_vector(7 downto 0) ;
   signal alloc_priority     : std_logic_vector(2 downto 0) ;
   signal alloc_requires_ack : std_logic ;

   signal release_req         : std_logic ;
   signal release_instance_id : std_logic_vector(7 downto 0) ;
   signal release_done        : std_logic ;
   signal release_ok          : std_logic ;

   signal auto_release_req         : std_logic ;
   signal auto_release_instance_id : std_logic_vector(7 downto 0) ;

   signal table_used        : std_logic_vector(0 to 7) ;
   signal table_priority    : priority_array_t(0 to 7) ;
   signal table_instance_id : instance_id_array_t(0 to 7) ;
   signal table_changed     : std_logic ;
   signal table_not_empty   : std_logic ;

   signal sched_active_valid  : std_logic ;
   signal sched_active_index  : integer range 0 to 7 ;
   signal sched_start_pulse   : std_logic ;
   signal sched_preempt_pulse : std_logic ;
   signal sched_timeout_pulse : std_logic ;

   signal active_priority : std_logic_vector(2 downto 0) ;
   signal leds            : std_logic_vector(8 downto 0) ; -- LEDG1(0) .. LEDG9(8)

   signal build_ack               : std_logic ;
   signal build_nack_bad_format   : std_logic ;
   signal build_nack_unknown      : std_logic ;
   signal build_nack_unknown_evt  : std_logic ;
   signal build_nack_table_full   : std_logic ;
   signal build_nack_unknown_inst : std_logic ;
   signal param_byte              : std_logic_vector(7 downto 0) ;

   signal resp_data   : std_logic_vector(32*8-1 downto 0) ;
   signal resp_length : std_logic_vector(7 downto 0) ;
   signal resp_ready  : std_logic ;

begin

   u_reset : reset_controller
      port map ( clk => CLOCK_50, resetN => resetN ) ;

   u_button0 : button_pulse
      port map ( resetN => resetN, clk => CLOCK_50, button_n => BUTTON0, pulse => button0_pulse ) ;

   u_button1 : button_pulse
      port map ( resetN => resetN, clk => CLOCK_50, button_n => BUTTON1, pulse => button1_pulse ) ;

   u_button2 : button_pulse
      port map ( resetN => resetN, clk => CLOCK_50, button_n => BUTTON2, pulse => button2_pulse ) ;

   u_master : system_master_ctrl
      port map ( resetN          => resetN        ,
                 clk             => CLOCK_50       ,
                 button0_pulse_i => button0_pulse  ,
                 button2_pulse_i => button2_pulse  ,
                 system_enable_o => system_enable  ) ;

   LEDG0 <= system_enable ;

   -----------------------------------------------------------------
   -- command chain: uart_rx -> RX fifo -> line_receiver ->        --
   -- text_command_parser -> command_dispatcher -> response_builder--
   -- -> response_sender -> uart_tx                                --
   -----------------------------------------------------------------

   u_uart_rx : uart_rx
      port map ( resetN     => resetN        ,
                 clk        => CLOCK_50       ,
                 rx         => RX2_BT         ,
                 read_dout  => '0'            , -- unused: data_valid pulse drives the RX fifo directly
                 data_valid => rx_data_valid  ,
                 dout       => rx_dout        ,
                 dout_ready => open           ) ;

   u_rx_fifo : sync_fifo
      generic map ( data_width => 8, depth => 16 )
      port map ( resetN   => resetN         ,
                 clk      => CLOCK_50        ,
                 wr_en    => rx_data_valid   ,
                 wr_data  => rx_dout         ,
                 rd_en    => rx_fifo_rd_en   ,
                 rd_data  => rx_fifo_rd_data ,
                 full     => rx_fifo_full    ,
                 empty    => rx_fifo_empty   ,
                 overflow => rx_fifo_overflow ) ;

   u_line_receiver : line_receiver
      generic map ( max_line_length => 32 )
      port map ( resetN       => resetN          ,
                 clk          => CLOCK_50         ,
                 fifo_empty   => rx_fifo_empty    ,
                 fifo_rd_data => rx_fifo_rd_data  ,
                 fifo_rd_en   => rx_fifo_rd_en    ,
                 line_data    => line_data        ,
                 line_length  => line_length      ,
                 line_ready   => line_ready       ,
                 line_error   => line_error       ) ;

   u_parser : text_command_parser
      generic map ( max_line_length => 32 )
      port map ( resetN      => resetN      ,
                 clk         => CLOCK_50     ,
                 line_data   => line_data    ,
                 line_length => line_length  ,
                 line_ready  => line_ready   ,
                 cmd_valid   => cmd_valid    ,
                 cmd_is_evt  => cmd_is_evt   ,
                 cmd_is_ack  => cmd_is_ack   ,
                 event_type  => event_type   ,
                 source_id   => source_id    ,
                 instance_id => instance_id  ,
                 cmd_error      => cmd_error      ,
                 cmd_error_code => cmd_error_code ) ;

   u_dispatcher : command_dispatcher
      port map ( resetN      => resetN      ,
                 clk         => CLOCK_50     ,
                 cmd_valid      => cmd_valid      ,
                 cmd_is_evt     => cmd_is_evt     ,
                 cmd_is_ack     => cmd_is_ack     ,
                 event_type     => event_type     ,
                 source_id      => source_id      ,
                 instance_id    => instance_id    ,
                 cmd_error      => cmd_error      ,
                 cmd_error_code => cmd_error_code ,
                 alloc_req          => alloc_req          ,
                 alloc_event_type   => alloc_event_type   ,
                 alloc_source_id    => alloc_source_id    ,
                 alloc_done         => alloc_done         ,
                 alloc_ok           => alloc_ok           ,
                 alloc_unknown_type => alloc_unknown_type ,
                 alloc_instance_id  => alloc_instance_id  ,
                 release_req          => release_req          ,
                 release_instance_id  => release_instance_id  ,
                 release_done         => release_done         ,
                 release_ok           => release_ok           ,
                 build_ack               => build_ack               ,
                 build_nack_bad_format   => build_nack_bad_format    ,
                 build_nack_unknown      => build_nack_unknown       ,
                 build_nack_unknown_evt  => build_nack_unknown_evt   ,
                 build_nack_table_full   => build_nack_table_full    ,
                 build_nack_unknown_inst => build_nack_unknown_inst  ,
                 param_byte              => param_byte               ) ;

   u_event_table : event_table_manager
      generic map ( event_slots => 8 )
      port map ( resetN             => resetN             ,
                 clk                => CLOCK_50            ,
                 full_reset         => button1_pulse       ,
                 alloc_req          => alloc_req           ,
                 event_type         => alloc_event_type    ,
                 source_id          => alloc_source_id     ,
                 alloc_done         => alloc_done          ,
                 alloc_ok           => alloc_ok            ,
                 alloc_unknown_type => alloc_unknown_type  ,
                 alloc_instance_id  => alloc_instance_id   ,
                 alloc_priority     => alloc_priority      ,
                 alloc_requires_ack => alloc_requires_ack  ,
                 release_req         => release_req         ,
                 release_instance_id => release_instance_id ,
                 release_done        => release_done        ,
                 release_ok          => release_ok          ,
                 auto_release_req         => auto_release_req         ,
                 auto_release_instance_id => auto_release_instance_id ,
                 table_used         => table_used         ,
                 table_priority     => table_priority     ,
                 table_instance_id  => table_instance_id  ,
                 table_changed      => table_changed      ) ;

   u_scheduler : priority_scheduler
      generic map ( event_slots => 8, preempt_threshold => 7, active_duration_cycles => 250_000_000 )
      port map ( resetN            => resetN            ,
                 clk               => CLOCK_50           ,
                 reschedule        => table_changed      ,
                 table_used        => table_used         ,
                 table_priority    => table_priority     ,
                 table_instance_id => table_instance_id  ,
                 active_valid      => sched_active_valid ,
                 active_index      => sched_active_index ,
                 start_pulse       => sched_start_pulse  ,
                 preempt_pulse     => sched_preempt_pulse ,
                 timeout_pulse     => sched_timeout_pulse ) ;

   active_priority <= table_priority(sched_active_index) ;

   -- active-duration timeout -> auto-release the timed-out instance from
   -- event_table_manager (Milestone 11, see priority_scheduler/
   -- event_table_manager headers for why this is a separate path from
   -- the manual release_req/ACK flow)
   auto_release_req         <= sched_timeout_pulse ;
   auto_release_instance_id <= table_instance_id(sched_active_index) ;

   u_led_pattern : led_pattern_controller
      generic map ( num_leds => 9, base_cycles => 25_000_000 )
      port map ( resetN          => resetN            ,
                 clk             => CLOCK_50           ,
                 active_valid    => sched_active_valid ,
                 active_priority => active_priority    ,
                 leds            => leds               ) ;

   LEDG1 <= leds(0) ;
   LEDG2 <= leds(1) ;
   LEDG3 <= leds(2) ;
   LEDG4 <= leds(3) ;
   LEDG5 <= leds(4) ;
   LEDG6 <= leds(5) ;
   LEDG7 <= leds(6) ;
   LEDG8 <= leds(7) ;
   LEDG9 <= leds(8) ;

   table_not_empty <= '0' when table_used = "00000000" else '1' ;

   u_buzzer : buzzer_controller
      generic map ( clk_hz => 50_000_000, beep_duration_cs => 20, beep_freq_hz => 2000 )
      port map ( resetN => resetN, clk => CLOCK_50,
                 system_enable => system_enable, table_not_empty => table_not_empty,
                 buzzer_out => SPEAKER ) ;

   u_response_builder : response_builder
      generic map ( max_response_length => 32 )
      port map ( resetN                 => resetN                ,
                 clk                    => CLOCK_50               ,
                 build_ack              => build_ack              ,
                 build_nack_bad_format  => build_nack_bad_format  ,
                 build_nack_unknown     => build_nack_unknown     ,
                 build_nack_unknown_evt => build_nack_unknown_evt ,
                 build_nack_table_full  => build_nack_table_full  ,
                 build_nack_unknown_inst=> build_nack_unknown_inst,
                 param_byte             => param_byte             ,
                 resp_data              => resp_data              ,
                 resp_length            => resp_length            ,
                 resp_ready             => resp_ready             ) ;

   u_response_sender : response_sender
      generic map ( max_response_length => 32 )
      port map ( resetN       => resetN      ,
                 clk          => CLOCK_50     ,
                 resp_data    => resp_data    ,
                 resp_length  => resp_length  ,
                 resp_ready   => resp_ready   ,
                 tx_din       => tx_din       ,
                 tx_write_din => tx_write_din ,
                 tx_ready     => tx_ready     ) ;

   u_uart_tx : uart_tx
      port map ( resetN    => resetN      ,
                 clk       => CLOCK_50     ,
                 din       => tx_din       ,
                 write_din => tx_write_din ,
                 tx        => TX2_BT       ,
                 tx_ready  => tx_ready     ) ;

end arc_event_system_top ;
