# Marketplace Returns Analysis

Pet project: investigated a return rate spike after a checkout UI redesign on a mobile marketplace.
Full cycle: DQ check → cleaning 1.9M rows across 5 tables → segment analysis → checkout funnel → Power BI dashboard.
Root cause located: the checkout completion step on Android.

**Stack:** T-SQL · SSMS · Power BI (DAX)

---

## Business Context

In June 2025, the team released a redesign of the checkout cart (new UI). Within a week, the return rate spiked.

**Questions from the product team:**
- Is this a bug, temporary noise, or a pattern?
- Who exactly started returning purchases more often?
- Which segments were affected the most?
- Did the update affect D7 Retention?

---

## Key Findings

**1. Return Rate before/after release**
After the UI update on June 15, the return rate almost doubled: **6.69% → 11.97%** (+5.3pp, +79%).
The daily RR line shows the jump exactly on June 15, and it stays elevated afterwards. This is a pattern, not noise.

**2. Android-specific problem**
Android: 6.73% → 14.34% (**+7.6pp**). iOS: 6.61% → 8.10% (+1.5pp).
Android was hit 5x harder than iOS, so this is not seasonality or assortment changes.

**3. Worst segment**
Android + EU + Paid: 6.28% → **19.93%** RR (+13.7pp), 3x above the normal level.

**4. Where users fail: checkout_complete step on Android**

| Step conversion | Android before | Android after | iOS before | iOS after |
|---|---|---|---|---|
| add_to_cart → checkout_start | 73.2% | 73.1% | 73.4% | 73.1% |
| checkout_start → checkout_complete | 66.4% | **54.7%** | 66.5% | 66.2% |
| checkout_complete → payment_success | 90.1% | 89.8% | 89.8% | 90.3% |

Only one step dropped, and only on Android. That is the new cart screen.

**5. Abandoned checkouts grew on Android**
Sessions with checkout_start but no payment: Android **43.7% → 53.8%** (+10.1pp), iOS 43.8% → 43.9% (stable).

**6. D7 Retention declined**
23.07% → 19.08% (−4.0pp).

**7. All user cohorts were affected equally**
RR after release by registration cohort: April 12.05% · May 12.16% · June 1–14 12.01% · after release 11.83%.
New users do not return more than old users. The problem is in the app, not in the traffic quality.

**8. Return speed did not change**
60% of returns happen within 24 hours, before and after (60.4% → 60.3%). The volume of returns grew, not the speed.

---

## Conclusions & Recommendations

| Question | Answer |
|---|---|
| Bug or noise? | Bug. The spike starts exactly on the release date and stays |
| Who is affected? | Android users, worst in EU + Paid. iOS almost unchanged |
| Root cause | checkout_start → checkout_complete on Android dropped by 11.7pp. Users start checkout but cannot finish it |
| New or old users? | All cohorts equally → the app, not the audience |

**Recommendations**
1. Urgent hotfix for the Android checkout screen
2. Prioritise Android + EU + Paid segment
3. A/B test an alternative checkout design
4. Monitor RR, checkout completion and D7 Retention after the fix

---

## Dataset

Synthetic dataset simulating real marketplace patterns.
Generated in Python with intentional data quality issues for DQ practice.

| Table | Raw rows | Clean rows | Description |
|---|---|---|---|
| p1_dim_user | 81,600 | 76,084 | User profiles |
| p1_fact_orders | 426,300 | 387,430 | Orders |
| p1_fact_refunds | 33,383 | 29,403 | Refunds |
| p1_fact_events | 1,299,493 | 1,180,234 | User events |
| p1_retention_d7 | 39,327 | 35,367 | D7 Retention |
| **Total** | **1,880,103** | **1,708,518** | |

### Data quality issues found

| Level | Issue | Example |
|---|---|---|
| Column | Typos and case in categories | `Andr0id`, `USA`, `ref`, `REFUNDED`, `organic ` (trailing space) |
| Column | Mixed date formats | `2025-04-01 06:18:00`, `20250401`, `01/04/2025`, `01-04-2025 06:18:00` |
| Column | Correct format, impossible value | `2025-13-45` (month 13) |
| Column | Invalid numbers | amount ≤ 0 or > 100,000; hours_to_refund < 0; retained_d7 = −1, 2, 99 |
| Table | Duplicates | dim_user, orders (exact copies); refunds, retention (**different values**) |
| Cross-table | Orphans | 12,994 events of users that do not exist |
| Cross-table | Conflicting sources | 3,821 users have a different segment in orders vs dim_user |
| Cross-table | Logical | ~50% of orders and events are dated **before** user registration |

