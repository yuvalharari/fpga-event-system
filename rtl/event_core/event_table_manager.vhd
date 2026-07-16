----------------------------------------------------------------
-- event_table_manager : allocates and releases real event        --
-- instances (spec section 7.2/8.1, FSM section 19.2).             --
--                                                                --
-- Reduced initial scope (vertical slice, matching the approach   --
-- used for text_command_parser/command_dispatcher so far):       --
--   - ALLOCATION (SEARCH_FREE -> LOAD_DEFINITION -> WRITE_SLOT -> --
--     RESPOND) and RELEASE (SEARCH by instance_id -> CANCEL_SCAN  --
--     -> RESPOND) are implemented, both collapsed into a single   --
--     clock cycle since event_slots is small enough for a         --
--     combinational search.                                       --
--   - NOT implemented yet: duplicate_detector / MERGE / REPLACE  --
--     / ESCALATE policies, PENDING -> ACTIVE transitions          --
--     (priority_scheduler's job, not built yet), partial          --
--     cancellation of multiple matching instances.                --
--   - release is driven by command_dispatcher on an ACK command   --
--     (spec's ack_manager role) - a release naming an instance_id --
--     that isn't currently occupying any slot (wrong id, already  --
--     released, never existed) fails cleanly (release_ok='0'),    --
--     the table is left untouched.                                --
--   - Only priority/requires_ack are looked up from              --
--     event_definition_rom and returned to the caller so far     --
--     (no full per-slot record storage yet beyond instance_id -   --
--     event_type/source_id/state etc. will be added once a       --
--     block actually needs to query them, e.g. priority_         --
--     scheduler).                                                 --
--   - instance_id is a free-running 8-bit counter (spec 8.1:     --
--     "הקצאת מזהה מופע 8-סיביות הבא"), not tied to slot index -   --
--     matches the "oldest_instance_id" tie-break rule (8.2),      --
--     which needs monotonically increasing ids.                  --
--   - a request naming an event_type not in event_definition_rom  --
--     is rejected outright (alloc_ok='0', alloc_unknown_type=     --
--     '1') without touching the table at all - checked before     --
--     the free-slot search, so it never consumes a slot or an     --
--     instance_id.                                                --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity event_table_manager is
   generic ( event_slots : positive := 8 ) ;
   port ( resetN             : in  std_logic                    ;
          clk                : in  std_logic                    ;

          -- allocation request (one-clock pulse, e.g. from command_dispatcher on a valid EVT command)
          alloc_req          : in  std_logic                    ;
          event_type         : in  std_logic_vector(7 downto 0) ;
          source_id          : in  std_logic_vector(7 downto 0) ;

          -- allocation response (one-clock pulse)
          alloc_done         : out std_logic                    ;
          alloc_ok           : out std_logic                    ; -- '1' success
          alloc_unknown_type : out std_logic                    ; -- '1' when failed because event_type isn't recognized (only meaningful when alloc_ok='0')
          alloc_instance_id  : out std_logic_vector(7 downto 0) ; -- valid when alloc_ok='1'
          alloc_priority     : out std_logic_vector(2 downto 0) ; -- valid when alloc_ok='1'
          alloc_requires_ack : out std_logic                    ; -- valid when alloc_ok='1'

          -- release request (one-clock pulse, e.g. from command_dispatcher on a valid ACK command)
          release_req         : in  std_logic                    ;
          release_instance_id : in  std_logic_vector(7 downto 0) ;

          -- release response (one-clock pulse)
          release_done       : out std_logic                    ;
          release_ok         : out std_logic                     ) ; -- '1' = a matching slot was found and freed, '0' = no such instance
end event_table_manager ;

architecture arc_event_table_manager of event_table_manager is

   component event_definition_rom
      port ( event_type   : in  std_logic_vector(7 downto 0) ;
             priority     : out std_logic_vector(2 downto 0) ;
             requires_ack : out std_logic                    ;
             type_valid   : out std_logic                    ) ;
   end component ;

   type instance_id_array_t is array (0 to event_slots - 1) of std_logic_vector(7 downto 0) ;

   signal slot_used         : std_logic_vector(0 to event_slots - 1) ;
   signal slot_instance_id  : instance_id_array_t ;
   signal next_instance_id  : unsigned(7 downto 0) ;

   signal rom_priority      : std_logic_vector(2 downto 0) ;
   signal rom_requires_ack  : std_logic ;
   signal rom_type_valid    : std_logic ;

   signal free_index        : integer range 0 to event_slots ; -- = event_slots means "table full"
   signal match_index       : integer range 0 to event_slots ; -- = event_slots means "no such instance"

begin

   u_rom : event_definition_rom
      port map ( event_type => event_type, priority => rom_priority,
                 requires_ack => rom_requires_ack, type_valid => rom_type_valid ) ;

   -- combinational first-free-slot search (small table, fits in one cycle)
   find_free : process (slot_used)
      variable idx : integer range 0 to event_slots ;
   begin
      idx := event_slots ;
      for i in 0 to event_slots - 1 loop
         if slot_used(i) = '0' and idx = event_slots then
            idx := i ;
         end if ;
      end loop ;
      free_index <= idx ;
   end process ;

   -- combinational search for the (at most one) used slot holding release_instance_id
   find_match : process (slot_used, slot_instance_id, release_instance_id)
      variable idx : integer range 0 to event_slots ;
   begin
      idx := event_slots ;
      for i in 0 to event_slots - 1 loop
         if slot_used(i) = '1' and slot_instance_id(i) = release_instance_id and idx = event_slots then
            idx := i ;
         end if ;
      end loop ;
      match_index <= idx ;
   end process ;

   process (resetN, clk)
   begin
      if resetN = '0' then
         slot_used          <= (others => '0') ;
         next_instance_id   <= (others => '0') ;
         alloc_done         <= '0' ;
         alloc_ok           <= '0' ;
         alloc_unknown_type <= '0' ;
         alloc_instance_id  <= (others => '0') ;
         alloc_priority     <= (others => '0') ;
         alloc_requires_ack <= '0' ;
         release_done       <= '0' ;
         release_ok         <= '0' ;
      elsif rising_edge(clk) then
         alloc_done   <= '0' ; -- one-clock pulses, defaulted low every cycle
         release_done <= '0' ;

         if alloc_req = '1' then
            alloc_done <= '1' ;
            if rom_type_valid = '0' then
               alloc_ok           <= '0' ;
               alloc_unknown_type <= '1' ; -- rejected outright, table untouched
            elsif free_index < event_slots then
               slot_used(free_index)        <= '1' ;
               slot_instance_id(free_index) <= std_logic_vector(next_instance_id) ;
               alloc_ok                     <= '1' ;
               alloc_unknown_type           <= '0' ;
               alloc_instance_id            <= std_logic_vector(next_instance_id) ;
               alloc_priority                <= rom_priority ;
               alloc_requires_ack            <= rom_requires_ack ;
               next_instance_id              <= next_instance_id + 1 ;
            else
               alloc_ok           <= '0' ; -- table full
               alloc_unknown_type <= '0' ;
            end if ;
         end if ;

         if release_req = '1' then
            release_done <= '1' ;
            if match_index < event_slots then
               slot_used(match_index) <= '0' ;
               release_ok              <= '1' ;
            else
               release_ok <= '0' ; -- no slot currently holds this instance_id
            end if ;
         end if ;
      end if ;
   end process ;

end arc_event_table_manager ;
