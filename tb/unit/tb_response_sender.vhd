----------------------------------------------------------------
-- tb_response_sender : self-checking testbench for              --
-- response_sender (spec section 21). Uses a mock tx_ready        --
-- generator (goes busy for a few clocks after every              --
-- tx_write_din pulse, mimicking a real uart_tx without needing   --
-- real baud timing - uart_tx itself is already verified          --
-- separately) and captures every (tx_din, on tx_write_din pulse) --
-- into a buffer to compare against the expected byte sequence.   --
--                                                               --
-- Scenarios:                                                    --
--   1) a short 2-byte response -> captured sequence must be      --
--      exactly those 2 bytes followed by CR, LF (4 total)        --
--   2) a 20-byte response (matching NACK,UNKNOWN_COMMAND's        --
--      length) -> all 20 bytes + CR + LF (22 total), in order    --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity tb_response_sender is
end tb_response_sender ;

architecture sim of tb_response_sender is

   constant clk_period     : time     := 20 ns ;
   constant g_max_resp_len : positive := 32    ;

   type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0) ;

   function pack_line ( constant bytes : byte_array_t ) return std_logic_vector is
      variable result : std_logic_vector(g_max_resp_len*8-1 downto 0) := (others => '0') ;
   begin
      for i in bytes'range loop
         result((i + 1) * 8 - 1 downto i * 8) := bytes(i) ;
      end loop ;
      return result ;
   end function ;

   signal clk         : std_logic := '0' ;
   signal resetN      : std_logic := '0' ;
   signal resp_data   : std_logic_vector(g_max_resp_len*8-1 downto 0) := (others => '0') ;
   signal resp_length : std_logic_vector(7 downto 0) := (others => '0') ;
   signal resp_ready  : std_logic := '0' ;
   signal tx_din       : std_logic_vector(7 downto 0) ;
   signal tx_write_din : std_logic ;
   signal tx_ready     : std_logic ;

   -- mock tx_ready: goes busy for a few clocks after every tx_write_din pulse
   signal busy_count : integer range 0 to 5 := 0 ;

   -- capture buffer: records every byte sent, in order
   type capture_array_t is array (0 to 39) of std_logic_vector(7 downto 0) ;
   signal captured     : capture_array_t ;
   signal capture_idx  : integer range 0 to 40 := 0 ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.response_sender
      generic map ( max_response_length => g_max_resp_len )
      port map ( resetN => resetN, clk => clk,
                 resp_data => resp_data, resp_length => resp_length, resp_ready => resp_ready,
                 tx_din => tx_din, tx_write_din => tx_write_din, tx_ready => tx_ready ) ;

   clk_gen : process
   begin
      while not sim_done loop
         wait for clk_period / 2 ;
         clk <= not clk ;
      end loop ;
      wait ;
   end process ;

   tx_ready <= '1' when busy_count = 0 else '0' ;

   process (resetN, clk)
   begin
      if resetN = '0' then
         busy_count <= 0 ;
      elsif rising_edge(clk) then
         if tx_write_din = '1' then
            busy_count <= 3 ;
         elsif busy_count > 0 then
            busy_count <= busy_count - 1 ;
         end if ;
      end if ;
   end process ;

   process (resetN, clk)
   begin
      if resetN = '0' then
         capture_idx <= 0 ;
      elsif rising_edge(clk) then
         if tx_write_din = '1' and capture_idx < 40 then
            captured(capture_idx) <= tx_din ;
            capture_idx           <= capture_idx + 1 ;
         end if ;
      end if ;
   end process ;

   check : process
      variable errors : natural := 0 ;

      procedure expect_sequence ( constant bytes : byte_array_t ; constant name : string ) is
         constant expect_count : natural := bytes'length + 2 ; -- + CR + LF
         variable start_idx    : natural ;
      begin
         start_idx := capture_idx ;
         resp_data   <= pack_line(bytes) ;
         resp_length <= std_logic_vector(to_unsigned(bytes'length, 8)) ;
         resp_ready  <= '1' ;
         wait until rising_edge(clk) ;
         resp_ready  <= '0' ;

         -- wait until expect_count more bytes have been captured (generous timeout)
         for i in 1 to 500 loop
            wait until rising_edge(clk) ;
            exit when (capture_idx - start_idx) >= expect_count ;
         end loop ;
         wait for 1 ns ;

         if (capture_idx - start_idx) /= expect_count then
            errors := errors + 1 ;
            report "tb_response_sender: FAIL - " & name & " - wrong number of bytes captured" severity error ;
            return ;
         end if ;

         for i in bytes'range loop
            if captured(start_idx + i) /= bytes(i) then
               errors := errors + 1 ;
               report "tb_response_sender: FAIL - " & name & " - wrong byte at position " & integer'image(i)
                  severity error ;
            end if ;
         end loop ;
         if captured(start_idx + bytes'length) /= x"0D" then
            errors := errors + 1 ;
            report "tb_response_sender: FAIL - " & name & " - missing/wrong CR terminator" severity error ;
         end if ;
         if captured(start_idx + bytes'length + 1) /= x"0A" then
            errors := errors + 1 ;
            report "tb_response_sender: FAIL - " & name & " - missing/wrong LF terminator" severity error ;
         end if ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      ------------------------------------------------------------
      -- 1) short response
      ------------------------------------------------------------
      expect_sequence( (x"41", x"42") , "short 2-byte response" ) ; -- "AB"

      ------------------------------------------------------------
      -- 2) a 20-byte response, matching NACK,UNKNOWN_COMMAND's length
      ------------------------------------------------------------
      expect_sequence(
         (x"4E", x"41", x"43", x"4B", x"2C", x"55", x"4E", x"4B",
          x"4E", x"4F", x"57", x"4E", x"5F", x"43", x"4F", x"4D",
          x"4D", x"41", x"4E", x"44") ,
         "20-byte response" ) ;

      if errors = 0 then
         report "tb_response_sender: ALL TESTS PASSED" severity note ;
      else
         report "tb_response_sender: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
