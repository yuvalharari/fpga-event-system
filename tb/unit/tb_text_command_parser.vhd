----------------------------------------------------------------
-- tb_text_command_parser : self-checking testbench for         --
-- text_command_parser (spec section 21). Drives line_data/      --
-- line_length/line_ready directly (line_receiver is already     --
-- verified separately) - a focused unit test of just the parser.--
--                                                               --
-- Scenarios:                                                   --
--   1) "EVT,01,03"  -> valid EVT, event_type=0x01, source=0x03  --
--   2) "ACK,17"     -> valid ACK, instance_id=0x17               --
--   3) "XYZ,01,02"  -> unknown command -> error code 02          --
--   4) "EVT,ZZ,03"  -> bad hex in field 1 -> error code 01       --
--   5) "EVT,01,ZZ"  -> bad hex in field 2 -> error code 01       --
--   6) "EVT,01"     -> wrong length for EVT -> some error, no    --
--                       cmd_valid                                --
--   7) "EVT,ab,cd"  -> lowercase hex digits also accepted        --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity tb_text_command_parser is
end tb_text_command_parser ;

architecture sim of tb_text_command_parser is

   constant clk_period        : time     := 20 ns ;
   constant g_max_line_length : positive := 32    ;

   type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0) ;

   function pack_line ( constant bytes : byte_array_t ) return std_logic_vector is
      variable result : std_logic_vector(g_max_line_length*8-1 downto 0) := (others => '0') ;
   begin
      for i in bytes'range loop
         result((i + 1) * 8 - 1 downto i * 8) := bytes(i) ;
      end loop ;
      return result ;
   end function ;

   signal clk         : std_logic := '0' ;
   signal resetN      : std_logic := '0' ;
   signal line_data   : std_logic_vector(g_max_line_length*8-1 downto 0) := (others => '0') ;
   signal line_length : std_logic_vector(7 downto 0) := (others => '0') ;
   signal line_ready  : std_logic := '0' ;

   signal cmd_valid      : std_logic ;
   signal cmd_is_evt     : std_logic ;
   signal cmd_is_ack     : std_logic ;
   signal event_type     : std_logic_vector(7 downto 0) ;
   signal source_id      : std_logic_vector(7 downto 0) ;
   signal instance_id    : std_logic_vector(7 downto 0) ;
   signal cmd_error      : std_logic ;
   signal cmd_error_code : std_logic_vector(7 downto 0) ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.text_command_parser
      generic map ( max_line_length => g_max_line_length )
      port map ( resetN => resetN, clk => clk,
                 line_data => line_data, line_length => line_length, line_ready => line_ready,
                 cmd_valid => cmd_valid, cmd_is_evt => cmd_is_evt, cmd_is_ack => cmd_is_ack,
                 event_type => event_type, source_id => source_id, instance_id => instance_id,
                 cmd_error => cmd_error, cmd_error_code => cmd_error_code ) ;

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

      -- presents a line for one clock and lets the DUT react. cmd_valid/
      -- cmd_error are one-clock pulses, so the check must happen right
      -- after THIS triggering edge settles - not a second edge later,
      -- which is exactly when the DUT clears the pulse back to '0'.
      procedure feed_line ( constant bytes : byte_array_t ) is
      begin
         line_data   <= pack_line(bytes) ;
         line_length <= std_logic_vector(to_unsigned(bytes'length, 8)) ;
         line_ready  <= '1' ;
         wait until rising_edge(clk) ;
         wait for 1 ns ; -- let this edge's registered outputs settle
         line_ready  <= '0' ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      ------------------------------------------------------------
      -- 1) valid EVT
      ------------------------------------------------------------
      feed_line( (x"45", x"56", x"54", x"2C", x"30", x"31", x"2C", x"30", x"33") ) ; -- "EVT,01,03"
      if cmd_valid /= '1' or cmd_is_evt /= '1' or event_type /= x"01" or source_id /= x"03" then
         errors := errors + 1 ;
         report "tb_text_command_parser: FAIL - valid EVT,01,03 not parsed correctly" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 2) valid ACK
      ------------------------------------------------------------
      feed_line( (x"41", x"43", x"4B", x"2C", x"31", x"37") ) ; -- "ACK,17"
      if cmd_valid /= '1' or cmd_is_ack /= '1' or instance_id /= x"17" then
         errors := errors + 1 ;
         report "tb_text_command_parser: FAIL - valid ACK,17 not parsed correctly" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 3) unknown command
      ------------------------------------------------------------
      feed_line( (x"58", x"59", x"5A", x"2C", x"30", x"31", x"2C", x"30", x"32") ) ; -- "XYZ,01,02"
      if cmd_error /= '1' or cmd_error_code /= x"02" or cmd_valid /= '0' then
         errors := errors + 1 ;
         report "tb_text_command_parser: FAIL - unknown command XYZ,01,02 not rejected as error 02" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 4) bad hex in field 1
      ------------------------------------------------------------
      feed_line( (x"45", x"56", x"54", x"2C", x"5A", x"5A", x"2C", x"30", x"33") ) ; -- "EVT,ZZ,03"
      if cmd_error /= '1' or cmd_error_code /= x"01" or cmd_valid /= '0' then
         errors := errors + 1 ;
         report "tb_text_command_parser: FAIL - EVT,ZZ,03 (bad hex field 1) not rejected as error 01" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 5) bad hex in field 2
      ------------------------------------------------------------
      feed_line( (x"45", x"56", x"54", x"2C", x"30", x"31", x"2C", x"5A", x"5A") ) ; -- "EVT,01,ZZ"
      if cmd_error /= '1' or cmd_error_code /= x"01" or cmd_valid /= '0' then
         errors := errors + 1 ;
         report "tb_text_command_parser: FAIL - EVT,01,ZZ (bad hex field 2) not rejected as error 01" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 6) wrong length for EVT
      ------------------------------------------------------------
      feed_line( (x"45", x"56", x"54", x"2C", x"30", x"31") ) ; -- "EVT,01" (6 chars, not 9)
      if cmd_error /= '1' or cmd_valid /= '0' then
         errors := errors + 1 ;
         report "tb_text_command_parser: FAIL - EVT,01 (wrong length) was not rejected" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 7) lowercase hex digits accepted
      ------------------------------------------------------------
      feed_line( (x"45", x"56", x"54", x"2C", x"61", x"62", x"2C", x"63", x"64") ) ; -- "EVT,ab,cd"
      if cmd_valid /= '1' or cmd_is_evt /= '1' or event_type /= x"AB" or source_id /= x"CD" then
         errors := errors + 1 ;
         report "tb_text_command_parser: FAIL - lowercase hex EVT,ab,cd not parsed correctly" severity error ;
      end if ;

      if errors = 0 then
         report "tb_text_command_parser: ALL TESTS PASSED" severity note ;
      else
         report "tb_text_command_parser: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
