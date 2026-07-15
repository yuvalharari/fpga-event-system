----------------------------------------------------------------
-- tb_sync_fifo : self-checking testbench for sync_fifo         --
-- (spec section 21, tb_fifo: "Full/empty, קריאה/כתיבה בו-זמנית, --
-- עטיפה, דגלי overflow/underflow").                             --
--                                                               --
-- Uses a small depth (4) for clear boundary testing. Checks:   --
--   1) empty/full/overflow correct right after reset            --
--   2) single write+read round trip, value and empty/full flags --
--   3) filling to exactly "full", in the right order (FIFO)     --
--   4) writing while full sets the sticky overflow flag         --
--   5) draining preserves write order (first in, first out)     --
--   6) simultaneous read+write while partially full keeps count --
--      consistent (does not become empty/full incorrectly)      --
--   7) pointers wrap correctly across more than "depth" writes  --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity tb_sync_fifo is
end tb_sync_fifo ;

architecture sim of tb_sync_fifo is

   type byte_array is array (natural range <>) of std_logic_vector(7 downto 0) ;

   constant clk_period : time     := 20 ns ;
   constant g_depth    : positive := 4     ;
   constant fill_order : byte_array(0 to 3) := (x"01", x"02", x"03", x"04") ;

   signal clk      : std_logic := '0' ;
   signal resetN   : std_logic := '0' ;
   signal wr_en    : std_logic := '0' ;
   signal wr_data  : std_logic_vector(7 downto 0) := (others => '0') ;
   signal rd_en    : std_logic := '0' ;
   signal rd_data  : std_logic_vector(7 downto 0) ;
   signal full     : std_logic ;
   signal empty    : std_logic ;
   signal overflow : std_logic ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.sync_fifo
      generic map ( data_width => 8, depth => g_depth )
      port map ( resetN => resetN, clk => clk, wr_en => wr_en, wr_data => wr_data,
                 rd_en => rd_en, rd_data => rd_data, full => full, empty => empty,
                 overflow => overflow ) ;

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

      procedure do_write ( constant b : std_logic_vector(7 downto 0) ) is
      begin
         wr_data <= b   ;
         wr_en   <= '1' ;
         wait until rising_edge(clk) ;
         wr_en   <= '0' ;
      end procedure ;

      procedure do_read is
      begin
         rd_en <= '1' ;
         wait until rising_edge(clk) ;
         rd_en <= '0' ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;
      wait for 1 ns ;

      ------------------------------------------------------------
      -- 1) state right after reset
      ------------------------------------------------------------
      if empty /= '1' or full /= '0' or overflow /= '0' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - wrong empty/full/overflow right after reset" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 2) single write + read round trip
      ------------------------------------------------------------
      do_write(x"11") ;
      wait for 1 ns ;
      if empty /= '0' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - still empty after one write" severity error ;
      end if ;
      if rd_data /= x"11" then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - rd_data does not show the item that was written" severity error ;
      end if ;

      do_read ;
      wait for 1 ns ;
      if empty /= '1' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - not empty after draining the single item" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 3) fill to exactly full (depth = 4)
      ------------------------------------------------------------
      do_write(x"01") ;
      do_write(x"02") ;
      do_write(x"03") ;
      do_write(x"04") ;
      wait for 1 ns ;
      if full /= '1' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - not full after writing exactly 'depth' items" severity error ;
      end if ;
      if overflow /= '0' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - overflow set too early (before any write-while-full)" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 4) write while full -> sticky overflow flag
      ------------------------------------------------------------
      do_write(x"FF") ;
      wait for 1 ns ;
      if overflow /= '1' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - overflow not set after writing while full" severity error ;
      end if ;
      if full /= '1' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - the rejected write while full corrupted the full flag" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 5) drain and check FIFO order is preserved (01,02,03,04)
      ------------------------------------------------------------
      for i in 0 to 3 loop
         wait for 1 ns ;
         if rd_data /= fill_order(i) then
            errors := errors + 1 ;
            report "tb_sync_fifo: FAIL - FIFO order wrong while draining, index " & integer'image(i)
               severity error ;
         end if ;
         do_read ;
      end loop ;
      wait for 1 ns ;
      if empty /= '1' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - not empty after draining everything" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 6) simultaneous read+write while partially full: count   --
      -- must stay consistent (not become empty or full wrongly)  --
      ------------------------------------------------------------
      do_write(x"AA") ;
      do_write(x"BB") ; -- count = 2 now
      wait for 1 ns ;

      wr_data <= x"CC" ;
      wr_en   <= '1' ;
      rd_en   <= '1' ; -- simultaneous: pop x"AA", push x"CC" -> count stays 2
      wait until rising_edge(clk) ;
      wr_en <= '0' ;
      rd_en <= '0' ;
      wait for 1 ns ;
      if empty = '1' or full = '1' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - simultaneous read+write changed count incorrectly" severity error ;
      end if ;
      if rd_data /= x"BB" then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - simultaneous read+write - wrong next item (expected the one behind what was popped)" severity error ;
      end if ;

      do_read ; -- pop BB
      wait for 1 ns ;
      if rd_data /= x"CC" then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - simultaneous read+write - the pushed item did not end up at the back correctly" severity error ;
      end if ;
      do_read ; -- pop CC, should be empty again
      wait for 1 ns ;
      if empty /= '1' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - not empty after draining following the simultaneous read+write test" severity error ;
      end if ;

      ------------------------------------------------------------
      -- 7) pointer wraparound: write/read more than 'depth' items --
      -- total across multiple fill/drain cycles                  --
      ------------------------------------------------------------
      for i in 0 to 9 loop
         do_write(std_logic_vector(to_unsigned(i, 8))) ;
         wait for 1 ns ;
         if rd_data /= std_logic_vector(to_unsigned(i, 8)) then
            errors := errors + 1 ;
            report "tb_sync_fifo: FAIL - wraparound test, index " & integer'image(i)
               severity error ;
         end if ;
         do_read ;
      end loop ;
      wait for 1 ns ;
      if empty /= '1' then
         errors := errors + 1 ;
         report "tb_sync_fifo: FAIL - not empty after the wraparound test" severity error ;
      end if ;

      if errors = 0 then
         report "tb_sync_fifo: ALL TESTS PASSED" severity note ;
      else
         report "tb_sync_fifo: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
