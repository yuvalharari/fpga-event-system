----------------------------------------------------------------
-- tb_led_pattern_controller : self-checking testbench for       --
-- led_pattern_controller. Generics overridden with small        --
-- simulation-friendly values (base_cycles=80, num_leds=4)       --
-- instead of the real 25,000,000/9 defaults, so speed            --
-- differences and wraparound are checkable in a handful of       --
-- clock cycles, with exact cycle-accurate expectations           --
-- (matching this project's established testing style).           --
--                                                               --
-- Scenarios (base_cycles=80 -> priority 0 step=80 cycles,        --
-- priority 7 step=10 cycles):                                    --
--   1) inactive -> all LEDs off                                  --
--   2) active, priority=0 -> after 35 cycles (< 80), position    --
--      has NOT advanced yet (still 0) - proves the slow case     --
--   3) active, priority=7 -> after 35 cycles, position has        --
--      advanced exactly 3 steps (35/10=3) - proves priority       --
--      really does speed up the chase                            --
--   4) active, priority=7, continuing -> after 40 cycles total    --
--      from a fresh start (4 steps, num_leds=4) position wraps    --
--      back around to 0                                           --
--   5) active_valid drops then rises again -> position resets to --
--      0 immediately, not resuming where it left off              --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity tb_led_pattern_controller is
end tb_led_pattern_controller ;

architecture sim of tb_led_pattern_controller is

   constant clk_period : time := 20 ns ;

   constant g_num_leds    : positive := 4  ;
   constant g_base_cycles : positive := 80 ;

   signal clk    : std_logic := '0' ;
   signal resetN : std_logic := '0' ;

   signal active_valid    : std_logic := '0' ;
   signal active_priority : std_logic_vector(2 downto 0) := (others => '0') ;
   signal leds            : std_logic_vector(g_num_leds - 1 downto 0) ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.led_pattern_controller
      generic map ( num_leds => g_num_leds, base_cycles => g_base_cycles )
      port map ( resetN => resetN, clk => clk,
                 active_valid => active_valid, active_priority => active_priority,
                 leds => leds ) ;

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
         wait for 1 ns ;
      end procedure ;

      procedure wait_cycles ( constant n : natural ) is
      begin
         for i in 1 to n loop
            pulse_clock ;
         end loop ;
      end procedure ;

      -- returns the (single) index currently lit, or g_num_leds if none/more than one
      impure function lit_index return natural is
         variable idx   : natural := g_num_leds ;
         variable count : natural := 0 ;
      begin
         for i in 0 to g_num_leds - 1 loop
            if leds(i) = '1' then
               idx := i ;
               count := count + 1 ;
            end if ;
         end loop ;
         if count /= 1 then
            return g_num_leds ; -- 0 or >1 lit - not a clean one-hot state
         end if ;
         return idx ;
      end function ;

      procedure expect_position ( constant exp : natural ; constant name : string ) is
      begin
         if lit_index /= exp then
            errors := errors + 1 ;
            report "tb_led_pattern_controller: FAIL - " & name & " - wrong lit LED index" severity error ;
         end if ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;
      wait for 1 ns ;

      ------------------------------------------------------------
      -- 1) inactive - all LEDs off
      ------------------------------------------------------------
      if leds /= "0000" then
         errors := errors + 1 ;
         report "tb_led_pattern_controller: FAIL - 1) LEDs should be off while inactive" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 2) active, priority=0 (slowest, step=80) - after 35
      -- cycles, position has not advanced yet
      ------------------------------------------------------------
      active_valid    <= '1' ;
      active_priority <= "000" ;
      wait_cycles( 35 ) ;
      expect_position( 0, "2) priority=0 after 35 cycles (step=80, should not have moved)" ) ;

      ------------------------------------------------------------
      -- 3) deactivate/reactivate at priority=7 (fastest, step=10) -
      -- deactivating first clears the leftover cycle_count from the
      -- priority=0 phase, so the step timing below is exact (a
      -- straight priority switch without resetting would leave a
      -- stale cycle_count and throw the expected step count off)
      ------------------------------------------------------------
      active_valid <= '0' ;
      wait_cycles( 2 ) ;
      active_valid    <= '1' ;
      active_priority <= "111" ;
      wait_cycles( 35 ) ;
      expect_position( 3, "3) priority=7 after 35 cycles (step=10, should be 3 steps in)" ) ;

      ------------------------------------------------------------
      -- 4) restart fresh at priority=7, run exactly 4 steps (40
      -- cycles, num_leds=4) - should wrap back around to 0
      ------------------------------------------------------------
      active_valid <= '0' ;
      wait_cycles( 2 ) ; -- let the inactive-reset take effect
      active_valid    <= '1' ;
      active_priority <= "111" ;
      wait_cycles( 40 ) ;
      expect_position( 0, "4) priority=7 after exactly 4 steps (40 cycles) - should wrap to 0" ) ;

      ------------------------------------------------------------
      -- 5) build up some position, then drop and re-raise
      -- active_valid - position must reset to 0, not resume
      ------------------------------------------------------------
      wait_cycles( 25 ) ; -- 2 more steps at priority=7 -> position should be 2
      expect_position( 2, "5a) priority=7 after 25 more cycles - should be 2 steps in" ) ;

      active_valid <= '0' ;
      wait_cycles( 2 ) ;
      if leds /= "0000" then
         errors := errors + 1 ;
         report "tb_led_pattern_controller: FAIL - 5b) LEDs should be off immediately when inactive" severity error ;
      end if ;

      active_valid <= '1' ; -- reactivate, still priority=7 from before
      wait_cycles( 1 ) ;
      expect_position( 0, "5c) reactivating should restart the chase at position 0, not resume at 2" ) ;

      if errors = 0 then
         report "tb_led_pattern_controller: ALL TESTS PASSED" severity note ;
      else
         report "tb_led_pattern_controller: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
