-- =============================================
-- 01_DQ_CHECK.SQL
-- Data Quality Check: 5 tables
-- Project: Marketplace Returns Analysis
-- =============================================

-- =============================================
-- 1. DQ CHECK: p1_dim_user
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_dim_user;
-- Result: 81,600

-- NULL check
SELECT 
    SUM(CASE WHEN user_id  IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN reg_date IS NULL THEN 1 ELSE 0 END) AS reg_date_nulls,
    SUM(CASE WHEN device   IS NULL THEN 1 ELSE 0 END) AS device_nulls,
    SUM(CASE WHEN region   IS NULL THEN 1 ELSE 0 END) AS region_nulls,
    SUM(CASE WHEN channel  IS NULL THEN 1 ELSE 0 END) AS channel_nulls
FROM p1_dim_user;

-- Unique values (brackets show hidden spaces)
SELECT '[' + device  + ']' AS device,  COUNT(*) AS cnt FROM p1_dim_user GROUP BY device;
SELECT '[' + region  + ']' AS region,  COUNT(*) AS cnt FROM p1_dim_user GROUP BY region;
SELECT '[' + channel + ']' AS channel, COUNT(*) AS cnt FROM p1_dim_user GROUP BY channel;
-- Result: device: Andr0id, ANDROID, ios, unknown | region: '  EU', 'LATAM ', USA, N/A | channel: ref, ORGANIC, 'organic ', N/A

-- Date formats by PATTERN
SELECT TRANSLATE(reg_date, '0123456789', '9999999999') AS pattern,
       COUNT(*) AS cnt, MIN(reg_date) AS example
FROM p1_dim_user
GROUP BY TRANSLATE(reg_date, '0123456789', '9999999999')
ORDER BY cnt DESC;
-- Result: 6 patterns — yyyy-mm-dd hh:mm:ss, yyyymmdd, dd-mm-yyyy hh:mm:ss (500), dd/mm/yyyy, 'not a date', NULL

-- Duplicates
SELECT COUNT(*) AS dup_users,
       SUM(CASE WHEN variants > 1 THEN 1 ELSE 0 END) AS different_rows
FROM (
    SELECT user_id, 
           COUNT(DISTINCT CONCAT(reg_date, device, region, channel)) AS variants
    FROM p1_dim_user
    GROUP BY user_id
    HAVING COUNT(*) > 1
) t;
-- Result: 1,600 duplicated users, 0 with different values --- exact copies

-- =============================================
-- 2. DQ CHECK: p1_fact_orders
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_fact_orders;
-- Result: 426,300

-- NULL check
SELECT 
    SUM(CASE WHEN order_id   IS NULL THEN 1 ELSE 0 END) AS order_id_nulls,
    SUM(CASE WHEN user_id    IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN order_date IS NULL THEN 1 ELSE 0 END) AS order_date_nulls,
    SUM(CASE WHEN amount     IS NULL THEN 1 ELSE 0 END) AS amount_nulls,
    SUM(CASE WHEN status     IS NULL THEN 1 ELSE 0 END) AS status_nulls
FROM p1_fact_orders;
-- Result: 0 | 0 | 2,144 | 2,091 | 3,158

-- Unique status values
SELECT '[' + status + ']' AS status, COUNT(*) AS cnt
FROM p1_fact_orders
GROUP BY status
ORDER BY cnt DESC;
-- Result: completed, refunded, cancelled + Completed, REFUNDED, complete, canceled, unknown, N/A, NULL

-- Amount anomalies
SELECT 
    SUM(CASE WHEN TRY_CONVERT(FLOAT, amount) IS NULL  THEN 1 ELSE 0 END) AS null_amount,
    SUM(CASE WHEN TRY_CONVERT(FLOAT, amount) <= 0     THEN 1 ELSE 0 END) AS negative_zero,
    SUM(CASE WHEN TRY_CONVERT(FLOAT, amount) > 100000 THEN 1 ELSE 0 END) AS outliers
FROM p1_fact_orders;
-- Result: 2,091 | 4,289 | 2,145

-- Date formats by PATTERN
SELECT TRANSLATE(order_date, '0123456789', '9999999999') AS pattern,
       COUNT(*) AS cnt, MIN(order_date) AS example
