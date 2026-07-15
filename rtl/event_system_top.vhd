----------------------------------------------------------------
-- event_system_top : top-level entity for the DE0 board.       --
--                                                               --
-- Grows incrementally as more blocks come online (spec section --
-- 23 work plan).                                                --
--                                                               --
-- Milestone 1: BUTTON0/BUTTON2 control the SYSTEM_ON/SYSTEM_OFF --
-- master state, shown live on LEDG0 (spec section 24 acceptance --
-- criteria: "BUTTON0/BUTTON1/BUTTON2 are implemented and         --
-- tested").                                                      --
--                                                               --
-- Milestone 2: TX1/RX1 (the Add-On board's FTDI/PC debug        --
-- channel) wired to uart_tx/uart_rx with a temporary echo test  --
-- (uart_echo_test - NOT final architecture, see its own header) --
-- to confirm the real UART link works against a PC terminal.    --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity event_system_top is
   port ( CLOCK_50 : in  std_logic ;
          BUTTON0  : in  std_logic ; -- active-low, System ON
          BUTTON2  : in  std_logic ; -- active-low, System OFF
          LEDG0    : out std_logic ; -- lit when SYSTEM_ON
          RX1      : in  std_logic ; -- Add-On board FTDI/PC UART, FPGA receive
          TX1      : out std_logic ) ; -- Add-On board FTDI/PC UART, FPGA transmit
end event_system_top ;

architecture arc_event_system_top of event_system_top is

   component reset_controller
      generic ( hold_cycles : positive := 16 ) ;
      port ( clk    : in  std_logic ;
             resetN : out std_logic ) ;
   end component ;

   component button_pulse
      generic ( clk_freq           : integer := 50_000_000 ;
                max_bounce_time_ms : integer := 10          ) ;
      port ( resetN   : in  std_logic ;
             clk      : in  std_logic ;
             button_n : in  std_logic ;
             pulse    : out std_logic ) ;
   end component ;

   component system_master_ctrl
      port ( resetN          : in  std_logic ;
             clk             : in  std_logic ;
             button0_pulse_i : in  std_logic ;
             button2_pulse_i : in  std_logic ;
             system_enable_o : out std_logic ) ;
   end component ;

   component uart_rx
      generic ( clk_hz    : integer := 50_000_000 ;
                baud_rate : integer := 9600        ) ;
      port ( resetN     : in  std_logic                     ;
             clk        : in  std_logic                     ;
             rx         : in  std_logic                     ;
             read_dout  : in  std_logic                     ;
             data_valid : out std_logic                     ;
             dout       : out std_logic_vector(7 downto 0)  ;
             dout_ready : out std_logic                      ) ;
   end component ;

   component uart_tx
      generic ( clk_hz    : integer := 50_000_000 ;
                baud_rate : integer := 9600        ) ;
      port ( resetN    : in  std_logic                    ;
             clk       : in  std_logic                    ;
             din       : in  std_logic_vector(7 downto 0) ;
             write_din : in  std_logic                    ;
             tx        : out std_logic                    ;
             tx_ready  : out std_logic                    ) ;
   end component ;

   component uart_echo_test
      port ( resetN        : in  std_logic                    ;
             clk           : in  std_logic                    ;
             rx_dout       : in  std_logic_vector(7 downto 0) ;
             rx_data_valid : in  std_logic                    ;
             rx_read_dout  : out std_logic                    ;
             tx_din        : out std_logic_vector(7 downto 0) ;
             tx_write_din  : out std_logic                    ;
             tx_ready      : in  std_logic                    ) ;
   end component ;

   signal resetN         : std_logic ;
   signal button0_pulse  : std_logic ;
   signal button2_pulse  : std_logic ;
   signal system_enable  : std_logic ;

   signal rx_dout        : std_logic_vector(7 downto 0) ;
   signal rx_data_valid  : std_logic ;
   signal rx_read_dout   : std_logic ;
   signal tx_din         : std_logic_vector(7 downto 0) ;
   signal tx_write_din   : std_logic ;
   signal tx_ready       : std_logic ;

begin

   u_reset : reset_controller
      port map ( clk => CLOCK_50, resetN => resetN ) ;

   u_button0 : button_pulse
      port map ( resetN => resetN, clk => CLOCK_50, button_n => BUTTON0, pulse => button0_pulse ) ;

   u_button2 : button_pulse
      port map ( resetN => resetN, clk => CLOCK_50, button_n => BUTTON2, pulse => button2_pulse ) ;

   u_master : system_master_ctrl
      port map ( resetN          => resetN        ,
                 clk             => CLOCK_50       ,
                 button0_pulse_i => button0_pulse  ,
                 button2_pulse_i => button2_pulse  ,
                 system_enable_o => system_enable  ) ;

   LEDG0 <= system_enable ;

   u_uart_rx : uart_rx
      port map ( resetN     => resetN        ,
                 clk        => CLOCK_50       ,
                 rx         => RX1            ,
                 read_dout  => rx_read_dout   ,
                 data_valid => rx_data_valid  ,
                 dout       => rx_dout        ,
                 dout_ready => open           ) ;

   u_uart_tx : uart_tx
      port map ( resetN    => resetN      ,
                 clk       => CLOCK_50     ,
                 din       => tx_din       ,
                 write_din => tx_write_din ,
                 tx        => TX1          ,
                 tx_ready  => tx_ready     ) ;

   u_echo : uart_echo_test
      port map ( resetN        => resetN        ,
                 clk           => CLOCK_50       ,
                 rx_dout       => rx_dout        ,
                 rx_data_valid => rx_data_valid  ,
                 rx_read_dout  => rx_read_dout   ,
                 tx_din        => tx_din         ,
                 tx_write_din  => tx_write_din   ,
                 tx_ready      => tx_ready       ) ;

end arc_event_system_top ;
