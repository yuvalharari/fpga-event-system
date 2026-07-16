----------------------------------------------------------------
-- response_builder : formats text ACK/NACK responses (spec     --
-- section 17, 10.2). Reduced initial scope, matching the        --
-- reduced text_command_parser scope so far:                     --
--   build_ack             -> "ACK,INSTANCE=<hex>"                --
--   build_nack_bad_format -> "NACK,BAD_FORMAT"                   --
--   build_nack_unknown    -> "NACK,UNKNOWN_COMMAND"               --
-- More response types (STARTED, PREEMPTED, STATUS, ...) will be --
-- added once the corresponding upstream blocks exist.            --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;
use ieee.numeric_std.all ;

entity response_builder is
   generic ( max_response_length : positive := 32 ) ;
   port ( resetN                 : in  std_logic                                          ;
          clk                    : in  std_logic                                          ;
          build_ack              : in  std_logic                                          ; -- request pulse
          build_nack_bad_format  : in  std_logic                                          ; -- request pulse
          build_nack_unknown     : in  std_logic                                          ; -- request pulse
          param_byte             : in  std_logic_vector(7 downto 0)                       ; -- instance id, for ACK
          resp_data              : out std_logic_vector(max_response_length*8-1 downto 0) ;
          resp_length            : out std_logic_vector(7 downto 0)                       ;
          resp_ready             : out std_logic                                          ) ; -- one-clock pulse
end response_builder ;

architecture arc_response_builder of response_builder is

   type byte_array_t is array (0 to max_response_length - 1) of std_logic_vector(7 downto 0) ;
   signal resp_buf : byte_array_t ;

   -- converts one 4-bit nibble to its ASCII hex character ('0'-'9','A'-'F')
   function nibble_to_hex ( constant n : std_logic_vector(3 downto 0) ) return std_logic_vector is
      variable result : unsigned(7 downto 0) ;
   begin
      if unsigned(n) <= 9 then
         result := x"30" + resize(unsigned(n), 8) ; -- '0' + n
      else
         result := x"37" + resize(unsigned(n), 8) ; -- 'A' - 10 + n
      end if ;
      return std_logic_vector(result) ;
   end function ;

begin

   process (resetN, clk)
      variable hi, lo : std_logic_vector(7 downto 0) ;
   begin
      if resetN = '0' then
         resp_ready  <= '0' ;
         resp_length <= (others => '0') ;
      elsif rising_edge(clk) then
         resp_ready <= '0' ; -- one-clock pulse, defaulted low every cycle

         if build_ack = '1' then
            hi := nibble_to_hex(param_byte(7 downto 4)) ;
            lo := nibble_to_hex(param_byte(3 downto 0)) ;
            -- "ACK,INSTANCE=" (13 chars, positions 0-12) + hi + lo = 15 chars
            resp_buf(0)  <= x"41" ; -- A
            resp_buf(1)  <= x"43" ; -- C
            resp_buf(2)  <= x"4B" ; -- K
            resp_buf(3)  <= x"2C" ; -- ,
            resp_buf(4)  <= x"49" ; -- I
            resp_buf(5)  <= x"4E" ; -- N
            resp_buf(6)  <= x"53" ; -- S
            resp_buf(7)  <= x"54" ; -- T
            resp_buf(8)  <= x"41" ; -- A
            resp_buf(9)  <= x"4E" ; -- N
            resp_buf(10) <= x"43" ; -- C
            resp_buf(11) <= x"45" ; -- E
            resp_buf(12) <= x"3D" ; -- =
            resp_buf(13) <= hi ;
            resp_buf(14) <= lo ;
            resp_length  <= x"0F" ; -- 15
            resp_ready   <= '1' ;

         elsif build_nack_bad_format = '1' then
            -- "NACK,BAD_FORMAT" = 15 chars
            resp_buf(0)  <= x"4E" ; -- N
            resp_buf(1)  <= x"41" ; -- A
            resp_buf(2)  <= x"43" ; -- C
            resp_buf(3)  <= x"4B" ; -- K
            resp_buf(4)  <= x"2C" ; -- ,
            resp_buf(5)  <= x"42" ; -- B
            resp_buf(6)  <= x"41" ; -- A
            resp_buf(7)  <= x"44" ; -- D
            resp_buf(8)  <= x"5F" ; -- _
            resp_buf(9)  <= x"46" ; -- F
            resp_buf(10) <= x"4F" ; -- O
            resp_buf(11) <= x"52" ; -- R
            resp_buf(12) <= x"4D" ; -- M
            resp_buf(13) <= x"41" ; -- A
            resp_buf(14) <= x"54" ; -- T
            resp_length  <= x"0F" ; -- 15
            resp_ready   <= '1' ;

         elsif build_nack_unknown = '1' then
            -- "NACK,UNKNOWN_COMMAND" = 20 chars
            resp_buf(0)  <= x"4E" ; -- N
            resp_buf(1)  <= x"41" ; -- A
            resp_buf(2)  <= x"43" ; -- C
            resp_buf(3)  <= x"4B" ; -- K
            resp_buf(4)  <= x"2C" ; -- ,
            resp_buf(5)  <= x"55" ; -- U
            resp_buf(6)  <= x"4E" ; -- N
            resp_buf(7)  <= x"4B" ; -- K
            resp_buf(8)  <= x"4E" ; -- N
            resp_buf(9)  <= x"4F" ; -- O
            resp_buf(10) <= x"57" ; -- W
            resp_buf(11) <= x"4E" ; -- N
            resp_buf(12) <= x"5F" ; -- _
            resp_buf(13) <= x"43" ; -- C
            resp_buf(14) <= x"4F" ; -- O
            resp_buf(15) <= x"4D" ; -- M
            resp_buf(16) <= x"4D" ; -- M
            resp_buf(17) <= x"41" ; -- A
            resp_buf(18) <= x"4E" ; -- N
            resp_buf(19) <= x"44" ; -- D
            resp_length  <= x"14" ; -- 20
            resp_ready   <= '1' ;
         end if ;
      end if ;
   end process ;

   flatten : for i in 0 to max_response_length - 1 generate
      resp_data((i + 1) * 8 - 1 downto i * 8) <= resp_buf(i) ;
   end generate ;

end arc_response_builder ;
