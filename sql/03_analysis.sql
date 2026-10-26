-- =============================================
-- 03_ANALYSIS.SQL
-- 7 Analytical Queries
-- Project: Marketplace Returns Analysis
-- =============================================

-- =============================================
-- 1. RETURN RATE BEFORE/AFTER RELEASE
-- =============================================

SELECT
    CASE WHEN is_after_release = 0 THEN 'Before Release'
         ELSE 'After Release' END                            AS period,
    COUNT(order_id)                                          AS total_orders,
    SUM(CASE WHEN status_clean = 'refunded' THEN 1 ELSE 0 END) AS refunds,
    CAST(SUM(CASE WHEN status_clean = 'refunded' THEN 1 ELSE 0 END) AS FLOAT) * 100
        / COUNT(order_id)                                    AS RR
FROM p1_fact_orders_clean
WHERE status_clean IN ('completed', 'refunded')
GROUP BY is_after_release
ORDER BY is_after_release;
-- Result: Before 6.69% --- After 11.97% (+79%)

-- =============================================
-- 2. SEGMENT ANALYSIS WITH DIFF
-- =============================================

WITH clean_orders AS (
    SELECT *
    FROM p1_fact_orders_clean
    WHERE status_clean IN ('completed', 'refunded')
),
rr_segments AS (
    SELECT 'device' AS segment_type, device_clean AS segment_value, is_after_release,
        CAST(SUM(CASE WHEN status_clean = 'refunded' THEN 1 ELSE 0 END) AS FLOAT) * 100
            / COUNT(order_id) AS RR
    FROM clean_orders
    GROUP BY device_clean, is_after_release
    UNION ALL
    SELECT 'region', region_clean, is_after_release,
        CAST(SUM(CASE WHEN status_clean = 'refunded' THEN 1 ELSE 0 END) AS FLOAT) * 100
            / COUNT(order_id)
    FROM clean_orders
    GROUP BY region_clean, is_after_release
    UNION ALL
    SELECT 'channel', channel_clean, is_after_release,
        CAST(SUM(CASE WHEN status_clean = 'refunded' THEN 1 ELSE 0 END) AS FLOAT) * 100
            / COUNT(order_id)
    FROM clean_orders
    GROUP BY channel_clean, is_after_release
)
SELECT
    segment_type,
    segment_value,
    ROUND(MAX(CASE WHEN is_after_release = 0 THEN RR END), 2) AS RR_before,
    ROUND(MAX(CASE WHEN is_after_release = 1 THEN RR END), 2) AS RR_after,
    ROUND(MAX(CASE WHEN is_after_release = 1 THEN RR END)
        - MAX(CASE WHEN is_after_release = 0 THEN RR END), 2) AS diff
FROM rr_segments
GROUP BY segment_type, segment_value
ORDER BY diff DESC;
-- Result: Android +7.61pp, EU +6.42pp, Paid +6.27pp | iOS +1.48pp

-- =============================================
-- 3. CHECKOUT FUNNEL BY SESSIONS
-- =============================================

WITH funnel AS (   -- 1 строка = 1 сессия (юзер × день)
    SELECT 
        user_id,
        event_date,
        device,
        CASE WHEN event_date >= '2025-06-15' THEN 'After_release'
             ELSE 'Before_release' END AS period,
        MAX(CASE WHEN event_name_clean = 'add_to_cart'       THEN 1 ELSE 0 END) AS add_to_cart,
        MAX(CASE WHEN event_name_clean = 'checkout_start'    THEN 1 ELSE 0 END) AS checkout_start,
        MAX(CASE WHEN event_name_clean = 'checkout_complete' THEN 1 ELSE 0 END) AS checkout_complete,
        MAX(CASE WHEN event_name_clean = 'payment_success'   THEN 1 ELSE 0 END) AS payment_success
    FROM p1_fact_events_clean
    GROUP BY user_id, event_date, device
),
stats AS (
    SELECT period, device,
        SUM(add_to_cart)       AS add_to_cart,
        SUM(checkout_start)    AS checkout_start,
        SUM(checkout_complete) AS checkout_complete,
        SUM(payment_success)   AS payment_success
    FROM funnel
    GROUP BY period, device
)
SELECT
    period, device,
    add_to_cart,
    checkout_start,
    ROUND(CAST(checkout_start    AS FLOAT) * 100 / NULLIF(add_to_cart, 0),       1) AS conv_to_start,
    checkout_complete,
    ROUND(CAST(checkout_complete AS FLOAT) * 100 / NULLIF(checkout_start, 0),    1) AS conv_to_complete,
    payment_success,
    ROUND(CAST(payment_success   AS FLOAT) * 100 / NULLIF(checkout_complete, 0), 1) AS conv_to_payment
FROM stats
ORDER BY device, period DESC;
-- Result: Android checkout_complete 66.4% --- 54.7% (-11.7pp) | iOS 66.5% --- 66.2% (stable)

-- =============================================
-- 4. D7 RETENTION
-- =============================================

SELECT 
    CASE WHEN after_release = 1 THEN 'After Release'
         ELSE 'Before Release' END                    AS period,
    COUNT(user_id)                                    AS total_users,
    SUM(retained_d7)                                  AS retained,
    CAST(SUM(retained_d7) AS FLOAT) * 100 
        / NULLIF(COUNT(user_id), 0)                   AS d7_pct
