# Marketplace Returns Analysis

Pet project: investigated a return rate spike after a checkout UI redesign on a mobile marketplace. Full cycle- DQ check, cleaning 1.9M rows across 5 tables, segment analysis, checkout funnel. Root cause identified: Android EU Paid segment. Deliverable: Power BI dashboard with actionable insights for the product team.

**Stack:** T-SQL · SSMS · Power BI
---
## Business Context

In June 2025, the team released a redesign of the checkout cart (new UI). Within a week, the return rate spiked significantly.

**Questions from the product team:**
- Is this a bug, temporary noise, or a pattern?
- Who exactly started returning purchases more often?

---
## Key Findings

- Overall RR grew from 6.68% → 11.95% after the UI update
- Android was hit hardest: +7.7pp (6.7% → 14.4%)
- iOS barely changed: +1.4pp (6.6% → 8.0%) - bug is Android-specific
- Highest impact segment: Android + EU + Paid → RR = 20.33%
- Checkout conversion dropped: 66.5% → 54.6% on Android
- D7 Retention declined: 23.25% → 19.25% (-4pp)
- 60% of returns happen within 24 hours - stable before and after release

**Recommendation:** urgent hotfix for Android UI checkout + A/B test of alternative checkout design

---
## Dataset
Synthetic dataset simulating real marketplace patterns.

| Table | Rows | Description |
|---|---|---|
| p1_dim_user | 80,000 | User profiles |
| p1_fact_orders | 411,600 | Orders |
| p1_fact_refunds | 32,221 | Refunds |
| p1_fact_events | 1,260,760 | User events |
| p1_retention_d7 | 38,148 | D7 retention |

---
## Project Structure
/sql
01_dq_check.sql  - Data Quality Check
02_cleaning.sql  - Data Cleaning
03_analysis.sql  - Analytical Queries
04_marts.sql     - Mart Tables for Power BI
/viz
dashboard.pbix   - Power BI Dashboard

## SQL Analysis

1. **Return Rate before/after release**
    RR grew from 6.68% to 11.95% (+79%)
2. **Segment analysis: Android vs iOS, EU vs US, Paid vs Organic**
    Android +7.7pp, iOS +1.4pp - bug is Android-specific

3. **Checkout funnel: add to cart- checkout- payment -refund**
   checkout_complete dropped from 66.5% to 54.6% on Android

4. **D7 Retention analysis**
   Declined from 23.25% to 19.25% (-4pp)

5. **Share of returns within 24 hours**
   60% stable before and after release

6. **Cohort analysis by order date**
   RR spike confirmed after June 15 across all cohorts

7. **Anti-join drop-off analysis**
   Drop-off rate stable: 6.3% → 5.9%
