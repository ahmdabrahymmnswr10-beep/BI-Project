# Research Question Answers

Scope: purchases from 2017-01-01 inclusive through 2018-08-31. Merchandise sales are item prices in BRL and exclude freight. Seller-level order and service counts overlap when an order has multiple sellers. Supporting result files are under `results/`.

## Common questions

- **G1 — Order status and delivered sales:** 96,211 of 99,092 scoped orders are delivered (97.1%). The delivered population has 93,104 distinct customers, R$13,181,027.13 in merchandise sales and R$137.00 average order value. Status percentages use all scoped orders as the denominator. See `G1_order_status.csv` and `G1_delivered_summary.csv`.
- **G2 — Monthly sales:** November 2017 is the peak month at R$987,765.37 across 7,289 delivered orders. February 2017 has the largest month-over-month growth (109.5%), from a low January baseline. All 20 months are included; growth is NULL when the prior month has no positive baseline. See `G2_monthly_sales.csv`.
- **G3 — Review and payment coverage:** valid review coverage is 99.33%; payment-record coverage is 100.0%. There are no delivered orders missing a payment record in the scoped period. Review and payment coverage are separate measures. See `G3_monthly_coverage.csv` and the two missing-match samples.

## Track E questions

- **E1 — Seller sales contribution:** the top seller has R$226,987.93 in merchandise sales (1.72% of total); the top ten contribute 13.30%. See `E1_seller_ranking.csv`.
- **E2 — Monthly seller results:** seller-month exports retain all 3,095 listed sellers across the 20-month sequence, including zero-activity months. November 2017 is the highest-sales month. Prior-month sales, monthly rank and NULL-safe growth are in `E2_seller_month.csv`.
- **E3 — Seller versus state peers:** seller sales are compared with the mean for active sellers in the same seller state. Seven states have fewer than five active sellers and are flagged as limited comparisons. See `E3_state_peer_comparison.csv`.
- **E4 — Customer-market exposure:** the five highest-sales customer states are SP, RJ, MG, RS and PR. SP contributes R$5,055,587.13 in merchandise sales. Seller exposure shares are in `E4_top_customer_markets.csv`.
- **E5 — Sellers with low-rated orders:** 1,676 sellers have at least one low-rated order, 1,265 have valid reviews but no low-rated order, and 4 have no valid reviews. Non-reviewers are kept separate from sellers with positive ratings. See `E5_review_segments.csv` and `E5_seller_review_detail.csv`.
- **E6 — Seller activity in two periods:** 499 sellers are active in both January–June periods, 421 only in 2017, and 1,473 only in 2018. Another 702 listed sellers have no recorded sales in either comparison period. See `E6_period_activity.csv`.
- **E7 — Seller service scorecard:** 625 sellers meet the minimum of 30 eligible seller-orders. In that qualifying cohort, the weighted late rate is 6.7%, low-rating rate is 13.4%, and valid-review coverage is 99.3%. Seller-level counts and denominators are in `E7_seller_scorecard.csv`.

## Additional questions

- **O1 — Seller category breadth:** sellers average 2.16 categories; the median seller has 100% of sales in its leading category. Median sales range from R$397.00 in the narrowest breadth quartile to R$3,658.30 in the broadest. This association does not establish that category breadth causes sales differences. See `O1_seller_portfolio.csv`.
- **O2 — Customer concentration:** the median seller gets 87.9% of sales from its five largest unique customers. Read this with each seller's distinct customer count, since small sellers naturally have concentrated sales. See `O2_customer_concentration.csv`.
