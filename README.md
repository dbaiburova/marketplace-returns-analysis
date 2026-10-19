# Marketplace Returns Analysis

Pet project: investigated a return rate spike after a checkout UI redesign on a mobile marketplace. 
Full cycle- DQ check, cleaning 1.9M rows across 5 tables, segment analysis, checkout funnel. 
Root cause identified: Android EU Paid segment.
Deliverable: Power BI dashboard with actionable insights for the product team.

**Stack:** T-SQL · SSMS · Power BI
---
## Business Context

In June 2025, the team released a redesign of the checkout cart (new UI). Within a week, the return rate spiked significantly.

**Questions from the product team:**
-Is this a bug, temporary noise, or a pattern?
- Who exactly started returning purchases more often?
- Which segments were affected the most?
- Did the update affect D7 Retention?

---
## Key Findings
1) **Return Rate before/after release**:
After the UI update on June 15, the return rate almost doubled - from 6.68% to 11.95% (+5.27pp, +79%).
This is not noise, cohort analysis confirms the spike started exactly on June 15.

2) **The interesting part:**
iOS barely changed (6.6% --- 8.0%, +1.4pp), while Android jumped (6.7% ---14.4%, +7.7pp).
This tells us it's an Android-specific bug, not seasonality or assortment changes.

3) **The worst hit segment:**
Android + EU + Paid reached 20.33% RR (+13.6pp) - 3x above normal.
Funnel analysis shows the drop happens at checkout_complete step:
66.5% --- 54.6% (-11.9pp)  on Android. iOS stayed stable: 66.6% --- 66.4%.

4)**D7 Retention analysis**:
Declined from 23.25% --- 19.25% (-4pp).
New users after the update return less.

5) **Share of returns within 24 hours**:
60% of returns stable before and after (60.2% --- 59.8%, -0.4pp).
The speed of returns didn't change, just the volume.

**Recommendation:** urgent hotfix for Android UI checkout + A/B test of alternative checkout design
---

## Dataset
Synthetic dataset simulating real marketplace patterns.
Generated in Python with intentional data quality issues for DQ check practice

| Table | Rows |Clean rows | Description |
| p1_dim_user | 81,600 | 76,084 | User profiles 
| p1_fact_orders | 426,300 | 411,600 | Orders 
| p1_fact_refunds | 33,383 | 32,077 | Refunds 
| p1_fact_events | 1,299,493 | 1,198,280 | User events
| p1_retention_d7 | 39,327 | 38,148 | D7 Retention |

**Total: 1,880,103 raw rows --- 1,756,189 clean rows**

**Data quality issues found**
- Duplicates, NULLs, typos in categorical columns
- Mixed date formats (YYYYMMDD, DD/MM/YYYY)
- Invalid values in numeric columns
- Orphan records in fact_events
    
---
## Project Structure
/sql
01_dq_check.sql - Data Quality Check (5 tables)
02_cleaning.sql - Data Cleaning
03_analysis.sql - 7 Analytical Queries
04_marts.sql - Mart Tables for Power BI
/viz
dashboard.pbix -Interactive Power BI Dashboard

## SQL Analysis / SQL Анализ
7 analytical queries were written to answer 
the business questions.

1. Return Rate before/after UI release
2. Segment analysis: Android vs iOS, EU vs US, Paid vs Organic
3. Checkout funnel by sessions (add_to_cart --- payment_success)
4. D7 Retention - new users before/after update
5. Share of returns within 24 hours
6. Cohort analysis by order date
7. Anti-join drop-off (checkout_start --- no payment)

## Dashboard 

Interactive Power BI dashboard with slicers  by device, region, channel and period.

**Visuals**

- KPI cards: Total Orders, Refunds, Return Rate%, D7 Retention%, Checkout Conversion%
- Line chart: RR by day - spike after June 15 visible
- Bar chart: RR by device - Android vs iOS before/after
- Funnel: Checkout conversion by device 
- D7 Retention: before/after comparison
- Scatter plot: segments by RR before vs after
  
**Tooltips:**
- Drop-off rate: Before 6.3% -- After 5.9% (stable)
- 60% of returns happen within 24h (stable)
