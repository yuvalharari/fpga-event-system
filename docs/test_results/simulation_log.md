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

---