FROM p1_fact_orders
GROUP BY TRANSLATE(order_date, '0123456789', '9999999999')
ORDER BY cnt DESC;
-- Result: yyyy-mm-dd hh:mm:ss 419,852 | dd/mm/yyyy 2,152 | yyyymmdd 2,152 | NULL 2,144

-- Invalid dates: correct pattern, impossible value
SELECT order_date, COUNT(*) AS cnt
FROM p1_fact_orders
WHERE order_date LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
  AND TRY_CONVERT(DATE, LEFT(order_date, 10), 120) IS NULL
GROUP BY order_date;
-- Result: '2025-13-45 00:00:00' — 2,069 rows (month 13)

-- is_after_release vs order_date (valid dates only)
SELECT 
    is_after_release,
    CASE WHEN TRY_CONVERT(DATE, LEFT(order_date, 10), 120) >= '2025-06-15' 
         THEN 1 ELSE 0 END AS after_by_date,
    COUNT(*) AS cnt
FROM p1_fact_orders
WHERE TRY_CONVERT(DATE, LEFT(order_date, 10), 120) IS NOT NULL
GROUP BY is_after_release,
         CASE WHEN TRY_CONVERT(DATE, LEFT(order_date, 10), 120) >= '2025-06-15' 
              THEN 1 ELSE 0 END;
-- Result: only (0,0) and (1,1) → flag is consistent with date

-- Duplicates
SELECT COUNT(*) AS dup_orders,
       SUM(CASE WHEN variants > 1 THEN 1 ELSE 0 END) AS different_rows
FROM (
    SELECT order_id,
           COUNT(DISTINCT CONCAT(user_id, order_date, amount, status, 
                                 device, region, channel, is_after_release)) AS variants
    FROM p1_fact_orders
    GROUP BY order_id
    HAVING COUNT(*) > 1
) t;
-- Result: 6,300 duplicated orders, 0 different → exact copies

-- Conflict between sources: segment in orders vs dim_user
SELECT COUNT(DISTINCT o.user_id) AS users_with_conflict
FROM p1_fact_orders o
JOIN p1_dim_user_clean u ON o.user_id = u.user_id
WHERE o.device  <> u.device_clean
   OR o.region  <> u.region_clean
   OR o.channel <> u.channel_clean;
-- Result: 3,821 users — dim_user chosen as single source of truth

-- =============================================
-- 3. DQ CHECK: p1_fact_refunds
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_fact_refunds;
-- Result: 33,383

-- NULL check
SELECT 
    SUM(CASE WHEN order_id        IS NULL THEN 1 ELSE 0 END) AS order_id_nulls,
    SUM(CASE WHEN user_id         IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN order_date      IS NULL THEN 1 ELSE 0 END) AS order_date_nulls,
    SUM(CASE WHEN hours_to_refund IS NULL THEN 1 ELSE 0 END) AS hours_nulls
FROM p1_fact_refunds;
-- Result: 0 | 0 | 165 | 234

-- hours_to_refund anomalies
SELECT
    SUM(CASE WHEN TRY_CONVERT(FLOAT, hours_to_refund) < 0   THEN 1 ELSE 0 END) AS negative,
    SUM(CASE WHEN TRY_CONVERT(FLOAT, hours_to_refund) = 0   THEN 1 ELSE 0 END) AS zero,
    SUM(CASE WHEN TRY_CONVERT(FLOAT, hours_to_refund) > 720 THEN 1 ELSE 0 END) AS over_30_days
FROM p1_fact_refunds;
-- Result: 251 | 251 | 265

-- Date formats by PATTERN
SELECT TRANSLATE(order_date, '0123456789', '9999999999') AS pattern,
       COUNT(*) AS cnt, MIN(order_date) AS example
FROM p1_fact_refunds
GROUP BY TRANSLATE(order_date, '0123456789', '9999999999')
ORDER BY cnt DESC;
-- Result: yyyy-mm-dd hh:mm:ss 32,881 | dd/mm/yyyy 192 | NULL 165 | yyyymmdd 145

