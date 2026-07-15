----------------------------------------------------------------
-- tb_reset_controller : self-checking testbench for           --
-- reset_controller (spec section 21).                          --
--                                                               --
-- Checks:                                                      --
--   1) resetN = '0' before the first clock edge                 --
--   2) resetN stays '0' through the first (hold_cycles-1) edges --
--   3) resetN releases to '1' on the hold_cycles-th edge        --
--   4) resetN stays '1' afterwards (never glitches back to '0') --
--                                                               --
-- Failures are counted in a variable rather than relying only  --
-- on "assert ... severity error" - severity error does not     --
-- stop the process by itself, so without this counter a real   --
-- failure could still be followed by a false "ALL TESTS        --
-- PASSED" report.                                               --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity tb_reset_controller is
end tb_reset_controller ;

architecture sim of tb_reset_controller is

   constant clk_period    : time     := 20 ns ;
   constant g_hold_cycles : positive := 5     ; -- small value for a fast simulation

   signal clk    : std_logic := '0' ;
   signal resetN : std_logic ;

   signal sim_done : boolean := false ; -- set true once check finishes, stops the clock

begin

   dut : entity work.reset_controller
      generic map ( hold_cycles => g_hold_cycles )
      port map ( clk => clk, resetN => resetN ) ;

   -- a process (not a bare concurrent assignment) so it can stop itself
   -- once sim_done goes true - otherwise "run -all" never returns.
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
   begin
      -- let any pending delta-cycle updates inside the DUT settle before
      -- sampling resetN's power-up value (the DUT drives its output port
      -- through an internal signal, which needs a delta cycle to
      -- propagate - sampling at the very first delta reads a stale value)
      wait for 1 ns ;

      -- initial value, before the first clock edge
      if resetN /= '0' then
         errors := errors + 1 ;
         report "tb_reset_controller: FAIL - resetN is not '0' before the first clock edge"
            severity error ;
      end if ;

      -- resetN must remain '0' through the first (hold_cycles - 1) edges
      for i in 1 to g_hold_cycles - 1 loop
         wait until rising_edge(clk) ;
         wait for 1 ns ; -- let the DUT's registered update settle
         if resetN /= '0' then
            errors := errors + 1 ;
            report "tb_reset_controller: FAIL - resetN released too early, at edge " & integer'image(i)
               severity error ;
         end if ;
      end loop ;

      -- on the hold_cycles-th edge, resetN must release to '1'
      wait until rising_edge(clk) ;
      wait for 1 ns ;
      if resetN /= '1' then
         errors := errors + 1 ;
         report "tb_reset_controller: FAIL - resetN did not release after " &
                integer'image(g_hold_cycles) & " clocks"
            severity error ;
      end if ;

      -- stability check: must stay '1' for many more clocks
      for i in 1 to 10 loop
         wait until rising_edge(clk) ;
         wait for 1 ns ;
         if resetN /= '1' then
            errors := errors + 1 ;
            report "tb_reset_controller: FAIL - resetN dropped back to 0 after release (edge " &
                   integer'image(i) & " past release)"
               severity error ;
         end if ;
      end loop ;

      if errors = 0 then
         report "tb_reset_controller: ALL TESTS PASSED" severity note ;
      else
         report "tb_reset_controller: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ; -- stop the clock so "run -all" returns
      wait ;
   end process ;

end sim ;
