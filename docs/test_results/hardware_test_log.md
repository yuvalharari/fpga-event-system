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

## Milestone 2 — UART echo test (TX1/RX1 -> uart_tx/uart_rx -> uart_echo_test)

**Date:** 2026-07-15
**Tool:** Quartus II 9.1sp2 + COMSH.EXE v2.8 (Amos Zaslavsky) as the PC-side
terminal, in `termb` (binary terminal) mode.
**Device:** Cyclone III EP3C16F484C6 (DE0 board), Add-On card on GPIO_1.

**What was tested:** real bidirectional UART communication over the Add-On
board's FTDI/PC channel (TX1/RX1), end to end: PC keyboard -> COMSH -> FTDI
-> Add-On ribbon cable -> FPGA `uart_rx` -> `uart_echo_test` -> FPGA
`uart_tx` -> FTDI -> COMSH -> PC screen. `event_system_top.vhd` extended
(alongside the existing BUTTON0/BUTTON2/LEDG0 logic from Milestone 1) with
`uart_rx`, `uart_tx`, and `uart_echo_test`, wired to `RX1`/`TX1`.

**Pin assignments added** (`quartus/top_pins.tcl`): `TX1`=PIN_R12,
`RX1`=PIN_T12, both at 3.3-V LVTTL.

**Physical test performed:** opened a serial connection to the Add-On
board's FTDI chip (settings: 9600 baud, 8 data bits, no parity, 1 stop bit,
no flow control - matching `uart_rx`/`uart_tx`'s default generics) and typed
characters, watching for each to be echoed back exactly.

**Result: PASS** - every character typed ('g', 'a', 't', 'h', ...) came back
identical, immediately, confirming both directions work correctly on real
hardware, not just in simulation.

**Issues found and fixed along the way (all on the PC/tooling side, not the
FPGA design):**
1. Initially tested against the wrong COM port entirely (COM3, a leftover/
   unrelated port) instead of the Add-On's actual FTDI port - confirmed via
   Device Manager by unplugging/replugging the Add-On's USB cable and
   watching which COM port disappeared/reappeared.
2. The Add-On's FTDI turned out to be assigned COM9 by Windows, but COMSH.EXE
   only supports port numbers 1-8 (`open [1|2|3|4|5|6|7|8]`) - a hard
   limitation of this specific tool version. Fixed by reassigning the port
   number in Device Manager -> Ports -> (FTDI device) -> Properties -> Port
   Settings -> Advanced... -> COM Port Number, to COM2 (an unused port in
   the supported 1-8 range).
3. COMSH's `termb` mode temporarily re-enables XON/XOFF input flow control
   regardless of an earlier `noflow` command - disabled again with `noflow`
   + `termset localecho 0` before re-entering `termb`, to rule out software
   flow control interference and avoid confusing local echo with the real
   FPGA round-trip.

**Note:** a hypothesis that the TX1/RX1 pin assignments might be physically
swapped (raised while debugging the COM port confusion above) turned out to
be wrong - the original pin mapping was correct all along. The whole failure
chain was caused by testing against the wrong COM port, nothing in the FPGA
design or pin assignments needed to change.

---

## Milestone 3 — full command chain (`uart_rx` -> `sync_fifo` -> `line_receiver` -> `text_command_parser` -> `command_dispatcher` -> `response_builder` -> `response_sender` -> `uart_tx`)

**Date:** 2026-07-16
**Tool:** Quartus II 9.1sp2 + COMSH.EXE v2.8, `termb` (binary terminal) mode.
**Device:** Cyclone III EP3C16F484C6 (DE0 board), Add-On card on GPIO_1.

**What was tested:** the temporary `uart_echo_test` block was replaced in
`event_system_top.vhd` with the real, full text-command processing chain
(each block already individually verified in ModelSim beforehand - see
`simulation_log.md`): an RX `sync_fifo` (16 bytes deep) buffers bytes from
`uart_rx`, `line_receiver` assembles them into complete CR/LF-terminated
lines, `text_command_parser` validates and tokenizes `EVT,<type>,<source>`
and `ACK,<instance>` commands, `command_dispatcher` maps the result to a
response request, `response_builder` formats the ASCII reply, and
`response_sender` streams it out through `uart_tx`, byte by byte, with a
trailing CR+LF.

**Physical test performed (via comsh, 9600/8/N/1, no flow control):**
1. `EVT,01,03` + Enter -> expected `ACK,INSTANCE=03`
2. `ACK,17` + Enter -> expected `ACK,INSTANCE=17`
3. Both of the above repeated a second time in the same session (no
   reprogram/reset in between) -> repeatability check, ruling out any
   internal state not resetting correctly between commands.