-- Invalid dates
SELECT COUNT(*) AS invalid_dates
FROM p1_fact_refunds
WHERE order_date LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
  AND TRY_CONVERT(DATE, LEFT(order_date, 10), 120) IS NULL;
-- Result: 146

-- Duplicates
SELECT COUNT(*) AS dup_orders,
       SUM(CASE WHEN variants > 1 THEN 1 ELSE 0 END) AS different_rows
FROM (
    SELECT order_id,
           COUNT(DISTINCT CONCAT(user_id, order_date, hours_to_refund)) AS variants
    FROM p1_fact_refunds
    GROUP BY order_id
    HAVING COUNT(*) > 1
) t;
-- Result: 525 duplicated orders, 516 differ (in hours_to_refund) → need a rule: keep earliest refund

-- Consistency with orders
SELECT
    SUM(CASE WHEN o.order_id IS NULL              THEN 1 ELSE 0 END) AS refund_without_order,
    SUM(CASE WHEN o.status   <> 'refunded'        THEN 1 ELSE 0 END) AS order_not_refunded,
    SUM(CASE WHEN o.user_id  <> r.user_id         THEN 1 ELSE 0 END) AS user_mismatch
FROM p1_fact_refunds r
LEFT JOIN (SELECT DISTINCT order_id, user_id, status FROM p1_fact_orders) o
       ON o.order_id = r.order_id;
-- Result: 0 | 0 | 0 → every refund matches a refunded order

