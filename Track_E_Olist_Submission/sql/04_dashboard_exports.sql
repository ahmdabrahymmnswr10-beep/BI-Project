/* Track E | Excel data exports | SQL Server T-SQL
   Save result sets as UTF-8 CSV with headers using the query IDs in the file names.
   These exports supply the workbook's selectable period/state KPI table and charts.
   Raw source data stays outside GitHub; dashboard controls filter only the stated grains.
*/
DECLARE @StartDate datetime2(0)='2017-01-01', @EndDate datetime2(0)='2018-09-01';

/* Dashboard_Months: one row per purchase month and seller state.
   Sales are item-attributed. Active sellers count distinct seller IDs in that state. */
SELECT CONVERT(char(7),o.order_purchase_timestamp,126) AS purchase_month,
 s.seller_state,
 SUM(i.price) AS sales_brl,
 COUNT(DISTINCT i.seller_id) AS active_sellers,
 COUNT(DISTINCT o.order_id) AS seller_orders
FROM dbo.order_items i JOIN dbo.orders o ON o.order_id=i.order_id
LEFT JOIN dbo.sellers s ON s.seller_id=i.seller_id
WHERE o.order_status='delivered' AND o.order_purchase_timestamp>=@StartDate AND o.order_purchase_timestamp<@EndDate
GROUP BY CONVERT(char(7),o.order_purchase_timestamp,126),s.seller_state
ORDER BY purchase_month,seller_state;

/* Dashboard_Period: one row per seller and period. Shared orders intentionally recur
   once for each seller. Derived items are grouped before order outcomes are joined. */
WITH Periods AS (
 SELECT v.period_label,CONVERT(datetime2(0),v.start_date) AS start_date,CONVERT(datetime2(0),v.end_date) AS end_date
 FROM (VALUES ('All scope','2017-01-01','2018-09-01'),('Jan-Jun 2017','2017-01-01','2017-07-01'),('Jan-Jun 2018','2018-01-01','2018-07-01')) v(period_label,start_date,end_date)
), OneReview AS (
 SELECT order_id,review_score,ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY
  CASE WHEN review_answer_timestamp IS NULL THEN 1 ELSE 0 END,review_answer_timestamp DESC,review_creation_date DESC,review_id DESC) AS rn
 FROM dbo.order_reviews WHERE review_score BETWEEN 1 AND 5
), SellerOrder AS (
 SELECT x.seller_id,x.order_id,x.sales_brl,x.freight_brl,s.seller_state,
 o.order_purchase_timestamp,o.order_delivered_customer_date,o.order_estimated_delivery_date,r.review_score
 FROM (
  SELECT i.seller_id,i.order_id,SUM(i.price) AS sales_brl,SUM(i.freight_value) AS freight_brl
  FROM dbo.order_items i JOIN dbo.orders oi ON oi.order_id=i.order_id
  WHERE oi.order_status='delivered' AND oi.order_purchase_timestamp>=@StartDate AND oi.order_purchase_timestamp<@EndDate
  GROUP BY i.seller_id,i.order_id
 ) x JOIN dbo.orders o ON o.order_id=x.order_id
 JOIN dbo.sellers s ON s.seller_id=x.seller_id
 LEFT JOIN OneReview r ON r.order_id=o.order_id AND r.rn=1
)
SELECT p.period_label AS period,so.seller_state,so.seller_id,
 COUNT(DISTINCT so.order_id) AS eligible_orders,SUM(so.sales_brl) AS sales_brl,SUM(so.freight_brl) AS freight_brl,
 SUM(CASE WHEN so.order_delivered_customer_date IS NOT NULL AND so.order_estimated_delivery_date IS NOT NULL
  AND CONVERT(date,so.order_delivered_customer_date)>CONVERT(date,so.order_estimated_delivery_date) THEN 1 ELSE 0 END) AS late_orders,
 SUM(CASE WHEN so.order_delivered_customer_date IS NOT NULL AND so.order_estimated_delivery_date IS NOT NULL THEN 1 ELSE 0 END) AS valid_delivery_date_orders,
 SUM(CASE WHEN so.review_score BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS valid_review_orders,
 SUM(CASE WHEN so.review_score IN (1,2) THEN 1 ELSE 0 END) AS low_rating_orders,
 SUM(CASE WHEN so.order_delivered_customer_date IS NOT NULL AND so.order_estimated_delivery_date IS NOT NULL
  AND CONVERT(date,so.order_delivered_customer_date)>CONVERT(date,so.order_estimated_delivery_date) THEN 1 ELSE 0 END)
  /NULLIF(CAST(SUM(CASE WHEN so.order_delivered_customer_date IS NOT NULL AND so.order_estimated_delivery_date IS NOT NULL THEN 1 ELSE 0 END) AS decimal(18,6)),0) AS late_delivery_rate,
 SUM(so.freight_brl)/NULLIF(SUM(so.sales_brl),0) AS freight_to_sales_ratio,
 SUM(CASE WHEN so.review_score BETWEEN 1 AND 5 THEN 1 ELSE 0 END)
  /NULLIF(CAST(COUNT(DISTINCT so.order_id) AS decimal(18,6)),0) AS review_coverage,
 SUM(CASE WHEN so.review_score IN (1,2) THEN 1 ELSE 0 END)
  /NULLIF(CAST(SUM(CASE WHEN so.review_score BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS decimal(18,6)),0) AS low_rating_rate
FROM Periods p JOIN SellerOrder so ON so.order_purchase_timestamp>=p.start_date AND so.order_purchase_timestamp<p.end_date
GROUP BY p.period_label,so.seller_state,so.seller_id
ORDER BY p.period_label,so.seller_state,so.seller_id;

/* E1 Seller ranking and E5 segment summary charts use the final result sets in
   sql/03_analysis.sql. E7 is also the dedicated seller-level scorecard export there.
   Export those question outputs unchanged so the workbook remains traceable to IDs.
   G1-G3, E2-E6, O1-O2 evidence is exported from the corresponding labelled SELECTs
   in sql/03_analysis.sql. Keep all numerator/count columns for Excel recalculation.
*/
