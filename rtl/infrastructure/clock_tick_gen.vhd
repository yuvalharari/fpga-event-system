----------------------------------------------------
-- clock_tick_gen : generates single-clock enable  --
-- pulses at 1us, 1ms, 10ms and 1s rates, cascaded  --
-- from the system clock (spec section 20).         --
--                                                   --
-- The divider counts are exposed as generics       --
-- (div_1us/div_1ms/div_10ms/div_1s) so a testbench  --
-- can override them with small values and verify    --
-- the cascading logic without simulating the full   --
-- 50,000,000-clock real-time period.                --
----------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity clock_tick_gen is
   generic ( div_1us  : positive := 50   ; -- clk cycles per tick_1us pulse (50 @ 50MHz)
             div_1ms  : positive := 1000 ; -- tick_1us pulses per tick_1ms pulse
             div_10ms : positive := 10   ; -- tick_1ms pulses per tick_10ms pulse
             div_1s   : positive := 100  ) ; -- tick_10ms pulses per tick_1s pulse
   port ( resetN    : in  std_logic ; -- active-low reset
          clk       : in  std_logic ;
          tick_1us  : out std_logic ; -- single-clock pulse every 1us
          tick_1ms  : out std_logic ; -- single-clock pulse every 1ms
          tick_10ms : out std_logic ; -- single-clock pulse every 10ms
          tick_1s   : out std_logic ) ; -- single-clock pulse every 1s
end clock_tick_gen ;

architecture arc_clock_tick_gen of clock_tick_gen is

   constant n_1us  : integer := div_1us  - 1 ;
   constant n_1ms  : integer := div_1ms  - 1 ;
   constant n_10ms : integer := div_10ms - 1 ;
   constant n_1s   : integer := div_1s   - 1 ;

   signal cnt_1us  : integer range 0 to n_1us  ;
   signal cnt_1ms  : integer range 0 to n_1ms  ;
   signal cnt_10ms : integer range 0 to n_10ms ;
   signal cnt_1s   : integer range 0 to n_1s   ;

   signal p_1us, p_1ms, p_10ms, p_1s : std_logic ;

begin

   ------------------------------------------------
   -- 1us pulse : divide the system clock         --
   ------------------------------------------------
   process (resetN, clk)
   begin
      if resetN = '0' then
         cnt_1us <= 0  ;
         p_1us   <= '0' ;
      elsif rising_edge(clk) then
         if cnt_1us = n_1us then
            cnt_1us <= 0   ;
            p_1us   <= '1' ;
         else
            cnt_1us <= cnt_1us + 1 ;
            p_1us   <= '0' ;
         end if ;
      end if ;
   end process ;

   ------------------------------------------------
   -- 1ms pulse : counts tick_1us pulses          --
   ------------------------------------------------
   process (resetN, clk)
   begin
      if resetN = '0' then
         cnt_1ms <= 0  ;
         p_1ms   <= '0' ;
      elsif rising_edge(clk) then
         p_1ms <= '0' ;
         if p_1us = '1' then
            if cnt_1ms = n_1ms then
               cnt_1ms <= 0   ;
               p_1ms   <= '1' ;
            else
               cnt_1ms <= cnt_1ms + 1 ;
            end if ;
         end if ;
      end if ;
   end process ;

   ------------------------------------------------
   -- 10ms pulse : counts tick_1ms pulses         --
   ------------------------------------------------
   process (resetN, clk)
   begin
      if resetN = '0' then
         cnt_10ms <= 0  ;
         p_10ms   <= '0' ;
      elsif rising_edge(clk) then
         p_10ms <= '0' ;
         if p_1ms = '1' then
            if cnt_10ms = n_10ms then
               cnt_10ms <= 0   ;
               p_10ms   <= '1' ;
            else
               cnt_10ms <= cnt_10ms + 1 ;
            end if ;
         end if ;
      end if ;
   end process ;

   ------------------------------------------------
   -- 1s pulse : counts tick_10ms pulses          --
   ------------------------------------------------
   process (resetN, clk)
   begin
      if resetN = '0' then
         cnt_1s <= 0  ;
         p_1s   <= '0' ;
      elsif rising_edge(clk) then
         p_1s <= '0' ;
         if p_10ms = '1' then
            if cnt_1s = n_1s then
               cnt_1s <= 0   ;
               p_1s   <= '1' ;
            else
               cnt_1s <= cnt_1s + 1 ;
            end if ;
         end if ;
      end if ;
   end process ;

   tick_1us  <= p_1us  ;
   tick_1ms  <= p_1ms  ;
   tick_10ms <= p_10ms ;
   tick_1s   <= p_1s   ;

end arc_clock_tick_gen ;
