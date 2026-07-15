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
