----------------------------------------------------------------
-- button_pulse : wires together the course-provided clean_key --
-- and gozer blocks (lib/course_blocks - kept local only, not  --
-- in the public repo, see project notes) to turn one raw      --
-- active-low button into a debounced, single-clock-wide,      --
-- active-high press pulse - the "debounced one-shot" signal   --
-- system_master_ctrl expects (spec sections 17, 18.4).         --
--                                                               --
-- clean_key debounces the raw input into a clean level (stays --
-- high the whole time the button is held); gozer's rise output --
-- turns that level into a one-clock pulse on the rising edge.  --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity button_pulse is
   generic ( clk_freq           : integer := 50_000_000 ;
             max_bounce_time_ms : integer := 10          ) ;
   port ( resetN   : in  std_logic ;
          clk      : in  std_logic ;
          button_n : in  std_logic ; -- raw active-low button pin
          pulse    : out std_logic ) ; -- one clock-cycle pulse per accepted press
end button_pulse ;

architecture arc_button_pulse of button_pulse is

   component clean_key
      generic( clk_freq           : integer := 50_000_000 ;
               max_bounce_time_ms : integer := 10          ;
               bypass             : integer := 0           ) ;
      port( resetN : in  std_logic ;
            clk_50 : in  std_logic ;
            keyN   : in  std_logic ;
            dout   : out std_logic ) ;
   end component ;

   component gozer
      port ( resetN, clk, din   : in  std_logic ;
             rise, fall, change : out std_logic ) ;
   end component ;

   signal debounced_level         : std_logic ;
   signal unused_fall, unused_chg : std_logic ;

begin

   u_clean_key : clean_key
      generic map ( clk_freq           => clk_freq ,
                    max_bounce_time_ms => max_bounce_time_ms ,
                    bypass             => 0 )
      port map ( resetN => resetN ,
                 clk_50 => clk    ,
                 keyN   => button_n ,
                 dout   => debounced_level ) ;

   u_gozer : gozer
      port map ( resetN => resetN ,
                 clk    => clk    ,
                 din    => debounced_level ,
                 rise   => pulse       ,
                 fall   => unused_fall ,
                 change => unused_chg  ) ;

end arc_button_pulse ;
