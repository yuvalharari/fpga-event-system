----------------------------------------------------------------
-- line_receiver : builds complete ASCII text lines out of the  --
-- byte stream popped from the RX FIFO (spec section 17: "line_ --
-- receiver - בניית שורות טקסט שלמות מבתים"). Commands are lines --
-- terminated by CR, LF, or both together (spec section 10.1).   --
--                                                               --
-- Handles:                                                     --
--   - CR, LF, or CR+LF (in either order) as ONE line terminator --
--     (the second character of a CRLF pair is silently         --
--     swallowed, not treated as a second, empty line)           --
--   - a line longer than max_line_length: raises line_error     --
--     once and discards bytes until the next terminator, so a  --
--     garbled/oversized line doesn't corrupt the next one       --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity line_receiver is
   generic ( max_line_length : positive := 32 ) ; -- spec section 15: command payload buffer, 32 bytes
   port ( resetN       : in  std_logic                                        ;
          clk          : in  std_logic                                        ;
          -- RX FIFO read-side (this block pulls bytes as fast as they arrive)
          fifo_empty   : in  std_logic                                        ;
          fifo_rd_data : in  std_logic_vector(7 downto 0)                     ;
          fifo_rd_en   : out std_logic                                        ;
          -- a complete line, valid for one clock when line_ready pulses
          line_data    : out std_logic_vector(max_line_length*8-1 downto 0)   ;
          line_length  : out std_logic_vector(7 downto 0)                     ; -- number of valid bytes in line_data
          line_ready   : out std_logic                                       ; -- one-clock pulse
          line_error   : out std_logic                                        ) ; -- one-clock pulse: line was too long, discarded
end line_receiver ;

architecture arc_line_receiver of line_receiver is

   constant CR : std_logic_vector(7 downto 0) := x"0D" ;
   constant LF : std_logic_vector(7 downto 0) := x"0A" ;

   type byte_array_t is array (0 to max_line_length - 1) of std_logic_vector(7 downto 0) ;
   signal line_buf : byte_array_t ;

   type state_t is (COLLECT, SKIP_PAIR, DISCARD) ;
   signal state : state_t ;

   signal pos             : integer range 0 to max_line_length ;
   signal last_terminator : std_logic_vector(7 downto 0) ;

begin

   -- pull a byte every cycle one is available; the FIFO's rd_data is
   -- combinational (always shows the front item), so this pop and this
   -- process's reaction to fifo_rd_data happen on the same clock edge
   fifo_rd_en <= not fifo_empty ;

   process (resetN, clk)
   begin
      if resetN = '0' then
         state           <= COLLECT ;
         pos             <= 0 ;
         last_terminator <= (others => '0') ;
         line_length     <= (others => '0') ;
         line_ready      <= '0' ;
         line_error      <= '0' ;
      elsif rising_edge(clk) then
         line_ready <= '0' ; -- one-clock pulses, defaulted low each cycle
         line_error <= '0' ;

         if fifo_empty = '0' then
            case state is

               ---------------------------------------------------------
               when COLLECT =>
                  if fifo_rd_data = CR or fifo_rd_data = LF then
                     line_length     <= std_logic_vector(to_unsigned(pos, 8)) ;
                     line_ready      <= '1' ;
                     last_terminator <= fifo_rd_data ;
                     pos             <= 0 ;
                     state           <= SKIP_PAIR ;
                  elsif pos = max_line_length then
                     -- buffer already full and still no terminator - too long
                     line_error <= '1' ;
                     pos        <= 0 ;
                     state      <= DISCARD ;
                  else
                     line_buf(pos) <= fifo_rd_data ;
                     pos           <= pos + 1 ;
                  end if ;

               ---------------------------------------------------------
               -- right after emitting a line: swallow one matching CR/LF
               -- pair character if present, otherwise this byte is the
               -- start of the next line and must not be discarded
               ---------------------------------------------------------
               when SKIP_PAIR =>
                  if (last_terminator = CR and fifo_rd_data = LF) or
                     (last_terminator = LF and fifo_rd_data = CR) then
                     state <= COLLECT ; -- consumed the paired terminator
                  elsif fifo_rd_data = CR or fifo_rd_data = LF then
                     -- an immediate empty line (e.g. "\n\n")
                     line_length     <= (others => '0') ;
                     line_ready      <= '1' ;
                     last_terminator <= fifo_rd_data ;
                     -- stay in SKIP_PAIR: chained empty lines/terminators
                  else
                     line_buf(0) <= fifo_rd_data ;
                     pos         <= 1 ;
                     state       <= COLLECT ;
                  end if ;

               ---------------------------------------------------------
               when DISCARD =>
                  if fifo_rd_data = CR or fifo_rd_data = LF then
                     last_terminator <= fifo_rd_data ;
                     state           <= SKIP_PAIR ;
                  end if ;
                  -- else: keep silently discarding this oversized line

            end case ;
         end if ;
      end if ;
   end process ;

   flatten : for i in 0 to max_line_length - 1 generate
      line_data((i + 1) * 8 - 1 downto i * 8) <= line_buf(i) ;
   end generate ;

end arc_line_receiver ;
