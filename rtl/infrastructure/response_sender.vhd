----------------------------------------------------------------
-- response_sender : takes a formatted response from            --
-- response_builder (up to max_response_length bytes) and sends  --
-- it out, byte by byte, through a uart_tx (spec section 17/18.3 --
-- ready/valid handshake convention) - waiting for tx_ready       --
-- between each byte, then appending CR+LF so the response shows --
-- as its own line on the receiving terminal.                    --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity response_sender is
   generic ( max_response_length : positive := 32 ) ;
   port ( resetN       : in  std_logic                                          ;
          clk          : in  std_logic                                          ;
          resp_data    : in  std_logic_vector(max_response_length*8-1 downto 0) ;
          resp_length  : in  std_logic_vector(7 downto 0)                       ;
          resp_ready   : in  std_logic                                          ; -- pulse: a new response is ready
          tx_din       : out std_logic_vector(7 downto 0)                       ;
          tx_write_din : out std_logic                                          ;
          tx_ready     : in  std_logic                                          ) ;
end response_sender ;

architecture arc_response_sender of response_sender is

   type byte_array_t is array (0 to max_response_length - 1) of std_logic_vector(7 downto 0) ;
   signal latched_data : byte_array_t ;
   signal latched_len  : integer range 0 to max_response_length ;
   signal send_idx     : integer range 0 to max_response_length ;

   type state_t is (IDLE, SEND_CHAR, SEND_CR, SEND_LF) ;
   signal state : state_t ;

begin

   process (resetN, clk)
   begin
      if resetN = '0' then
         state        <= IDLE ;
         send_idx     <= 0 ;
         latched_len  <= 0 ;
         tx_write_din <= '0' ;
         tx_din       <= (others => '0') ;
      elsif rising_edge(clk) then
         tx_write_din <= '0' ; -- one-clock pulse, defaulted low every cycle

         case state is

            when IDLE =>
               if resp_ready = '1' then
                  for i in 0 to max_response_length - 1 loop
                     latched_data(i) <= resp_data((i + 1) * 8 - 1 downto i * 8) ;
                  end loop ;
                  latched_len <= to_integer(unsigned(resp_length)) ;
                  send_idx    <= 0 ;
                  state       <= SEND_CHAR ;
               end if ;

            when SEND_CHAR =>
               if send_idx = latched_len then
                  state <= SEND_CR ;
               elsif tx_ready = '1' then
                  tx_din       <= latched_data(send_idx) ;
                  tx_write_din <= '1' ;
                  send_idx     <= send_idx + 1 ;
               end if ;

            when SEND_CR =>
               if tx_ready = '1' then
                  tx_din       <= x"0D" ;
                  tx_write_din <= '1' ;
                  state        <= SEND_LF ;
               end if ;

            when SEND_LF =>
               if tx_ready = '1' then
                  tx_din       <= x"0A" ;
                  tx_write_din <= '1' ;
                  state        <= IDLE ;
               end if ;

            when others =>
               state <= IDLE ;

         end case ;
      end if ;
   end process ;

end arc_response_sender ;
