----------------------------------------------------------------
-- sevenseg_controller : drives the DE0's four 7-segment displays  --
-- (project's own reduced design, NOT the spec's multi-page        --
-- cycling scheme - section 13.3 - see project memory "final       --
-- product vision"). Two views, toggled live by SW9:               --
--                                                               --
--   SW9='1' : active event's instance_id, all four digits,        --
--             DECIMAL, zero-padded (0000-0255) - hex3=thousands   --
--             (always 0), hex2=hundreds, hex1=tens, hex0=ones.    --
--             Deliberately decimal, not hex, even though           --
--             instance_id is an 8-bit binary counter and the       --
--             phone's ACK,INSTANCE=<hex> response is hex - decided --
--             2026-07-19 for readability to a non-technical viewer --
--             looking only at the board (won't visually match the  --
--             phone's text for values >= 10 - an accepted,          --
--             deliberate inconsistency, not a bug).                --
--                                                               --
--   SW9='0' (default): hex0 = active event's priority (0-7);       --
--             hex1 = blank (visual gap); hex3/hex2 = a live         --
--             countdown of seconds remaining until                 --
--             priority_scheduler's active-duration timeout fires    --
--             for this event (hex3=tens, hex2=ones, zero-padded,   --
--             e.g. "05"->"04"->...->"00"). Added 2026-07-19 after   --
--             discussing what to do with the two spare digits once --
--             the ID view moved to using all four.                 --
--                                                               --
-- The countdown is a SEPARATE internal counter, not a value read    --
-- out of priority_scheduler - it re-derives the same reset          --
-- conditions from event_start_pulse (the caller ORs together        --
-- priority_scheduler's start_pulse and preempt_pulse - both mean    --
-- "a new/different event just became active, restart the clock")   --
-- and active_valid, rather than exposing priority_scheduler's        --
-- internal duration_count as a new port - keeps that already-       --
-- verified, hardware-proven block completely untouched. The two     --
-- counters WILL stay in lockstep as long as clk_hz*duration_seconds --
-- here equals priority_scheduler's active_duration_cycles generic -  --
-- both are set from the same two numbers at the top level.           --
--                                                               --
-- All digits blank when active_valid='0' (spec's "Safe Output        --
-- State" idea, section 16.2), overriding both views.                --
--                                                               --
-- Segment encoding: standard active-low 7-segment (DE0 convention, --
-- '0' lights a segment), bit order (6 downto 0) = g f e d c b a.   --
-- Exact polarity/order to be re-confirmed against real hardware at --
-- the bring-up stage, same as every other output block so far.    --
--                                                               --
-- SW9 is a raw physical switch (not a one-shot pulse like the      --
-- buttons) - only 2-flop synchronized here against metastability,  --
-- no debounce needed: a few ms of display flicker while the switch --
-- physically settles is harmless (unlike a button pulse driving a  --
-- one-shot action). event_start_pulse, by contrast, IS already a   --
-- clean one-clock pulse (it comes straight from priority_scheduler --
-- via the top level), so it needs no synchronization of its own.   --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity sevenseg_controller is
   generic ( clk_hz           : integer  := 50_000_000 ; -- must match priority_scheduler's clock
             duration_seconds : positive := 5            ) ; -- must match active_duration_cycles/clk_hz
   port ( resetN             : in  std_logic ;
          clk                : in  std_logic ;
          active_valid       : in  std_logic ;
          active_priority    : in  std_logic_vector(2 downto 0) ;
          active_instance_id : in  std_logic_vector(7 downto 0) ;
          event_start_pulse  : in  std_logic ; -- one-clock pulse: active event just started/switched
          sw9                : in  std_logic ; -- raw, asynchronous
          hex0               : out std_logic_vector(6 downto 0) ; -- rightmost digit
          hex1               : out std_logic_vector(6 downto 0) ;
          hex2               : out std_logic_vector(6 downto 0) ;
          hex3               : out std_logic_vector(6 downto 0) ) ; -- leftmost digit
end sevenseg_controller ;

architecture arc_sevenseg_controller of sevenseg_controller is

   constant BLANK : std_logic_vector(6 downto 0) := "1111111" ;

   signal sw9_meta : std_logic ;
   signal sw9_sync : std_logic ;

   signal cycle_in_second : integer range 0 to clk_hz - 1 ;
   signal seconds_left    : integer range 0 to duration_seconds ;

   function digit_to_seg ( constant n : std_logic_vector(3 downto 0) ) return std_logic_vector is
   begin
      case n is
         when "0000" => return "1000000" ; -- 0
         when "0001" => return "1111001" ; -- 1
         when "0010" => return "0100100" ; -- 2
         when "0011" => return "0110000" ; -- 3
         when "0100" => return "0011001" ; -- 4
         when "0101" => return "0010010" ; -- 5
         when "0110" => return "0000010" ; -- 6
         when "0111" => return "1111000" ; -- 7
         when "1000" => return "0000000" ; -- 8
         when others => return "0010000" ; -- 9
      end case ;
   end function ;

begin

   -- 2-flop synchronizer for the raw SW9 input (spec section 20)
   process (resetN, clk)
   begin
      if resetN = '0' then
         sw9_meta <= '0' ;
         sw9_sync <= '0' ;
      elsif rising_edge(clk) then
         sw9_meta <= sw9 ;
         sw9_sync <= sw9_meta ;
      end if ;
   end process ;

   -- countdown: seconds_left starts at duration_seconds when a new event
   -- becomes active, decrements once per real second, saturates at 0
   process (resetN, clk)
   begin
      if resetN = '0' then
         cycle_in_second <= 0 ;
         seconds_left    <= duration_seconds ;
      elsif rising_edge(clk) then
         if active_valid = '0' or event_start_pulse = '1' then
            cycle_in_second <= 0 ;
            seconds_left    <= duration_seconds ;
         elsif cycle_in_second = clk_hz - 1 then
            cycle_in_second <= 0 ;
            if seconds_left > 0 then
               seconds_left <= seconds_left - 1 ;
            end if ;
         else
            cycle_in_second <= cycle_in_second + 1 ;
         end if ;
      end if ;
   end process ;

   process (active_valid, sw9_sync, active_priority, active_instance_id, seconds_left)
      variable inst_int : integer range 0 to 255 ;
      variable thousands, hundreds, tens, ones : integer range 0 to 9 ;
   begin
      if active_valid = '0' then
         hex0 <= BLANK ;
         hex1 <= BLANK ;
         hex2 <= BLANK ;
         hex3 <= BLANK ;
      elsif sw9_sync = '1' then
         inst_int  := to_integer(unsigned(active_instance_id)) ;
         thousands := 0 ; -- instance_id maxes at 255, thousands digit is always 0
         hundreds  := inst_int / 100 ;
         tens      := (inst_int / 10) mod 10 ;
         ones      := inst_int mod 10 ;
         hex0 <= digit_to_seg(std_logic_vector(to_unsigned(ones, 4))) ;
         hex1 <= digit_to_seg(std_logic_vector(to_unsigned(tens, 4))) ;
         hex2 <= digit_to_seg(std_logic_vector(to_unsigned(hundreds, 4))) ;
         hex3 <= digit_to_seg(std_logic_vector(to_unsigned(thousands, 4))) ;
      else
         hex0 <= digit_to_seg('0' & active_priority) ;
         hex1 <= BLANK ;
         hex2 <= digit_to_seg(std_logic_vector(to_unsigned(seconds_left mod 10, 4))) ;
         hex3 <= digit_to_seg(std_logic_vector(to_unsigned(seconds_left / 10, 4))) ;
      end if ;
   end process ;

end arc_sevenseg_controller ;
