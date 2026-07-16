----------------------------------------------------------------
-- tb_command_dispatcher : self-checking testbench for           --
-- command_dispatcher (spec section 21).                         --
--                                                               --
-- command_dispatcher now drives a real allocation handshake     --
-- with event_table_manager for EVT commands, so this testbench  --
-- instantiates a REAL event_table_manager alongside the DUT     --
-- (already verified standalone in tb_event_table_manager) -     --
-- this checks the actual integration contract between the two   --
-- blocks, not a guessed mock of event_table_manager's timing.   --
--                                                                --
-- Scenarios:                                                    --
--   1) cmd_valid+cmd_is_ack, instance_id=0x17 -> build_ack,      --
--      param_byte=0x17 (single cycle, no allocation involved)   --
--   2) cmd_error, code=0x01 -> build_nack_bad_format             --
--   3) cmd_error, code=0x02 -> build_nack_unknown                --
--   4) EVT, event_type=01 (LIFE_THREATENING_EMERGENCY) -> real   --
--      allocation succeeds, build_ack, param_byte=instance_id=0 --
--   5) EVT, event_type=07 (MEDICATION_MISSED) -> succeeds,       --
--      param_byte=instance_id=1                                 --
--   6) EVT, event_type=0D (not in the catalog) ->                --
--      build_nack_unknown_evt                                   --
--   7) fill the remaining 6 slots (event_slots=8), then a 9th    --
--      EVT -> build_nack_table_full                              --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity tb_command_dispatcher is
end tb_command_dispatcher ;

