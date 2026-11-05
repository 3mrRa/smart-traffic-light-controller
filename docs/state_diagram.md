# FSM State Diagram

The controller has seven states. The synthesizable DUT uses one-hot encoding; the reference model uses binary encoding.

```mermaid
stateDiagram-v2
    [*] --> MAIN_GREEN
    MAIN_GREEN --> MAIN_GREEN: no queued request / minimum not reached
    MAIN_GREEN --> MAIN_YELLOW: timer >= 59 and request pending
    MAIN_YELLOW --> ALL_RED1: 4 periods
    ALL_RED1 --> PEDESTRIAN: 2 periods and P_queued
    ALL_RED1 --> SIDE_GREEN: 2 periods and V_queued only
    ALL_RED1 --> MAIN_GREEN: 2 periods and no request
    SIDE_GREEN --> SIDE_YELLOW: 40 periods
    PEDESTRIAN --> SIDE_YELLOW: 40 periods
    SIDE_YELLOW --> ALL_RED2: 5 periods
    ALL_RED2 --> MAIN_GREEN: 3 periods
```

## State outputs

| State | Main light | Side light | Walk |
|---|---|---|---|
| MAIN_GREEN | Green | Red | 0 |
| MAIN_YELLOW | Yellow | Red | 0 |
| ALL_RED1 | Red | Red | 0 |
| SIDE_GREEN | Red | Green | 0 |
| PEDESTRIAN | Red | Red | 1 |
| SIDE_YELLOW | Red | Yellow | 0 |
| ALL_RED2 | Red | Red | 0 |

At ALL_RED1, a pending pedestrian request has priority over a vehicle request. A pedestrian request arriving during SIDE_GREEN remains queued for the next cycle.
