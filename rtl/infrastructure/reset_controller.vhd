----------------------------------------------------------------
-- reset_controller : power-on reset generator (spec section 17,20) --
--                                                                --
-- The DE0 board has no dedicated hardware reset pin routed to   --
-- the FPGA (BUTTON0..2 are all reassigned to system-level roles --
-- by the v1.1 spec, section 14). So this block simply holds     --
-- resetN low for hold_cycles clocks after configuration/power-  --
-- up (relying on the FPGA's register power-up initial values,   --
-- a standard Cyclone III idiom) and then releases it high for   --
-- good - there is no external assertion to synchronize.         --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity reset_controller is
   generic ( hold_cycles : positive := 16 ) ; -- clocks to hold resetN low after power-up
   port ( clk    : in  std_logic ;
          resetN : out std_logic ) ; -- active-low reset for the rest of the design
end reset_controller ;

architecture arc_reset_controller of reset_controller is

   signal count      : integer range 0 to hold_cycles - 1 := 0   ;
   signal resetN_int : std_logic                          := '0' ;

begin

   process (clk)
   begin
      if rising_edge(clk) then
         if count < hold_cycles - 1 then
            count <= count + 1 ;
         else
            resetN_int <= '1' ; -- stays high forever once released
         end if ;
      end if ;
   end process ;

   resetN <= resetN_int ;

end arc_reset_controller ;
