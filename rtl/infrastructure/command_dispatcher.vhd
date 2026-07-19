----------------------------------------------------------------
-- command_dispatcher : maps text_command_parser's output to    --
-- the right response_builder request.                          --
--                                                               --
-- EVT commands go through a real allocation request/response    --
-- handshake with event_table_manager (spec section 8.1) - a     --
-- three-state FSM (IDLE / WAIT_ALLOC / WAIT_RELEASE) issues      --
-- alloc_req and waits one cycle for alloc_done, then picks the   --
-- right response: ACK,INSTANCE=<real id> on success,             --
-- NACK,UNKNOWN_EVENT if event_type isn't in the catalog, or      --
-- NACK,TABLE_FULL if there's no free slot (error codes 03/04,    --
-- spec section 16).                                              --
--                                                                --
-- ACK commands now go through a real release request/response    --
-- handshake too (the spec's ack_manager role) - frees the slot   --
-- holding the named instance_id. Success -> ACK,INSTANCE=<id>    --
-- as before; if no slot currently holds that instance_id (wrong  --
-- id, already released, never existed) -> a new, project-defined --
-- NACK,UNKNOWN_INSTANCE (not in the spec's error table, added    --
-- here since silently ACKing a bogus instance in a medical        --
-- monitoring system would give false confidence that something   --
-- was actually acknowledged).                                    --
--                                                               --
-- system_enable gate (spec 14.1 - fixes a real gap found on       --
-- 2026-07-19: system_master_ctrl's system_enable existed but was  --
-- never actually wired anywhere to block new events, so EVT       --
-- commands kept succeeding even while SYSTEM_OFF). Only EVT is    --
-- gated - checked BEFORE alloc_req is issued, so a blocked EVT    --
-- never touches event_table_manager at all (no slot/instance_id   --
-- consumed), matching the spec's event_ingress_arbiter concept.   --
-- ACK is deliberately NOT gated: spec 14.1 says already-active     --
-- events keep running in the background during SYSTEM_OFF, and    --
-- there is no reason an operator shouldn't still be able to        --
-- acknowledge one. Response: NACK,SYSTEM_OFF (project-defined,     --
-- same reasoning as NACK,UNKNOWN_INSTANCE above - the spec never   --
-- names a response text for a rejected-because-OFF event).         --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity command_dispatcher is
   port ( resetN      : in  std_logic                    ;
          clk         : in  std_logic                    ;

          -- from text_command_parser
          cmd_valid      : in  std_logic                    ;
          cmd_is_evt     : in  std_logic                    ;
          cmd_is_ack     : in  std_logic                    ;
          event_type     : in  std_logic_vector(7 downto 0) ;
          source_id      : in  std_logic_vector(7 downto 0) ;
          instance_id    : in  std_logic_vector(7 downto 0) ;
          cmd_error      : in  std_logic                    ;
          cmd_error_code : in  std_logic_vector(7 downto 0) ;

          -- from system_master_ctrl - gates new EVT commands only (see header)
          system_enable  : in  std_logic                    ;

          -- to event_table_manager (allocation request/response)
          alloc_req          : out std_logic                    ;
          alloc_event_type   : out std_logic_vector(7 downto 0) ;
          alloc_source_id    : out std_logic_vector(7 downto 0) ;
          alloc_done         : in  std_logic                    ;
          alloc_ok           : in  std_logic                    ;
          alloc_unknown_type : in  std_logic                    ;
          alloc_instance_id  : in  std_logic_vector(7 downto 0) ;

          -- to event_table_manager (release request/response)
          release_req          : out std_logic                    ;
          release_instance_id  : out std_logic_vector(7 downto 0) ;
          release_done         : in  std_logic                    ;
          release_ok           : in  std_logic                    ;

          -- to response_builder
          build_ack               : out std_logic                    ;
          build_nack_bad_format   : out std_logic                    ;
          build_nack_unknown      : out std_logic                    ;
          build_nack_unknown_evt  : out std_logic                    ;
          build_nack_table_full   : out std_logic                    ;
          build_nack_unknown_inst : out std_logic                    ;
          build_nack_system_off   : out std_logic                    ;
          param_byte              : out std_logic_vector(7 downto 0) ) ;
end command_dispatcher ;

architecture arc_command_dispatcher of command_dispatcher is

   type state_t is (IDLE, WAIT_ALLOC, WAIT_RELEASE) ;
   signal state : state_t ;

begin

   process (resetN, clk)
   begin
      if resetN = '0' then
         state                   <= IDLE ;
         build_ack                <= '0' ;
         build_nack_bad_format    <= '0' ;
         build_nack_unknown       <= '0' ;
         build_nack_unknown_evt   <= '0' ;
         build_nack_table_full    <= '0' ;
         build_nack_unknown_inst  <= '0' ;
         build_nack_system_off    <= '0' ;
         param_byte               <= (others => '0') ;
         alloc_req                <= '0' ;
         alloc_event_type         <= (others => '0') ;
         alloc_source_id          <= (others => '0') ;
         release_req              <= '0' ;
         release_instance_id      <= (others => '0') ;
      elsif rising_edge(clk) then
         -- one-clock pulses, defaulted low every cycle
         build_ack               <= '0' ;
         build_nack_bad_format   <= '0' ;
         build_nack_unknown      <= '0' ;
         build_nack_unknown_evt  <= '0' ;
         build_nack_table_full   <= '0' ;
         build_nack_unknown_inst <= '0' ;
         build_nack_system_off   <= '0' ;
         alloc_req               <= '0' ;
         release_req              <= '0' ;

         case state is

            when IDLE =>
               if cmd_valid = '1' then
                  if cmd_is_evt = '1' then
                     if system_enable = '0' then
                        build_nack_system_off <= '1' ; -- rejected before ever reaching event_table_manager
                     else
                        alloc_event_type <= event_type ;
                        alloc_source_id  <= source_id ;
                        alloc_req        <= '1' ;
                        state            <= WAIT_ALLOC ;
                     end if ;
                  else -- cmd_is_ack
                     release_instance_id <= instance_id ;
                     release_req         <= '1' ;
                     state                <= WAIT_RELEASE ;
                  end if ;

               elsif cmd_error = '1' then
                  if cmd_error_code = x"01" then
                     build_nack_bad_format <= '1' ;
                  elsif cmd_error_code = x"02" then
                     build_nack_unknown <= '1' ;
                  end if ;
               end if ;

            when WAIT_ALLOC =>
               if alloc_done = '1' then
                  if alloc_ok = '1' then
                     build_ack  <= '1' ;
                     param_byte <= alloc_instance_id ;
                  elsif alloc_unknown_type = '1' then
                     build_nack_unknown_evt <= '1' ;
                  else
                     build_nack_table_full <= '1' ;
                  end if ;
                  state <= IDLE ;
               end if ;

            when WAIT_RELEASE =>
               if release_done = '1' then
                  if release_ok = '1' then
                     build_ack  <= '1' ;
                     param_byte <= instance_id ;
                  else
                     build_nack_unknown_inst <= '1' ;
                  end if ;
                  state <= IDLE ;
               end if ;

            when others =>
               state <= IDLE ;

         end case ;
      end if ;
   end process ;

end arc_command_dispatcher ;
