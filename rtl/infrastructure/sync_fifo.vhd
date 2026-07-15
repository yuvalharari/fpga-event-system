----------------------------------------------------------------
-- sync_fifo : generic synchronous FIFO, reused for RX/TX byte  --
-- queues (spec section 17: "sync_fifo - FIFO גנרי לשימוש חוזר"; --
-- section 15 memory table lists RX FIFO 16/32 bytes, TX FIFO   --
-- 32/64 bytes - both built from this same generic block).      --
--                                                               --
-- Standard ready/valid-ish handshake: wr_en/wr_data to push,   --
-- rd_en to pop (rd_data is valid combinationally the same cycle --
-- rd_en is asserted, for whatever is at the front of the queue --
-- at that moment). full/empty are always up to date; overflow  --
-- is a sticky flag set if a write is attempted while full (spec --
-- section 16 error table: overflow -> sticky flag, error count).--
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity sync_fifo is
   generic ( data_width : positive := 8  ;
             depth      : positive := 16 ) ;
   port ( resetN   : in  std_logic                               ;
          clk      : in  std_logic                               ;
          wr_en    : in  std_logic                               ;
          wr_data  : in  std_logic_vector(data_width-1 downto 0) ;
          rd_en    : in  std_logic                               ;
          rd_data  : out std_logic_vector(data_width-1 downto 0) ;
          full     : out std_logic                               ;
          empty    : out std_logic                               ;
          overflow : out std_logic                               ) ; -- sticky, cleared only by resetN
end sync_fifo ;

architecture arc_sync_fifo of sync_fifo is

   type mem_t is array (0 to depth-1) of std_logic_vector(data_width-1 downto 0) ;
   signal mem : mem_t ;

   signal wr_ptr : integer range 0 to depth-1 ;
   signal rd_ptr : integer range 0 to depth-1 ;
   signal count  : integer range 0 to depth   ;

   signal overflow_reg : std_logic ;

begin

   full     <= '1' when count = depth else '0' ;
   empty    <= '1' when count = 0     else '0' ;
   overflow <= overflow_reg ;
   rd_data  <= mem(rd_ptr) ;

   process (resetN, clk)
      variable wr_ok : boolean ;
      variable rd_ok : boolean ;
   begin
      if resetN = '0' then
         wr_ptr       <= 0   ;
         rd_ptr       <= 0   ;
         count        <= 0   ;
         overflow_reg <= '0' ;
      elsif rising_edge(clk) then

         wr_ok := (wr_en = '1') and (count < depth) ;
         rd_ok := (rd_en = '1') and (count > 0) ;

         -- a write attempted while genuinely full sets the sticky overflow flag
         if wr_en = '1' and count = depth then
            overflow_reg <= '1' ;
         end if ;

         if wr_ok then
            mem(wr_ptr) <= wr_data ;
            if wr_ptr = depth - 1 then
               wr_ptr <= 0 ;
            else
               wr_ptr <= wr_ptr + 1 ;
            end if ;
         end if ;

         if rd_ok then
            if rd_ptr = depth - 1 then
               rd_ptr <= 0 ;
            else
               rd_ptr <= rd_ptr + 1 ;
            end if ;
         end if ;

         -- simultaneous read+write: one item in, one out, count unchanged
         if wr_ok and not rd_ok then
            count <= count + 1 ;
         elsif rd_ok and not wr_ok then
            count <= count - 1 ;
         end if ;

      end if ;
   end process ;

end arc_sync_fifo ;
