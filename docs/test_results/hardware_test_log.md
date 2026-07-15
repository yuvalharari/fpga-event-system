# Hardware Test Log

Record of every real-hardware verification on the DE0 board (Cyclone III
EP3C16), separate from the ModelSim simulation log (`simulation_log.md`).
Every entry here first passed simulation before being burned to hardware.

---

## Milestone 1 — `event_system_top` (BUTTON0/BUTTON2 -> system_master_ctrl -> LEDG0)

**Date:** 2026-07-15
**Tool:** Quartus II 9.1sp2
**Device:** Cyclone III EP3C16F484C6 (DE0 board)

**What was tested:** the first real-hardware checkpoint for the project
(spec section 24 acceptance criteria - "BUTTON0/BUTTON1/BUTTON2 are
implemented and tested"). Top-level `event_system_top.vhd` wires together
`reset_controller`, two instances of `button_pulse` (BUTTON0, BUTTON2) and
`system_master_ctrl`, driving `LEDG0` from `system_enable_o`.

**Blocks involved (all already passed their own ModelSim testbenches
individually before this integration test):** `reset_controller`,
`button_pulse` (which itself wraps the course's `clean_key` + `gozer`),
`system_master_ctrl`.

**Pin assignments** (`quartus/top_pins.tcl`): `CLOCK_50`=PIN_G21,
`BUTTON0`=PIN_H2, `BUTTON2`=PIN_F1, `LEDG0`=PIN_J1, all at 3.3-V LVTTL
(overriding Quartus's default 2.5V, since the DE0 supplies 3.3V to these
I/O banks).

**Physical test performed:**
- press BUTTON0 -> LEDG0 lights up
- press BUTTON0 again while already lit -> no change
- press BUTTON2 -> LEDG0 turns off
- press BUTTON2 again while already off -> no change

**Result: PASS** - all four checks behaved as expected on real hardware.

**Issue found and fixed along the way:** all *other* LEDs (LEDG1-LEDG9, not
part of this design at all) glowed dimly instead of staying fully off. Cause:
Quartus's default behavior for unused/unassigned pins is a weak-pullup input,
which leaks just enough current through the LED series resistors to glow
faintly. Fixed with a global assignment identified in the course-provided
`de0_pins.tcl` (which documents this exact DE0-specific quirk):
```tcl
set_global_assignment -name RESERVE_ALL_UNUSED_PINS_WEAK_PULLUP "AS INPUT TRI-STATED"
```
After re-compiling and re-programming with this setting, all unused LEDs
stayed fully off.

**Note on project location:** the actual Quartus project files (`.qpf`/
`.qsf`, compilation database) live outside this git repo, at
`C:\altera\91sp2\quartus\event_system_top\` - not `quartus/` in this repo.
This was a workaround for a Quartus 9.1 permissions error when the working
directory was a space-containing path inside OneDrive (`...\VHDL Project\...`).
The actual VHDL source files are still referenced from this repo's `rtl/`
and `lib/course_blocks/` folders. Only `quartus/top_pins.tcl` (the pin/
assignment script, hand-written and reusable) lives in this repo.

---