---

## Data Decisions

| Decision | Reason |
|---|---|
| Users with Unknown device / region / channel removed (3,916) | Cannot be assigned to a segment; keeps all marts on the same population |
| Categories and dates cleaned with a whitelist (`ELSE 'Unknown'` / `NULL`) | A new type of dirty value cannot slip into the results |
| dim_user is the single source of truth for segments | Funnel and retention can only use dim_user; one source for all marts. Impact on RR is minimal (Android 14.35% vs 14.38%) |
| Refund duplicates: keep the earliest refund | 516 of 525 duplicates differ in hours_to_refund; a rule is needed |
| Refunds kept only for refunded orders in clean orders | A refund cannot exist without its order |
| Retention: 252 users with both 0 and 1 excluded | The true value is unknown; taking MAX would inflate retention |
| Cohort analysis uses only orders after registration date | ~50% of orders are dated before registration (generator flaw) |
| Rates calculated as SUM / SUM (DAX measures), not stored in marts | An average of percentages gives wrong results |

---

## Limitations

- **Q5 (returns within 24h)** covers 29,403 refunds with a valid hours_to_refund, which is 93% of all refunded orders.
- **D7 Retention:** 10% of users registered after July 24. Events end on July 31, so their 7-day window is incomplete. In a real product they would be excluded as an immature cohort.
- **Before-release retention cohort** is only 2 weeks (June 1–14).
- **Dataset is synthetic.** Dates in orders and events were generated independently from registration dates.

---

## Self-Review: What I Fixed

After finishing the project, I re-ran the whole pipeline from raw data and checked every number. This changed two conclusions and fixed one chart.

| What | Before review | After review |
|---|---|---|
| Drop-off analysis | Anti-join over the whole period: "stable, 6.3% → 5.9%" | By sessions, before/after: **Android 43.7% → 53.8%**. The conclusion flipped and now supports the bug hypothesis |
| Funnel chart | Showed the **average** of daily conversion % → iOS looked like it grew (66.4 → 67.1) | DAX measure SUM / SUM → iOS 66.5 → 66.2, no growth |
| "Cohort" analysis | Grouped by **order** month (repeated Q1) | Grouped by **registration** date → all cohorts ~12% |
| Database state | Tables were built by different script versions (3,916 Unknown users leaked into marts) | Full rebuild in order, checked row counts at every step |
| DQ check | Single-table checks; date formats checked by `LEN()` | Pattern check with `TRANSLATE()`, duplicates in all tables, orphans in both directions, cross-table logical checks |

**Lessons**
- Check date formats by pattern, not by length. Then check that the date is real.
- A child table is cleaned against its parent table (refunds → orders).
- Never average percentages. Store counts, calculate rates as SUM / SUM.
- Single-table checks are not enough. The worst issues appear only when tables are compared.

---

## Project Structure

```
/sql
  01_dq_check.sql   – Data Quality Check (5 tables + cross-table checks)
  02_cleaning.sql   – Data Cleaning
  03_analysis.sql   – Analytical Queries
  04_marts.sql      – Mart Tables for Power BI
/viz
  dashboard.pbix    – Interactive Power BI Dashboard
```

## SQL Analysis

| # | Query | Result |
|---|---|---|
| 1 | Return Rate before/after release | 6.69% → 11.97% |
| 2 | Segment analysis: device, region, channel | Android +7.6pp, EU +6.4pp, Paid +6.3pp |
| 3 | Checkout funnel by sessions | Android checkout_complete 66.4% → 54.7% |
| 4 | D7 Retention before/after | 23.07% → 19.08% |
| 5 | Share of returns within 24 hours | 60.4% → 60.3% |
| 6 | Cohort analysis by registration date | All cohorts ~12% after release |
| 7a | Anti-join: users who never paid (whole period) | 5,667 users |
| 7b | Checkout drop-off by sessions, before/after | Android 43.7% → 53.8% |

## Dashboard

Interactive Power BI dashboard with slicers by device, region, channel and period.

- KPI cards: Total Orders, Refunds, Return Rate %, D7 Retention %, Checkout Conversion %
- Line chart: RR by day, spike after June 15
- Bar chart: RR by device, before/after
- Funnel: step conversion by device, before/after (DAX measure)
- Bar chart: D7 Retention before/after
- Table: segments with the largest RR growth

**Tooltips**
- Checkout drop-off by sessions: Android 43.7% → 53.8%, iOS stable
- 60% of returns happen within 24h (stable)

