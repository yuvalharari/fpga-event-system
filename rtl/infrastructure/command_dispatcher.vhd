----------------------------------------------------------------
-- command_dispatcher : maps text_command_parser's output to    --
-- the right response_builder request.                          --
--                                                               --
-- ACK commands are still answered directly, in one cycle, as    --
-- before. EVT commands now go through a real allocation         --
-- request/response handshake with event_table_manager (spec     --
-- section 8.1) instead of using source_id as a placeholder      --
-- instance id - a small two-state FSM (IDLE / WAIT_ALLOC) issues --
-- alloc_req and waits one cycle for alloc_done, then picks the   --
-- right response: ACK,INSTANCE=<real id> on success,             --
-- NACK,UNKNOWN_EVENT if event_type isn't in the catalog, or      --
-- NACK,TABLE_FULL if there's no free slot (error codes 03/04,    --
-- spec section 16).                                              --
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

          -- to event_table_manager (allocation request/response)
          alloc_req          : out std_logic                    ;
          alloc_event_type   : out std_logic_vector(7 downto 0) ;
          alloc_source_id    : out std_logic_vector(7 downto 0) ;
          alloc_done         : in  std_logic                    ;
          alloc_ok           : in  std_logic                    ;
          alloc_unknown_type : in  std_logic                    ;
          alloc_instance_id  : in  std_logic_vector(7 downto 0) ;

          -- to response_builder
          build_ack              : out std_logic                    ;
          build_nack_bad_format  : out std_logic                    ;
          build_nack_unknown     : out std_logic                    ;
          build_nack_unknown_evt : out std_logic                    ;
          build_nack_table_full  : out std_logic                    ;
          param_byte             : out std_logic_vector(7 downto 0) ) ;
end command_dispatcher ;

architecture arc_command_dispatcher of command_dispatcher is

   type state_t is (IDLE, WAIT_ALLOC) ;
   signal state : state_t ;

begin

   process (resetN, clk)
   begin
      if resetN = '0' then
         state                  <= IDLE ;
         build_ack               <= '0' ;
         build_nack_bad_format   <= '0' ;
         build_nack_unknown      <= '0' ;
         build_nack_unknown_evt  <= '0' ;
         build_nack_table_full   <= '0' ;
         param_byte              <= (others => '0') ;
         alloc_req               <= '0' ;
         alloc_event_type        <= (others => '0') ;
         alloc_source_id         <= (others => '0') ;
      elsif rising_edge(clk) then
         -- one-clock pulses, defaulted low every cycle
         build_ack              <= '0' ;
         build_nack_bad_format  <= '0' ;
         build_nack_unknown     <= '0' ;
         build_nack_unknown_evt <= '0' ;
         build_nack_table_full  <= '0' ;
         alloc_req              <= '0' ;

         case state is

            when IDLE =>
               if cmd_valid = '1' then
                  if cmd_is_evt = '1' then
                     alloc_event_type <= event_type ;
                     alloc_source_id  <= source_id ;
                     alloc_req        <= '1' ;
                     state            <= WAIT_ALLOC ;
                  else -- cmd_is_ack
                     build_ack  <= '1' ;
                     param_byte <= instance_id ;
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

            when others =>
               state <= IDLE ;

         end case ;
      end if ;
   end process ;

end arc_command_dispatcher ;
