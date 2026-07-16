----------------------------------------------------------------
-- tb_event_definition_rom : self-checking testbench for          --
-- event_definition_rom (spec section 7.5 catalog, custom         --
-- medical-monitoring theme). Purely combinational DUT - no clock --
-- needed, just drive event_type and check the looked-up outputs. --
--                                                                --
-- Scenarios: all 12 defined event types (exact priority/ACK      --
-- match) plus 3 unrecognized codes (x"00", x"0D", x"FF") that    --
-- must report type_valid='0'.                                    --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity tb_event_definition_rom is
end tb_event_definition_rom ;

architecture sim of tb_event_definition_rom is

   signal event_type   : std_logic_vector(7 downto 0) := (others => '0') ;
   signal priority     : std_logic_vector(2 downto 0) ;
   signal requires_ack : std_logic ;
   signal type_valid   : std_logic ;

begin

   dut : entity work.event_definition_rom
      port map ( event_type => event_type, priority => priority,
                 requires_ack => requires_ack, type_valid => type_valid ) ;

   check : process
      variable errors : natural := 0 ;

      procedure expect_valid ( constant t        : std_logic_vector(7 downto 0) ;
                                constant exp_pri  : std_logic_vector(2 downto 0) ;
                                constant exp_ack  : std_logic ;
                                constant name     : string ) is
      begin
         event_type <= t ;
         wait for 1 ns ;
         if type_valid /= '1' then
            errors := errors + 1 ;
            report "tb_event_definition_rom: FAIL - " & name & " - expected type_valid='1'" severity error ;
         end if ;
         if priority /= exp_pri then
            errors := errors + 1 ;
            report "tb_event_definition_rom: FAIL - " & name & " - wrong priority" severity error ;
         end if ;
         if requires_ack /= exp_ack then
            errors := errors + 1 ;
            report "tb_event_definition_rom: FAIL - " & name & " - wrong requires_ack" severity error ;
         end if ;
      end procedure ;

      procedure expect_invalid ( constant t : std_logic_vector(7 downto 0) ; constant name : string ) is
      begin
         event_type <= t ;
         wait for 1 ns ;
         if type_valid /= '0' then
            errors := errors + 1 ;
            report "tb_event_definition_rom: FAIL - " & name & " - expected type_valid='0'" severity error ;
         end if ;
      end procedure ;

   begin
      -- the 12 defined entries
      expect_valid( x"01", "111", '1', "01 LIFE_THREATENING_EMERGENCY" ) ;
      expect_valid( x"02", "110", '1', "02 LOW_OXYGEN" ) ;
      expect_valid( x"03", "110", '1', "03 SEVERE_TACHYCARDIA" ) ;
      expect_valid( x"04", "101", '1', "04 SEVERE_BRADYCARDIA" ) ;
      expect_valid( x"05", "101", '1', "05 HIGH_FEVER" ) ;
      expect_valid( x"06", "100", '1', "06 HIGH_BLOOD_PRESSURE" ) ;
      expect_valid( x"07", "011", '0', "07 MEDICATION_MISSED" ) ;
      expect_valid( x"08", "011", '0', "08 LOW_DEVICE_BATTERY" ) ;
      expect_valid( x"09", "011", '1', "09 PATIENT_DISCHARGE" ) ;
      expect_valid( x"0A", "010", '1', "0A SENSOR_DISCONNECTED" ) ;
      expect_valid( x"0B", "001", '0', "0B CHECKUP_REMINDER" ) ;
      expect_valid( x"0C", "000", '0', "0C SYSTEM_READY" ) ;

      -- unrecognized codes
      expect_invalid( x"00", "00 (never assigned)" ) ;
      expect_invalid( x"0D", "0D (one past the last defined entry)" ) ;
      expect_invalid( x"FF", "FF (arbitrary unrecognized byte)" ) ;

      if errors = 0 then
         report "tb_event_definition_rom: ALL TESTS PASSED" severity note ;
      else
         report "tb_event_definition_rom: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      wait ;
   end process ;

end sim ;