architecture sim of tb_command_dispatcher is

   constant clk_period : time := 20 ns ;

   signal clk    : std_logic := '0' ;
   signal resetN : std_logic := '0' ;

   signal cmd_valid      : std_logic := '0' ;
   signal cmd_is_evt     : std_logic := '0' ;
   signal cmd_is_ack     : std_logic := '0' ;
   signal event_type     : std_logic_vector(7 downto 0) := (others => '0') ;
   signal source_id      : std_logic_vector(7 downto 0) := (others => '0') ;
   signal instance_id    : std_logic_vector(7 downto 0) := (others => '0') ;
   signal cmd_error      : std_logic := '0' ;
   signal cmd_error_code : std_logic_vector(7 downto 0) := (others => '0') ;

   signal alloc_req          : std_logic ;
   signal alloc_event_type   : std_logic_vector(7 downto 0) ;
   signal alloc_source_id    : std_logic_vector(7 downto 0) ;
   signal alloc_done         : std_logic ;
   signal alloc_ok           : std_logic ;
   signal alloc_unknown_type : std_logic ;
   signal alloc_instance_id  : std_logic_vector(7 downto 0) ;
   signal alloc_priority     : std_logic_vector(2 downto 0) ;
   signal alloc_requires_ack : std_logic ;

   signal build_ack             : std_logic ;
   signal build_nack_bad_format : std_logic ;
   signal build_nack_unknown    : std_logic ;
   signal build_nack_unknown_evt: std_logic ;
   signal build_nack_table_full : std_logic ;
   signal param_byte            : std_logic_vector(7 downto 0) ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.command_dispatcher
      port map ( resetN => resetN, clk => clk,
                 cmd_valid => cmd_valid, cmd_is_evt => cmd_is_evt, cmd_is_ack => cmd_is_ack,
                 event_type => event_type, source_id => source_id, instance_id => instance_id,
                 cmd_error => cmd_error, cmd_error_code => cmd_error_code,
                 alloc_req => alloc_req, alloc_event_type => alloc_event_type, alloc_source_id => alloc_source_id,
                 alloc_done => alloc_done, alloc_ok => alloc_ok, alloc_unknown_type => alloc_unknown_type,
                 alloc_instance_id => alloc_instance_id,
                 build_ack => build_ack, build_nack_bad_format => build_nack_bad_format,
                 build_nack_unknown => build_nack_unknown, build_nack_unknown_evt => build_nack_unknown_evt,
                 build_nack_table_full => build_nack_table_full, param_byte => param_byte ) ;

   table : entity work.event_table_manager
      generic map ( event_slots => 8 )
      port map ( resetN => resetN, clk => clk,
                 alloc_req => alloc_req, event_type => alloc_event_type, source_id => alloc_source_id,
                 alloc_done => alloc_done, alloc_ok => alloc_ok, alloc_unknown_type => alloc_unknown_type,
                 alloc_instance_id => alloc_instance_id, alloc_priority => alloc_priority,
                 alloc_requires_ack => alloc_requires_ack ) ;

   clk_gen : process
   begin
      while not sim_done loop
         wait for clk_period / 2 ;
         clk <= not clk ;
      end loop ;
      wait ;
   end process ;

   check : process
      variable errors : natural := 0 ;

      procedure pulse_clock is
      begin
         wait until rising_edge(clk) ;
         wait for 1 ns ; -- let this edge's registered outputs settle
      end procedure ;

      -- EVT commands take 2 extra clock cycles: one for command_dispatcher
      -- to issue alloc_req, one for event_table_manager to respond with
      -- alloc_done, one for command_dispatcher to register build_ack/nack.
      procedure send_evt ( constant t : std_logic_vector(7 downto 0) ; constant s : std_logic_vector(7 downto 0) ) is
      begin
         event_type <= t ;
         source_id  <= s ;
         cmd_is_evt <= '1' ;
         cmd_valid  <= '1' ;
         wait until rising_edge(clk) ; -- dispatcher captures cmd_valid, issues alloc_req
         cmd_valid  <= '0' ;
         cmd_is_evt <= '0' ;
         wait until rising_edge(clk) ; -- event_table_manager processes alloc_req
         wait until rising_edge(clk) ; -- dispatcher registers the build_* response
         wait for 1 ns ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      ------------------------------------------------------------
      -- 1) ACK success (unchanged, single-cycle path)
      ------------------------------------------------------------
      cmd_valid   <= '1' ;
      cmd_is_ack  <= '1' ;
      instance_id <= x"17" ;
      pulse_clock ;
      cmd_valid  <= '0' ;
      cmd_is_ack <= '0' ;
      if build_ack /= '1' or param_byte /= x"17" then
         errors := errors + 1 ;
         report "tb_command_dispatcher: FAIL - ACK success did not produce build_ack with instance_id" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 2) error code 01 -> bad format
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      cmd_error      <= '1' ;
      cmd_error_code <= x"01" ;
      pulse_clock ;
      cmd_error <= '0' ;
      if build_nack_bad_format /= '1' then
         errors := errors + 1 ;
         report "tb_command_dispatcher: FAIL - error code 01 did not produce build_nack_bad_format" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 3) error code 02 -> unknown command
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      cmd_error      <= '1' ;
      cmd_error_code <= x"02" ;
      pulse_clock ;
      cmd_error <= '0' ;
      if build_nack_unknown /= '1' then
         errors := errors + 1 ;
         report "tb_command_dispatcher: FAIL - error code 02 did not produce build_nack_unknown" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 4) EVT success - real allocation, instance_id=0
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      send_evt( x"01", x"05" ) ;
      if build_ack /= '1' or param_byte /= x"00" then
         errors := errors + 1 ;
         report "tb_command_dispatcher: FAIL - 1st EVT did not produce build_ack with instance_id=0" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 5) EVT success - real allocation, instance_id=1
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      send_evt( x"07", x"02" ) ;
      if build_ack /= '1' or param_byte /= x"01" then
         errors := errors + 1 ;
         report "tb_command_dispatcher: FAIL - 2nd EVT did not produce build_ack with instance_id=1" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 6) EVT with unrecognized event_type
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      send_evt( x"0D", x"03" ) ;
      if build_nack_unknown_evt /= '1' then
         errors := errors + 1 ;
         report "tb_command_dispatcher: FAIL - EVT with event_type=0D did not produce build_nack_unknown_evt" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 7) fill the remaining 6 slots, then a 9th EVT -> table full
      ------------------------------------------------------------
      for n in 2 to 7 loop
         wait until rising_edge(clk) ;
         send_evt( x"0C", x"00" ) ;
         if build_ack /= '1' then
            errors := errors + 1 ;
            report "tb_command_dispatcher: FAIL - filler EVT #" & integer'image(n) & " did not succeed" severity error ;
         end if ;
      end loop ;

      wait until rising_edge(clk) ;
      send_evt( x"01", x"09" ) ;
      if build_nack_table_full /= '1' then
         errors := errors + 1 ;
         report "tb_command_dispatcher: FAIL - 9th EVT did not produce build_nack_table_full" severity error ;
      end if ;

      if errors = 0 then
         report "tb_command_dispatcher: ALL TESTS PASSED" severity note ;
      else
         report "tb_command_dispatcher: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
