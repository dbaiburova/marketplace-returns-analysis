-- =============================================
-- 03_ANALYSIS.SQL
-- 7 Analytical Queries
-- Project: Marketplace Returns Analysis
-- =============================================

-- =============================================
-- 1. RETURN RATE BEFORE/AFTER RELEASE
-- =============================================

WITH clean_orders AS (
    SELECT *
    FROM p1_fact_orders_clean
    WHERE status_clean NOT IN ('unknown','cancelled')
)
SELECT
    CASE
        WHEN is_after_release = 0 THEN 'Before Release'
        WHEN is_after_release = 1 THEN 'After Release'
    END AS period,
    COUNT(order_id) AS total_orders,
    SUM(CASE WHEN status_clean = 'refunded' 
        THEN 1 ELSE 0 END) AS refunds,
    CAST(SUM(CASE WHEN status_clean = 'refunded' 
        THEN 1 ELSE 0 END) AS FLOAT) * 100
    / COUNT(order_id) AS RR
FROM clean_orders
GROUP BY is_after_release
ORDER BY is_after_release
-- Result: Before 6.68% --- After 11.95% (+79%)

-- =============================================
-- 2. SEGMENT ANALYSIS WITH DIFF
-- =============================================

WITH clean_orders AS (
    SELECT *
    FROM p1_fact_orders_clean
    WHERE status_clean NOT IN ('unknown','cancelled')
),
rr_segments AS (
    SELECT 'device' AS segment_type, device_clean AS segment_value,
        is_after_release,
        CAST(SUM(CASE WHEN status_clean = 'refunded' 
            THEN 1 ELSE 0 END) AS FLOAT) * 100 
        / COUNT(order_id) AS RR
    FROM clean_orders
    GROUP BY device_clean, is_after_release
    UNION ALL
    SELECT 'region' AS segment_type, region_clean AS segment_value,
        is_after_release,
        CAST(SUM(CASE WHEN status_clean = 'refunded' 
            THEN 1 ELSE 0 END) AS FLOAT) * 100 
        / COUNT(order_id) AS RR
    FROM clean_orders
    GROUP BY region_clean, is_after_release
    UNION ALL
    SELECT 'channel' AS segment_type, channel_clean AS segment_value,
        is_after_release,
        CAST(SUM(CASE WHEN status_clean = 'refunded' 
            THEN 1 ELSE 0 END) AS FLOAT) * 100 
        / COUNT(order_id) AS RR
    FROM clean_orders
    GROUP BY channel_clean, is_after_release
)
SELECT
    segment_type,
    segment_value,
    ROUND(MAX(CASE WHEN is_after_release = 0 THEN RR END), 2) AS RR_before,
    ROUND(MAX(CASE WHEN is_after_release = 1 THEN RR END), 2) AS RR_after,
    ROUND(MAX(CASE WHEN is_after_release = 1 THEN RR END) -
    MAX(CASE WHEN is_after_release = 0 THEN RR END), 2) AS diff
FROM rr_segments
GROUP BY segment_type, segment_value
ORDER BY diff DESC
-- Result: Android +7.7pp, EU +6.4pp, Paid +6.3pp

-- =============================================
-- 3. CHECKOUT FUNNEL BY SESSIONS
-- =============================================

