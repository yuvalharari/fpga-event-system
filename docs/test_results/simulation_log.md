# Simulation Log

Chronological record of every ModelSim testbench run for this project. One
entry per block, appended to as new blocks are simulated (spec section 21 -
verification plan).

---

## clock_tick_gen — `tb_clock_tick_gen.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `clock_tick_gen` does:** generates single-clock-cycle enable pulses at
1µs / 1ms / 10ms / 1s rates, cascaded from the system clock (spec section 20 -
tick generation).

**What the testbench checks:**
- The DUT's divider generics (`div_1us`/`div_1ms`/`div_10ms`/`div_1s`) are
  overridden to 4/4/4/4 instead of the real 50MHz-derived values, so the full
  cascade (1us -> 1ms -> 10ms -> 1s) completes in 4x4x4x4 = 256 clock cycles
  instead of the real 50,000,000. This validates the *cascading structure* of
  the design. The default 50MHz divider constants are plain integer division
  and will be re-confirmed visually on real hardware later via a 1Hz
  heartbeat LED.
- For each of the four outputs (`tick_1us`, `tick_1ms`, `tick_10ms`,
  `tick_1s`):
  - pulse width is exactly one clock cycle
  - three consecutive periods match the expected divider count (4, 16, 64,
    256 clocks respectively)

**Result: ALL TESTS PASSED** — no errors, simulation completed and halted on
its own (no fatal errors, no manual stop needed).

```
tb_clock_tick_gen: tick_1us width+period check PASSED    Time: 420 ns
tb_clock_tick_gen: tick_1ms width+period check PASSED    Time: 1400 ns
tb_clock_tick_gen: tick_10ms width+period check PASSED   Time: 5260 ns
tb_clock_tick_gen: tick_1s width+period check PASSED     Time: 20640 ns
tb_clock_tick_gen: ALL TESTS PASSED                       Time: 20640 ns
```

Waveform (`add wave -r /*` before `run -all`) confirmed visually: `tick_1us`
toggles fastest, `tick_1ms`/`tick_10ms`/`tick_1s` each fire at a quarter the
rate of the one before them, matching the 4/4/4/4 generic override.

**Note - testbench bug found and fixed during this session:** an earlier run
of this same testbench crashed with `Fatal: (vsim-3421) Value -2147483648 for
cycle is out of range` after simulating ~43 seconds of simulated time. Cause:
the testbench's free-running clock never stopped after the checks finished,
so `run -all` had no natural end point and its internal cycle counter
(a 32-bit `natural`) eventually overflowed. Fixed by adding a `sim_done` flag
that halts the clock-generator process once `main_check` finishes, so
`run -all` now returns control immediately after "ALL TESTS PASSED". The same
fix was applied to `tb_reset_controller.vhd` pre-emptively.

**Note - second testbench bug found (via `tb_reset_controller`) and fixed:**
the `sim_done` fix above introduced `clk <= not clk;` *before* `wait for
clk_period/2;` inside the clock-generator process, which makes the very first
clock edge land at time 0 (a delta cycle) instead of at `clk_period/2` like
the original bare `clk <= not clk after clk_period/2;` did - a half-period
phase shift versus what earlier runs assumed. This went unnoticed here
because this testbench only measures *relative* periods between pulses, which
aren't affected by a one-time phase shift at time 0 - but it broke the
absolute edge-counting in `tb_reset_controller`. Fixed by swapping the order
(`wait` before `clk <= not clk`) in both testbenches. Re-run confirmed below.

**Re-run after both fixes (phase + errors counter):**
```
tb_clock_tick_gen: tick_1us width+period check done    Time: 430 ns
tb_clock_tick_gen: tick_1ms width+period check done    Time: 1410 ns
tb_clock_tick_gen: tick_10ms width+period check done   Time: 5270 ns
tb_clock_tick_gen: tick_1s width+period check done     Time: 20650 ns
tb_clock_tick_gen: ALL TESTS PASSED                    Time: 20650 ns
```
Same timings as the very first (pre-bug) run - confirms the fix fully restored
correct behaviour.

---

