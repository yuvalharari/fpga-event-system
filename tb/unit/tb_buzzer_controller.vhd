----------------------------------------------------------------
-- tb_buzzer_controller : self-checking testbench for            --
-- buzzer_controller. The internal course-provided blocks         --
-- (gozer/pacer/audio_gen) are already trusted/proven - this      --
-- testbench checks the WIRING logic we actually wrote: which     --
-- edges trigger a beep, that only edges (not held levels)        --
-- trigger, and that the beep is bounded (returns to silence).    --
-- It does not try to bit-exactly verify the tone's internal      --
-- timing.                                                        --
--                                                               --
-- Generics are overridden with small simulation-friendly values --
-- (clk_hz=1000 "cycles" instead of a real 50MHz) so a beep       --
-- window is on the order of tens of clock cycles, not seconds.  --
--                                                               --
-- Scenarios:                                                    --
--   1) at reset / idle, buzzer_out stays silent ('0')            --
--   2) system_enable rising edge -> some tone activity appears   --
--      within the expected beep window, then returns to silence --
--   3) holding system_enable at '1' (no new edge) -> no new beep --
--   4) table_not_empty rising edge -> a fresh beep, independent  --
--      of the system_enable trigger                              --
--   5) table_not_empty dropping then rising again -> another      --
--      fresh beep (each new edge re-triggers, not just the       --
--      first-ever one)                                            --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity tb_buzzer_controller is
end tb_buzzer_controller ;

architecture sim of tb_buzzer_controller is

   constant clk_period : time := 20 ns ;

   -- small simulation-friendly values - see header
   constant g_clk_hz           : integer  := 1000 ;
   constant g_beep_duration_cs : positive := 5    ; -- ~50 clock cycles
   constant g_beep_freq_hz     : positive := 100  ;

   signal clk    : std_logic := '0' ;
   signal resetN : std_logic := '0' ;

   signal system_enable   : std_logic := '0' ;
   signal table_not_empty : std_logic := '0' ;
   signal buzzer_out      : std_logic ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.buzzer_controller
      generic map ( clk_hz => g_clk_hz, beep_duration_cs => g_beep_duration_cs, beep_freq_hz => g_beep_freq_hz )
      port map ( resetN => resetN, clk => clk,
                 system_enable => system_enable, table_not_empty => table_not_empty,
                 buzzer_out => buzzer_out ) ;

   clk_gen : process
   begin
      while not sim_done loop
         wait for clk_period / 2 ;
         clk <= not clk ;
      end loop ;
      wait ;
   end process ;

   check : process
      variable errors    : natural := 0 ;
      variable seen_high  : boolean ;

      -- watches buzzer_out for n clock cycles, records whether it was ever '1'
      procedure watch_for_activity ( constant n : natural ; variable seen : out boolean ) is
      begin
         seen := false ;
         for i in 1 to n loop
            wait until rising_edge(clk) ;
            wait for 1 ns ;
            if buzzer_out = '1' then
               seen := true ;
            end if ;
         end loop ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;
      wait for 1 ns ;

      ------------------------------------------------------------
      -- 1) idle - silent
      ------------------------------------------------------------
      if buzzer_out /= '0' then
         errors := errors + 1 ;
         report "tb_buzzer_controller: FAIL - 1) buzzer_out should be silent at idle" severity error ;
      end if ;
      watch_for_activity( 20, seen_high ) ;
      if seen_high then
         errors := errors + 1 ;
         report "tb_buzzer_controller: FAIL - 1) buzzer_out should stay silent with no triggers" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 2) system_enable rising edge -> beep, then silence again
      ------------------------------------------------------------
      system_enable <= '1' ;
      watch_for_activity( 80, seen_high ) ;
      if not seen_high then
         errors := errors + 1 ;
         report "tb_buzzer_controller: FAIL - 2) expected tone activity after system_enable rising edge" severity error ;
      end if ;
      watch_for_activity( 40, seen_high ) ; -- well past the beep window
      if seen_high then
         errors := errors + 1 ;
         report "tb_buzzer_controller: FAIL - 2) beep should have ended by now (bounded duration)" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 3) system_enable held at '1' (no new edge) -> no new beep
      ------------------------------------------------------------
      watch_for_activity( 60, seen_high ) ;
      if seen_high then
         errors := errors + 1 ;
         report "tb_buzzer_controller: FAIL - 3) holding system_enable should not retrigger a beep" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 4) table_not_empty rising edge -> a fresh, independent beep
      ------------------------------------------------------------
      table_not_empty <= '1' ;
      watch_for_activity( 80, seen_high ) ;
      if not seen_high then
         errors := errors + 1 ;
         report "tb_buzzer_controller: FAIL - 4) expected tone activity after table_not_empty rising edge" severity error ;
      end if ;
      watch_for_activity( 40, seen_high ) ;
      if seen_high then
         errors := errors + 1 ;
         report "tb_buzzer_controller: FAIL - 4) beep should have ended by now" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 5) table_not_empty drops then rises again -> another fresh beep
      ------------------------------------------------------------
      table_not_empty <= '0' ;
      wait until rising_edge(clk) ;
      wait for 1 ns ;
      table_not_empty <= '1' ;
      watch_for_activity( 80, seen_high ) ;
      if not seen_high then
         errors := errors + 1 ;
         report "tb_buzzer_controller: FAIL - 5) expected a fresh beep on the second rising edge" severity error ;
      end if ;

      if errors = 0 then
         report "tb_buzzer_controller: ALL TESTS PASSED" severity note ;
      else
         report "tb_buzzer_controller: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
