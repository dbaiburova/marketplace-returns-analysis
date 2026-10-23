-- =============================================
-- 1. CLEAN: p1_dim_user --- p1_dim_user_clean
-- =============================================

DROP TABLE IF EXISTS p1_dim_user_clean;

SELECT user_id, reg_date_clean, device_clean, region_clean, channel_clean
INTO p1_dim_user_clean
FROM (
    SELECT 
        user_id,

        -- Дата: 5 форматов в сырых данных
        CASE 
            WHEN reg_date IS NULL OR reg_date = 'not a date'           THEN NULL
            WHEN LEN(reg_date) = 8                                     THEN TRY_CONVERT(DATE, reg_date, 112)  -- 20250401
            WHEN LEN(reg_date) = 10                                    THEN TRY_CONVERT(DATE, reg_date, 103)  -- 01/04/2025
            WHEN reg_date LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]%'
                                                                       THEN TRY_CONVERT(DATE, LEFT(reg_date, 10), 105)  -- 01-04-2025 06:18:00
            ELSE TRY_CONVERT(DATE, reg_date, 120)                                                              -- 2025-04-01 06:18:00
        END AS reg_date_clean,

        -- Device: перечисляем хорошие значения, остальное --- Unknown
        CASE 
            WHEN UPPER(TRIM(device)) IN ('ANDROID','ANDR0ID') THEN 'Android'
            WHEN UPPER(TRIM(device)) = 'IOS'                  THEN 'iOS'
            ELSE 'Unknown'
        END AS device_clean,

        -- Region
        CASE 
            WHEN UPPER(TRIM(region)) IN ('US','USA')              THEN 'US'
            WHEN UPPER(TRIM(region)) IN ('EU','APAC','LATAM')     THEN UPPER(TRIM(region))
            ELSE 'Unknown'
        END AS region_clean,

        -- Channel
        CASE 
            WHEN UPPER(TRIM(channel)) IN ('REF','REFERRAL') THEN 'Referral'
            WHEN UPPER(TRIM(channel)) = 'ORGANIC'           THEN 'Organic'
            WHEN UPPER(TRIM(channel)) = 'PAID'              THEN 'Paid'
            ELSE 'Unknown'
        END AS channel_clean,

        -- Дубли: 1,600 юзеров, все дубли — точные копии
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY user_id) AS rn
    FROM p1_dim_user
) t
WHERE rn = 1
AND device_clean  != 'Unknown'
AND region_clean  != 'Unknown'
AND channel_clean != 'Unknown';

-- Result: 76,084 rows, 0 Unknown


-- =============================================
-- 2. CLEAN: p1_fact_orders --- p1_fact_orders_clean
-- =============================================

-- =============================================
-- 2. CLEAN: p1_fact_orders --- p1_fact_orders_clean
-- =============================================

DROP TABLE IF EXISTS p1_fact_orders_clean;

SELECT order_id, user_id, order_date_clean, amount,
       status_clean, device_clean, region_clean,
       channel_clean, is_after_release
INTO p1_fact_orders_clean
FROM (
    SELECT
        o.order_id,
        o.user_id,
        TRY_CONVERT(DECIMAL(10,2), o.amount) AS amount,
        CAST(o.is_after_release AS INT)      AS is_after_release,

        CASE 
            WHEN LOWER(TRIM(o.status)) IN ('completed','complete') THEN 'completed'
            WHEN LOWER(TRIM(o.status)) = 'refunded'                THEN 'refunded'
            WHEN LOWER(TRIM(o.status)) IN ('cancelled','canceled') THEN 'cancelled'
            ELSE 'Unknown'
        END AS status_clean,

        CASE 
            WHEN o.order_date LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
                THEN TRY_CONVERT(DATE, LEFT(o.order_date, 10), 120)
            WHEN o.order_date LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
                THEN TRY_CONVERT(DATE, o.order_date, 112)
            WHEN o.order_date LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'
                THEN TRY_CONVERT(DATE, o.order_date, 103)
            ELSE NULL
        END AS order_date_clean,

        u.device_clean,
        u.region_clean,
        u.channel_clean,
        ROW_NUMBER() OVER (PARTITION BY o.order_id ORDER BY o.order_id) AS rn
    FROM p1_fact_orders o
    JOIN p1_dim_user_clean u ON o.user_id = u.user_id
    WHERE TRY_CONVERT(FLOAT, o.amount) > 0
      AND TRY_CONVERT(FLOAT, o.amount) <= 100000
) t
WHERE rn = 1
  AND order_date_clean IS NOT NULL;
