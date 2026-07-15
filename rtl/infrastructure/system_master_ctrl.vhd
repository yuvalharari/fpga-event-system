----------------------------------------------------------------
-- system_master_ctrl : the system-wide SYSTEM_ON/SYSTEM_OFF   --
-- master state (spec sections 14.1, 18.4, 19.5).               --
--                                                               --
-- BUTTON0's debounced one-shot pulse turns the system ON;      --
-- BUTTON2's turns it OFF. A pulse that doesn't apply to the    --
-- current state (e.g. BUTTON0 while already ON) has no effect --
-- (spec section 14.2). Power-up/reset default is SYSTEM_OFF     --
-- (the "safe output state", spec section 16.2).                 --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity system_master_ctrl is
   port ( resetN          : in  std_logic ;
          clk             : in  std_logic ;
          button0_pulse_i : in  std_logic ; -- debounced one-shot: System ON
          button2_pulse_i : in  std_logic ; -- debounced one-shot: System OFF
          system_enable_o : out std_logic ) ; -- '1' = SYSTEM_ON, '0' = SYSTEM_OFF
end system_master_ctrl ;

architecture arc_system_master_ctrl of system_master_ctrl is

   type state_t is (SYS_OFF, SYS_ON) ;
   signal state : state_t ;

begin

   process (resetN, clk)
   begin
      if resetN = '0' then
         state <= SYS_OFF ;
      elsif rising_edge(clk) then
         case state is
            when SYS_OFF =>
               if button0_pulse_i = '1' then
                  state <= SYS_ON ;
               end if ;
            when SYS_ON =>
               if button2_pulse_i = '1' then
                  state <= SYS_OFF ;
               end if ;
         end case ;
      end if ;
   end process ;

   system_enable_o <= '1' when state = SYS_ON else '0' ;

end arc_system_master_ctrl ;
