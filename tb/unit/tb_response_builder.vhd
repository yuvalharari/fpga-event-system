----------------------------------------------------------------
-- tb_response_builder : self-checking testbench for            --
-- response_builder (spec section 21). Checks every byte of each --
-- formatted response against the expected ASCII text, not just  --
-- a couple of spot checks - the response tables were typed out   --
-- by hand, character by character, so thorough checking matters.--
--                                                               --
-- Scenarios:                                                    --
--   1) build_ack, param=0x17      -> "ACK,INSTANCE=17" (15 chars)--
--   2) build_ack, param=0xAB      -> "ACK,INSTANCE=AB" (hex      --
--      letters, not just digits)                                --
--   3) build_nack_bad_format      -> "NACK,BAD_FORMAT" (15 chars)--
--   4) build_nack_unknown         -> "NACK,UNKNOWN_COMMAND" (20) --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity tb_response_builder is
end tb_response_builder ;

architecture sim of tb_response_builder is

   constant clk_period      : time     := 20 ns ;
   constant g_max_resp_len  : positive := 32    ;

   type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0) ;

   signal clk   : std_logic := '0' ;
   signal resetN : std_logic := '0' ;

   signal build_ack             : std_logic := '0' ;
   signal build_nack_bad_format : std_logic := '0' ;
   signal build_nack_unknown    : std_logic := '0' ;
   signal param_byte            : std_logic_vector(7 downto 0) := (others => '0') ;

   signal resp_data   : std_logic_vector(g_max_resp_len*8-1 downto 0) ;
   signal resp_length : std_logic_vector(7 downto 0) ;
   signal resp_ready  : std_logic ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.response_builder
      generic map ( max_response_length => g_max_resp_len )
      port map ( resetN => resetN, clk => clk,
                 build_ack => build_ack, build_nack_bad_format => build_nack_bad_format,
                 build_nack_unknown => build_nack_unknown, param_byte => param_byte,
                 resp_data => resp_data, resp_length => resp_length, resp_ready => resp_ready ) ;

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

      procedure check_response ( constant expected : byte_array_t ; constant name : string ) is
      begin
         wait for 1 ns ;
         if resp_ready /= '1' then
            errors := errors + 1 ;
            report "tb_response_builder: FAIL - " & name & " - resp_ready did not pulse" severity error ;
            return ;
         end if ;
         if to_integer(unsigned(resp_length)) /= expected'length then
            errors := errors + 1 ;
            report "tb_response_builder: FAIL - " & name & " - wrong resp_length" severity error ;
            return ;
         end if ;
         for i in expected'range loop
            if resp_data((i + 1) * 8 - 1 downto i * 8) /= expected(i) then
               errors := errors + 1 ;
               report "tb_response_builder: FAIL - " & name & " - wrong byte at position " & integer'image(i)
                  severity error ;
            end if ;
         end loop ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      ------------------------------------------------------------
      -- 1) ACK with param 0x17 -> "ACK,INSTANCE=17"
      ------------------------------------------------------------
      param_byte <= x"17" ;
      build_ack  <= '1' ;
      wait until rising_edge(clk) ;
      build_ack  <= '0' ;
      check_response(
         (x"41", x"43", x"4B", x"2C", x"49", x"4E", x"53", x"54",
          x"41", x"4E", x"43", x"45", x"3D", x"31", x"37") ,          -- "ACK,INSTANCE=17"
         "ACK,INSTANCE=17" ) ;

      ------------------------------------------------------------
      -- 2) ACK with param 0xAB -> "ACK,INSTANCE=AB" (hex letters)
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      param_byte <= x"AB" ;
      build_ack  <= '1' ;
      wait until rising_edge(clk) ;
      build_ack  <= '0' ;
      check_response(
         (x"41", x"43", x"4B", x"2C", x"49", x"4E", x"53", x"54",
          x"41", x"4E", x"43", x"45", x"3D", x"41", x"42") ,          -- "ACK,INSTANCE=AB"
         "ACK,INSTANCE=AB" ) ;

      ------------------------------------------------------------
      -- 3) NACK,BAD_FORMAT
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      build_nack_bad_format <= '1' ;
      wait until rising_edge(clk) ;
      build_nack_bad_format <= '0' ;
      check_response(
         (x"4E", x"41", x"43", x"4B", x"2C", x"42", x"41", x"44",
          x"5F", x"46", x"4F", x"52", x"4D", x"41", x"54") ,          -- "NACK,BAD_FORMAT"
         "NACK,BAD_FORMAT" ) ;

      ------------------------------------------------------------
      -- 4) NACK,UNKNOWN_COMMAND
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      build_nack_unknown <= '1' ;
      wait until rising_edge(clk) ;
      build_nack_unknown <= '0' ;
      check_response(
         (x"4E", x"41", x"43", x"4B", x"2C", x"55", x"4E", x"4B",
          x"4E", x"4F", x"57", x"4E", x"5F", x"43", x"4F", x"4D",
          x"4D", x"41", x"4E", x"44") ,                               -- "NACK,UNKNOWN_COMMAND"
         "NACK,UNKNOWN_COMMAND" ) ;

      if errors = 0 then
         report "tb_response_builder: ALL TESTS PASSED" severity note ;
      else
         report "tb_response_builder: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
