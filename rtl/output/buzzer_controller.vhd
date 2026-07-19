----------------------------------------------------------------
-- buzzer_controller : drives the passive piezo buzzer for      --
-- exactly two triggers (spec section 13.1 concept, but a        --
-- project-specific reduced design - see project memory          --
-- "final product vision", decided 2026-07-16, which replaces    --
-- the spec's per-event-type BUZZER_PATTERN opcode entirely):    --
--   1) system_enable rising edge (BUTTON0 -> SYSTEM_ON)          --
--   2) table_not_empty rising edge (the first event enters an   --
--      otherwise-empty event_table_manager table)                --
-- Both produce the same short beep - no other event ever makes  --
-- the buzzer sound again while it's active.                     --
--                                                               --
-- Reuses course-provided blocks (lib/course_blocks) end to end: --
--   gozer   - edge-detects each level input into a one-clock     --
--             rising-edge pulse                                  --
--   pacer   - turns a one-clock trigger pulse into a fixed-      --
--             duration "note" window (note_duration, no space)   --
--   audio_gen - generates the actual square-wave tone while its  --
--             din is held high (i.e. exactly for the pacer's     --
--             note window) - the buzzer is passive (confirmed    --
--             from the Add-On card's schematic, see project      --
--             notes), so a real tone must be generated, not just --
--             an on/off gate.                                    --
----------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all ;

entity buzzer_controller is
   generic ( clk_hz          : integer  := 50_000_000 ;
             beep_duration_cs: positive := 20         ; -- [1/100 sec] units - 20 = 0.2s
             beep_freq_hz    : positive := 2000        ) ;
   port ( resetN          : in  std_logic ;
          clk             : in  std_logic ;
          system_enable   : in  std_logic ; -- level, from system_master_ctrl
          table_not_empty : in  std_logic ; -- level, '1' when event_table_manager holds at least one event
          buzzer_out      : out std_logic ) ;
end buzzer_controller ;

architecture arc_buzzer_controller of buzzer_controller is

   component gozer
      port ( resetN, clk, din   : in  std_logic ;
             rise, fall, change : out std_logic ) ;
   end component ;

   component pacer
      generic ( f_clk          : positive := 25000000 ;
                note_duration  : positive :=       50 ;
                space_duration : natural  :=       50 ) ;
      port ( resetN, clk : in  std_logic ;
             din         : in  std_logic ;
             dout        : out std_logic ) ;
   end component ;

   component audio_gen
      generic ( idle_state : natural  := 0        ;
                f_clk      : positive := 25000000 ;
                f_audio    : positive := 500       ) ;
      port ( resetN, clk : in  std_logic ;
             din         : in  std_logic ;
             aout        : out std_logic ) ;
   end component ;

   signal system_on_rise   : std_logic ;
   signal first_event_rise : std_logic ;
   signal unused_fall1, unused_chg1 : std_logic ;
   signal unused_fall2, unused_chg2 : std_logic ;

   signal beep_trigger : std_logic ;
   signal beep_window  : std_logic ;

begin

   u_edge_system_on : gozer
      port map ( resetN => resetN, clk => clk, din => system_enable,
                 rise => system_on_rise, fall => unused_fall1, change => unused_chg1 ) ;

   u_edge_first_event : gozer
      port map ( resetN => resetN, clk => clk, din => table_not_empty,
                 rise => first_event_rise, fall => unused_fall2, change => unused_chg2 ) ;

   beep_trigger <= system_on_rise or first_event_rise ;

   u_pacer : pacer
      generic map ( f_clk => clk_hz, note_duration => beep_duration_cs, space_duration => 0 )
      port map ( resetN => resetN, clk => clk, din => beep_trigger, dout => beep_window ) ;

   u_audio_gen : audio_gen
      generic map ( idle_state => 0, f_clk => clk_hz, f_audio => beep_freq_hz )
      port map ( resetN => resetN, clk => clk, din => beep_window, aout => buzzer_out ) ;

end arc_buzzer_controller ;
