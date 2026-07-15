----------------------------------------------------------------
-- uart_echo_test : TEMPORARY hardware bring-up block only -    --
-- NOT part of the final event system. Whatever byte uart_rx    --
-- receives, this sends straight back out via uart_tx. Used to  --
-- confirm the real UART link (both directions at once) works   --
-- against a PC terminal, before building the real text command --
-- parser + response builder (spec section 10) that will        --
-- eventually replace this block entirely.                       --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity uart_echo_test is
   port ( resetN        : in  std_logic                    ;
          clk           : in  std_logic                    ;
          rx_dout       : in  std_logic_vector(7 downto 0) ; -- byte received by uart_rx
          rx_data_valid : in  std_logic                    ; -- pulse: rx_dout just arrived
          rx_read_dout  : out std_logic                    ; -- acknowledge to uart_rx
          tx_din        : out std_logic_vector(7 downto 0) ; -- byte to send via uart_tx
          tx_write_din  : out std_logic                    ; -- request uart_tx to send tx_din
          tx_ready      : in  std_logic                    ) ; -- uart_tx is idle, can accept a byte
end uart_echo_test ;

architecture arc_uart_echo_test of uart_echo_test is

   type state_t is (idle, wait_tx_ready, sending) ;
   signal state    : state_t ;
   signal byte_reg : std_logic_vector(7 downto 0) ;

begin

   process (resetN, clk)
   begin
      if resetN = '0' then
         state        <= idle ;
         byte_reg     <= (others => '0') ;
         rx_read_dout <= '0' ;
         tx_din       <= (others => '0') ;
         tx_write_din <= '0' ;
      elsif rising_edge(clk) then
         rx_read_dout <= '0' ; -- one-clock pulses, defaulted low each cycle
         tx_write_din <= '0' ;

         case state is

            when idle =>
               if rx_data_valid = '1' then
                  byte_reg     <= rx_dout ;
                  rx_read_dout <= '1' ; -- acknowledge the byte was captured
                  state        <= wait_tx_ready ;
               end if ;

            when wait_tx_ready =>
               if tx_ready = '1' then
                  tx_din       <= byte_reg ;
                  tx_write_din <= '1' ; -- request the send, one clock
                  state        <= sending ;
               end if ;

            when sending =>
               state <= idle ;

            when others =>
               state <= idle ;

         end case ;
      end if ;
   end process ;

end arc_uart_echo_test ;
