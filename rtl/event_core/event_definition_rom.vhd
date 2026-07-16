----------------------------------------------------------------
-- event_definition_rom : lookup table of default properties per --
-- event_type (spec section 7.5 "קטלוג אירועים ראשוני" / 18.1).   --
--                                                                --
-- Reduced initial scope: only priority and requires_ack are      --
-- looked up so far (script_id/audio_track will be added once     --
-- the script engine exists). Purely combinational - a ROM has    --
-- no state of its own, so no clk/resetN needed.                  --
--                                                                --
-- Catalog (custom, medical-monitoring theme - NOT the spec's     --
-- example fire-alarm catalog, chosen since the underlying        --
-- engine is generic and doesn't care what the labels mean):      --
--   01 LIFE_THREATENING_EMERGENCY  pri 7  ACK                    --
--   02 LOW_OXYGEN                  pri 6  ACK                    --
--   03 SEVERE_TACHYCARDIA          pri 6  ACK                    --
--   04 SEVERE_BRADYCARDIA          pri 5  ACK                    --
--   05 HIGH_FEVER                  pri 5  ACK                    --
--   06 HIGH_BLOOD_PRESSURE         pri 4  ACK                    --
--   07 MEDICATION_MISSED           pri 3  no ACK                 --
--   08 LOW_DEVICE_BATTERY          pri 3  no ACK                 --
--   09 PATIENT_DISCHARGE           pri 3  ACK                    --
--   0A SENSOR_DISCONNECTED         pri 2  ACK                    --
--   0B CHECKUP_REMINDER            pri 1  no ACK                 --
--   0C SYSTEM_READY                pri 0  no ACK                 --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity event_definition_rom is
   port ( event_type   : in  std_logic_vector(7 downto 0) ;
          priority     : out std_logic_vector(2 downto 0) ;
          requires_ack : out std_logic                    ;
          type_valid   : out std_logic                    ) ; -- '1' if event_type is a recognized entry
end event_definition_rom ;

architecture arc_event_definition_rom of event_definition_rom is
begin

   process (event_type)
   begin
      case event_type is
         when x"01" => priority <= "111" ; requires_ack <= '1' ; type_valid <= '1' ; -- LIFE_THREATENING_EMERGENCY
         when x"02" => priority <= "110" ; requires_ack <= '1' ; type_valid <= '1' ; -- LOW_OXYGEN
         when x"03" => priority <= "110" ; requires_ack <= '1' ; type_valid <= '1' ; -- SEVERE_TACHYCARDIA
         when x"04" => priority <= "101" ; requires_ack <= '1' ; type_valid <= '1' ; -- SEVERE_BRADYCARDIA
         when x"05" => priority <= "101" ; requires_ack <= '1' ; type_valid <= '1' ; -- HIGH_FEVER
         when x"06" => priority <= "100" ; requires_ack <= '1' ; type_valid <= '1' ; -- HIGH_BLOOD_PRESSURE
         when x"07" => priority <= "011" ; requires_ack <= '0' ; type_valid <= '1' ; -- MEDICATION_MISSED
         when x"08" => priority <= "011" ; requires_ack <= '0' ; type_valid <= '1' ; -- LOW_DEVICE_BATTERY
         when x"09" => priority <= "011" ; requires_ack <= '1' ; type_valid <= '1' ; -- PATIENT_DISCHARGE
         when x"0A" => priority <= "010" ; requires_ack <= '1' ; type_valid <= '1' ; -- SENSOR_DISCONNECTED
         when x"0B" => priority <= "001" ; requires_ack <= '0' ; type_valid <= '1' ; -- CHECKUP_REMINDER
         when x"0C" => priority <= "000" ; requires_ack <= '0' ; type_valid <= '1' ; -- SYSTEM_READY
         when others => priority <= "000" ; requires_ack <= '0' ; type_valid <= '0' ; -- unrecognized event_type
      end case ;
   end process ;

end arc_event_definition_rom ;