## reset_controller — `tb_reset_controller.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `reset_controller` does:** power-on reset generator. The DE0 has no
dedicated hardware reset pin routed to the FPGA (BUTTON0-2 are all reassigned
to system-level roles by spec section 14), so this block just holds `resetN`
low for `hold_cycles` clocks after configuration/power-up (relying on the
FPGA's register power-up initial values) and then releases it high for good
(spec sections 17, 20).

**What the testbench checks** (`hold_cycles` overridden to 5 for a fast sim):
- `resetN = '0'` before the first clock edge
- `resetN` stays `'0'` through the first `hold_cycles - 1` (4) edges
- `resetN` releases to `'1'` exactly on the 5th edge
- `resetN` stays `'1'` afterwards for 10 more clocks (no glitching back to 0)

**Result: ALL TESTS PASSED** — no errors, simulation completed and halted on
its own.

```
tb_reset_controller: ALL TESTS PASSED   Time: 291 ns
```

**Testbench bugs found and fixed along the way (see notes on the
`clock_tick_gen` entry above for the full explanation):**
1. The very first check (`resetN = '0'` "at time 0") read a stale/
   uninitialized value because it sampled before the DUT's internal signal
   had a chance to propagate through a delta cycle. Fixed by adding
   `wait for 1 ns;` before that first check.
2. `assert ... severity error` alone does not stop the process or flag
   overall failure - an earlier version of this testbench printed a false
   "ALL TESTS PASSED" even after a real check had already failed. Fixed by
   tracking failures in an `errors` counter and only reporting PASSED when
   `errors = 0` (same fix applied to `tb_clock_tick_gen.vhd`).
3. The clock-generator phase-shift bug described above caused a false
   "released too early, at edge 4" failure on the first attempt after fixes
   1-2 were applied. Fixed by reordering `wait` before `clk <= not clk`.

---

## button_pulse — `tb_button_pulse.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `button_pulse` does:** wraps the course-provided `clean_key` (debounce,
outputs a clean level) and `gozer` (rise/fall/change edge detector) blocks
together to turn one raw active-low DE0 push-button into a debounced,
single-clock-wide, active-high press pulse - the "debounced one-shot" signal
`system_master_ctrl` needs (spec sections 17, 18.4). `clean_key`/`gozer`
themselves are course material kept local-only in `lib/course_blocks/` (not
in the public repo); `button_pulse.vhd` is original wiring code.

**What the testbench checks** (`clk_freq`/`max_bounce_time_ms` overridden to
500/10 so `clean_key`'s internal debounce window is 5 clocks instead of the
real 500,000 @ 50MHz/10ms):
- a clean press produces exactly one pulse
- a clean release produces zero pulses
- a bouncy press (rapid toggles before settling) still collapses to exactly
  one pulse
- a bouncy release produces zero pulses
- a second clean press pulses again (confirms it isn't "stuck" after the
  first press)

**Result: ALL TESTS PASSED** — no errors, all 5 scenarios passed, simulation
completed and halted on its own.

```
tb_button_pulse: ALL TESTS PASSED   Time: 3911 ns
```

Waveform confirmed visually: `button_n` bounces (visible narrow glitches)
during the bouncy-press/release scenarios, while `pulse` still only fires
once, cleanly, per genuine press.

---

## system_master_ctrl — `tb_system_master_ctrl.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `system_master_ctrl` does:** the system-wide SYSTEM_ON/SYSTEM_OFF
master state (spec sections 14.1, 18.4, 19.5). BUTTON0's debounced one-shot
pulse turns the system ON; BUTTON2's turns it OFF. A pulse that doesn't apply
to the current state (e.g. BUTTON0 while already ON) has no effect. Power-up/
reset default is SYSTEM_OFF (the "safe output state", spec section 16.2).

**What the testbench checks** (button pulses driven directly as one-clock
pulses - the debounce itself is verified separately in `tb_button_pulse`,
this is a focused unit test of just the FSM logic):
1. after reset, `system_enable_o = '0'` (SYSTEM_OFF)
2. a BUTTON0 pulse turns it ON (`system_enable_o = '1'`)
3. a second BUTTON0 pulse while already ON has no effect
4. a BUTTON2 pulse turns it OFF
5. a second BUTTON2 pulse while already OFF has no effect
6. a second full ON/OFF cycle works (not a one-shot fluke)

**Result: ALL TESTS PASSED** — no errors, all 6 checks passed, simulation
completed and halted on its own.

```
tb_system_master_ctrl: ALL TESTS PASSED   Time: 291 ns
```

---

