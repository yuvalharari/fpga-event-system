----------------------------------------------------------------
-- event_system_top : top-level entity for the DE0 board.       --
--                                                               --
-- Grows incrementally as more blocks come online (spec section --
-- 23 work plan). Current milestone: BUTTON0/BUTTON2 control the --
-- SYSTEM_ON/SYSTEM_OFF master state, shown live on LEDG0 - the  --
-- first real-hardware checkpoint for the project (spec section  --
-- 24 acceptance criteria: "BUTTON0/BUTTON1/BUTTON2 are           --
-- implemented and tested").                                     --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity event_system_top is
   port ( CLOCK_50 : in  std_logic ;
          BUTTON0  : in  std_logic ; -- active-low, System ON
          BUTTON2  : in  std_logic ; -- active-low, System OFF
          LEDG0    : out std_logic ) ; -- lit when SYSTEM_ON
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

   signal resetN         : std_logic ;
   signal button0_pulse  : std_logic ;
   signal button2_pulse  : std_logic ;
   signal system_enable  : std_logic ;

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

end arc_event_system_top ;
