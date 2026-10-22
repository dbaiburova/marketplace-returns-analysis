-- =============================================
-- 04_MARTS.SQL
-- Mart Tables for Power BI Dashboard
-- Project: Marketplace Returns Analysis
-- =============================================

-- =============================================
-- 1. DIM_DATE - Calendar table
-- =============================================

-- Already created separately
-- 365 rows (Jan-Dec 2025)
-- Columns: date, year, month, day, quarter,
--          month_name, day_name, is_after_release, period

-- =============================================
-- 2. DIM_SEGMENTS - Unique segments
-- =============================================

SELECT DISTINCT
    device_clean + '|' + region_clean + '|' + channel_clean AS segment_key,
    device_clean  AS device,
    region_clean  AS region,
    channel_clean AS channel
INTO dim_segments
FROM p1_dim_user_clean
WHERE device_clean  != 'Unknown'
AND   region_clean  != 'Unknown'
AND   channel_clean != 'Unknown'
-- Result: 24 rows (2 devices × 4 regions × 3 channels)

-- =============================================
-- 3. MART_MAIN - Main metrics by day
-- =============================================
SELECT
    o.order_date_clean                                                AS order_date,
    u.device_clean + '|' + u.region_clean + '|' + u.channel_clean     AS segment_key,
    u.device_clean                                                    AS device,
    u.region_clean                                                    AS region,
    u.channel_clean                                                   AS channel,
    o.is_after_release,
    CASE WHEN o.is_after_release = 1 THEN 'After_release'
         ELSE 'Before_release' END                                    AS period,
    COUNT(o.order_id)                                                 AS total_orders,
    SUM(CASE WHEN o.status_clean = 'refunded' 
        THEN 1 ELSE 0 END)                                            AS refunds,
    CAST(SUM(CASE WHEN o.status_clean = 'refunded' 
        THEN 1 ELSE 0 END) AS FLOAT) * 100
    / NULLIF(COUNT(o.order_id), 0)                                    AS RR
INTO mart_main
FROM p1_fact_orders_clean o
JOIN p1_dim_user_clean u ON o.user_id = u.user_id
WHERE o.status_clean    NOT IN ('unknown', 'cancelled')
AND   o.order_date_clean IS NOT NULL
AND   u.device_clean    != 'Unknown'
AND   u.region_clean    != 'Unknown'
AND   u.channel_clean   != 'Unknown'
GROUP BY
    o.order_date_clean,
    u.device_clean,
    u.region_clean,
    u.channel_clean,
    o.is_after_release
-- Result: 2,904 rows

-- =============================================
-- 4. MART_FUNNEL - Checkout funnel by day
-- =============================================

