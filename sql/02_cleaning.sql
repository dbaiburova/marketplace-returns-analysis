-- =============================================
-- 02_CLEANING.SQL
-- Data Cleaning: 5 tables
-- Project: Marketplace Returns Analysis
-- =============================================

-- =============================================
-- 1. CLEAN: p1_dim_user --- p1_dim_user_clean
-- =============================================

SELECT user_id, reg_date_clean, device_clean, region_clean, channel_clean
INTO p1_dim_user_clean
FROM (
    SELECT 
        user_id,
        CASE 
            WHEN LEN(reg_date) = 8  THEN TRY_CONVERT(DATE, reg_date, 112)
            WHEN LEN(reg_date) = 10 THEN TRY_CONVERT(DATE, reg_date, 103)
            WHEN reg_date = 'not a date' THEN NULL
            ELSE TRY_CONVERT(DATE, reg_date, 120)
        END AS reg_date_clean,
        CASE 
            WHEN UPPER(device) IN ('ANDROID','ANDR0ID') THEN 'Android'
            WHEN UPPER(device) = 'IOS'                  THEN 'iOS'
            ELSE 'Unknown'
        END AS device_clean,
        CASE 
            WHEN UPPER(TRIM(region)) = 'USA'                       THEN 'US'
            WHEN UPPER(TRIM(region)) IN ('EU','US','APAC','LATAM') THEN UPPER(TRIM(region))
            ELSE 'Unknown'
        END AS region_clean,
        CASE 
            WHEN channel = 'ref'                    THEN 'Referral'
            WHEN channel IN ('unknown','N/A') 
                 OR channel IS NULL                 THEN 'Unknown'
            ELSE channel
        END AS channel_clean,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY reg_date) AS rn
    FROM p1_dim_user
) t
WHERE rn = 1
AND device_clean  != 'Unknown'
AND region_clean  != 'Unknown'
AND channel_clean != 'Unknown'

-- =============================================
-- 2. CLEAN: p1_fact_orders --- p1_fact_orders_clean
-- =============================================

SELECT order_id, user_id, order_date_clean, amount, 
       status_clean, device_clean, region_clean, 
       channel_clean, is_after_release
INTO p1_fact_orders_clean
FROM (
    SELECT
        o.order_id,
        o.user_id,
        o.amount,
        o.is_after_release,
        CASE 
            WHEN status = 'complete'  THEN 'completed'
            WHEN status = 'canceled'  THEN 'cancelled'
            WHEN status IN ('unknown','N/A') 
                 OR status IS NULL    THEN 'Unknown'
            ELSE status
        END AS status_clean,
        CASE 
            WHEN LEN(order_date) = 8  THEN TRY_CONVERT(DATE, order_date, 112)
            WHEN LEN(order_date) = 10 THEN TRY_CONVERT(DATE, order_date, 103)
            WHEN order_date = 'not a date' THEN NULL
            ELSE TRY_CONVERT(DATE, order_date, 120)
        END AS order_date_clean,
        u.device_clean,
        u.region_clean,
        u.channel_clean,
        ROW_NUMBER() OVER (PARTITION BY o.order_id ORDER BY o.order_date) AS rn
    FROM p1_fact_orders o
    JOIN p1_dim_user_clean u ON o.user_id = u.user_id
    WHERE o.amount IS NOT NULL
    AND   TRY_CONVERT(FLOAT, o.amount) > 0
    AND   TRY_CONVERT(FLOAT, o.amount) <= 100000
) t
WHERE rn = 1

-- =============================================
-- 3. CLEAN: p1_fact_refunds → p1_fact_refunds_clean
-- =============================================

SELECT order_id, user_id, order_date_clean, hours_to_refund
INTO p1_fact_refunds_clean
FROM (
    SELECT 
        order_id,
        user_id,
        TRY_CONVERT(FLOAT, hours_to_refund) AS hours_to_refund,
        CASE 
            WHEN LEN(order_date) = 8  THEN TRY_CONVERT(DATE, order_date, 112)
            WHEN LEN(order_date) = 10 THEN TRY_CONVERT(DATE, order_date, 103)
            WHEN order_date = 'not a date' THEN NULL
            ELSE TRY_CONVERT(DATE, order_date, 120)
        END AS order_date_clean
    FROM p1_fact_refunds
    WHERE hours_to_refund IS NOT NULL
) t
WHERE TRY_CONVERT(FLOAT, hours_to_refund) > 0
AND   TRY_CONVERT(FLOAT, hours_to_refund) <= 720
AND   order_date_clean IS NOT NULL

-- =============================================
-- 4. CLEAN: p1_fact_events --- p1_fact_events_clean
-- =============================================

SELECT event_id, user_id, event_date, device, event_name_clean
INTO p1_fact_events_clean
FROM (
    SELECT 
        e.event_id,
        e.user_id,
        TRY_CONVERT(DATE, e.event_date, 120) AS event_date,
        e.device,
        CASE 
            WHEN UPPER(REPLACE(e.event_name,' ','_')) = 'CHECKOUT_START' THEN 'checkout_start'
            WHEN e.event_name = 'unknown_event' 
                 OR e.event_name IS NULL THEN 'Unknown'
            ELSE e.event_name
        END AS event_name_clean
    FROM p1_fact_events e
    JOIN p1_dim_user_clean u ON e.user_id = u.user_id
) t
WHERE event_date IS NOT NULL

-- =============================================
-- 5. CLEAN: p1_retention_d7 --- p1_retention_d7_clean
-- =============================================

SELECT user_id, reg_date, after_release, retained_d7
INTO p1_retention_d7_clean
FROM p1_retention_d7
WHERE retained_d7 IN ('0.0', '1.0')
AND EXISTS (
    SELECT 1 
    FROM p1_dim_user_clean u 
    WHERE u.user_id = p1_retention_d7.user_id
)
