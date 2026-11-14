# Smart Traffic Light Controller with Pedestrian Request

A seven-state Verilog FSM for a main road, a side road and a pedestrian crossing,
with a self-checking verification environment and an FPGA-ready top level.

## Project structure
| File | Purpose |
|---|---|
| `rtl/traffic_ctrl.v` | Synthesizable one-hot FSM. `traffic_ctrl_core` (with `tick` enable) and `traffic_ctrl` (original interface) |
| `rtl/traffic_top.v` | Board wrapper: tick prescaler (seconds), reset synchronizer, input synchronizers |
| `rtl/traffic_ctrl_ref.v` | Independent reference model (binary, down-counter, single process) - simulation only |
| `tb/traffic_checker.v` | Black-box protocol checker (safety, sequence, durations, priority, liveness) |
| `tb/traffic_ctrl_tb.v` | Main self-checking testbench (directed + constrained-random) |
| `tb/traffic_top_tb.v` | Smoke test for the board wrapper |
| `docs/state_diagram.md` | State transitions and output table |

## Interface (`traffic_ctrl`)
Inputs: `clk`, active-high asynchronous `rst`, vehicle request `VS`, pedestrian request `PB`.
Outputs: `light_main[2:0]`, `light_side[2:0]`, `walk` (registered, glitch-free).

Light encodings: RED=3'b001, YEL=3'b010, GRN=3'b100.

`traffic_ctrl_core` has the same ports plus `tick`: the phase timer only advances
on clocks where `tick=1`. `traffic_ctrl` ties `tick` to 1, so it counts clock periods.

## Parameters
| Parameter | Default | Meaning |
|---|---|---|
| `MAIN_GREEN_MIN` | 60 | Minimum main green; then waits for a pending request |
| `MAIN_YELLOW_TIME` | 4 | Main yellow |
| `ALL_RED1_TIME` | 2 | All red after main yellow |
| `SIDE_GREEN_TIME` | 40 | Side green |
| `WALK_TIME` | 40 | Pedestrian walk (both roads red) |
| `SIDE_YELLOW_TIME` | 5 | Side yellow (after side green or walk) |
| `ALL_RED2_TIME` | 3 | All red before main green |
| `SYNC_INPUTS` | 0 | 1 = two-flop synchronizer on `VS`/`PB` (+2 clocks latency) |
| `FAIR_ARB` | 0 | 1 = alternate when both requests are pending (prevents starvation) |

With the defaults the timing is cycle-for-cycle identical to the original
specification (verified against both the original and the new reference model).

## Timing
The timer is cleared on state entry, so a phase of duration N lasts exactly N ticks.
If main green has already passed its minimum, a request is latched on clock
edge 1, main yellow starts on edge 2, and the served phase starts on edge 8
(MY 4 + AR1 2).

## Request behavior
* Requests are latched.
* A request is cleared while its service phase is active (a press during the
  phase it is asking for is absorbed).
* A pedestrian request received during side green is held for the next cycle,
  and vice versa.
* At ALL_RED1 pedestrians have priority over vehicles.
  **Known limitation of strict priority:** if pedestrians keep pressing every
  cycle, a waiting side-road vehicle is never served. Set `FAIR_ARB=1` to fix this:
  when both are pending, whichever was *not* served last time goes first.

## Run the tests (Icarus Verilog)
```bash
make test          # main regression + board wrapper
make seeds         # 5 random seeds x 50k cycles
make sim SEED=42 CYCLES=100000
make wave          # open build/traffic_ctrl.vcd in GTKWave
make synth         # Yosys synthesis check
```
Without `make`:
```bash
iverilog -g2012 -Wall -o traffic_sim rtl/traffic_ctrl.v rtl/traffic_ctrl_ref.v tb/traffic_checker.v tb/traffic_ctrl_tb.v
vvp traffic_sim +seed=1
```
A successful run prints `PASS`. GitHub Actions runs the same tests on each push.

## Verification
The testbench drives five DUT configurations with the same stimulus:

| Instance | Configuration | Checked by |
|---|---|---|
| `u_dut` | defaults | reference model (lock-step) + checker |
| `u_fair` | `FAIR_ARB=1` | reference model + checker |
| `u_small` | short custom timings | reference model + checker |
| `u_sync` | `SYNC_INPUTS=1` | checker (2-clock latency model) |
| `u_tick` | core with random `tick` | checker (tick-based timing) |

The checker looks only at the outputs and verifies: legal lamp combinations
(no conflicting greens, walk only with all reds), legal phase order, exact phase
durations, minimum main green, no spurious cycles, arbitration, and bounded
waiting time. Directed tests cover idle behavior, exact service latency,
simultaneous requests, requests during service, asynchronous reset mid-phase,
and the starvation scenario.

The environment was checked by mutation testing: off-by-one timer, wrong
priority, request never cleared, skipped all-red, unsafe lamp output, ignored
tick, missing synchronizer and inverted fair arbitration are all detected.

## FPGA
`traffic_top` (defaults: 50 MHz clock, 1 tick per second, active-low reset
button) drives six lamp LEDs and a walk LED. Change `CLK_HZ` to match your board
and assign the pins in your vendor's constraint file.