WITH periods_cte AS (
    SELECT 
        e.event_id, e.user_id, e.event_date, e.event_name_clean,
        u.device_clean + '|' + u.region_clean + '|' + u.channel_clean AS segment_key,
        u.device_clean  AS device,
        u.region_clean  AS region,
        u.channel_clean AS channel,
        CASE 
            WHEN e.event_date >= '2025-06-15' THEN 'After_release'
            ELSE 'Before_release'
        END AS period
    FROM p1_fact_events_clean e
    JOIN p1_dim_user_clean u ON e.user_id = u.user_id
    WHERE u.device_clean  != 'Unknown'
    AND   u.region_clean  != 'Unknown'
    AND   u.channel_clean != 'Unknown'
),
funnel AS (
    SELECT 
        user_id, CAST(event_date AS DATE) AS event_date,
        segment_key, period, device, region, channel,
        MAX(CASE WHEN event_name_clean = 'add_to_cart' 
            THEN 1 ELSE 0 END) AS add_to_cart,
        MAX(CASE WHEN event_name_clean = 'checkout_start' 
            THEN 1 ELSE 0 END) AS checkout_start,
        MAX(CASE WHEN event_name_clean = 'checkout_complete' 
            THEN 1 ELSE 0 END) AS checkout_complete,
        MAX(CASE WHEN event_name_clean = 'payment_success' 
            THEN 1 ELSE 0 END) AS payment_success
    FROM periods_cte
    GROUP BY user_id, CAST(event_date AS DATE),
             segment_key, period, device, region, channel
),
stats AS (
    SELECT event_date, segment_key, period, device, region, channel,
        COUNT(CASE WHEN add_to_cart = 1 THEN 1 END)       AS add_to_cart,
        COUNT(CASE WHEN checkout_start = 1 THEN 1 END)    AS checkout_start,
        COUNT(CASE WHEN checkout_complete = 1 THEN 1 END) AS checkout_complete,
        COUNT(CASE WHEN payment_success = 1 THEN 1 END)   AS payment_success
    FROM funnel
    GROUP BY event_date, segment_key, period, device, region, channel
)
SELECT *
INTO mart_funnel
FROM (
    SELECT
        event_date, segment_key, period, device, region, channel,
        step_name, step_order, sessions,
        COALESCE(
            ROUND(CAST(sessions AS FLOAT) * 100 /
                NULLIF(LAG(sessions) OVER (
                    PARTITION BY event_date, segment_key, period
                    ORDER BY step_order), 0), 1),
            100
        ) AS conv_pct
    FROM (
        SELECT event_date, segment_key, period, device, region, channel,
               '1_add_to_cart'       AS step_name, 1 AS step_order, add_to_cart       AS sessions FROM stats
        UNION ALL
        SELECT event_date, segment_key, period, device, region, channel,
               '2_checkout_start'    AS step_name, 2 AS step_order, checkout_start    AS sessions FROM stats
        UNION ALL
        SELECT event_date, segment_key, period, device, region, channel,
               '3_checkout_complete' AS step_name, 3 AS step_order, checkout_complete AS sessions FROM stats
        UNION ALL
        SELECT event_date, segment_key, period, device, region, channel,
               '4_payment_success'   AS step_name, 4 AS step_order, payment_success   AS sessions FROM stats
    ) steps
) t
ORDER BY event_date, segment_key, period, step_order
-- Result: 11,672 rows

-- =============================================
-- 5. MART_RETENTION - D7 Retention by segment
-- =============================================

SELECT
    r.reg_date                                                      AS date,
    u.device_clean + '|' + u.region_clean + '|' + u.channel_clean  AS segment_key,
    CASE WHEN r.after_release = 1 THEN 'After_release'
         ELSE 'Before_release' END                                  AS period,
    u.device_clean  AS device,
    u.region_clean  AS region,
    u.channel_clean AS channel,
    COUNT(r.user_id)                                                AS total_users,
    SUM(CASE WHEN r.retained_d7 = '1.0' THEN 1 ELSE 0 END)         AS retained
INTO mart_retention
FROM p1_retention_d7_clean r
JOIN p1_dim_user_clean u ON r.user_id = u.user_id
WHERE u.device_clean  != 'Unknown'
AND   u.region_clean  != 'Unknown'
AND   u.channel_clean != 'Unknown'
GROUP BY r.reg_date, r.after_release,
         u.device_clean, u.region_clean, u.channel_clean
-- Result: 1,439 rows

-- =============================================
-- 6. MART_SEGMENTS - Segment diff table
-- =============================================

WITH rr AS (
    SELECT 'device'  AS segment_type, device    AS segment_value, period,
        CAST(SUM(refunds) AS FLOAT)*100/NULLIF(SUM(total_orders),0) AS RR
    FROM mart_main GROUP BY device, period
    UNION ALL
    SELECT 'region'  AS segment_type, region    AS segment_value, period,
        CAST(SUM(refunds) AS FLOAT)*100/NULLIF(SUM(total_orders),0) AS RR
    FROM mart_main GROUP BY region, period
    UNION ALL
    SELECT 'channel' AS segment_type, channel   AS segment_value, period,
        CAST(SUM(refunds) AS FLOAT)*100/NULLIF(SUM(total_orders),0) AS RR
    FROM mart_main GROUP BY channel, period
)
SELECT
    segment_type, segment_value,
    ROUND(MAX(CASE WHEN period = 'Before_release' THEN RR END), 2) AS RR_before,
    ROUND(MAX(CASE WHEN period = 'After_release'  THEN RR END), 2) AS RR_after,
    ROUND(MAX(CASE WHEN period = 'After_release'  THEN RR END) -
          MAX(CASE WHEN period = 'Before_release' THEN RR END), 2) AS diff
INTO mart_segments
FROM rr
GROUP BY segment_type, segment_value
ORDER BY diff DESC
-- Result: 9 rows
