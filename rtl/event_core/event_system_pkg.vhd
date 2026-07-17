----------------------------------------------------------------
-- event_system_pkg : shared types for the Event Core blocks    --
-- (spec section 18 suggests exactly this - a shared package so --
-- top-level table connections between event_table_manager and  --
-- priority_scheduler don't need per-width copy-pasted types).   --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

package event_system_pkg is

   type priority_array_t    is array (natural range <>) of std_logic_vector(2 downto 0) ;
   type instance_id_array_t is array (natural range <>) of std_logic_vector(7 downto 0) ;

end package event_system_pkg ;