## uart_tx + uart_rx loopback — `tb_uart_loopback.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `uart_tx`/`uart_rx` do:** wrap the course-provided UART engines
(`receiver.vhd` as-is; `transmitter.vhd`, bug-fixed - see its own header
comment for what was wrong and why) with this project's naming conventions
and, for `uart_rx`, an extra synchronizer flip-flop stage ahead of the raw
async `rx` input (spec section 11.3 requires at least two stages; the
underlying `receiver.vhd` only has one internally, so this wrapper adds the
second).

**What the testbench checks** (`clk_hz`/`baud_rate` overridden to 5000/100,
i.e. 50 clocks/bit, for a fast simulation of the same relative timing as the
real 50MHz/9600baud case): `uart_tx`'s serial output is wired directly to
`uart_rx`'s input (loopback). Sends 4 bytes back-to-back and checks, for
each: `data_valid` fires, the received byte matches exactly what was sent,
`dout_ready` asserts and then clears correctly after being acknowledged with
`read_dout`. Bytes chosen to stress every bit transition (0x55, 0xA3) and
both all-zero/all-one edge cases (0x00, 0xFF).

**Result: ALL TESTS PASSED** — no errors, all 4 bytes round-tripped
correctly, simulation completed and halted on its own.

```
tb_uart_loopback: ALL TESTS PASSED   Time: 41471 ns
```

4 benign warnings appeared, all at Time: 0 ps only (`"There is an
'U'|'X'|'W'|'Z'|'-' in an arithmetic operand"`) - a well-known artifact of
`std_logic_unsigned`-style arithmetic on signals that haven't been reset yet
at the very first simulation instant. Not a functional issue: it appears
exactly once (not recurring throughout the run), and the actual post-reset
behavior is fully verified correct by the passing checks.

---

## uart_echo_test — `tb_uart_echo_test.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `uart_echo_test` does:** TEMPORARY hardware bring-up block only (not
part of the final event system) - whatever byte `uart_rx` receives, sends
straight back out via `uart_tx`. Used to confirm the real UART link works
end-to-end against a PC terminal, before the real text command parser +
response builder (spec section 10) replaces it.

**What the testbench checks** (drives the `rx_dout`/`rx_data_valid`/
`tx_ready` interface directly - `uart_rx`/`uart_tx` themselves are already
verified separately in `tb_uart_loopback.vhd`, this is a focused unit test of
just the echo FSM):
1. `rx_data_valid` pulse -> `rx_read_dout` acknowledges within one clock
2. with `tx_ready` held low, `tx_write_din` must NOT fire prematurely - the
   FSM must actually wait for the transmitter to be ready
3. once `tx_ready` goes high, the correct byte is sent back
4. a second, different byte works right after (not "stuck" after the first)

**Result: ALL TESTS PASSED** — no errors, simulation completed and halted on
its own.

```
tb_uart_echo_test: ALL TESTS PASSED   Time: 231 ns
```

---

