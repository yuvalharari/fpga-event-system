----------------------------------------------------------------
-- tb_button_pulse : self-checking testbench for button_pulse  --
-- (spec section 21) - the wrapper around the course-provided  --
-- clean_key + gozer blocks.                                    --
--                                                               --
-- clk_freq/max_bounce_time_ms are overridden (500 / 10) so     --
-- clean_key's internal max_count = 500*10/1000 = 5 clocks,     --
-- instead of the real 500,000 @ 50MHz/10ms - fast simulation   --
-- of the same debounce logic.                                  --
--                                                               --
-- Scenarios, each checked by counting pulses over a window     --
-- comfortably longer than the debounce+sync latency:            --
--   1) a clean press must produce exactly one pulse             --
--   2) a clean release must produce zero pulses                --
--   3) a bouncy press (several rapid toggles before settling)  --
--      must still collapse to exactly one pulse                --
--   4) a bouncy release must produce zero pulses                --
--   5) a second clean press must pulse again (not "stuck")     --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity tb_button_pulse is
end tb_button_pulse ;

architecture sim of tb_button_pulse is

   constant clk_period          : time    := 20 ns ;
   constant g_clk_freq          : integer := 500   ; -- fictional, only scales clean_key's math
   constant g_max_bounce_ms     : integer := 10     ; -- -> max_count = 500*10/1000 = 5 clocks
   constant settle_wait         : time    := clk_period * 30 ; -- generous margin

   signal clk      : std_logic := '0' ;
   signal resetN   : std_logic := '0' ;
   signal button_n : std_logic := '1' ; -- idle = released (active-low)
   signal pulse    : std_logic ;

   signal sim_done : boolean := false ;

   signal pulse_count : natural := 0 ;

begin

   dut : entity work.button_pulse
      generic map ( clk_freq           => g_clk_freq      ,
                    max_bounce_time_ms => g_max_bounce_ms )
      port map ( resetN => resetN, clk => clk, button_n => button_n, pulse => pulse ) ;

   clk_gen : process
   begin
      while not sim_done loop
         wait for clk_period / 2 ;
         clk <= not clk ;
      end loop ;
      wait ;
   end process ;

   -- pulse monitor : counts every pulse cycle seen, independent of the
   -- stimulus/check process below
   process (clk)
   begin
      if rising_edge(clk) then
         if pulse = '1' then
            pulse_count <= pulse_count + 1 ;
         end if ;
      end if ;
   end process ;

   stim_and_check : process
      variable errors       : natural := 0 ;
      variable count_before : natural ;

      procedure expect_pulses ( constant n : natural ; constant name : string ) is
      begin
         if (pulse_count - count_before) /= n then
            errors := errors + 1 ;
            report "tb_button_pulse: FAIL - " & name & " expected " & integer'image(n) &
                   " pulse(s), got " & integer'image(pulse_count - count_before)
               severity error ;
         end if ;
         count_before := pulse_count ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;
      wait for 1 ns ;
      count_before := pulse_count ;

      ------------------------------------------------------------
      -- 1) clean press
      ------------------------------------------------------------
      button_n <= '0' ;
      wait for settle_wait ;
      expect_pulses(1, "clean press") ;

      ------------------------------------------------------------
      -- 2) clean release - must not pulse
      ------------------------------------------------------------
      button_n <= '1' ;
      wait for settle_wait ;
      expect_pulses(0, "clean release") ;

      ------------------------------------------------------------
      -- 3) bouncy press - rapid toggles before settling pressed,  --
      -- must still collapse to exactly one pulse                  --
      ------------------------------------------------------------
      for i in 1 to 3 loop
         button_n <= '0' ;
         wait for clk_period ;
         button_n <= '1' ;
         wait for clk_period ;
      end loop ;
      button_n <= '0' ; -- settles pressed
      wait for settle_wait ;
      expect_pulses(1, "bouncy press") ;

      ------------------------------------------------------------
      -- 4) bouncy release - must not pulse                        --
      ------------------------------------------------------------
      for i in 1 to 3 loop
         button_n <= '1' ;
         wait for clk_period ;
         button_n <= '0' ;
         wait for clk_period ;
      end loop ;
      button_n <= '1' ; -- settles released
      wait for settle_wait ;
      expect_pulses(0, "bouncy release") ;

      ------------------------------------------------------------
      -- 5) second clean press - must pulse again                  --
      ------------------------------------------------------------
      button_n <= '0' ;
      wait for settle_wait ;
      expect_pulses(1, "second press") ;
      button_n <= '1' ;
      wait for settle_wait ;

      if errors = 0 then
         report "tb_button_pulse: ALL TESTS PASSED" severity note ;
      else
         report "tb_button_pulse: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
