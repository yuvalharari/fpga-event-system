----------------------------------------------------------------
-- command_dispatcher : maps text_command_parser's output to    --
-- the right response_builder request.                          --
--                                                               --
-- Reduced scope note: a successful EVT reports back the source  --
-- id as a placeholder "instance" (we don't have a real           --
-- event_table_manager yet to allocate an actual instance id) -  --
-- a successful ACK correctly reports the real instance id it    --
-- named. This will be corrected once event_table_manager exists.--
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
          source_id      : in  std_logic_vector(7 downto 0) ;
          instance_id    : in  std_logic_vector(7 downto 0) ;
          cmd_error      : in  std_logic                    ;
          cmd_error_code : in  std_logic_vector(7 downto 0) ;

          -- to response_builder
          build_ack              : out std_logic                    ;
          build_nack_bad_format  : out std_logic                    ;
          build_nack_unknown     : out std_logic                    ;
          param_byte             : out std_logic_vector(7 downto 0) ) ;
end command_dispatcher ;

architecture arc_command_dispatcher of command_dispatcher is
begin

   process (resetN, clk)
   begin
      if resetN = '0' then
         build_ack             <= '0' ;
         build_nack_bad_format <= '0' ;
         build_nack_unknown    <= '0' ;
         param_byte             <= (others => '0') ;
      elsif rising_edge(clk) then
         -- one-clock pulses, defaulted low every cycle
         build_ack             <= '0' ;
         build_nack_bad_format <= '0' ;
         build_nack_unknown    <= '0' ;

         if cmd_valid = '1' then
            build_ack <= '1' ;
            if cmd_is_evt = '1' then
               param_byte <= source_id ;   -- placeholder until event_table_manager exists
            else -- cmd_is_ack
               param_byte <= instance_id ;
            end if ;

         elsif cmd_error = '1' then
            if cmd_error_code = x"01" then
               build_nack_bad_format <= '1' ;
            elsif cmd_error_code = x"02" then
               build_nack_unknown <= '1' ;
            end if ;
         end if ;
      end if ;
   end process ;

end arc_command_dispatcher ;
