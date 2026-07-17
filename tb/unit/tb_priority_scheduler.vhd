----------------------------------------------------------------
-- tb_priority_scheduler : self-checking testbench for           --
-- priority_scheduler (spec section 8.2, reduced scope - see the --
-- DUT's own header). Drives a mock table directly (table_used/   --
-- table_priority/table_instance_id) rather than a real            --
-- event_table_manager - this block doesn't write back to the     --
-- table, it only reads a snapshot, so a direct mock is enough    --
-- and keeps the scenarios easy to control precisely.             --
--                                                               --
-- Scenarios (default generics: event_slots=8, preempt_threshold=7):--
--   1) empty table -> active_valid='0'                           --
--   2) two slots at the SAME priority (3), different              --
--      instance_id -> the LOWER instance_id wins the tie          --
--      (oldest, spec 8.2)                                         --
--   3) add a lower-priority slot (1) -> no change                --
--   4) add a higher-priority slot (6) but BELOW the threshold (7) --
--      -> no change (doesn't qualify to preempt)                 --
--   5) add a priority-7 slot -> PREEMPTS (meets threshold AND     --
--      strictly higher)                                           --
--   6) release the active (priority-7) slot -> falls back to the --
--      next-highest remaining slot (priority 6) - a fresh start, --
--      not a preempt                                              --
--   7) release everything -> active_valid='0' again               --
--   8) reschedule again on an still-empty table -> idempotent,    --
--      no spurious pulses                                         --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;
use work.event_system_pkg.all ;

entity tb_priority_scheduler is
end tb_priority_scheduler ;

architecture sim of tb_priority_scheduler is

   constant clk_period  : time     := 20 ns ;
   constant g_slots      : positive := 8 ;
   constant g_threshold  : natural  := 7 ;

   signal clk    : std_logic := '0' ;
   signal resetN : std_logic := '0' ;

   signal reschedule : std_logic := '0' ;

   signal table_used        : std_logic_vector(0 to g_slots - 1) := (others => '0') ;
   signal table_priority    : priority_array_t(0 to g_slots - 1) := (others => (others => '0')) ;
   signal table_instance_id : instance_id_array_t(0 to g_slots - 1) := (others => (others => '0')) ;

   signal active_valid  : std_logic ;
   signal active_index  : integer range 0 to g_slots - 1 ;
   signal start_pulse   : std_logic ;
   signal preempt_pulse : std_logic ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.priority_scheduler
      generic map ( event_slots => g_slots, preempt_threshold => g_threshold )
      port map ( resetN => resetN, clk => clk,
                 reschedule => reschedule,
                 table_used => table_used, table_priority => table_priority, table_instance_id => table_instance_id,
                 active_valid => active_valid, active_index => active_index,
                 start_pulse => start_pulse, preempt_pulse => preempt_pulse ) ;

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

      procedure set_slot ( constant i : natural ; constant pri : natural ; constant id : natural ) is
      begin
         table_used(i)        <= '1' ;
         table_priority(i)    <= std_logic_vector(to_unsigned(pri, 3)) ;
         table_instance_id(i) <= std_logic_vector(to_unsigned(id, 8)) ;
      end procedure ;

      procedure clear_slot ( constant i : natural ) is
      begin
         table_used(i) <= '0' ;
      end procedure ;

      procedure do_reschedule is
      begin
         reschedule <= '1' ;
         wait until rising_edge(clk) ;
         wait for 1 ns ; -- let this edge's registered outputs settle
         reschedule <= '0' ;
      end procedure ;

      procedure expect ( constant exp_valid   : std_logic ;
                          constant exp_index   : natural ;
                          constant exp_start   : std_logic ;
                          constant exp_preempt : std_logic ;
                          constant name        : string ) is
      begin
         if active_valid /= exp_valid then
            errors := errors + 1 ;
            report "tb_priority_scheduler: FAIL - " & name & " - wrong active_valid" severity error ;
         end if ;
         if exp_valid = '1' and active_index /= exp_index then
            errors := errors + 1 ;
            report "tb_priority_scheduler: FAIL - " & name & " - wrong active_index" severity error ;
         end if ;
         if start_pulse /= exp_start then
            errors := errors + 1 ;
            report "tb_priority_scheduler: FAIL - " & name & " - wrong start_pulse" severity error ;
         end if ;
         if preempt_pulse /= exp_preempt then
            errors := errors + 1 ;
            report "tb_priority_scheduler: FAIL - " & name & " - wrong preempt_pulse" severity error ;
         end if ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      ------------------------------------------------------------
      -- 1) empty table
      ------------------------------------------------------------
      do_reschedule ;
      expect( '0', 0, '0', '0', "1) empty table" ) ;

      ------------------------------------------------------------
      -- 2) two same-priority slots - lower instance_id wins the tie
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      set_slot( 0, 3, 5 ) ; -- priority 3, instance_id=5
      set_slot( 1, 3, 2 ) ; -- priority 3, instance_id=2 (older - should win)
      do_reschedule ;
      expect( '1', 1, '1', '0', "2) tie broken by lowest instance_id" ) ;

      ------------------------------------------------------------
      -- 3) add a lower-priority slot - no change
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      set_slot( 2, 1, 3 ) ;
      do_reschedule ;
      expect( '1', 1, '0', '0', "3) lower-priority arrival does not preempt" ) ;

      ------------------------------------------------------------
      -- 4) add a higher-priority slot, but below threshold - no change
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      set_slot( 3, 6, 4 ) ;
      do_reschedule ;
      expect( '1', 1, '0', '0', "4) higher priority but below preempt_threshold does not preempt" ) ;

      ------------------------------------------------------------
      -- 5) add a priority-7 slot - preempts
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      set_slot( 4, 7, 9 ) ;
      do_reschedule ;
      expect( '1', 4, '0', '1', "5) priority 7 preempts" ) ;

      ------------------------------------------------------------
      -- 6) release the active slot - falls back to next-highest (slot 3, pri 6)
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      clear_slot( 4 ) ;
      do_reschedule ;
      expect( '1', 3, '1', '0', "6) release of active falls back to next-highest remaining" ) ;

      ------------------------------------------------------------
      -- 7) release everything - back to no active
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      clear_slot( 0 ) ;
      clear_slot( 1 ) ;
      clear_slot( 2 ) ;
      clear_slot( 3 ) ;
      do_reschedule ;
      expect( '0', 0, '0', '0', "7) release everything - back to no active, no pulse (nothing to start)" ) ;

      ------------------------------------------------------------
      -- 8) reschedule again on an empty table - idempotent
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      do_reschedule ;
      expect( '0', 0, '0', '0', "8) reschedule on empty table again - no spurious pulses" ) ;

      if errors = 0 then
         report "tb_priority_scheduler: ALL TESTS PASSED" severity note ;
      else
         report "tb_priority_scheduler: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