4. `FOO,01` + Enter (unrecognized command name) -> expected
   `NACK,UNKNOWN_COMMAND` (the longest response currently supported, 20
   chars + CR + LF = 22 bytes - also the response type that first exposed
   the bug below).

**Result: PASS** (after one bug found and fixed along the way, see below) -
every scenario above produced the exact expected byte sequence, byte for
byte, confirmed in comsh's binary terminal (`tx =>` / `rx <=` traces).

**Bug found and fixed:** the very first end-to-end attempt (`EVT,01,03`, but
mistakenly typed with embedded spaces as `EVT, 01, 03`, an 11-character line
that correctly falls through to the "unknown command" path) came back
corrupted - only every *other* byte of the intended `NACK,UNKNOWN_COMMAND`
response arrived, in a precise, repeatable pattern (bytes at even positions
of the transmission only). Root-caused to the course-provided
`lib/course_blocks/transmitter.vhd` (already bug-fixed twice before, see its
header): its `tx_ready` output was purely combinational off `present_state`,
which only updates on the clock edge *after* a `write_din` is first sampled
in `idle`. This left a one-clock window where a fast consumer sending
several bytes back-to-back (like `response_sender`, unlike the old
`uart_echo_test` which only ever sent one byte at a time with long natural
gaps) could still read `tx_ready = '1'` right after its first write was
accepted, issue a second write immediately, and lose that byte - the
transmitter had already left `idle` and wouldn't reload `din` until back in
`idle`. Fixed by making `tx_ready` also drop the same cycle a write is
accepted:
```vhdl
tx_ready <= '0' when (present_state = idle) and (write_din = '1') and (write_armed = '1') else
            '1' when (present_state = idle) else
            '0';
```
Verified directly on hardware after the fix (re-simulation was intentionally
skipped for this fix, per explicit instruction, in favor of direct hardware
re-verification) - all scenarios above passed cleanly afterward, with no
further byte loss across two full repeated test rounds.

**Pin assignments:** unchanged from Milestone 2 (`TX1`=PIN_R12,
`RX1`=PIN_T12) - this milestone added only internal logic, no new physical
I/O.

---

## Milestone 4 — `event_table_manager` wired in (real instance allocation)

**Date:** 2026-07-16
**Tool:** Quartus II 9.1sp2 + COMSH.EXE v2.8, `termb` mode.
**Device:** Cyclone III EP3C16F484C6 (DE0 board), Add-On card on GPIO_1.

**What was tested:** `event_table_manager` (spec section 8.1, reduced
allocation-only scope - see its own header) wired into `command_dispatcher`,
replacing the old `source_id`-as-placeholder behavior with a real
allocation request/response handshake. A successful EVT command now gets a
real, monotonically-increasing `instance_id` from `event_table_manager`
instead of an echo of whatever `source_id` was sent. `response_builder`
gained two new response types (`NACK,UNKNOWN_EVENT` / `NACK,TABLE_FULL`,
spec section 16 error codes 03/04) to report allocation failures.

