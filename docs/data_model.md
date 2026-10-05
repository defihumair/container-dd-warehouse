# Data Model: Container Detention & Demurrage Warehouse

All data in this project is synthetic. Rates are illustrative and do not represent any carrier.

## Container cycle (import)

| Event | Meaning |
| --- | --- |
| LOAD | Container loaded on vessel at origin port |
| DISC | Container discharged at destination terminal |
| GTOT | Full container gates out of the terminal to the customer |
| GTIN | Empty container gates back in |

## Charges

| Charge | Clock starts | Clock stops | Free days |
| --- | --- | --- | --- |
| Demurrage | DISC | GTOT | 5 |
| Detention | GTOT | GTIN | 7 |

Day counting: calendar days; the day of the starting event counts as day 1.

## Tariff tiers (illustrative, USD per day)

| Charge | Container type | Days | Rate |
| --- | --- | --- | --- |
| Demurrage | 20DC | 1–5 | 0 |
| Demurrage | 20DC | 6–10 | 40 |
| Demurrage | 20DC | 11+ | 80 |
| Demurrage | 40DC | 1–5 | 0 |
| Demurrage | 40DC | 6–10 | 60 |
| Demurrage | 40DC | 11+ | 120 |
| Demurrage | 40HC | 1–5 | 0 |
| Demurrage | 40HC | 6–10 | 70 |
| Demurrage | 40HC | 11+ | 140 |
| Demurrage | 40RF | 1–5 | 0 |
| Demurrage | 40RF | 6–10 | 120 |
| Demurrage | 40RF | 11+ | 240 |
| Detention | 20DC | 1–7 | 0 |
| Detention | 20DC | 8–14 | 30 |
| Detention | 20DC | 15+ | 60 |
| Detention | 40DC | 1–7 | 0 |
| Detention | 40DC | 8–14 | 45 |
| Detention | 40DC | 15+ | 90 |
| Detention | 40HC | 1–7 | 0 |
| Detention | 40HC | 8–14 | 50 |
| Detention | 40HC | 15+ | 100 |
| Detention | 40RF | 1–7 | 0 |
| Detention | 40RF | 8–14 | 100 |
| Detention | 40RF | 15+ | 200 |

## Entities

| Entity | Key columns | Notes |
| --- | --- | --- |
| port | port_code (UN/LOCODE), port_name, country | |
| customer | customer_id, customer_name, segment | |
| vessel | vessel_id, vessel_name, imo_no | |
| container | container_no (ISO 6346), container_type, owner_type, effective_date | Type and owner can change: SCD Type 2 |
| voyage | voyage_no, vessel_id, origin_port, destination_port, departure_ts, arrival_ts | |
| shipment | booking_ref, customer_id, container_no, voyage_no | |
| container_event | event_id, container_no, event_type, event_ts, port_code, booking_ref, voyage_no | One row per event |
| tariff_tier | charge_type, container_type, from_day, to_day (empty = open-ended), rate_usd | |

## Fact grains

| Fact | Grain |
| --- | --- |
| fact_container_event | One row per container event |
| fact_dd_charge | One row per container cycle per charge type |

## Edge cases

- Container still out (no GTIN): calculate open exposure up to an as-of date.
- Missing GTOT: flag in data quality; do not charge.
- Events out of order or arriving in a later file: order by event_ts, never by file.
- Watermark uses arrival time (stg_loaded_at), not event time, so late events are still loaded.