FROM p1_retention_d7_clean
GROUP BY after_release
ORDER BY after_release;
-- Result: Before 23.07% --- After 19.08% (-4.0pp)
-- =============================================
-- 5. SHARE OF RETURNS WITHIN 24 HOURS
-- =============================================
-- =============================================
-- 5. SHARE OF RETURNS WITHIN 24 HOURS
-- =============================================

SELECT 
    CASE WHEN order_date_clean < '2025-06-15' THEN 'Before_release'
         ELSE 'After_release' END                              AS period,
    COUNT(order_id)                                            AS total_refunds,
    SUM(CASE WHEN hours_to_refund <= 24 THEN 1 ELSE 0 END)     AS refunds_24h,
    CAST(SUM(CASE WHEN hours_to_refund <= 24 THEN 1 ELSE 0 END) AS FLOAT) * 100
        / NULLIF(COUNT(order_id), 0)                           AS pct_24h
FROM p1_fact_refunds_clean
GROUP BY CASE WHEN order_date_clean < '2025-06-15' THEN 'Before_release'
              ELSE 'After_release' END
ORDER BY period DESC;
-- Result: Before 60.4% --- After 60.3% (stable)
-- =============================================


-- 6. COHORT ANALYSIS BY REGISTRATION DATE
-- Question: do users registered after the release refund more than earlier cohorts?
-- Compare RR on orders AFTER release only (same time period for all cohorts)
-- =============================================

SELECT
    CASE 
        WHEN u.reg_date_clean >= '2025-06-15' THEN '4_reg_after_release'
        WHEN u.reg_date_clean >= '2025-06-01' THEN '3_reg_2025-06 (1-14)'
        WHEN u.reg_date_clean >= '2025-05-01' THEN '2_reg_2025-05'
        ELSE '1_reg_2025-04'
    END                                                       AS cohort,
    COUNT(o.order_id)                                         AS orders,
    CAST(SUM(CASE WHEN o.status_clean = 'refunded' THEN 1 ELSE 0 END) AS FLOAT) * 100
        / NULLIF(COUNT(o.order_id), 0)                        AS RR
FROM p1_fact_orders_clean o
JOIN p1_dim_user_clean u ON o.user_id = u.user_id
WHERE o.status_clean IN ('completed', 'refunded')
  AND o.is_after_release = 1                  -- одинаковый период для всех когорт
  AND u.reg_date_clean IS NOT NULL
  AND o.order_date_clean >= u.reg_date_clean  -- только логически возможные заказы
GROUP BY
    CASE 
        WHEN u.reg_date_clean >= '2025-06-15' THEN '4_reg_after_release'
        WHEN u.reg_date_clean >= '2025-06-01' THEN '3_reg_2025-06 (1-14)'
        WHEN u.reg_date_clean >= '2025-05-01' THEN '2_reg_2025-05'
        ELSE '1_reg_2025-04'
    END
ORDER BY cohort;
-- Result: Apr 12.05% | May 12.16% | Jun 1-14 12.01% | After release 11.83%
-- → all cohorts ...12%: the spike hit everyone, not just new users

-- =============================================
-- 7a. ANTI-JOIN: users who started checkout but NEVER paid (whole period)
-- =============================================

WITH checkout_start_users AS (
    SELECT DISTINCT user_id
    FROM p1_fact_events_clean
    WHERE event_name_clean = 'checkout_start'
),
payment_success_users AS (
    SELECT DISTINCT user_id
    FROM p1_fact_events_clean
    WHERE event_name_clean = 'payment_success'
)
SELECT COUNT(*) AS never_paid_users
FROM checkout_start_users cs
LEFT JOIN payment_success_users ps ON cs.user_id = ps.user_id
WHERE ps.user_id IS NULL;
-- Result: 5,667 users never completed a payment in Apr–Jul
-- Note: user-level metric over the whole period, NOT a before/after comparison


-- =============================================
-- 7b. CHECKOUT DROP-OFF BY SESSIONS (before/after)
-- =============================================

WITH sessions AS (
    SELECT
        user_id,
        event_date,
        device,
        CASE WHEN event_date >= '2025-06-15' THEN 'After_release'
             ELSE 'Before_release' END AS period,
        MAX(CASE WHEN event_name_clean = 'checkout_start'  THEN 1 ELSE 0 END) AS started,
        MAX(CASE WHEN event_name_clean = 'payment_success' THEN 1 ELSE 0 END) AS paid
    FROM p1_fact_events_clean
    GROUP BY user_id, event_date, device
)
SELECT
    device,
    period,
    SUM(started)                                              AS checkout_sessions,
    SUM(CASE WHEN started = 1 AND paid = 0 THEN 1 ELSE 0 END) AS dropoff_sessions,
    CAST(SUM(CASE WHEN started = 1 AND paid = 0 THEN 1 ELSE 0 END) AS FLOAT) * 100
        / NULLIF(SUM(started), 0)                             AS dropoff_pct
FROM sessions
GROUP BY device, period
ORDER BY device, period DESC;
-- Result: Android 43.7% → 53.8% (+10.1pp) | iOS 43.8% → 43.9% (stable)