-- Reverse: refunded orders without refund record
SELECT COUNT(DISTINCT o.order_id) AS refunded_without_record
FROM p1_fact_orders o
WHERE o.status = 'refunded'
  AND NOT EXISTS (SELECT 1 FROM p1_fact_refunds r
    
-- =============================================
-- 4. DQ CHECK: p1_fact_events
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_fact_events;
-- Result: 1,299,493

-- NULL check
SELECT 
    SUM(CASE WHEN event_id   IS NULL THEN 1 ELSE 0 END) AS event_id_nulls,
    SUM(CASE WHEN user_id    IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN event_date IS NULL THEN 1 ELSE 0 END) AS event_date_nulls,
    SUM(CASE WHEN device     IS NULL THEN 1 ELSE 0 END) AS device_nulls,
    SUM(CASE WHEN event_name IS NULL THEN 1 ELSE 0 END) AS event_name_nulls
FROM p1_fact_events;
-- Result: 0 | 0 | 8,718 | 0 | 13,000

-- Unique event_name values
SELECT '[' + event_name + ']' AS event_name, COUNT(*) AS cnt
FROM p1_fact_events
GROUP BY event_name
ORDER BY cnt DESC;
-- Result: 4 valid + Add_To_Cart, CHECKOUT_START, 'checkout start', unknown_event, NULL

-- Date formats by PATTERN
SELECT TRANSLATE(event_date, '0123456789', '9999999999') AS pattern,
       COUNT(*) AS cnt, MIN(event_date) AS example
FROM p1_fact_events
GROUP BY TRANSLATE(event_date, '0123456789', '9999999999')
ORDER BY cnt DESC;
-- Result: yyyy-mm-dd hh:mm:ss 1,273,504 | NULL 8,718 | 'not a date' 8,663 | yyyy-mm-dd 8,608

-- Invalid dates
SELECT COUNT(*) AS invalid_dates
FROM p1_fact_events
WHERE event_date LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
  AND TRY_CONVERT(DATE, LEFT(event_date, 10), 120) IS NULL;
-- Result: 8,608 → all 'yyyy-mm-dd' dates are invalid (e.g. 2025-13-01)

-- Duplicates
SELECT COUNT(*) AS dup_events
FROM (SELECT event_id FROM p1_fact_events GROUP BY event_id HAVING COUNT(*) > 1) t;
-- Result: 0

-- Orphans: user not in RAW dim_user
SELECT COUNT(*) AS orphan_events, COUNT(DISTINCT e.user_id) AS orphan_users
FROM p1_fact_events e
WHERE NOT EXISTS (SELECT 1 FROM p1_dim_user u WHERE u.user_id = e.user_id);
-- Result: 12,994 events | 12,178 users (e.g. user_id 980693 — out of range)

-- Conflict between sources: device in events vs dim_user
SELECT COUNT(*) AS events_with_conflict, COUNT(DISTINCT e.user_id) AS users
FROM p1_fact_events e
JOIN p1_dim_user_clean u ON e.user_id = u.user_id
WHERE e.device <> u.device_clean;
-- Result: 14,787 events | 915 users → device taken from dim_user in cleaning\

-- =============================================
-- 5. DQ CHECK: p1_retention_d7
-- =============================================

-- Row count
SELECT COUNT(*) AS total FROM p1_retention_d7;
-- Result: 39,327

-- NULL check
SELECT 
    SUM(CASE WHEN user_id     IS NULL THEN 1 ELSE 0 END) AS user_id_nulls,
    SUM(CASE WHEN reg_date    IS NULL THEN 1 ELSE 0 END) AS reg_date_nulls,
    SUM(CASE WHEN retained_d7 IS NULL THEN 1 ELSE 0 END) AS retained_nulls
FROM p1_retention_d7;
-- Result: 0 | 0 | 309

-- Unique retained_d7 values
SELECT retained_d7, COUNT(*) AS cnt
FROM p1_retention_d7
GROUP BY retained_d7
ORDER BY cnt DESC;
-- Result: 0.0, 1.0 valid | -1.0, 2.0, 99.0, NULL invalid

-- Duplicates + conflicting values
SELECT 
    COUNT(*)                                             AS dup_users,
    SUM(CASE WHEN distinct_values > 1 THEN 1 ELSE 0 END) AS conflicting_users
FROM (
    SELECT user_id, COUNT(DISTINCT retained_d7) AS distinct_values
    FROM p1_retention_d7
    GROUP BY user_id
    HAVING COUNT(*) > 1
) t;
-- Result: 770 duplicated | 290 conflicting (252 after removing invalid values) → excluded in cleaning

-- after_release vs reg_date
SELECT 
    after_release,
    MIN(reg_date) AS min_date,
    MAX(reg_date) AS max_date,
    COUNT(*)      AS cnt
FROM p1_retention_d7
GROUP BY after_release;
-- Result: 0 → 2025-06-01..2025-06-14 | 1 → 2025-06-15..2025-07-30 → consistent

-- reg_date matches dim_user
SELECT 
    COUNT(*) AS matched,
    SUM(CASE WHEN TRY_CONVERT(DATE, r.reg_date, 120) <> u.reg_date_clean 
             THEN 1 ELSE 0 END) AS different_dates
FROM p1_retention_d7 r
JOIN p1_dim_user_clean u ON r.user_id = u.user_id
WHERE u.reg_date_clean IS NOT NULL;
-- Result: different_dates = 0 → both tables agree

-- Immature cohort: not enough days for D7 (events end 2025-07-31)
SELECT 
    COUNT(*) AS total,
    SUM(CASE WHEN TRY_CONVERT(DATE, reg_date, 120) > '2025-07-24' 
             THEN 1 ELSE 0 END) AS immature_users
FROM p1_retention_d7;
-- Result: 3,951 of

-- =============================================
-- 6. CROSS-TABLE LOGICAL CHECKS (run after cleaning)
-- =============================================

-- 6.1 Orders placed before user registration
SELECT 
    COUNT(*) AS orders,
    SUM(CASE WHEN o.order_date_clean < u.reg_date_clean THEN 1 ELSE 0 END) AS before_reg
FROM p1_fact_orders_clean o
JOIN p1_dim_user_clean u ON o.user_id = u.user_id
WHERE u.reg_date_clean IS NOT NULL;
-- Result: 189,721 of 382,791 (49.6%) — generator flaw
-- Decision: cohort analysis (Q6) uses only orders with order_date >= reg_date

-- 6.2 Events before user registration
SELECT 
    COUNT(*) AS events,
    SUM(CASE WHEN e.event_date < u.reg_date_clean THEN 1 ELSE 0 END) AS before_reg
FROM p1_fact_events_clean e
JOIN p1_dim_user_clean u ON e.user_id = u.user_id
WHERE u.reg_date_clean IS NOT NULL;
-- Result: 583,987 before registration (~49%) — same generator flaw
-- Decision: funnel compares periods by event_date, not by user cohort → not affected
