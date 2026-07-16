----------------------------------------------------------------
-- tb_command_dispatcher : self-checking testbench for           --
-- command_dispatcher (spec section 21).                         --
--                                                               --
-- Scenarios:                                                    --
--   1) cmd_valid + cmd_is_evt, source_id=0x03 -> build_ack,      --
--      param_byte=0x03                                          --
--   2) cmd_valid + cmd_is_ack, instance_id=0x17 -> build_ack,    --
--      param_byte=0x17                                          --
--   3) cmd_error, code=0x01 -> build_nack_bad_format             --
--   4) cmd_error, code=0x02 -> build_nack_unknown                --
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
   signal source_id      : std_logic_vector(7 downto 0) := (others => '0') ;
   signal instance_id    : std_logic_vector(7 downto 0) := (others => '0') ;
   signal cmd_error      : std_logic := '0' ;
   signal cmd_error_code : std_logic_vector(7 downto 0) := (others => '0') ;

   signal build_ack             : std_logic ;
   signal build_nack_bad_format : std_logic ;
   signal build_nack_unknown    : std_logic ;
   signal param_byte            : std_logic_vector(7 downto 0) ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.command_dispatcher
      port map ( resetN => resetN, clk => clk,
                 cmd_valid => cmd_valid, cmd_is_evt => cmd_is_evt, cmd_is_ack => cmd_is_ack,
                 source_id => source_id, instance_id => instance_id,
                 cmd_error => cmd_error, cmd_error_code => cmd_error_code,
                 build_ack => build_ack, build_nack_bad_format => build_nack_bad_format,
                 build_nack_unknown => build_nack_unknown, param_byte => param_byte ) ;

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

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      ------------------------------------------------------------
      -- 1) EVT success
      ------------------------------------------------------------
      cmd_valid  <= '1' ;
      cmd_is_evt <= '1' ;
      cmd_is_ack <= '0' ;
      source_id  <= x"03" ;
      pulse_clock ;
      cmd_valid  <= '0' ;
      cmd_is_evt <= '0' ;
      if build_ack /= '1' or param_byte /= x"03" then
         errors := errors + 1 ;
         report "tb_command_dispatcher: FAIL - EVT success did not produce build_ack with source_id" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 2) ACK success
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
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
      -- 3) error code 01 -> bad format
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
      -- 4) error code 02 -> unknown command
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

      if errors = 0 then
         report "tb_command_dispatcher: ALL TESTS PASSED" severity note ;
      else
         report "tb_command_dispatcher: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
