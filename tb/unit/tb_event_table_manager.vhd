----------------------------------------------------------------
-- tb_event_table_manager : self-checking testbench for           --
-- event_table_manager (spec section 8.1, reduced scope - see     --
-- the DUT's own header for exactly what's implemented so far).   --
--                                                                --
-- Scenarios (default generic, event_slots = 8):                  --
--   1) allocate event_type=01 (LIFE_THREATENING_EMERGENCY) ->     --
--      instance_id=0, priority=111, requires_ack='1'              --
--   2) allocate event_type=07 (MEDICATION_MISSED) ->               --
--      instance_id=1, priority=011, requires_ack='0'              --
--   3) allocate event_type=0D (not in the catalog) -> rejected     --
--      (alloc_ok='0', alloc_unknown_type='1'), and does NOT        --
--      consume a slot/instance_id - verified by the next          --
--      successful allocation still getting instance_id=2          --
--   4) fill the remaining 6 slots (instance_id 2..7 in order)     --
--   5) 9th allocation -> table full (alloc_ok='0')                --
--   6) a second attempt right after -> still table full           --
--      (idempotent, no state corruption on a failed request)      --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity tb_event_table_manager is
end tb_event_table_manager ;

architecture sim of tb_event_table_manager is

   constant clk_period : time := 20 ns ;

   signal clk    : std_logic := '0' ;
   signal resetN : std_logic := '0' ;

   signal alloc_req          : std_logic := '0' ;
   signal event_type         : std_logic_vector(7 downto 0) := (others => '0') ;
   signal source_id          : std_logic_vector(7 downto 0) := (others => '0') ;

   signal alloc_done         : std_logic ;
   signal alloc_ok           : std_logic ;
   signal alloc_unknown_type : std_logic ;
   signal alloc_instance_id  : std_logic_vector(7 downto 0) ;
   signal alloc_priority     : std_logic_vector(2 downto 0) ;
   signal alloc_requires_ack : std_logic ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.event_table_manager
      generic map ( event_slots => 8 )
      port map ( resetN => resetN, clk => clk,
                 alloc_req => alloc_req, event_type => event_type, source_id => source_id,
                 alloc_done => alloc_done, alloc_ok => alloc_ok, alloc_unknown_type => alloc_unknown_type,
                 alloc_instance_id => alloc_instance_id, alloc_priority => alloc_priority,
                 alloc_requires_ack => alloc_requires_ack ) ;

   clk_gen : process
   begin
      while not sim_done loop
         wait for clk_period / 2 ;
         clk <= not clk ;
      end loop ;
      wait ;
   end process ;

   check : process
      variable errors : natural := 0 ;

      procedure request_alloc ( constant t : std_logic_vector(7 downto 0) ; constant s : std_logic_vector(7 downto 0) ) is
      begin
         event_type <= t ;
         source_id  <= s ;
         alloc_req  <= '1' ;
         wait until rising_edge(clk) ;
         wait for 1 ns ; -- let this edge's registered outputs settle
         alloc_req  <= '0' ;
      end procedure ;

      procedure expect_success ( constant exp_id  : std_logic_vector(7 downto 0) ;
                                  constant exp_pri : std_logic_vector(2 downto 0) ;
                                  constant exp_ack : std_logic ;
                                  constant name    : string ) is
      begin
         if alloc_done /= '1' then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - alloc_done did not pulse" severity error ;
         end if ;
         if alloc_ok /= '1' then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - expected alloc_ok='1'" severity error ;
         end if ;
         if alloc_instance_id /= exp_id then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - wrong instance_id" severity error ;
         end if ;
         if alloc_priority /= exp_pri then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - wrong priority" severity error ;
         end if ;
         if alloc_requires_ack /= exp_ack then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - wrong requires_ack" severity error ;
         end if ;
      end procedure ;

      procedure expect_table_full ( constant name : string ) is
      begin
         if alloc_done /= '1' then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - alloc_done did not pulse" severity error ;
         end if ;
         if alloc_ok /= '0' then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - expected alloc_ok='0' (table full)" severity error ;
         end if ;
         if alloc_unknown_type /= '0' then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - expected alloc_unknown_type='0' (it's full, not an unknown type)" severity error ;
         end if ;
      end procedure ;

      procedure expect_unknown_type ( constant name : string ) is
      begin
         if alloc_done /= '1' then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - alloc_done did not pulse" severity error ;
         end if ;
         if alloc_ok /= '0' then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - expected alloc_ok='0' (unknown type)" severity error ;
         end if ;
         if alloc_unknown_type /= '1' then
            errors := errors + 1 ;
            report "tb_event_table_manager: FAIL - " & name & " - expected alloc_unknown_type='1'" severity error ;
         end if ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      ------------------------------------------------------------
      -- 1) first allocation - LIFE_THREATENING_EMERGENCY
      ------------------------------------------------------------
      request_alloc( x"01", x"05" ) ;
      expect_success( x"00", "111", '1', "1st alloc (LIFE_THREATENING_EMERGENCY)" ) ;

      ------------------------------------------------------------
      -- 2) second allocation - MEDICATION_MISSED
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      request_alloc( x"07", x"02" ) ;
      expect_success( x"01", "011", '0', "2nd alloc (MEDICATION_MISSED)" ) ;

      ------------------------------------------------------------
      -- 3) unrecognized event_type - rejected, no slot/id consumed
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      request_alloc( x"0D", x"03" ) ;
      expect_unknown_type( "3rd request (event_type=0D, not in the catalog)" ) ;

      ------------------------------------------------------------
      -- 4) fill the remaining 6 slots (instance_id 2..7) - the
      -- rejected request above must NOT have consumed instance_id=2
      ------------------------------------------------------------
      for n in 2 to 7 loop
         wait until rising_edge(clk) ;
         request_alloc( x"0C", x"00" ) ; -- SYSTEM_READY, arbitrary filler type
         expect_success( std_logic_vector(to_unsigned(n, 8)), "000", '0',
                          "filler alloc #" & integer'image(n) ) ;
      end loop ;

      ------------------------------------------------------------
      -- 5) 9th allocation - table full
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      request_alloc( x"01", x"09" ) ;
      expect_table_full( "9th alloc (table should be full)" ) ;

      ------------------------------------------------------------
      -- 6) a second attempt right after - still table full, no corruption
      ------------------------------------------------------------
      wait until rising_edge(clk) ;
      request_alloc( x"01", x"0A" ) ;
      expect_table_full( "10th alloc (still full, idempotent)" ) ;

      if errors = 0 then
         report "tb_event_table_manager: ALL TESTS PASSED" severity note ;
      else
         report "tb_event_table_manager: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
