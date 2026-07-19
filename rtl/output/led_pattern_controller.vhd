----------------------------------------------------------------
-- led_pattern_controller : chase/marquee animation across all   --
-- LEDs whenever an event is active (project's own reduced       --
-- design, NOT the spec's LED0-7 meaning table or per-pattern    --
-- LED_PATTERN opcode - see project memory "final product        --
-- vision"). Speed scales with the active event's priority -     --
-- higher priority = faster chase.                                --
--                                                               --
-- One LED lit at a time, position advancing by one every        --
-- "step_period" clocks, wrapping around after num_leds steps.   --
-- step_period is derived from base_cycles (the slowest, priority--
-- 0, step period) divided by (priority+1) - priority 7 is 8x    --
-- faster than priority 0. The division is by a case-selected     --
-- LITERAL constant (2,3,4...8), not a runtime divisor, so it's   --
-- resolved to plain constants at elaboration - no hardware       --
-- divider is inferred.                                           --
--                                                               --
-- When active_valid='0', all LEDs are off and the chase position--
-- resets to 0, so every new active event restarts the animation --
-- cleanly from the same starting LED rather than resuming        --
-- wherever a previous event's chase happened to stop.            --
--                                                               --
-- Direction note: "position 0" maps to leds(0) - depending on    --
-- which physical LED that pin drives on the board, the visual    --
-- direction (left-to-right or right-to-left) may need the vector --
-- reversed at the top-level port map once seen on real hardware. --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity led_pattern_controller is
   generic ( num_leds    : positive := 9         ; -- LEDG1..LEDG9 by default (LEDG0 stays SYSTEM_ON)
             base_cycles : positive := 25_000_000 ) ; -- priority-0 (slowest) step period, in clk cycles
   port ( resetN          : in  std_logic ;
          clk             : in  std_logic ;
          active_valid    : in  std_logic ;
          active_priority : in  std_logic_vector(2 downto 0) ;
          leds            : out std_logic_vector(num_leds - 1 downto 0) ) ;
end led_pattern_controller ;

architecture arc_led_pattern_controller of led_pattern_controller is

   signal step_period : integer range 0 to base_cycles ;
   signal cycle_count  : integer range 0 to base_cycles ;
   signal position      : integer range 0 to num_leds - 1 ;

begin

   -- priority -> step period (elaboration-time constants, see header)
   process (active_priority)
   begin
      case active_priority is
         when "000" => step_period <= base_cycles      ; -- priority 0, slowest
         when "001" => step_period <= base_cycles / 2  ;
         when "010" => step_period <= base_cycles / 3  ;
         when "011" => step_period <= base_cycles / 4  ;
         when "100" => step_period <= base_cycles / 5  ;
         when "101" => step_period <= base_cycles / 6  ;
         when "110" => step_period <= base_cycles / 7  ;
         when others => step_period <= base_cycles / 8 ; -- priority 7, fastest
      end case ;
   end process ;

   process (resetN, clk)
   begin
      if resetN = '0' then
         cycle_count <= 0 ;
         position    <= 0 ;
      elsif rising_edge(clk) then
         if active_valid = '0' then
            cycle_count <= 0 ;
            position    <= 0 ; -- restart the chase cleanly for the next active event
         else
            if cycle_count >= step_period - 1 then
               cycle_count <= 0 ;
               if position = num_leds - 1 then
                  position <= 0 ;
               else
                  position <= position + 1 ;
               end if ;
            else
               cycle_count <= cycle_count + 1 ;
            end if ;
         end if ;
      end if ;
   end process ;

   process (active_valid, position)
   begin
      leds <= (others => '0') ;
      if active_valid = '1' then
         leds(position) <= '1' ;
      end if ;
   end process ;

end arc_led_pattern_controller ;