**Physical test performed (via comsh, 9600/8/N/1, no flow control):**
1. `EVT,01,03` + Enter -> `ACK,INSTANCE=00` (first real allocation).
2. `EVT,01,03` + Enter again -> `ACK,INSTANCE=01` (instance_id incremented,
   proving it's a real counter, not an echo of `source_id=03` like before).

**Result: PASS** - both responses matched exactly, byte for byte, confirmed
in comsh's binary terminal (`tx =>` / `rx <=` traces). No bugs found this
round.

**New source files added to the Quartus project:**
`rtl/event_core/event_definition_rom.vhd`,
`rtl/event_core/event_table_manager.vhd`.

**Pin assignments:** unchanged - this milestone added only internal logic,
no new physical I/O.

**Known limitation carried forward from the reduced scope (see
`event_table_manager.vhd`'s header):** no slot release yet, so after 8
successful EVT allocations (`event_slots` default), every further EVT will
return `NACK,TABLE_FULL` until a reset - not yet re-tested on hardware in
this round, deferred until `ack_manager`/release logic exists.

---

## Milestone 6 — BUTTON1 full_reset

**Date:** 2026-07-16
**Tool:** Quartus II 9.1sp2 + COMSH.EXE v2.8, `termb` mode.
**Device:** Cyclone III EP3C16F484C6 (DE0 board), Add-On card on GPIO_1.

**What was tested:** `BUTTON1` wired to a new `button_pulse` instance,
driving `event_table_manager`'s new `full_reset` input (spec section
14.2.1) - clears the entire event table in one clock on a debounced
BUTTON1 press, without resetting the `instance_id` counter or touching
`SYSTEM_ON`/`SYSTEM_OFF`.

**Pin assignment added** (`quartus/top_pins.tcl`): `BUTTON1`=PIN_G3,
3.3-V LVTTL (same source/confidence as BUTTON0/BUTTON2's existing
assignments).

**Physical test performed (via comsh, 9600/8/N/1, no flow control):**
1. Sent `EVT,01,03` eight times in a row -> `ACK,INSTANCE=00` through
   `ACK,INSTANCE=07`, filling all 8 slots.
2. Sent `EVT,01,03` a 9th time -> `NACK,TABLE_FULL`, confirming the table
   was genuinely full.
3. Pressed BUTTON1 physically on the DE0 board.
4. Sent `EVT,01,03` again -> `ACK,INSTANCE=08` (succeeded immediately,
   proving the table was cleared - AND the id continued from 08 rather
   than resetting to 00, proving the instance_id counter was left
   running, exactly as designed).

**Result: PASS** - all four steps matched expectations exactly, confirmed
in comsh's binary terminal (`tx =>` / `rx <=` traces).

**Issue found along the way (tooling, not the FPGA design):** investigated
`comsh`'s `TX`/`TERM` commands as a more convenient alternative to typing
character-by-character in `termb`. Found: `TX <string>` does not append a
CR terminator, which left a stray unterminated line sitting in
`line_receiver`'s buffer and corrupted the next command (got
`NACK,UNKNOWN_COMMAND` for a well-formed `EVT,01,03` because it had been
silently concatenated with the leftover text). `TERM` (dumb text terminal
mode) hit the same "Temporary Setting of XON/XOFF Input flow to: 1" quirk
already seen with `termb` in Milestone 2, and blocked keyboard input;
switching `TERMSET` options didn't help since none of them control
XON/XOFF (that's likely `XFLOW`, not yet tried). Resolution: kept using
`termb` character-by-character, which is proven and reliable - the
convenience commands are not required for correctness.

---

## Milestone 7 — `priority_scheduler` LED demo

**Date:** 2026-07-16
**Tool:** Quartus II 9.1sp2 + COMSH.EXE v2.8, `termb` mode.
**Device:** Cyclone III EP3C16F484C6 (DE0 board), Add-On card on GPIO_1.

**What was tested:** `priority_scheduler` (spec section 8.2, reduced
scope) wired to `event_table_manager`'s new `table_changed` output, with
its decision shown live on LEDs (matching the spec's own days 10-12
acceptance criteria: "הדגמת מתזמן מבוססת-LED בלבד"). `LEDG1` = some event
is active; `LEDG2-4` = active slot index in binary.

**Pin assignments added** (`quartus/top_pins.tcl`): `LEDG1`=PIN_J2,
`LEDG2`=PIN_J3, `LEDG3`=PIN_H1, `LEDG4`=PIN_F2, all 3.3-V LVTTL.

**New source files added to the Quartus project:**
`rtl/event_core/event_system_pkg.vhd`, `rtl/event_core/priority_scheduler.vhd`.

**Physical test performed (via comsh, "scenario A" - lower priority first,
then higher):**
1. `EVT,07,01` (priority 3, MEDICATION_MISSED) -> `ACK,INSTANCE=00`,
   slot 0 -> `LEDG1` lit, `LEDG2-4`=`000`.
2. `EVT,01,03` (priority 7, LIFE_THREATENING_EMERGENCY) ->
   `ACK,INSTANCE=01`, slot 1 -> preempts -> `LEDG1` stays lit,
   `LEDG2-4`=`001` (LEDG4 only).
3. `ACK,00` (release the non-active slot 0) -> no visible change, as
   expected - releasing a slot that isn't the active one doesn't affect
   the scheduler's decision.
4. `ACK,01` (release the active slot 1) -> `LEDG1` turns off correctly
   (no active event left).

**Result: PASS** for the scheduler's actual decisions (preemption,
no-op on releasing a non-active slot, correctly detecting "no active
event left") - all matched expectations exactly.

**Cosmetic display quirk found, not fixed (by explicit user choice):**
after step 4, `LEDG4` stayed lit even though `LEDG1` correctly turned
off. Root cause: `priority_scheduler`'s `active_index` output is only
specified to be meaningful `when active_valid='1'` (see the entity's own
port comment) - when the table empties out, `active_index` simply holds
its last value rather than being cleared, since nothing in the block's
contract requires otherwise. On a real LED you can't "ignore" a lit bit
the way a downstream consumer checking `active_valid` first would - so
this reads as a stale/confusing indicator, not a logic bug. Proposed fix
(deferred): gate `LEDG2-4` with `active_valid` at the top level (matching
the spec's own SW0-3 output-gating principle, section 14.3), so they
force to `000` whenever `LEDG1` is off. User decided the underlying
scheduler behavior was sufficiently proven and chose not to apply this
cosmetic fix for now.

---

## Milestones 8-10 — Bluetooth command channel + `buzzer_controller` + `led_pattern_controller` (combined hardware pass)

**Date:** 2026-07-19
**Tool:** Quartus II 9.1sp2 + Android "Serial Bluetooth Terminal" app (Kai
Morich), connected to the Add-On board's HC-06 over Bluetooth Classic (SPP).
**Device:** Cyclone III EP3C16F484C6 (DE0 board), Add-On card on GPIO_1.

**What was tested, all in one combined pass since none of these three had
been hardware-verified yet:**
- **Milestone 8:** the command chain's UART moved from `TX1`/`RX1` (PC/FTDI
  debug) to `TX2_BT`/`RX2_BT` (the Add-On's HC-06 Bluetooth channel) - same
  `uart_rx`/`uart_tx`, same 9600 baud, just different physical pins, so
  testing could be driven from the phone instead of comsh.
- **Milestone 9:** `buzzer_controller` wired to `SPEAKER` - two triggers
  only (`system_enable` rising edge, `table_not_empty` rising edge), see
  project memory "final product vision".
- **Milestone 10:** `led_pattern_controller` wired to `LEDG1`-`LEDG9`,
  replacing the old Milestone 7 binary-index demo with a chase animation
  whose speed scales with the active event's priority.

**Pin assignments added** (`quartus/top_pins.tcl`): `TX2_BT`=PIN_V7,
`RX2_BT`=PIN_U8, `SPEAKER`=PIN_W17, `LEDG5`=PIN_E1, `LEDG6`=PIN_C1,
`LEDG7`=PIN_C2, `LEDG8`=PIN_B2, `LEDG9`=PIN_B1, all 3.3-V LVTTL.

**New source files added to the Quartus project:**
`rtl/output/buzzer_controller.vhd`, `rtl/output/led_pattern_controller.vhd`,
`lib/course_blocks/pacer.vhd`, `lib/course_blocks/audio_gen.vhd`
(`gozer.vhd` was already in the project from an earlier milestone).

**Physical test performed (via the phone's Bluetooth terminal, CR+LF line
endings):**
1. Pressed BUTTON0 -> `LEDG0` lit + a short beep (buzzer trigger 1).
2. Sent `EVT,01,03` (priority 7) -> ACK response received correctly over
   Bluetooth, a second beep (buzzer trigger 2, table went 0->1 events),
   and the LED chase running across `LEDG1`-`LEDG9` at the fast,
   priority-7 speed.
3. Sent a second, lower-priority EVT while the first was still active ->
   no additional beep (only the empty-to-non-empty edge triggers it), and
   it queued behind the active event as expected.
4. Sent `ACK` to release the active instance -> confirmed correct
   scheduler hand-off / LED behavior.

**Result: PASS** - Bluetooth command channel, buzzer triggers, and the
LED chase all confirmed working together on real hardware. User confirmed:
"מעולה הכל עובד מושלם!"

**Compile issue found and fixed along the way (Quartus project setup, not
the FPGA design itself):** first compile attempt failed with "Node instance
u_pacer/u_audio_gen instantiates undefined entity" - `pacer.vhd` and
`audio_gen.vhd` (used internally by `buzzer_controller`) had not yet been
added to the Quartus project's file list (`gozer.vhd` had been, from an
earlier block). Fixed via Project > Add/Remove Files in Project.

---

## Milestone 11 — `priority_scheduler` active-duration timeout (auto-release)

**Date:** 2026-07-19
**Tool:** Quartus II 9.1sp2 + Android "Serial Bluetooth Terminal" app.
**Device:** Cyclone III EP3C16F484C6 (DE0 board), Add-On card on GPIO_1.

**What was tested:** the new active-duration timeout (project-specific
addition beyond the spec, see `priority_scheduler.vhd`'s header and
project memory "scheduler active-duration timeout" for the full design
reasoning). Every active event now gets a real 5-second budget
(`active_duration_cycles=250_000_000` @ 50MHz) before
`priority_scheduler`'s `timeout_pulse` auto-releases it from
`event_table_manager` via the independent `auto_release_req` path -
without ever touching `command_dispatcher`'s ACK handshake.

**Pin assignments / new source files:** none - this milestone only
changed logic inside already-instantiated blocks (`event_table_manager.vhd`,
`priority_scheduler.vhd`, `event_system_top.vhd`), so the existing Quartus
project file list and pin assignments needed no changes, just a
recompile.

**Physical test performed:** sent `EVT,01,03` over Bluetooth (fast,
priority-7 LED chase started as expected) and deliberately did **not**
send an ACK - just waited. After exactly ~5 real seconds, the LED chase
stopped on its own with no further command sent, confirming the event was
auto-released from the table purely by the timeout, on real silicon (not
just in simulation with a scaled-down `active_duration_cycles`).

**Result: PASS** - user confirmed: "צרבתי וזה עובד בצורה מדויקת!"

---
