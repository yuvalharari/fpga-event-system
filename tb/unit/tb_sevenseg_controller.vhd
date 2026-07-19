----------------------------------------------------------------
-- tb_sevenseg_controller : self-checking testbench for           --
-- sevenseg_controller. Generics overridden with small simulation- --
-- friendly values (clk_hz=10, duration_seconds=5, so a "second"   --
-- is 10 clock cycles and the full countdown is 50 cycles) instead --
-- of the real 50,000,000/5 defaults, so the countdown is checkable --
-- in a handful of clock cycles with exact-cycle expectations.     --
--                                                               --
-- Scenarios:                                                    --
--   1) active_valid='0' (reset default) -> all four digits blank  --
--   2) instance_id view (sw9='1', after 2-cycle sync), all four   --
--      digits, DECIMAL zero-padded: spot-checked at 0, 5, 42,     --
--      100, 255 -> "0000","0005","0042","0100","0255"             --
--   3) priority view (sw9='0'): event_start_pulse fires -> seconds --
--      countdown starts at 5 (hex3="0",hex2="5"), hex1 blank,     --
--      hex0=priority digit                                       --
--   4) after exactly clk_hz cycles, countdown drops to 4; keeps    --
--      decrementing once per clk_hz cycles down through 0         --
--   5) once at 0, stays at 0 (saturates) even after more time      --
--      passes - does not wrap negative                            --
--   6) the countdown keeps running in the background even while    --
--      sw9='1' (ID view shown) - switching views does not pause    --
--      or reset it (2 seconds pass hidden behind the ID view,      --
--      countdown shows 5-2=3 once back on the priority view)       --
--   7) a fresh event_start_pulse mid-countdown resets it back to 5 --
--   8) active_valid='0' - blanks everything regardless of sw9/     --
--      countdown state                                             --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity tb_sevenseg_controller is
end tb_sevenseg_controller ;

