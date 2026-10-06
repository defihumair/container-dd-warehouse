-- Question: Which bookings have physically impossible event sequences?
-- Technique: correlated EXISTS / NOT EXISTS subqueries
-- Result: GTOT before DISC = 693, GTIN without GTOT = 906, GTIN before GTOT = 0.
--         693 of 700 injected out-of-order events detected; 7 lost their partner event upstream.
USE dd_warehouse;
GO

WITH booking_events AS (
    SELECT dc.container_no, f.booking_ref, f.event_type, f.event_ts
    FROM dw.fact_container_event AS f
    JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
    WHERE f.container_sk <> -1
)
SELECT N'GTOT before DISC' AS problem, COUNT(*) AS bookings
FROM booking_events AS d
WHERE d.event_type = N'DISC'
  AND EXISTS (SELECT 1 FROM booking_events AS g
              WHERE g.booking_ref = d.booking_ref AND g.container_no = d.container_no
                AND g.event_type = N'GTOT' AND g.event_ts < d.event_ts)
UNION ALL
SELECT N'GTIN before GTOT', COUNT(*)
FROM booking_events AS g
WHERE g.event_type = N'GTOT'
  AND EXISTS (SELECT 1 FROM booking_events AS i
              WHERE i.booking_ref = g.booking_ref AND i.container_no = g.container_no
                AND i.event_type = N'GTIN' AND i.event_ts < g.event_ts)
UNION ALL
SELECT N'GTIN without GTOT', COUNT(*)
FROM booking_events AS i
WHERE i.event_type = N'GTIN'
  AND NOT EXISTS (SELECT 1 FROM booking_events AS g
                  WHERE g.booking_ref = i.booking_ref AND g.container_no = i.container_no
                    AND g.event_type = N'GTOT');

SELECT TOP (10) dc.container_no, d.booking_ref, d.event_ts AS disc_ts, g.event_ts AS gtot_ts,
       DATEDIFF(HOUR, g.event_ts, d.event_ts) AS hours_gtot_before_disc
FROM dw.fact_container_event AS d
JOIN dw.dim_container AS dc ON dc.container_sk = d.container_sk
JOIN dw.fact_container_event AS g
  ON g.booking_ref = d.booking_ref AND g.container_sk = d.container_sk
 AND g.event_type = N'GTOT' AND g.event_ts < d.event_ts
WHERE d.event_type = N'DISC' AND d.container_sk <> -1
ORDER BY d.event_ts;
GO
