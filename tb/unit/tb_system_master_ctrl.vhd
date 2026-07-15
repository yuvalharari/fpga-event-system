----------------------------------------------------------------
-- tb_system_master_ctrl : self-checking testbench for          --
-- system_master_ctrl (spec section 21, tb_system_master_ctrl). --
--                                                               --
-- Drives button0_pulse_i/button2_pulse_i directly as one-clock --
-- pulses (the debounce itself is already verified separately   --
-- in tb_button_pulse.vhd - this is a focused unit test of just --
-- the FSM logic).                                               --
--                                                               --
-- Checks:                                                      --
--   1) after reset, system_enable_o = '0' (SYSTEM_OFF)          --
--   2) BUTTON0 pulse -> system_enable_o = '1' (SYSTEM_ON)       --
--   3) a second BUTTON0 pulse while already ON has no effect    --
--   4) BUTTON2 pulse -> system_enable_o = '0' (SYSTEM_OFF)      --
--   5) a second BUTTON2 pulse while already OFF has no effect   --
--   6) a second full ON/OFF cycle works (not a one-shot fluke)  --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity tb_system_master_ctrl is
end tb_system_master_ctrl ;

architecture sim of tb_system_master_ctrl is

   constant clk_period : time := 20 ns ;

   signal clk             : std_logic := '0' ;
   signal resetN          : std_logic := '0' ;
   signal button0_pulse_i : std_logic := '0' ;
   signal button2_pulse_i : std_logic := '0' ;
   signal system_enable_o : std_logic ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.system_master_ctrl
      port map ( resetN          => resetN          ,
                 clk             => clk             ,
                 button0_pulse_i => button0_pulse_i ,
                 button2_pulse_i => button2_pulse_i ,
                 system_enable_o => system_enable_o ) ;

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

      -- issues a clean one-clock pulse on the given button signal,
      -- timed so the DUT samples it '1' on exactly one rising edge
      procedure pulse_button ( signal btn : out std_logic ) is
      begin
         wait until rising_edge(clk) ;
         btn <= '1' ;
         wait until rising_edge(clk) ;
         btn <= '0' ;
      end procedure ;

      procedure check_enable ( constant expected : std_logic ; constant name : string ) is
      begin
         wait for 1 ns ; -- let the combinational output settle
         if system_enable_o /= expected then
            errors := errors + 1 ;
            report "tb_system_master_ctrl: FAIL - " & name & " expected system_enable_o=" &
                   std_logic'image(expected) & ", got " & std_logic'image(system_enable_o)
               severity error ;
         end if ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;

      -- 1) after reset, must be SYSTEM_OFF
      check_enable('0', "after reset") ;

      -- 2) BUTTON0 pulse turns system ON
      pulse_button(button0_pulse_i) ;
      check_enable('1', "after BUTTON0 pulse") ;

      -- 3) another BUTTON0 pulse while already ON must have no effect
      pulse_button(button0_pulse_i) ;
      check_enable('1', "second BUTTON0 pulse while ON") ;

      -- 4) BUTTON2 pulse turns system OFF
      pulse_button(button2_pulse_i) ;
      check_enable('0', "after BUTTON2 pulse") ;

      -- 5) another BUTTON2 pulse while already OFF must have no effect
      pulse_button(button2_pulse_i) ;
      check_enable('0', "second BUTTON2 pulse while OFF") ;

      -- 6) repeat a full ON/OFF cycle - not a one-shot fluke
      pulse_button(button0_pulse_i) ;
      check_enable('1', "second ON cycle") ;
      pulse_button(button2_pulse_i) ;
      check_enable('0', "second OFF cycle") ;

      if errors = 0 then
         report "tb_system_master_ctrl: ALL TESTS PASSED" severity note ;
      else
         report "tb_system_master_ctrl: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
