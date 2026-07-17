----------------------------------------------------------------
-- priority_scheduler : picks the winning event instance out of --
-- event_table_manager's whole table (spec section 8.2, entity   --
-- example section 18.2).                                        --
--                                                               --
-- Winner selection: highest priority among all OCCUPIED slots;  --
-- ties broken by lowest instance_id (= oldest, since instance_id--
-- is monotonically increasing - spec 8.2 "oldest_instance_id").  --
--                                                               --
-- Preemption rule (spec 8.2/8.3), with a project-specific        --
-- addition agreed with the user: the winner only takes over an  --
-- already-active event if BOTH:                                 --
--   1) its priority is strictly greater than the active event's --
--      priority (equal priority never preempts - two same-       --
--      priority events would otherwise fight for the slot        --
--      forever)                                                  --
--   2) its priority is >= preempt_threshold (generic, default    --
--      7 = only the single highest tier can preempt at all;      --
--      everything else just queues by priority and waits for     --
--      the active event to finish naturally - avoids cascades    --
--      like "4 preempts 3 preempts 2 preempts 1" for events that --
--      aren't actually urgent enough to justify interrupting     --
--      whatever's already running)                                --
-- Both conditions together also guarantee priority 7 never       --
-- preempts another priority-7 event (7 > 7 is false), with no    --
-- special-casing needed.                                         --
--                                                               --
-- Reduced initial scope:                                        --
--   - re-evaluates only on an explicit reschedule pulse (spec    --
--     18.2's reschedule_i), driven externally whenever the table --
--     actually changes (a successful allocation or release) -    --
--     not every clock cycle.                                     --
--   - no context save/restore (that's preemption_manager's job,  --
--     not built yet) - this block only decides WHICH slot should --
--     be active, not what happens to a preempted event's script  --
--     state.                                                     --
--   - no resume_pulse yet (nothing to resume without              --
--     preemption_manager) - kept out of the port list for now,   --
--     unlike the spec's example interface.                       --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;
use work.event_system_pkg.all ;

entity priority_scheduler is
   generic ( event_slots       : positive := 8 ;
             preempt_threshold : natural  := 7 ) ; -- min priority a NEW event needs to preempt an active one at all
   port ( resetN         : in  std_logic                                     ;
          clk            : in  std_logic                                     ;

          reschedule     : in  std_logic                                     ; -- one-clock pulse: table changed, please re-evaluate

          table_used        : in  std_logic_vector(0 to event_slots - 1)     ;
          table_priority    : in  priority_array_t(0 to event_slots - 1)     ;
          table_instance_id : in  instance_id_array_t(0 to event_slots - 1)  ;

          active_valid   : out std_logic                                     ; -- '1' when some slot is active
          active_index   : out integer range 0 to event_slots - 1            ; -- valid when active_valid='1'
          start_pulse    : out std_logic                                     ; -- one-clock pulse: went from no-active to active
          preempt_pulse  : out std_logic                                      ) ; -- one-clock pulse: active slot just switched
end priority_scheduler ;

architecture arc_priority_scheduler of priority_scheduler is

   signal active_slot   : integer range 0 to event_slots ; -- = event_slots means "no active slot"
   signal best_index    : integer range 0 to event_slots ; -- = event_slots means "table empty"

begin

   -- combinational: highest-priority occupied slot overall, ties broken by lowest instance_id
   find_best : process (table_used, table_priority, table_instance_id)
      variable idx     : integer range 0 to event_slots ;
      variable pri      : integer range 0 to 7 ;
      variable inst_id  : integer range 0 to 255 ;
   begin
      idx    := event_slots ;
      pri    := 0 ;
      inst_id := 0 ;
      for i in 0 to event_slots - 1 loop
         if table_used(i) = '1' then
            if idx = event_slots
               or to_integer(unsigned(table_priority(i))) > pri
               or (to_integer(unsigned(table_priority(i))) = pri and to_integer(unsigned(table_instance_id(i))) < inst_id) then
               idx     := i ;
               pri     := to_integer(unsigned(table_priority(i))) ;
               inst_id := to_integer(unsigned(table_instance_id(i))) ;
            end if ;
         end if ;
      end loop ;
      best_index <= idx ;
   end process ;

   process (resetN, clk)
   begin
      if resetN = '0' then
         active_slot   <= event_slots ;
         active_valid  <= '0' ;
         active_index  <= 0 ;
         start_pulse   <= '0' ;
         preempt_pulse <= '0' ;
      elsif rising_edge(clk) then
         start_pulse   <= '0' ; -- one-clock pulses, defaulted low every cycle
         preempt_pulse <= '0' ;

         if reschedule = '1' then
            -- VHDL-93 has no short-circuit "or" - active_slot must be
            -- confirmed a valid index (not the event_slots sentinel)
            -- before table_used(active_slot) is evaluated, so this is a
            -- nested if/elsif rather than a single combined condition.
            if active_slot = event_slots then
               -- never had an active slot - just take the best, if any
               if best_index < event_slots then
                  active_slot  <= best_index ;
                  active_valid <= '1' ;
                  active_index <= best_index ;
                  start_pulse  <= '1' ;
               else
                  active_valid <= '0' ;
               end if ;

            elsif table_used(active_slot) = '0' then
               -- the previously-active slot was released - take the best, if any
               if best_index < event_slots then
                  active_slot  <= best_index ;
                  active_valid <= '1' ;
                  active_index <= best_index ;
                  start_pulse  <= '1' ;
               else
                  active_slot  <= event_slots ;
                  active_valid <= '0' ;
               end if ;

            elsif best_index /= active_slot
                  and to_integer(unsigned(table_priority(best_index))) > to_integer(unsigned(table_priority(active_slot)))
                  and to_integer(unsigned(table_priority(best_index))) >= preempt_threshold then
               -- a strictly-higher-priority, above-threshold candidate exists - preempt
               active_slot   <= best_index ;
               active_index  <= best_index ;
               preempt_pulse <= '1' ;
               -- active_valid stays '1' - still an active event, just switched slots

            end if ;
            -- else: current active slot is still the right choice, nothing changes
         end if ;
      end if ;
   end process ;

end arc_priority_scheduler ;
