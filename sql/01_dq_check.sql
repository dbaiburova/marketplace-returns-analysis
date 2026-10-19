-- =============================================
-- 01_DQ_CHECK.SQL
-- Data Quality Check: 5 tables
-- Project: Marketplace Returns Analysis
-- =============================================

-- =============================================
-- 1. DQ CHECK: p1_dim_user
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_dim_user

-- NULL check
SELECT 
    SUM(CASE WHEN user_id  IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN reg_date IS NULL THEN 1 ELSE 0 END) AS reg_date_nulls,
    SUM(CASE WHEN device   IS NULL THEN 1 ELSE 0 END) AS device_nulls,
    SUM(CASE WHEN region   IS NULL THEN 1 ELSE 0 END) AS region_nulls,
    SUM(CASE WHEN channel  IS NULL THEN 1 ELSE 0 END) AS channel_nulls
FROM p1_dim_user

-- Unique values
SELECT DISTINCT device  FROM p1_dim_user
SELECT DISTINCT region, LEN(region) AS len FROM p1_dim_user ORDER BY region
SELECT DISTINCT channel FROM p1_dim_user

-- Date formats
SELECT DISTINCT LEN(reg_date) AS len, COUNT(*) AS cnt
FROM p1_dim_user
GROUP BY LEN(reg_date)
ORDER BY len

SELECT DISTINCT reg_date, LEN(reg_date) AS len
FROM p1_dim_user
WHERE LEN(reg_date) != 19
ORDER BY LEN(reg_date)
    
-- Duplicates
SELECT user_id, COUNT(*) AS cnt
FROM p1_dim_user
GROUP BY user_id
HAVING COUNT(*) > 1

-- =============================================
-- 2. DQ CHECK: p1_fact_orders
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_fact_orders

-- NULL check
SELECT 
    SUM(CASE WHEN order_id   IS NULL THEN 1 ELSE 0 END) AS order_id_nulls,
    SUM(CASE WHEN user_id    IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN order_date IS NULL THEN 1 ELSE 0 END) AS order_date_nulls,
    SUM(CASE WHEN amount     IS NULL THEN 1 ELSE 0 END) AS amount_nulls,
    SUM(CASE WHEN status     IS NULL THEN 1 ELSE 0 END) AS status_nulls
FROM p1_fact_orders

-- Unique status values
SELECT DISTINCT status, COUNT(*) AS cnt
FROM p1_fact_orders
GROUP BY status
ORDER BY cnt DESC

-- Amount anomalies
SELECT 
    SUM(CASE WHEN TRY_CONVERT(FLOAT, amount) IS NULL  THEN 1 ELSE 0 END) AS null_amount,
    SUM(CASE WHEN TRY_CONVERT(FLOAT, amount) <= 0     THEN 1 ELSE 0 END) AS negative_zero,
    SUM(CASE WHEN TRY_CONVERT(FLOAT, amount) > 100000 THEN 1 ELSE 0 END) AS outliers
FROM p1_fact_orders

-- Date formats
SELECT DISTINCT LEN(order_date) AS len, COUNT(*) AS cnt
FROM p1_fact_orders
GROUP BY LEN(order_date)
ORDER BY len

-- Duplicates
SELECT order_id, COUNT(*) AS cnt
FROM p1_fact_orders
GROUP BY order_id
HAVING COUNT(*) > 1

-- =============================================
-- 3. DQ CHECK: p1_fact_refunds
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_fact_refunds

-- NULL check
SELECT 
    SUM(CASE WHEN order_id        IS NULL THEN 1 ELSE 0 END) AS order_id_nulls,
    SUM(CASE WHEN user_id         IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN order_date      IS NULL THEN 1 ELSE 0 END) AS order_date_nulls,
    SUM(CASE WHEN hours_to_refund IS NULL THEN 1 ELSE 0 END) AS hours_nulls
FROM p1_fact_refunds

-- hours_to_refund anomalies
SELECT
    SUM(CASE WHEN hours_to_refund IS NULL THEN 1 ELSE 0 END)                    AS null_hours,
    SUM(CASE WHEN TRY_CONVERT(FLOAT, hours_to_refund) < 0   THEN 1 ELSE 0 END) AS negative,
    SUM(CASE WHEN TRY_CONVERT(FLOAT, hours_to_refund) = 0   THEN 1 ELSE 0 END) AS zero,
    SUM(CASE WHEN TRY_CONVERT(FLOAT, hours_to_refund) > 720 THEN 1 ELSE 0 END) AS outliers
FROM p1_fact_refunds

-- =============================================
-- 4. DQ CHECK: p1_fact_events
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_fact_events

-- NULL check
SELECT 
    SUM(CASE WHEN user_id    IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN event_date IS NULL THEN 1 ELSE 0 END) AS event_date_nulls,
    SUM(CASE WHEN device     IS NULL THEN 1 ELSE 0 END) AS device_nulls,
    SUM(CASE WHEN event_name IS NULL THEN 1 ELSE 0 END) AS event_name_nulls
FROM p1_fact_events

-- Unique event_name values
SELECT DISTINCT event_name, COUNT(*) AS cnt
FROM p1_fact_events
GROUP BY event_name
ORDER BY cnt DESC

-- Date formats
SELECT DISTINCT LEN(event_date) AS len, COUNT(*) AS cnt
FROM p1_fact_events
GROUP BY LEN(event_date)
ORDER BY len

-- Orphan records
SELECT COUNT(*) AS orphan_count
FROM p1_fact_events e
LEFT JOIN p1_dim_user_clean u ON e.user_id = u.user_id
WHERE u.user_id IS NULL

-- =============================================
-- 5. DQ CHECK: p1_retention_d7
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_retention_d7

-- NULL check
SELECT 
    SUM(CASE WHEN user_id     IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN reg_date    IS NULL THEN 1 ELSE 0 END) AS reg_date_nulls,
    SUM(CASE WHEN retained_d7 IS NULL THEN 1 ELSE 0 END) AS retained_nulls
FROM p1_retention_d7

-- Unique retained_d7 values
SELECT DISTINCT retained_d7, COUNT(*) AS cnt
FROM p1_retention_d7
GROUP BY retained_d7
ORDER BY cnt DESC