WITH periods_cte AS (
    SELECT *,
        CASE 
            WHEN event_date >= '2025-06-15' THEN 'After_release'
            ELSE 'Before_release'
        END AS period
    FROM p1_fact_events_clean
),
funnel AS (
    SELECT 
        user_id, period, device,
        CAST(event_date AS DATE) AS session_date,
        MAX(CASE WHEN event_name_clean = 'add_to_cart' 
            THEN 1 ELSE 0 END) AS add_to_cart,
        MAX(CASE WHEN event_name_clean = 'checkout_start' 
            THEN 1 ELSE 0 END) AS checkout_start,
        MAX(CASE WHEN event_name_clean = 'checkout_complete' 
            THEN 1 ELSE 0 END) AS checkout_complete,
        MAX(CASE WHEN event_name_clean = 'payment_success' 
            THEN 1 ELSE 0 END) AS payment_success
    FROM periods_cte
    GROUP BY user_id, period, device, CAST(event_date AS DATE)
),
stats AS (
    SELECT period, device,
        COUNT(CASE WHEN add_to_cart = 1 THEN 1 END)       AS add_to_cart,
        COUNT(CASE WHEN checkout_start = 1 THEN 1 END)    AS checkout_start,
        COUNT(CASE WHEN checkout_complete = 1 THEN 1 END) AS checkout_complete,
        COUNT(CASE WHEN payment_success = 1 THEN 1 END)   AS payment_success
    FROM funnel
    GROUP BY period, device
)
SELECT
    period, device,
    add_to_cart,
    checkout_start,
    ROUND(CAST(checkout_start AS FLOAT)*100/add_to_cart, 1)        AS conv_to_start,
    checkout_complete,
    ROUND(CAST(checkout_complete AS FLOAT)*100/checkout_start, 1)  AS conv_to_complete,
    payment_success,
    ROUND(CAST(payment_success AS FLOAT)*100/checkout_complete, 1) AS conv_to_payment
FROM stats
ORDER BY period, device
-- Result: Android checkout_complete 66.5% ---54.6% (-11.9pp)

-- =============================================
-- 4. D7 RETENTION
-- =============================================

SELECT 
    CASE WHEN after_release = 1 THEN 'After Release'
         ELSE 'Before Release'
    END AS period,
    COUNT(user_id) AS total,
    SUM(CASE WHEN retained_d7 = '1.0' THEN 1 ELSE 0 END) AS retained,
    CAST(SUM(CASE WHEN retained_d7 = '1.0' 
        THEN 1 ELSE 0 END) AS FLOAT) * 100 
    / COUNT(user_id) AS d7_pct
FROM p1_retention_d7_clean
GROUP BY after_release
-- Result: 23.25% --- 19.25% (-4pp)

-- =============================================
-- 5. SHARE OF RETURNS WITHIN 24 HOURS
-- =============================================

WITH periods_cte AS (
    SELECT *,
        CASE 
            WHEN order_date_clean < '2025-06-15' THEN 'Before_release'
            ELSE 'After_release'
        END AS period
    FROM p1_fact_refunds_clean
)
SELECT 
    period,
    COUNT(order_id) AS total_refunds,
    SUM(CASE WHEN hours_to_refund <= 24 THEN 1 ELSE 0 END) AS refunds_24h,
    CAST(SUM(CASE WHEN hours_to_refund <= 24 
        THEN 1 ELSE 0 END) AS FLOAT) * 100
    / COUNT(order_id) AS pct_24h
FROM periods_cte
GROUP BY period
-- Result: 60% stable before and after

-- =============================================
-- 6. COHORT ANALYSIS BY ORDER DATE
-- =============================================

WITH cohorts AS (
    SELECT 
        t2.order_id,
        CASE 
            WHEN t2.order_date_clean >= '2025-06-15' THEN '2025-06 After'
            ELSE FORMAT(t2.order_date_clean, 'yyyy-MM')
        END AS cohort_month,
        t2.status_clean
    FROM p1_dim_user_clean t1
    LEFT JOIN p1_fact_orders_clean t2 ON t1.user_id = t2.user_id
    WHERE t2.status_clean NOT IN ('unknown', 'cancelled')
    AND   t2.order_date_clean IS NOT NULL
)
SELECT 
    cohort_month,
    COUNT(order_id) AS total_orders,
    ROUND(CAST(SUM(CASE WHEN status_clean = 'refunded' 
        THEN 1 ELSE 0 END) AS FLOAT) * 100
    / SUM(CASE WHEN status_clean IN ('refunded','completed') 
        THEN 1 ELSE 0 END), 2) AS RR
FROM cohorts
GROUP BY cohort_month
ORDER BY cohort_month
-- Result: Apr 6.76% | May 6.62% | Jun 6.68% | Jun After 11.96%

-- =============================================
-- 7. ANTI-JOIN DROP-OFF ANALYSIS
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
SELECT COUNT(*) AS dropoff_users
FROM checkout_start_users cs
LEFT JOIN payment_success_users ps ON cs.user_id = ps.user_id
WHERE ps.user_id IS NULL
-- Result: 5,915 users | Before 6.3% --- After 5.9% (stable)