-- Result: 387,430 rows

-- =============================================
-- 3. CLEAN: p1_fact_refunds --- p1_fact_refunds_clean
-- =============================================
DROP TABLE IF EXISTS p1_fact_refunds_clean;

SELECT order_id, user_id, order_date_clean, hours_to_refund
INTO p1_fact_refunds_clean
FROM (
    SELECT
        r.order_id,
        r.user_id,
        TRY_CONVERT(FLOAT, r.hours_to_refund) AS hours_to_refund,
        CASE 
            WHEN r.order_date LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
                THEN TRY_CONVERT(DATE, LEFT(r.order_date, 10), 120)
            WHEN r.order_date LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
                THEN TRY_CONVERT(DATE, r.order_date, 112)
            WHEN r.order_date LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'
                THEN TRY_CONVERT(DATE, r.order_date, 103)
            ELSE NULL
        END AS order_date_clean,
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id 
            ORDER BY TRY_CONVERT(FLOAT, r.hours_to_refund)
        ) AS rn
    FROM p1_fact_refunds r
    WHERE TRY_CONVERT(FLOAT, r.hours_to_refund) > 0
      AND TRY_CONVERT(FLOAT, r.hours_to_refund) <= 720
      AND EXISTS (
          SELECT 1 FROM p1_fact_orders_clean o
          WHERE o.order_id = r.order_id
            AND o.status_clean = 'refunded'
      )
) t
WHERE rn = 1
  AND order_date_clean IS NOT NULL;

-- =============================================
-- 4. CLEAN: p1_fact_events --- p1_fact_events_clean
-- =============================================

DROP TABLE IF EXISTS p1_fact_events_clean;

SELECT event_id, user_id, event_date, device, event_name_clean
INTO p1_fact_events_clean
FROM (
    SELECT 
        CAST(e.event_id AS INT)                  AS event_id,
        CAST(e.user_id  AS INT)                  AS user_id,
        CASE 
            WHEN e.event_date LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
                THEN TRY_CONVERT(DATE, LEFT(e.event_date, 10), 120)
            ELSE NULL
        END                                      AS event_date,
        CAST(u.device_clean AS VARCHAR(10))      AS device,
        CAST(CASE LOWER(REPLACE(TRIM(e.event_name), ' ', '_'))
            WHEN 'add_to_cart'       THEN 'add_to_cart'
            WHEN 'checkout_start'    THEN 'checkout_start'
            WHEN 'checkout_complete' THEN 'checkout_complete'
            WHEN 'payment_success'   THEN 'payment_success'
            ELSE 'Unknown'
        END AS VARCHAR(20))                      AS event_name_clean
    FROM p1_fact_events e
    JOIN p1_dim_user_clean u ON e.user_id = u.user_id
) t
WHERE event_date IS NOT NULL
  AND event_name_clean <> 'Unknown';
-- Result: 1,180,234 rows

-- =============================================
-- 5. CLEAN: p1_retention_d7 --- p1_retention_d7_clean
-- =============================================
-- =============================================
-- 5. CLEAN: p1_retention_d7 --- p1_retention_d7_clean
-- =============================================

DROP TABLE IF EXISTS p1_retention_d7_clean;

SELECT
    user_id,
    MIN(reg_date)      AS reg_date,
    MIN(after_release) AS after_release,
    MIN(retained_d7)   AS retained_d7
INTO p1_retention_d7_clean
FROM (
    SELECT
        CAST(r.user_id AS INT)                               AS user_id,
        TRY_CONVERT(DATE, r.reg_date, 120)                   AS reg_date,
        CAST(r.after_release AS INT)                         AS after_release,
        CAST(TRY_CONVERT(FLOAT, r.retained_d7) AS INT)       AS retained_d7
    FROM p1_retention_d7 r
    WHERE r.retained_d7 IN ('0.0', '1.0')
      AND EXISTS (
          SELECT 1 FROM p1_dim_user_clean u
          WHERE u.user_id = r.user_id
      )
) t
GROUP BY user_id
HAVING COUNT(DISTINCT retained_d7) = 1;
-- Result: 35,367 rows
