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

DROP TABLE IF EXISTS dim_segments;

SELECT DISTINCT
    device_clean + '|' + region_clean + '|' + channel_clean AS segment_key,
    device_clean  AS device,
    region_clean  AS region,
    channel_clean AS channel
INTO dim_segments
FROM p1_dim_user_clean;
-- Result: 24 rows

-- =============================================
-- 3. MART_MAIN - Main metrics by day
-- =============================================
DROP TABLE IF EXISTS mart_main;

SELECT
    order_date_clean                                          AS order_date,
    device_clean + '|' + region_clean + '|' + channel_clean   AS segment_key,
    device_clean                                              AS device,
    region_clean                                              AS region,
    channel_clean                                             AS channel,
    is_after_release,
    CASE WHEN is_after_release = 1 THEN 'After_release'
         ELSE 'Before_release' END                            AS period,
    COUNT(order_id)                                           AS total_orders,
    SUM(CASE WHEN status_clean = 'refunded' THEN 1 ELSE 0 END) AS refunds
INTO mart_main
FROM p1_fact_orders_clean
WHERE status_clean IN ('completed', 'refunded')
GROUP BY
    order_date_clean, device_clean, region_clean, channel_clean, is_after_release;
-- Result: 2,904 rows

-- =============================================
-- 4. MART_FUNNEL - Checkout funnel by day
-- =============================================

DROP TABLE IF EXISTS mart_funnel;

WITH periods_cte AS (
    SELECT 
        e.user_id, e.event_date, e.event_name_clean,
        u.device_clean + '|' + u.region_clean + '|' + u.channel_clean AS segment_key,
        u.device_clean  AS device,
        u.region_clean  AS region,
        u.channel_clean AS channel,
        CASE WHEN e.event_date >= '2025-06-15' THEN 'After_release'
             ELSE 'Before_release' END AS period
    FROM p1_fact_events_clean e
    JOIN p1_dim_user_clean u ON e.user_id = u.user_id
),
funnel AS (   -- 1 строка = 1 сессия (юзер × день)
    SELECT 
        user_id, event_date, segment_key, period, device, region, channel,
        MAX(CASE WHEN event_name_clean = 'add_to_cart'       THEN 1 ELSE 0 END) AS add_to_cart,
        MAX(CASE WHEN event_name_clean = 'checkout_start'    THEN 1 ELSE 0 END) AS checkout_start,
        MAX(CASE WHEN event_name_clean = 'checkout_complete' THEN 1 ELSE 0 END) AS checkout_complete,
        MAX(CASE WHEN event_name_clean = 'payment_success'   THEN 1 ELSE 0 END) AS payment_success
    FROM periods_cte
    GROUP BY user_id, event_date, segment_key, period, device, region, channel
),
stats AS (    -- сумма сессий по дню × сегменту
    SELECT event_date, segment_key, period, device, region, channel,
        SUM(add_to_cart)       AS add_to_cart,
        SUM(checkout_start)    AS checkout_start,
        SUM(checkout_complete) AS checkout_complete,
        SUM(payment_success)   AS payment_success
    FROM funnel
    GROUP BY event_date, segment_key, period, device, region, channel
)
SELECT event_date, segment_key, period, device, region, channel,
       step_name, step_order, sessions
INTO mart_funnel
FROM (
    SELECT *, '1_add_to_cart'       AS step_name, 1 AS step_order, add_to_cart       AS sessions FROM stats
    UNION ALL
    SELECT *, '2_checkout_start',                 2,               checkout_start                FROM stats
    UNION ALL
    SELECT *, '3_checkout_complete',              3,               checkout_complete             FROM stats
    UNION ALL
    SELECT *, '4_payment_success',                4,               payment_success               FROM stats
) steps;
-- Result: 11,672 rows

-- =============================================
-- 5. MART_RETENTION - D7 Retention by segment
-- =============================================
DROP TABLE IF EXISTS mart_retention;

SELECT
    r.reg_date                                                     AS date,
    u.device_clean + '|' + u.region_clean + '|' + u.channel_clean  AS segment_key,
    CASE WHEN r.after_release = 1 THEN 'After_release'
         ELSE 'Before_release' END                                 AS period,
    u.device_clean  AS device,
    u.region_clean  AS region,
    u.channel_clean AS channel,
    COUNT(r.user_id)   AS total_users,
    SUM(r.retained_d7) AS retained
INTO mart_retention
FROM p1_retention_d7_clean r
JOIN p1_dim_user_clean u ON r.user_id = u.user_id
GROUP BY r.reg_date, r.after_release,
         u.device_clean, u.region_clean, u.channel_clean;
-- Result: 1,439 rows

-- =============================================
-- 6. MART_SEGMENTS - Segment diff table
-- =============================================

DROP TABLE IF EXISTS mart_segments;

WITH rr AS (
    SELECT 'device'  AS segment_type, device  AS segment_value, period,
        CAST(SUM(refunds) AS FLOAT)*100/NULLIF(SUM(total_orders),0) AS RR
    FROM mart_main GROUP BY device, period
    UNION ALL
    SELECT 'region'  AS segment_type, region  AS segment_value, period,
        CAST(SUM(refunds) AS FLOAT)*100/NULLIF(SUM(total_orders),0) AS RR
    FROM mart_main GROUP BY region, period
    UNION ALL
    SELECT 'channel' AS segment_type, channel AS segment_value, period,
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
GROUP BY segment_type, segment_value;
-- Result: 9 rows