architecture sim of tb_sevenseg_controller is

   constant clk_period : time := 20 ns ;

   constant g_clk_hz : integer  := 10 ;
   constant g_dur_s   : positive := 5 ;

   type patterns_t is array (0 to 9) of std_logic_vector(6 downto 0) ;
   constant SEG : patterns_t := (
      "1000000", "1111001", "0100100", "0110000", "0011001", -- 0 1 2 3 4
      "0010010", "0000010", "1111000", "0000000", "0010000"  -- 5 6 7 8 9
   ) ;
   constant BLANK : std_logic_vector(6 downto 0) := "1111111" ;

   signal clk    : std_logic := '0' ;
   signal resetN : std_logic := '0' ;

   signal active_valid       : std_logic := '0' ;
   signal active_priority    : std_logic_vector(2 downto 0) := (others => '0') ;
   signal active_instance_id : std_logic_vector(7 downto 0) := (others => '0') ;
   signal event_start_pulse  : std_logic := '0' ;
   signal sw9                : std_logic := '0' ;

   signal hex0, hex1, hex2, hex3 : std_logic_vector(6 downto 0) ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.sevenseg_controller
      generic map ( clk_hz => g_clk_hz, duration_seconds => g_dur_s )
      port map ( resetN => resetN, clk => clk,
                 active_valid => active_valid, active_priority => active_priority,
                 active_instance_id => active_instance_id, event_start_pulse => event_start_pulse,
                 sw9 => sw9,
                 hex0 => hex0, hex1 => hex1, hex2 => hex2, hex3 => hex3 ) ;

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

      procedure expect_all ( constant e0, e1, e2, e3 : std_logic_vector(6 downto 0) ; constant name : string ) is
      begin
         if hex0 /= e0 then
            errors := errors + 1 ;
            report "tb_sevenseg_controller: FAIL - " & name & " - wrong hex0" severity error ;
         end if ;
         if hex1 /= e1 then
            errors := errors + 1 ;
            report "tb_sevenseg_controller: FAIL - " & name & " - wrong hex1" severity error ;
         end if ;
         if hex2 /= e2 then
            errors := errors + 1 ;
            report "tb_sevenseg_controller: FAIL - " & name & " - wrong hex2" severity error ;
         end if ;
         if hex3 /= e3 then
            errors := errors + 1 ;
            report "tb_sevenseg_controller: FAIL - " & name & " - wrong hex3" severity error ;
         end if ;
      end procedure ;

      procedure expect_instance ( constant n : natural ; constant name : string ) is
      begin
         expect_all( SEG(n mod 10), SEG((n / 10) mod 10), SEG((n / 100) mod 10), SEG(0), name ) ;
      end procedure ;

      procedure expect_countdown ( constant secs : natural ; constant pri : natural ; constant name : string ) is
      begin
         expect_all( SEG(pri), BLANK, SEG(secs mod 10), SEG(secs / 10), name ) ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;
      wait for 1 ns ;

      ------------------------------------------------------------
      -- 1) reset default - active_valid='0' -> all blank
      ------------------------------------------------------------
      expect_all( BLANK, BLANK, BLANK, BLANK, "1) idle after reset" ) ;

      ------------------------------------------------------------
      -- 2) instance_id view (sw9='1'), all four digits, decimal
      ------------------------------------------------------------
      active_valid <= '1' ;
      sw9           <= '1' ;
      wait_cycles( 2 ) ; -- let the 2-flop synchronizer settle

      active_instance_id <= std_logic_vector(to_unsigned(0, 8)) ;
      wait for 1 ns ;
      expect_instance( 0, "2a) instance_id=0 -> 0000" ) ;
      wait_cycles( 1 ) ;

      active_instance_id <= std_logic_vector(to_unsigned(5, 8)) ;
      wait for 1 ns ;
      expect_instance( 5, "2b) instance_id=5 -> 0005" ) ;
      wait_cycles( 1 ) ;

      active_instance_id <= std_logic_vector(to_unsigned(42, 8)) ;
      wait for 1 ns ;
      expect_instance( 42, "2c) instance_id=42 -> 0042" ) ;
      wait_cycles( 1 ) ;

      active_instance_id <= std_logic_vector(to_unsigned(100, 8)) ;
      wait for 1 ns ;
      expect_instance( 100, "2d) instance_id=100 -> 0100" ) ;
      wait_cycles( 1 ) ;

      active_instance_id <= std_logic_vector(to_unsigned(255, 8)) ;
      wait for 1 ns ;
      expect_instance( 255, "2e) instance_id=255 -> 0255 (max)" ) ;

      ------------------------------------------------------------
      -- 3) priority view (sw9='0') - fresh event_start_pulse starts
      -- the countdown at duration_seconds=5
      ------------------------------------------------------------
      sw9             <= '0' ;
      active_priority <= "011" ; -- 3
      wait_cycles( 2 ) ; -- let the synchronizer settle
      event_start_pulse <= '1' ;
      wait until rising_edge(clk) ;
      event_start_pulse <= '0' ;
      wait for 1 ns ;
      expect_countdown( 5, 3, "3) fresh start - countdown=5, priority=3" ) ;

      ------------------------------------------------------------
      -- 4) countdown decrements once per g_clk_hz cycles, all the
      -- way down through 0
      ------------------------------------------------------------
      for s in 4 downto 0 loop
         wait_cycles( g_clk_hz ) ;
         expect_countdown( s, 3, "4) countdown=" & integer'image(s) ) ;
      end loop ;

      ------------------------------------------------------------
      -- 5) once at 0, stays at 0 (saturates, does not wrap)
      ------------------------------------------------------------
      wait_cycles( g_clk_hz * 2 ) ;
      expect_countdown( 0, 3, "5) countdown saturates at 0" ) ;

      ------------------------------------------------------------
      -- 6) the countdown keeps running in the background even while
      -- sw9='1' (ID view is selected) - it must NOT wait for the
      -- switch. Start a fresh countdown, immediately switch to the
      -- ID view for 2 seconds' worth of cycles, switch back, and
      -- confirm the countdown shows 5-2=3, not still 5 (frozen) and
      -- not reset to 5 (as if switching views restarted it)
      ------------------------------------------------------------
      event_start_pulse <= '1' ;
      wait until rising_edge(clk) ;
      event_start_pulse <= '0' ;
      sw9 <= '1' ;
      wait_cycles( 2 ) ; -- let the synchronizer settle into the ID view
      wait_cycles( g_clk_hz * 2 ) ; -- 2 full seconds pass while ID view is shown
      sw9 <= '0' ;
      wait_cycles( 2 ) ; -- let the synchronizer settle back to the priority view
      wait for 1 ns ;
      expect_countdown( 3, 3, "6) countdown kept running behind the ID view (5-2=3)" ) ;

      ------------------------------------------------------------
      -- 7) a fresh event_start_pulse mid/post-countdown resets it
      -- back to 5 (also change priority, proving it updates too)
      ------------------------------------------------------------
      active_priority    <= "110" ; -- 6
      event_start_pulse  <= '1' ;
      wait until rising_edge(clk) ;
      event_start_pulse  <= '0' ;
      wait for 1 ns ;
      expect_countdown( 5, 6, "7) event_start_pulse resets countdown to 5, priority=6" ) ;

      ------------------------------------------------------------
      -- 8) active_valid='0' - blanks everything regardless of sw9/
      -- countdown state
      ------------------------------------------------------------
      active_valid <= '0' ;
      wait for 1 ns ;
      expect_all( BLANK, BLANK, BLANK, BLANK, "8) idle blanks everything" ) ;

      if errors = 0 then
         report "tb_sevenseg_controller: ALL TESTS PASSED" severity note ;
      else
         report "tb_sevenseg_controller: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
