# Smart Traffic Light Controller with Pedestrian Request

A seven-state Verilog FSM for a main road, a side road, and a pedestrian crossing.

## Project structure
- `rtl/traffic_ctrl.v` — synthesizable one-hot FSM
- `rtl/traffic_ctrl_ref.v` — binary-encoded reference model for simulation
- `tb/traffic_ctrl_tb.v` — self-checking testbench
- `docs/state_diagram.md` — state transitions and output table

## Interface
Inputs: `clk`, active-high asynchronous `rst`, vehicle request `VS`, pedestrian request `PB`.
Outputs: `light_main[2:0]`, `light_side[2:0]`, `walk`.

Light encodings: RED=3'b001, YEL=3'b010, GRN=3'b100.

## Timing
- Main green: minimum 60 clock periods; waits for a pending request.
- Main yellow: 4 periods.
- ALL_RED1: 2 periods.
- Side green: 40 periods.
- Pedestrian walk: 40 periods.
- Side yellow: 5 periods.
- ALL_RED2: 3 periods.

The timer is cleared on state entry. Fixed-duration phases therefore last the configured number of complete clock periods.

## Request behavior
Requests are latched. At ALL_RED1, pedestrian requests have priority over vehicle requests. A pedestrian request received during side green is held for the next cycle. Requests are cleared while their corresponding service phase is active.

## Run with Icarus Verilog
```bash
iverilog -g2012 -Wall -o traffic_sim \
  rtl/traffic_ctrl.v rtl/traffic_ctrl_ref.v tb/traffic_ctrl_tb.v
vvp traffic_sim
gtkwave traffic_ctrl.vcd
```

The testbench compares DUT outputs against a separately encoded reference model and includes directed and randomized stimulus. A successful run should print PASS.

## Verification note
The reference model in this repository implements the timing and request behavior documented here. If your instructor supplied a separate reference module, test the DUT against that original file as an additional compatibility check. This repository has not been independently simulated in the current upload session.
