----------------------------------------------------------------
-- tb_line_receiver : self-checking testbench for line_receiver --
-- (spec section 21). Feeds a pre-loaded byte sequence through a --
-- small mock FIFO interface (fifo_empty/fifo_rd_data/fifo_rd_en, --
-- serving bytes in order - a real sync_fifo is verified          --
-- separately in tb_sync_fifo.vhd, this is a focused unit test of --
-- just the line-framing FSM).                                    --
--                                                               --
-- max_line_length = 8 (small, for an easy-to-trigger overflow   --
-- test). Scenarios, in one continuous byte stream:               --
--   "A\n"        -> one line, length 1, "A"        (LF only)     --
--   "BB\r\n"     -> one line, length 2, "BB"        (CR+LF together, one terminator)
--   "C\rX\n"     -> two lines: "C" (CR only), then "X" (not      --
--                   swallowed as a pair - proves a non-matching   --
--                   byte after a terminator starts a new line)   --
--   "D\n\n"      -> "D", then an immediate EMPTY line (length 0) --
--   "123456789\n"-> too long for max_line_length=8: line_error   --
--                   pulses once, no line_ready for this garbage  --
--   "OK\n"       -> a clean line right after - confirms recovery --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity tb_line_receiver is
end tb_line_receiver ;

architecture sim of tb_line_receiver is

   constant clk_period        : time     := 20 ns ;
   constant g_max_line_length : positive := 8     ;

   type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0) ;

   -- 'A' LF 'B' 'B' CR LF 'C' CR 'X' LF 'D' LF LF '1'..'9' LF 'O' 'K' LF
   constant test_bytes : byte_array_t(0 to 25) := (
      x"41", x"0A",                     -- "A\n"
      x"42", x"42", x"0D", x"0A",       -- "BB\r\n"
      x"43", x"0D", x"58", x"0A",       -- "C\rX\n"
      x"44", x"0A", x"0A",              -- "D\n\n"
      x"31", x"32", x"33", x"34", x"35", x"36", x"37", x"38", x"39", x"0A", -- "123456789\n" (9 chars, too long for max_line_length=8)
      x"4F", x"4B", x"0A"               -- "OK\n"
   ) ;

   signal clk          : std_logic := '0' ;
   signal resetN       : std_logic := '0' ;
   signal fifo_empty   : std_logic ;
   signal fifo_rd_data  : std_logic_vector(7 downto 0) ;
   signal fifo_rd_en   : std_logic ;
   signal line_data    : std_logic_vector(g_max_line_length*8-1 downto 0) ;
   signal line_length  : std_logic_vector(7 downto 0) ;
   signal line_ready   : std_logic ;
   signal line_error   : std_logic ;

   signal byte_idx : integer range 0 to test_bytes'length := 0 ;

   signal sim_done : boolean := false ;

begin

   dut : entity work.line_receiver
      generic map ( max_line_length => g_max_line_length )
      port map ( resetN => resetN, clk => clk,
                 fifo_empty => fifo_empty, fifo_rd_data => fifo_rd_data, fifo_rd_en => fifo_rd_en,
                 line_data => line_data, line_length => line_length,
                 line_ready => line_ready, line_error => line_error ) ;

   -- mock read-only FIFO: serves test_bytes in order, one per fifo_rd_en pulse
   fifo_empty  <= '1' when byte_idx >= test_bytes'length else '0' ;
   fifo_rd_data <= test_bytes(byte_idx) when byte_idx < test_bytes'length else (others => '0') ;

   process (resetN, clk)
   begin
      if resetN = '0' then
         byte_idx <= 0 ;
      elsif rising_edge(clk) then
         if fifo_rd_en = '1' and byte_idx < test_bytes'length then
            byte_idx <= byte_idx + 1 ;
         end if ;
      end if ;
   end process ;

   clk_gen : process
   begin
      while not sim_done loop
         wait for clk_period / 2 ;
         clk <= not clk ;
      end loop ;
      wait ;
   end process ;

   check : process
      variable errors        : natural := 0 ;
      variable error_pulses  : natural := 0 ;

      -- waits (with a timeout) for the next line_ready pulse and checks
      -- its length and first two content bytes against what's expected
      procedure expect_line ( constant exp_len   : natural ;
                               constant exp_byte0 : std_logic_vector(7 downto 0) ;
                               constant exp_byte1 : std_logic_vector(7 downto 0) ;
                               constant name       : string ) is
         variable timed_out : boolean := true ;
      begin
         for i in 1 to 200 loop
            wait until rising_edge(clk) ;
            wait for 1 ns ; -- let the DUT's registered outputs for this edge settle
            if line_ready = '1' then
               timed_out := false ;
               exit ;
            end if ;
         end loop ;

         if timed_out then
            errors := errors + 1 ;
            report "tb_line_receiver: FAIL - " & name & " - timed out waiting for line_ready"
               severity error ;
         else
            if unsigned(line_length) /= exp_len then
               errors := errors + 1 ;
               report "tb_line_receiver: FAIL - " & name & " - wrong line_length" severity error ;
            end if ;
            if exp_len >= 1 and line_data(7 downto 0) /= exp_byte0 then
               errors := errors + 1 ;
               report "tb_line_receiver: FAIL - " & name & " - wrong first byte" severity error ;
            end if ;
            if exp_len >= 2 and line_data(15 downto 8) /= exp_byte1 then
               errors := errors + 1 ;
               report "tb_line_receiver: FAIL - " & name & " - wrong second byte" severity error ;
            end if ;
         end if ;
      end procedure ;

   begin
      resetN <= '0' ;
      wait for clk_period * 3 ;
      resetN <= '1' ;
      wait until rising_edge(clk) ;

      -- watch for the single expected line_error pulse concurrently, in a
      -- separate lightweight pass isn't possible in one process without
      -- extra machinery, so just count it opportunistically below by
      -- checking after the whole sequence has been consumed instead.

      expect_line(1, x"41", x"00", "A (LF only)") ;
      expect_line(2, x"42", x"42", "BB (CR+LF together)") ;
      expect_line(1, x"43", x"00", "C (CR only)") ;
      expect_line(1, x"58", x"00", "X (not swallowed after CR)") ;
      expect_line(1, x"44", x"00", "D") ;
      expect_line(0, x"00", x"00", "immediate empty line after D") ;
      -- the 9-char overflow line produces no line_ready at all - skip straight
      -- to the recovery line, but first make sure line_error did pulse once
      for i in 1 to 300 loop
         wait until rising_edge(clk) ;
         wait for 1 ns ; -- let the DUT's registered outputs for this edge settle
         if line_error = '1' then
            error_pulses := error_pulses + 1 ;
         end if ;
         exit when line_ready = '1' ;
      end loop ;
      if error_pulses /= 1 then
         errors := errors + 1 ;
         report "tb_line_receiver: FAIL - expected exactly one line_error pulse for the too-long line, got " &
                integer'image(error_pulses)
            severity error ;
      end if ;
      if unsigned(line_length) /= 2 or line_data(7 downto 0) /= x"4F" or line_data(15 downto 8) /= x"4B" then
         errors := errors + 1 ;
         report "tb_line_receiver: FAIL - recovery line 'OK' after the overflow was wrong" severity error ;
      end if ;

      if errors = 0 then
         report "tb_line_receiver: ALL TESTS PASSED" severity note ;
      else
         report "tb_line_receiver: " & integer'image(errors) & " CHECK(S) FAILED" severity error ;
      end if ;

      sim_done <= true ;
      wait ;
   end process ;

end sim ;
