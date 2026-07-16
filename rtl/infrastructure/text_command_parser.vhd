----------------------------------------------------------------
-- text_command_parser : tokenizes and validates ASCII commands --
-- from a complete line (spec section 17, section 10.1 protocol, --
-- section 19.1 parser FSM).                                     --
--                                                               --
-- Reduced initial scope (vertical slice, spec section 3.3):     --
-- only the two most basic commands are supported so far -      --
--   EVT,<type>,<source>   e.g. "EVT,01,03"  (9 chars, fixed)    --
--   ACK,<instance>        e.g. "ACK,17"     (6 chars, fixed)    --
-- both hex byte fields. A general tokenizer for the full 12-    --
-- command protocol (SCHED, PERIODIC, CANCEL, STATUS, ...) will  --
-- replace this once the basic path is proven end to end.        --
--                                                               --
-- Errors reported (spec section 16 error table):                --
--   01 = bad format (wrong length, missing comma, bad hex digit)--
--   02 = unknown command name                                   --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity text_command_parser is
   generic ( max_line_length : positive := 32 ) ;
   port ( resetN      : in  std_logic                                      ;
          clk         : in  std_logic                                      ;
          line_data   : in  std_logic_vector(max_line_length*8-1 downto 0) ;
          line_length : in  std_logic_vector(7 downto 0)                   ;
          line_ready  : in  std_logic                                      ;

          cmd_valid   : out std_logic                    ; -- one-clock pulse: a command was parsed OK
          cmd_is_evt  : out std_logic                    ; -- qualifies event_type/source_id, valid with cmd_valid
          cmd_is_ack  : out std_logic                    ; -- qualifies instance_id, valid with cmd_valid
          event_type  : out std_logic_vector(7 downto 0) ;
          source_id   : out std_logic_vector(7 downto 0) ;
          instance_id : out std_logic_vector(7 downto 0) ;

          cmd_error      : out std_logic                    ; -- one-clock pulse: the line did not parse
          cmd_error_code : out std_logic_vector(7 downto 0) ) ;
end text_command_parser ;

architecture arc_text_command_parser of text_command_parser is

   -- extracts byte i (0 = first character of the line) from a flattened line
   function get_byte ( constant d : std_logic_vector ; constant i : natural ) return std_logic_vector is
   begin
      return d((i + 1) * 8 - 1 downto i * 8) ;
   end function ;

   -- decodes one ASCII hex digit: result(4)='1' if it was a valid hex
   -- digit, result(3 downto 0) is its nibble value
   function hex_nibble ( constant c : std_logic_vector(7 downto 0) ) return std_logic_vector is
      constant ch_0     : std_logic_vector(7 downto 0) := x"30" ;
      constant ch_9     : std_logic_vector(7 downto 0) := x"39" ;
      constant ch_upperA : std_logic_vector(7 downto 0) := x"41" ;
      constant ch_upperF : std_logic_vector(7 downto 0) := x"46" ;
      constant ch_lowerA : std_logic_vector(7 downto 0) := x"61" ;
      constant ch_lowerF : std_logic_vector(7 downto 0) := x"66" ;
      variable n : unsigned(3 downto 0) ;
   begin
      if unsigned(c) >= unsigned(ch_0) and unsigned(c) <= unsigned(ch_9) then
         n := unsigned(c(3 downto 0)) ;
         return '1' & std_logic_vector(n) ;
      elsif unsigned(c) >= unsigned(ch_upperA) and unsigned(c) <= unsigned(ch_upperF) then
         n := unsigned(c(3 downto 0)) + 9 ;
         return '1' & std_logic_vector(n) ;
      elsif unsigned(c) >= unsigned(ch_lowerA) and unsigned(c) <= unsigned(ch_lowerF) then
         n := unsigned(c(3 downto 0)) + 9 ;
         return '1' & std_logic_vector(n) ;
      else
         return "00000" ;
      end if ;
   end function ;

   constant CH_COMMA : std_logic_vector(7 downto 0) := x"2C" ;

begin

   process (resetN, clk)
      variable len            : integer range 0 to max_line_length ;
      variable is_evt, is_ack : boolean ;
      variable n1, n2         : std_logic_vector(4 downto 0) ;
      variable byte1, byte2   : std_logic_vector(7 downto 0) ;
      variable ok             : boolean ;
   begin
      if resetN = '0' then
         cmd_valid      <= '0' ;
         cmd_is_evt     <= '0' ;
         cmd_is_ack     <= '0' ;
         event_type     <= (others => '0') ;
         source_id      <= (others => '0') ;
         instance_id    <= (others => '0') ;
         cmd_error      <= '0' ;
         cmd_error_code <= (others => '0') ;
      elsif rising_edge(clk) then
         -- one-clock pulses, defaulted low every cycle
         cmd_valid  <= '0' ;
         cmd_is_evt <= '0' ;
         cmd_is_ack <= '0' ;
         cmd_error  <= '0' ;

         if line_ready = '1' then
            len := to_integer(unsigned(line_length)) ;

            is_evt := (len = 9)
                  and (get_byte(line_data, 0) = x"45")   -- 'E'
                  and (get_byte(line_data, 1) = x"56")   -- 'V'
                  and (get_byte(line_data, 2) = x"54")   -- 'T'
                  and (get_byte(line_data, 3) = CH_COMMA)
                  and (get_byte(line_data, 6) = CH_COMMA) ;

            is_ack := (len = 6)
                  and (get_byte(line_data, 0) = x"41")   -- 'A'
                  and (get_byte(line_data, 1) = x"43")   -- 'C'
                  and (get_byte(line_data, 2) = x"4B")   -- 'K'
                  and (get_byte(line_data, 3) = CH_COMMA) ;

            if is_evt then
               n1 := hex_nibble(get_byte(line_data, 4)) ;
               n2 := hex_nibble(get_byte(line_data, 5)) ;
               byte1 := n1(3 downto 0) & n2(3 downto 0) ;
               ok := (n1(4) = '1') and (n2(4) = '1') ;

               n1 := hex_nibble(get_byte(line_data, 7)) ;
               n2 := hex_nibble(get_byte(line_data, 8)) ;
               byte2 := n1(3 downto 0) & n2(3 downto 0) ;
               ok := ok and (n1(4) = '1') and (n2(4) = '1') ;

               if ok then
                  cmd_valid  <= '1' ;
                  cmd_is_evt <= '1' ;
                  event_type <= byte1 ;
                  source_id  <= byte2 ;
               else
                  cmd_error      <= '1' ;
                  cmd_error_code <= x"01" ; -- bad format
               end if ;

            elsif is_ack then
               n1 := hex_nibble(get_byte(line_data, 4)) ;
               n2 := hex_nibble(get_byte(line_data, 5)) ;
               byte1 := n1(3 downto 0) & n2(3 downto 0) ;
               ok := (n1(4) = '1') and (n2(4) = '1') ;

               if ok then
                  cmd_valid   <= '1' ;
                  cmd_is_ack  <= '1' ;
                  instance_id <= byte1 ;
               else
                  cmd_error      <= '1' ;
                  cmd_error_code <= x"01" ; -- bad format
               end if ;

            else
               cmd_error      <= '1' ;
               cmd_error_code <= x"02" ; -- unknown command
            end if ;
         end if ;
      end if ;
   end process ;

end arc_text_command_parser ;
