----------------------------------------------------------------
-- uart_tx : wraps the course-provided transmitter.vhd (bug-    --
-- fixed - see its header comment), exposing the naming/generics --
-- used consistently across this project's own blocks.           --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity uart_tx is
   generic ( clk_hz    : integer := 50_000_000 ;
             baud_rate : integer := 9600        ) ;
   port ( resetN    : in  std_logic                    ;
          clk       : in  std_logic                    ;
          din       : in  std_logic_vector(7 downto 0) ; -- byte to send
          write_din : in  std_logic                    ; -- request to send din
          tx        : out std_logic                    ; -- serial output
          tx_ready  : out std_logic                    ) ; -- '1' when idle, able to accept a new byte
end uart_tx ;

architecture arc_uart_tx of uart_tx is

   component transmitter
      generic ( clockfreq : integer := 25000000 ;
                baud      : integer := 115200   ) ;
      port ( resetN    : in     std_logic                    ;
             clk       : in     std_logic                    ;
             write_din : in     std_logic                    ;
             din       : in     std_logic_vector(7 downto 0) ;
             tx        : out std_logic                       ;
             tx_ready  : out std_logic                       ) ;
   end component ;

begin

   u_transmitter : transmitter
      generic map ( clockfreq => clk_hz    ,
                    baud      => baud_rate )
      port map ( resetN    => resetN    ,
                 clk       => clk       ,
                 write_din => write_din ,
                 din       => din       ,
                 tx        => tx        ,
                 tx_ready  => tx_ready  ) ;

end arc_uart_tx ;
