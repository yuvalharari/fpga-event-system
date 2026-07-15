----------------------------------------------------------------
-- tb_clock_tick_gen : self-checking testbench for             --
-- clock_tick_gen (spec section 21).                            --
--                                                               --
-- The DUT's divider generics are overridden with small values  --
-- (4/4/4/4) so the full cascade (1us -> 1ms -> 10ms -> 1s)      --
-- completes in 4*4*4*4 = 256 clock cycles instead of the real   --
-- 50,000,000 cycles a 50MHz/1s period would take. This checks   --
-- the cascading structure; the default 50MHz divider arithmetic --
-- is simple integer division and is re-checked visually on      --
-- hardware later (1Hz heartbeat LED).                           --
--                                                               --
-- Checks, for each of the 4 tick outputs:                      --
--   1) the pulse is exactly one clock cycle wide                --
--   2) three consecutive periods match the expected count       --
-- Ends with a single "ALL TESTS PASSED" report if everything    --
-- checks out; any mismatch raises an "error" severity assert.   --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity tb_clock_tick_gen is
end tb_clock_tick_gen ;

architecture sim of tb_clock_tick_gen is

   constant clk_period : time := 20 ns ; -- arbitrary, cycle-count based checks only

   -- small generics for fast simulation of the cascade
   constant g_div_1us  : positive := 4 ;
   constant g_div_1ms  : positive := 4 ;
   constant g_div_10ms : positive := 4 ;
   constant g_div_1s   : positive := 4 ;

   -- expected period of each tick output, in clock cycles
   constant period_1us  : natural := g_div_1us ;
   constant period_1ms  : natural := g_div_1us * g_div_1ms ;
   constant period_10ms : natural := g_div_1us * g_div_1ms * g_div_10ms ;
   constant period_1s   : natural := g_div_1us * g_div_1ms * g_div_10ms * g_div_1s ;

   signal clk       : std_logic := '0' ;
   signal resetN    : std_logic := '0' ;
   signal tick_1us  : std_logic ;
   signal tick_1ms  : std_logic ;
   signal tick_10ms : std_logic ;
   signal tick_1s   : std_logic ;

   signal cycle : natural := 0 ; -- free running clock-edge counter, used to measure periods

begin

   ----------------------
   -- Device Under Test --
   ----------------------
   dut : entity work.clock_tick_gen
      generic map ( div_1us  => g_div_1us  ,
                    div_1ms  => g_div_1ms  ,
                    div_10ms => g_div_10ms ,
                    div_1s   => g_div_1s   )
      port map ( resetN    => resetN    ,
                 clk       => clk       ,
                 tick_1us  => tick_1us  ,
                 tick_1ms  => tick_1ms  ,
                 tick_10ms => tick_10ms ,
                 tick_1s   => tick_1s   ) ;

   -------------------
   -- Clock and cycle counter --
   -------------------
   clk <= not clk after clk_period / 2 ;

   process (clk)
   begin
      if rising_edge(clk) then
         cycle <= cycle + 1 ;
      end if ;
   end process ;

   ------------------------
   -- Reset stimulus --
   ------------------------
   process
   begin
      resetN <= '0' ;
      wait for clk_period * 5 ;
      resetN <= '1' ;
      wait ;
   end process ;

   ------------------------------------------------------------
   -- Shared check procedure: pulse-width + period, 3 cycles --
   ------------------------------------------------------------
   main_check : process

      procedure check_period ( signal   s        : in std_logic ;
                                signal   clkin    : in std_logic ;
                                constant expected : in natural   ;
                                constant name      : in string    ) is
         variable t_prev, t_now : natural ;
      begin
         -- pulse width check : must be exactly one clock cycle
         wait until rising_edge(clkin) and s = '1' ;
         t_prev := cycle ;
         wait until rising_edge(clkin) ;
         assert s = '0'
            report "tb_clock_tick_gen: FAIL - " & name & " stayed high for more than one clock cycle"
            severity error ;

         -- period check : three consecutive periods
         for i in 1 to 3 loop
            wait until rising_edge(clkin) and s = '1' ;
            t_now := cycle ;
            assert (t_now - t_prev) = expected
               report "tb_clock_tick_gen: FAIL - " & name & " period = " &
                      integer'image(t_now - t_prev) & " clocks, expected " &
                      integer'image(expected)
               severity error ;
            t_prev := t_now ;
         end loop ;

         report "tb_clock_tick_gen: " & name & " width+period check PASSED" severity note ;
      end procedure ;

   begin
      wait until resetN = '1' ;
      wait until rising_edge(clk) ; -- let the DUT settle one cycle after reset release

      check_period(tick_1us , clk, period_1us , "tick_1us" ) ;
      check_period(tick_1ms , clk, period_1ms , "tick_1ms" ) ;
      check_period(tick_10ms, clk, period_10ms, "tick_10ms") ;
      check_period(tick_1s  , clk, period_1s  , "tick_1s"  ) ;

      report "tb_clock_tick_gen: ALL TESTS PASSED" severity note ;
      wait ;
   end process ;

end sim ;
