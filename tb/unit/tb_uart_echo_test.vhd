----------------------------------------------------------------
-- tb_uart_echo_test : self-checking testbench for              --
-- uart_echo_test (spec section 21). Drives the rx_dout/         --
-- rx_data_valid/tx_ready interface directly (the underlying     --
-- uart_rx/uart_tx engines are already verified separately in    --
-- tb_uart_loopback.vhd) - a focused unit test of just the echo  --
-- FSM logic before it gets wired into event_system_top.         --
--                                                               --
-- Checks:                                                      --
--   1) rx_data_valid pulse -> rx_read_dout acknowledges (1 clk) --
--   2) once tx_ready goes high, tx_din/tx_write_din fire with   --
--      the correct byte (tested with tx_ready held low first,  --
--      to confirm the FSM actually waits for it)                --
--   3) a second, different byte works right after (not "stuck") --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity tb_uart_echo_test is
end tb_uart_echo_test ;

architecture sim of tb_uart_echo_test is

   constant clk_period : time := 20 ns ;

   signal clk           : std_logic := '0' ;
   signal resetN        : std_logic := '0' ;
   signal rx_dout        : std_logic_vector(7 downto 0) := (others => '0') ;
   signal rx_data_valid  : std_logic := '0' ;
   signal rx_read_dout   : std_logic ;
   signal tx_din         : std_logic_vector(7 downto 0) ;
   signal tx_write_din   : std_logic ;
   signal tx_ready       : std_logic := '0' ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.uart_echo_test
      port map ( resetN => resetN, clk => clk,
                 rx_dout => rx_dout, rx_data_valid => rx_data_valid, rx_read_dout => rx_read_dout,
                 tx_din => tx_din, tx_write_din => tx_write_din, tx_ready => tx_ready ) ;

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
   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      -----------------------------------------------------------------
      -- 1) deliver a byte on rx side while tx_ready is LOW - the FSM --
      -- must wait for it, not send garbage or get stuck              --
      -----------------------------------------------------------------
      tx_ready <= '0' ;
      rx_dout       <= "11001010" ;
      rx_data_valid <= '1' ;
      wait until rising_edge(clk) ;
      rx_data_valid <= '0' ;
      wait for 1 ns ;
      if rx_read_dout /= '1' then
         errors := errors + 1 ;
         report "tb_uart_echo_test: FAIL - rx_read_dout did not acknowledge the byte"
            severity error ;
      end if ;

      -- hold tx_ready low for a few clocks - tx_write_din must stay 0 meanwhile
      for i in 1 to 3 loop
         wait until rising_edge(clk) ;
         wait for 1 ns ;
         if tx_write_din /= '0' then
            errors := errors + 1 ;
            report "tb_uart_echo_test: FAIL - tx_write_din fired before tx_ready went high"
               severity error ;
         end if ;
      end loop ;

      -- now release tx_ready - the byte must be sent with the correct value
      tx_ready <= '1' ;
      wait until rising_edge(clk) ;
      wait for 1 ns ;
      if tx_write_din /= '1' then
         errors := errors + 1 ;
         report "tb_uart_echo_test: FAIL - tx_write_din did not fire once tx_ready went high"
            severity error ;
      end if ;
      if tx_din /= "11001010" then
         errors := errors + 1 ;
         report "tb_uart_echo_test: FAIL - tx_din does not match the byte that was received"
            severity error ;
      end if ;
      tx_ready <= '0' ;

      wait until rising_edge(clk) ;
      wait for 1 ns ;
      if tx_write_din /= '0' then
         errors := errors + 1 ;
         report "tb_uart_echo_test: FAIL - tx_write_din stayed high for more than one clock"
            severity error ;
      end if ;

      -----------------------------------------------------------------
      -- 2) a second, different byte right after - not "stuck"        --
      -----------------------------------------------------------------
      rx_dout       <= "01010111" ;
      rx_data_valid <= '1' ;
      wait until rising_edge(clk) ;
      rx_data_valid <= '0' ;
      wait for 1 ns ;
      if rx_read_dout /= '1' then
         errors := errors + 1 ;
         report "tb_uart_echo_test: FAIL - second byte - rx_read_dout did not acknowledge"
            severity error ;
      end if ;

      tx_ready <= '1' ;
      wait until rising_edge(clk) ;
      wait for 1 ns ;
      if tx_write_din /= '1' or tx_din /= "01010111" then
         errors := errors + 1 ;
         report "tb_uart_echo_test: FAIL - second byte did not echo correctly"
            severity error ;
      end if ;
      tx_ready <= '0' ;

      if errors = 0 then
         report "tb_uart_echo_test: ALL TESTS PASSED" severity note ;
      else
         report "tb_uart_echo_test: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
