----------------------------------------------------------------
-- uart_rx : wraps the course-provided receiver.vhd, adding an --
-- extra synchronizer flip-flop on the raw async rx input.     --
--                                                               --
-- receiver.vhd already double-checks the start bit and samples --
-- near the middle of every bit, but only synchronizes rx with  --
-- ONE flip-flop internally. Spec section 11.3 requires "at     --
-- least two" - this wrapper adds a second stage ahead of it,   --
-- so the signal reaching receiver.vhd is already synchronized. --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity uart_rx is
   generic ( clk_hz    : integer := 50_000_000 ;
             baud_rate : integer := 9600        ) ;
   port ( resetN     : in  std_logic                     ;
          clk        : in  std_logic                     ;
          rx         : in  std_logic                     ; -- raw async serial input
          read_dout  : in  std_logic                     ; -- consumer acknowledges dout was read
          data_valid : out std_logic                     ; -- one-clock pulse: a new byte just arrived
          dout       : out std_logic_vector(7 downto 0)  ;
          dout_ready : out std_logic                      ) ; -- level: a byte is waiting to be read
end uart_rx ;

architecture arc_uart_rx of uart_rx is

   component receiver
      generic ( clockfreq : integer := 25000000 ;
                baud      : integer := 9600 ) ;
      port ( resetN     : in  std_logic                    ;
             clk        : in  std_logic                    ;
             rx         : in  std_logic                    ;
             read_dout  : in  std_logic                    ;
             rx_ready   : out std_logic                    ;
             dout       : out std_logic_vector(7 downto 0) ;
             dout_new   : out std_logic                    ;
             dout_ready : out std_logic                    ) ;
   end component ;

   signal rx_sync1, rx_sync2 : std_logic ;
   signal rx_ready_unused    : std_logic ;

begin

   process (resetN, clk)
   begin
      if resetN = '0' then
         rx_sync1 <= '1' ; -- idle level is high
         rx_sync2 <= '1' ;
      elsif rising_edge(clk) then
         rx_sync1 <= rx       ;
         rx_sync2 <= rx_sync1 ;
      end if ;
   end process ;

   u_receiver : receiver
      generic map ( clockfreq => clk_hz    ,
                    baud      => baud_rate )
      port map ( resetN     => resetN            ,
                 clk        => clk               ,
                 rx         => rx_sync2          , -- already synchronized
                 read_dout  => read_dout         ,
                 rx_ready   => rx_ready_unused   ,
                 dout       => dout              ,
                 dout_new   => data_valid        ,
                 dout_ready => dout_ready        ) ;

end arc_uart_rx ;