## sync_fifo — `tb_sync_fifo.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `sync_fifo` does:** generic synchronous FIFO (circular buffer), reused
for both the RX and TX byte queues (spec section 17: "sync_fifo - FIFO גנרי
לשימוש חוזר"; section 15 memory table). Push with `wr_en`/`wr_data`, pop with
`rd_en` (`rd_data` always shows the front of the queue), `full`/`empty`
status, `overflow` sticky flag if a write is attempted while full.

**What the testbench checks** (small depth=4 for clear boundary testing):
1. empty/full/overflow correct right after reset
2. single write+read round trip (value and empty/full flags)
3. filling to exactly "full", in the right order
4. writing while full sets the sticky overflow flag, without corrupting
   `full`
5. draining preserves write order (first in, first out)
6. simultaneous read+write while partially full keeps the internal count
   consistent (doesn't become empty/full incorrectly)
7. pointer wraparound across more writes/reads than `depth` (10 items
   through a depth-4 FIFO)

**Result: ALL TESTS PASSED** — no errors, all 7 scenarios passed, simulation
completed and halted on its own.

```
tb_sync_fifo: ALL TESTS PASSED   Time: 791 ns
```

---

## line_receiver — `tb_line_receiver.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `line_receiver` does:** builds complete ASCII text lines out of the
byte stream popped from the RX FIFO (spec section 17; commands are lines
terminated by CR, LF, or both together, spec section 10.1). Handles CR-only,
LF-only, and CR+LF-together as a single terminator (the second character of
a pair is silently swallowed, not treated as a second empty line), and lines
longer than `max_line_length` (raises `line_error` once and discards bytes
until the next terminator, so a garbled/oversized line doesn't corrupt what
comes after it).

**What the testbench checks** (`max_line_length` = 8, small, to make the
overflow case easy to trigger; bytes fed through a mock read-only FIFO
interface - a real `sync_fifo` is verified separately):
1. `"A\n"` -> one line, length 1, "A" (LF only)
2. `"BB\r\n"` -> one line, length 2, "BB" (CR+LF together, one terminator)
3. `"C\rX\n"` -> two lines: "C" (CR only), then "X" (proves a non-matching
   byte right after a terminator starts a new line, isn't swallowed)
4. `"D\n\n"` -> "D", then an immediate empty line (length 0)
5. `"123456789\n"` -> 9 characters into an 8-byte buffer: `line_error`
   pulses exactly once, no `line_ready` for the garbled data
6. `"OK\n"` right after the overflow -> a clean line, confirms recovery

**Result: ALL TESTS PASSED** — no errors, all 6 scenarios passed, simulation
completed and halted on its own.

```
tb_line_receiver: ALL TESTS PASSED   Time: 571 ns
```

**Testbench bug found and fixed:** the same class of delta-cycle race we
already hit in `tb_reset_controller.vhd` - `expect_line`'s wait loop checked
`line_ready` immediately after `wait until rising_edge(clk)`, without
letting the DUT's registered outputs for that same edge settle first. This
caused checks to intermittently catch a *later* line's pulse instead of the
intended one, showing up as "wrong first byte" failures (content mismatches)
even though the design itself was correct. Fixed by adding `wait for 1 ns`
before reading `line_ready`/`line_error` in both wait loops.

---

## text_command_parser — `tb_text_command_parser.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `text_command_parser` does:** tokenizes and validates ASCII commands
from a complete line (spec sections 17, 10.1, 19.1). Reduced initial scope
(vertical slice, spec section 3.3): only `EVT,<type>,<source>` (fixed 9
characters) and `ACK,<instance>` (fixed 6 characters) are supported so far,
both hex byte fields. A general tokenizer for the full 12-command protocol
will replace this once the basic path is proven end to end. Reports error
code 01 (bad format) or 02 (unknown command) per spec section 16.

**What the testbench checks** (`line_data`/`line_length`/`line_ready` driven
directly - `line_receiver` is verified separately):
1. valid `"EVT,01,03"` -> `cmd_is_evt`, `event_type=0x01`, `source_id=0x03`
2. valid `"ACK,17"` -> `cmd_is_ack`, `instance_id=0x17`
3. `"XYZ,01,02"` (unknown command) -> error code 02
4. `"EVT,ZZ,03"` (bad hex in field 1) -> error code 01
5. `"EVT,01,ZZ"` (bad hex in field 2) -> error code 01
6. `"EVT,01"` (wrong length for EVT) -> rejected
7. `"EVT,ab,cd"` (lowercase hex digits) -> accepted, same as uppercase

**Result: ALL TESTS PASSED** — no errors, all 7 scenarios passed, simulation
completed and halted on its own.

```
tb_text_command_parser: ALL TESTS PASSED   Time: 211 ns
```

**Testbench bug found and fixed:** `feed_line` waited for *two* clock edges
before checking `cmd_valid`/`cmd_error` - but those are one-clock pulses that
rise on the first edge and are cleared again by the DUT's own default
assignment on the second edge, so every check was reading the pulse *after*
it had already ended (all 7 scenarios failed the same way as a result).
Fixed by checking right after the first (triggering) edge settles, not a
second edge later.

---

## response_builder — `tb_response_builder.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `response_builder` does:** formats text ACK/NACK responses (spec
sections 17, 10.2). Reduced initial scope, matching `text_command_parser`'s
current scope: `build_ack` -> `"ACK,INSTANCE=<hex>"`, `build_nack_bad_format`
-> `"NACK,BAD_FORMAT"`, `build_nack_unknown` -> `"NACK,UNKNOWN_COMMAND"`.
More response types (STARTED, PREEMPTED, STATUS, ...) will be added once the
corresponding upstream blocks exist.

**What the testbench checks:** every single byte of each formatted response
(not just a couple of spot checks - the text tables were typed out by hand,
character by character, so full coverage matters here):
1. `build_ack`, param=0x17 -> `"ACK,INSTANCE=17"` (15 chars)
2. `build_ack`, param=0xAB -> `"ACK,INSTANCE=AB"` (hex letters, not just
   digits)
3. `build_nack_bad_format` -> `"NACK,BAD_FORMAT"` (15 chars)
4. `build_nack_unknown` -> `"NACK,UNKNOWN_COMMAND"` (20 chars)

**Result: ALL TESTS PASSED** — no errors, all 4 scenarios (every byte of
each) passed, simulation completed and halted on its own.

```
tb_response_builder: ALL TESTS PASSED   Time: 211 ns
```

---

## response_sender — `tb_response_sender.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `response_sender` does:** takes a formatted response from
`response_builder` (up to `max_response_length` bytes) and sends it out,
byte by byte, through a `uart_tx` (spec sections 17, 18.3 ready/valid
handshake), waiting for `tx_ready` between each byte, then appending CR+LF
so the response shows as its own line on the receiving terminal.

**What the testbench checks:** a mock `tx_ready` generator (goes busy for a
few clocks after every `tx_write_din` pulse, mimicking a real `uart_tx`
without needing real baud timing - `uart_tx` itself is verified separately)
plus a capture buffer recording every byte actually sent, compared against
the expected sequence:
1. a short 2-byte response -> exactly those 2 bytes + CR + LF (4 total)
2. a 20-byte response (matching `NACK,UNKNOWN_COMMAND`'s length) -> all 20
   bytes + CR + LF (22 total), in the right order

**Result: ALL TESTS PASSED** — no errors, both scenarios passed, simulation
completed and halted on its own.

```
tb_response_sender: ALL TESTS PASSED   Time: 1611 ns
```

---

## command_dispatcher — `tb_command_dispatcher.vhd`

**Date:** 2026-07-15
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `command_dispatcher` does:** maps `text_command_parser`'s output to
the right `response_builder` request. Reduced-scope note: a successful EVT
reports back the source id as a placeholder "instance" (no
`event_table_manager` yet to allocate a real instance id); a successful ACK
correctly reports the real instance id it named.

**What the testbench checks:**
1. `cmd_valid`+`cmd_is_evt`, `source_id=0x03` -> `build_ack`,
   `param_byte=0x03`
2. `cmd_valid`+`cmd_is_ack`, `instance_id=0x17` -> `build_ack`,
   `param_byte=0x17`
3. `cmd_error`, code=0x01 -> `build_nack_bad_format`
4. `cmd_error`, code=0x02 -> `build_nack_unknown`

**Result: ALL TESTS PASSED** — no errors, all 4 scenarios passed, simulation
completed and halted on its own.

```
tb_command_dispatcher: ALL TESTS PASSED   Time: 211 ns
```

---

## event_definition_rom — `tb_event_definition_rom.vhd`

**Date:** 2026-07-16
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `event_definition_rom` does:** lookup table of default properties per
`event_type` (spec section 7.5/18.1). Reduced initial scope: only `priority`
and `requires_ack` looked up so far (`script_id`/`audio_track` will follow
once the script engine exists). Purely combinational - no `clk`/`resetN`, a
ROM has no state of its own. Uses a custom medical-monitoring event catalog
(12 types) instead of the spec's example fire-alarm catalog - see
`event_definition_rom.vhd`'s header for the full table (type 01
LIFE_THREATENING_EMERGENCY down to 0C SYSTEM_READY).

**What the testbench checks:**
1. All 12 defined event types (`x"01"`-`x"0C"`) -> exact `priority` and
   `requires_ack` match, `type_valid='1'`.
2. Three unrecognized codes (`x"00"`, `x"0D"`, `x"FF"`) -> `type_valid='0'`.

**Result: ALL TESTS PASSED** — no errors, all 15 scenarios passed, simulation
completed and halted on its own (no clock needed for this combinational DUT).

```
tb_event_definition_rom: ALL TESTS PASSED   Time: 15 ns
```

---

## event_table_manager — `tb_event_table_manager.vhd`

**Date:** 2026-07-16
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What `event_table_manager` does:** allocates real event instances (spec
section 7.2/8.1). Reduced initial scope: only allocation is implemented
(search a free slot, load defaults from `event_definition_rom`, write the
slot, assign a real `instance_id` from a free-running 8-bit counter) - no
duplicate detection, merge/replace/escalate policies, slot release, or
ACK-driven state transitions yet (those belong to `duplicate_detector`,
`ack_manager`, `priority_scheduler`, none built yet). A request naming an
`event_type` not in `event_definition_rom`'s catalog is rejected outright
(`alloc_unknown_type='1'`) without touching the table. `event_slots`
defaults to 8 for now (dev/debug default, not final - see
`project_event_slots_sizing` note on why it'll likely grow later).

**What the testbench checks:**
1. Allocate `event_type=01` (LIFE_THREATENING_EMERGENCY) -> `instance_id=0`,
   `priority=111`, `requires_ack='1'`.
2. Allocate `event_type=07` (MEDICATION_MISSED) -> `instance_id=1`,
   `priority=011`, `requires_ack='0'`.
3. Allocate `event_type=0D` (not in the catalog) -> rejected
   (`alloc_ok='0'`, `alloc_unknown_type='1'`), and does NOT consume a
   slot/instance_id - confirmed by the next successful allocation still
   getting `instance_id=2`.
4. Fill the remaining 6 slots (`instance_id` 2..7 in order).
5. A 9th allocation -> table full (`alloc_ok='0'`, `alloc_unknown_type='0'`).
6. A 10th allocation right after -> still table full, no state corruption
   from the failed request.

**Result: ALL TESTS PASSED** — no errors, all scenarios passed, simulation
completed and halted on its own.

```
tb_event_table_manager: ALL TESTS PASSED   Time: 491 ns
```

---

## response_builder (update) — `tb_response_builder.vhd`

**Date:** 2026-07-16
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What changed:** added two new response types (spec section 16 error
table), needed to wire `event_table_manager` into the response chain:
- `build_nack_unknown_evt` -> `"NACK,UNKNOWN_EVENT"` (18 chars, error 03 -
  a syntactically valid EVT command naming an `event_type` not in
  `event_definition_rom`'s catalog).
- `build_nack_table_full` -> `"NACK,TABLE_FULL"` (15 chars, error 04 - a
  valid EVT command but `event_table_manager` has no free slot).

**What the testbench checks (6 scenarios total, unchanged 1-4 plus new
5-6):**
1. `build_ack`, param=0x17 -> `"ACK,INSTANCE=17"`
2. `build_ack`, param=0xAB -> `"ACK,INSTANCE=AB"` (hex letters)
3. `build_nack_bad_format` -> `"NACK,BAD_FORMAT"`
4. `build_nack_unknown` -> `"NACK,UNKNOWN_COMMAND"`
5. `build_nack_unknown_evt` -> `"NACK,UNKNOWN_EVENT"`
6. `build_nack_table_full` -> `"NACK,TABLE_FULL"`

Every byte of every response is checked against the expected ASCII text,
not just spot checks.

**Result: ALL TESTS PASSED** — no errors, all 6 scenarios passed, simulation
completed and halted on its own.

```
tb_response_builder: ALL TESTS PASSED   Time: 291 ns
```

---

## command_dispatcher (update) — `tb_command_dispatcher.vhd`

**Date:** 2026-07-16
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What changed:** EVT commands now go through a real allocation request/
response handshake with `event_table_manager` (spec section 8.1) instead of
using `source_id` as a placeholder instance id. A small two-state FSM
(IDLE / WAIT_ALLOC) issues `alloc_req` and waits for `alloc_done`, then
picks `build_ack` (real instance id), `build_nack_unknown_evt`, or
`build_nack_table_full` based on the result. ACK commands and parser-error
codes 01/02 are still answered directly in one cycle, unchanged.

This testbench instantiates a REAL `event_table_manager` alongside the DUT
(not a mock) - already verified standalone in `tb_event_table_manager` -
to check the actual integration contract between the two blocks.

**What the testbench checks:**
1. `cmd_valid`+`cmd_is_ack`, `instance_id=0x17` -> `build_ack`,
   `param_byte=0x17` (single cycle, unchanged).
2. `cmd_error`, code=0x01 -> `build_nack_bad_format`.
3. `cmd_error`, code=0x02 -> `build_nack_unknown`.
4. EVT, `event_type=01` -> real allocation succeeds, `build_ack`,
   `param_byte=instance_id=0`.
5. EVT, `event_type=07` -> succeeds, `param_byte=instance_id=1`.
6. EVT, `event_type=0D` (not in the catalog) -> `build_nack_unknown_evt`.
7. Fill the remaining 6 slots, then a 9th EVT -> `build_nack_table_full`.

**Result: ALL TESTS PASSED** — no errors, all 7 scenarios passed, simulation
completed and halted on its own.

```
tb_command_dispatcher: ALL TESTS PASSED   Time: 971 ns
```

---

## event_table_manager (update) — `tb_event_table_manager.vhd`

**Date:** 2026-07-16
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What changed:** added slot release (spec's `ack_manager` role, section
8.1/19.2 CANCEL_SCAN). Each slot now also stores the `instance_id` it was
assigned. A new `release_req`/`release_instance_id` request searches the
occupied slots for a match and frees it (`release_ok='1'`); a request
naming an `instance_id` that doesn't currently occupy any slot (wrong id,
already released, never allocated) fails cleanly (`release_ok='0'`)
without touching the table.

**What the testbench checks (10 scenarios total, unchanged 1-6 plus new
7-10):**
1-6. Unchanged (see previous entry - allocation, unknown type rejection,
   table fill, table full).
7. Release `instance_id=3` (occupies a slot) -> `release_ok='1'`, frees it.
8. Allocate again -> succeeds now that a slot is free, gets a NEW
   `instance_id=8` (the counter keeps climbing, `id=3` is not reused).
9. Release `instance_id=3` again -> `release_ok='0'` (no longer occupies
   any slot - the freed slot now holds `instance_id=8`).
10. Release `instance_id=99` (never allocated) -> `release_ok='0'`.

**Result: ALL TESTS PASSED** — no errors, all 10 scenarios passed,
simulation completed and halted on its own.

```
tb_event_table_manager: ALL TESTS PASSED   Time: 651 ns
```

---

## response_builder (update 2) — `tb_response_builder.vhd`

**Date:** 2026-07-16
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What changed:** added `build_nack_unknown_inst` -> `"NACK,UNKNOWN_INSTANCE"`
(21 chars) - a project-defined response, not in the spec's error table,
used when an ACK command names an `instance_id` that doesn't currently
occupy any slot in `event_table_manager` (see `command_dispatcher`'s
header for the reasoning).

**What the testbench checks:** all 6 previous scenarios unchanged, plus a
new scenario 7: `build_nack_unknown_inst` -> `"NACK,UNKNOWN_INSTANCE"`,
checked byte for byte like every other response.

**Result: ALL TESTS PASSED** — no errors, all 7 scenarios passed,
simulation completed and halted on its own.

```
tb_response_builder: ALL TESTS PASSED   Time: 331 ns
```

---

## command_dispatcher (update 2) — `tb_command_dispatcher.vhd`

**Date:** 2026-07-16
**Tool:** ModelSim ALTERA STARTER EDITION 6.5b

**What changed:** ACK commands now go through a real release request/
response handshake with `event_table_manager` (the spec's `ack_manager`
role) instead of blindly echoing back `instance_id`. A three-state FSM
(IDLE / WAIT_ALLOC / WAIT_RELEASE) issues `release_req` and waits for
`release_done`: success frees the slot and answers `ACK,INSTANCE=<id>`;
failure (no slot currently holds that `instance_id`) answers the new
`NACK,UNKNOWN_INSTANCE`.

This testbench again instantiates a REAL `event_table_manager` alongside
the DUT to check the actual integration contract, not a mock.

**What the testbench checks (9 scenarios, reordered from the previous
version since ACK now depends on real table state):**
1. `cmd_error` code 0x01 -> `build_nack_bad_format`.
2. `cmd_error` code 0x02 -> `build_nack_unknown`.
3. EVT, `event_type=01` -> real allocation succeeds, `instance_id=0`.
4. EVT, `event_type=07` -> succeeds, `instance_id=1`.
5. EVT, `event_type=0D` (not in the catalog) -> `build_nack_unknown_evt`.
6. ACK, `instance_id=0` (real, just allocated) -> real release succeeds,
   `build_ack`, `param_byte=0`, slot freed.
7. ACK, `instance_id=0` again (already released) ->
   `build_nack_unknown_inst`.
8. ACK, `instance_id=99` (never allocated) -> `build_nack_unknown_inst`.
9. Fill the remaining 7 slots (only `instance_id=1` still occupies a slot
   after step 6), then one more EVT -> `build_nack_table_full`.

**Result: ALL TESTS PASSED** — no errors, all 9 scenarios passed,
simulation completed and halted on its own.

```
tb_command_dispatcher: ALL TESTS PASSED   Time: 1251 ns
```

---
