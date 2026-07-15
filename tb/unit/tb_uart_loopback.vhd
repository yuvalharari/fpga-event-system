----------------------------------------------------------------
-- tb_uart_loopback : self-checking testbench for uart_tx +     --
-- uart_rx together (spec section 21, tb_uart_rx_tx), wired in  --
-- a direct loopback (tx output -> rx input).                   --
--                                                               --
-- clk_hz/baud_rate are overridden (5000/100 -> 50 clocks/bit)  --
-- for a fast simulation of the same relative timing as the real--
-- 50MHz/9600baud (~5208 clocks/bit) case.                       --
--                                                               --
-- Sends 4 bytes back-to-back through the loopback and checks,  --
-- for each: the receiver reports data_valid, the received byte --
-- matches exactly, dout_ready asserts and then clears correctly--
-- after being acknowledged with read_dout. Bytes chosen to      --
-- stress every bit transition (0x55, 0xA3) and both edge cases  --
-- (0x00, 0xFF).                                                 --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity tb_uart_loopback is
end tb_uart_loopback ;

architecture sim of tb_uart_loopback is

   constant clk_period   : time    := 20 ns ;
   constant g_clk_hz     : integer := 5000  ;
   constant g_baud_rate  : integer := 100   ; -- -> 50 clocks/bit
   constant byte_timeout : natural := 1000  ; -- clocks, comfortably > one full byte (~500-550)

   signal clk    : std_logic := '0' ;
   signal resetN : std_logic := '0' ;

   -- TX side
   signal tx_din       : std_logic_vector(7 downto 0) := (others => '0') ;
   signal tx_write_din : std_logic := '0' ;
   signal tx_line      : std_logic ; -- serial line, looped back to RX
   signal tx_ready     : std_logic ;

   -- RX side
   signal rx_read_dout  : std_logic := '0' ;
   signal rx_data_valid : std_logic ;
   signal rx_dout       : std_logic_vector(7 downto 0) ;
   signal rx_dout_ready : std_logic ;

   signal sim_done : boolean := false ;

begin

   u_tx : entity work.uart_tx
      generic map ( clk_hz => g_clk_hz, baud_rate => g_baud_rate )
      port map ( resetN => resetN, clk => clk, din => tx_din, write_din => tx_write_din,
                 tx => tx_line, tx_ready => tx_ready ) ;

   u_rx : entity work.uart_rx
      generic map ( clk_hz => g_clk_hz, baud_rate => g_baud_rate )
      port map ( resetN => resetN, clk => clk, rx => tx_line, read_dout => rx_read_dout,
                 data_valid => rx_data_valid, dout => rx_dout, dout_ready => rx_dout_ready ) ;

   clk_gen : process
   begin
      while not sim_done loop
         wait for clk_period / 2 ;
         clk <= not clk ;
      end loop ;
      wait ;
   end process ;

   stim_and_check : process
      variable errors : natural := 0 ;

      -- sends one byte on the TX side once it reports ready
      procedure send_byte ( constant b : std_logic_vector(7 downto 0) ) is
      begin
         wait until rising_edge(clk) and tx_ready = '1' ;
         tx_din       <= b   ;
         tx_write_din <= '1' ;
         wait until rising_edge(clk) ;
         tx_write_din <= '0' ;
      end procedure ;

      -- waits (with a timeout) for the receiver to report a new byte, then
      -- checks its value and the dout_ready handshake, then acknowledges it
      procedure expect_byte ( constant expected : std_logic_vector(7 downto 0) ;
                               constant name     : string ) is
         variable timed_out : boolean := true ;
      begin
         for i in 1 to byte_timeout loop
            wait until rising_edge(clk) ;
            if rx_data_valid = '1' then
               timed_out := false ;
               exit ;
            end if ;
         end loop ;

         if timed_out then
            errors := errors + 1 ;
            report "tb_uart_loopback: FAIL - " & name & " - timed out waiting for data_valid"
               severity error ;
         else
            wait for 1 ns ;
            if rx_dout /= expected then
               errors := errors + 1 ;
               report "tb_uart_loopback: FAIL - " & name & " - received byte does not match what was sent"
                  severity error ;
            end if ;
            if rx_dout_ready /= '1' then
               errors := errors + 1 ;
               report "tb_uart_loopback: FAIL - " & name & " - dout_ready not asserted after data_valid"
                  severity error ;
            end if ;

            -- acknowledge the byte
            rx_read_dout <= '1' ;
            wait until rising_edge(clk) ;
            rx_read_dout <= '0' ;
            wait until rising_edge(clk) ;
            wait for 1 ns ;
            if rx_dout_ready /= '0' then
               errors := errors + 1 ;
               report "tb_uart_loopback: FAIL - " & name & " - dout_ready did not clear after read_dout"
                  severity error ;
            end if ;
         end if ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 5 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      -- 1) alternating bit pattern - stresses every bit transition
      send_byte("01010101") ;
      expect_byte("01010101", "byte 1 (0x55)") ;

      -- 2) a different pattern, sent immediately after (back-to-back)
      send_byte("10100011") ;
      expect_byte("10100011", "byte 2 (0xA3, back-to-back)") ;

      -- 3) edge cases: all-zero and all-one data bytes
      send_byte("00000000") ;
      expect_byte("00000000", "byte 3 (0x00)") ;

      send_byte("11111111") ;
      expect_byte("11111111", "byte 4 (0xFF)") ;

      if errors = 0 then
         report "tb_uart_loopback: ALL TESTS PASSED" severity note ;
      else
         report "tb_uart_loopback: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
