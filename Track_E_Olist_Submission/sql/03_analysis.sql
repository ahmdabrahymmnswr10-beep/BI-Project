/* Track E | Analysis SQL | SQL Server T-SQL
   Common scope: purchase timestamp >= 2017-01-01 and < 2018-09-01.
   Money is BRL. Merchandise sales = SUM(item price), excluding freight.
   Seller outcomes use seller-order grain; shared orders are attributed to each seller.
*/
DECLARE @StartDate datetime2(0) = '2017-01-01';
DECLARE @EndDate   datetime2(0) = '2018-09-01';

/* G1 | Order statuses and delivered summary; percentage denominator is all scoped orders. */
WITH ScopedOrders AS (
 SELECT order_id, customer_id, order_status FROM dbo.orders
 WHERE order_purchase_timestamp >= @StartDate AND order_purchase_timestamp < @EndDate
), StatusCounts AS (
 SELECT order_status, COUNT(DISTINCT order_id) AS order_count FROM ScopedOrders GROUP BY order_status
)
SELECT order_status, order_count,
 CAST(order_count AS decimal(18,6)) / NULLIF((SELECT COUNT(DISTINCT order_id) FROM ScopedOrders),0) AS order_share
FROM StatusCounts ORDER BY order_count DESC;
WITH Delivered AS (
 SELECT order_id, customer_id FROM dbo.orders WHERE order_status='delivered'
 AND order_purchase_timestamp >= @StartDate AND order_purchase_timestamp < @EndDate
), ItemOrder AS (
 SELECT d.order_id, d.customer_id, SUM(i.price) AS merchandise_sales_brl
 FROM Delivered d LEFT JOIN dbo.order_items i ON i.order_id=d.order_id GROUP BY d.order_id,d.customer_id
)
SELECT COUNT(DISTINCT io.order_id) AS delivered_orders,
 COUNT(DISTINCT c.customer_unique_id) AS distinct_customers,
 SUM(io.merchandise_sales_brl) AS merchandise_sales_brl,
 SUM(io.merchandise_sales_brl)/NULLIF(COUNT(DISTINCT io.order_id),0) AS average_order_value_brl
FROM ItemOrder io LEFT JOIN dbo.customers c ON c.customer_id=io.customer_id;

/* G2 | Complete month sequence, CTE stages, LAG and aggregate window. */
WITH MonthList AS (
 SELECT CONVERT(date,v.month_start) AS month_start FROM (VALUES
 ('2017-01-01'),('2017-02-01'),('2017-03-01'),('2017-04-01'),('2017-05-01'),('2017-06-01'),
 ('2017-07-01'),('2017-08-01'),('2017-09-01'),('2017-10-01'),('2017-11-01'),('2017-12-01'),
 ('2018-01-01'),('2018-02-01'),('2018-03-01'),('2018-04-01'),('2018-05-01'),('2018-06-01'),
 ('2018-07-01'),('2018-08-01')) v(month_start)
), MonthlySales AS (
 SELECT DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1) AS month_start,
 SUM(i.price) AS merchandise_sales_brl
 FROM dbo.orders o JOIN dbo.order_items i ON i.order_id=o.order_id
 WHERE o.order_status='delivered' AND o.order_purchase_timestamp >= @StartDate AND o.order_purchase_timestamp < @EndDate
 GROUP BY DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1)
), MonthlyOrders AS (
 SELECT DATEFROMPARTS(YEAR(order_purchase_timestamp),MONTH(order_purchase_timestamp),1) AS month_start,
 COUNT(DISTINCT order_id) AS delivered_orders
 FROM dbo.orders WHERE order_status='delivered' AND order_purchase_timestamp >= @StartDate AND order_purchase_timestamp < @EndDate
 GROUP BY DATEFROMPARTS(YEAR(order_purchase_timestamp),MONTH(order_purchase_timestamp),1)
), Monthly AS (
 SELECT COALESCE(s.month_start,o.month_start) AS month_start,s.merchandise_sales_brl,o.delivered_orders
 FROM MonthlySales s FULL OUTER JOIN MonthlyOrders o ON o.month_start=s.month_start
), CompleteMonths AS (
 SELECT m.month_start, COALESCE(x.merchandise_sales_brl,0) AS merchandise_sales_brl,
 COALESCE(x.delivered_orders,0) AS delivered_orders FROM MonthList m LEFT JOIN Monthly x ON x.month_start=m.month_start
), Trends AS (
 SELECT *, LAG(merchandise_sales_brl) OVER(ORDER BY month_start) AS previous_sales_brl,
 SUM(merchandise_sales_brl) OVER(ORDER BY month_start ROWS UNBOUNDED PRECEDING) AS running_sales_brl
 FROM CompleteMonths
)
SELECT month_start, merchandise_sales_brl, delivered_orders,
 merchandise_sales_brl/NULLIF(delivered_orders,0) AS average_order_value_brl,
 (merchandise_sales_brl-previous_sales_brl)/NULLIF(previous_sales_brl,0) AS sales_growth,
 running_sales_brl FROM Trends ORDER BY month_start;

/* G3 | Independent coverage measures; one review per order and payment table pre-aggregated. */
WITH Delivered AS (
 SELECT order_id, DATEFROMPARTS(YEAR(order_purchase_timestamp),MONTH(order_purchase_timestamp),1) AS month_start
 FROM dbo.orders WHERE order_status='delivered' AND order_purchase_timestamp >= @StartDate AND order_purchase_timestamp < @EndDate
), ReviewRank AS (
 SELECT order_id, review_score, ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY
  CASE WHEN review_answer_timestamp IS NULL THEN 1 ELSE 0 END,
  review_answer_timestamp DESC, review_creation_date DESC, review_id DESC) AS rn
 FROM dbo.order_reviews WHERE review_score BETWEEN 1 AND 5
), PaymentByOrder AS (
 SELECT order_id, COUNT_BIG(*) AS payment_rows FROM dbo.order_payments GROUP BY order_id
)
SELECT d.month_start, COUNT(DISTINCT d.order_id) AS delivered_orders,
 SUM(CASE WHEN EXISTS (SELECT 1 FROM ReviewRank r WHERE r.order_id=d.order_id AND r.rn=1) THEN 1 ELSE 0 END) AS reviewed_orders,
 SUM(CASE WHEN NOT EXISTS (SELECT 1 FROM ReviewRank r WHERE r.order_id=d.order_id AND r.rn=1) THEN 1 ELSE 0 END) AS missing_review_orders,
 SUM(CASE WHEN p.payment_rows IS NOT NULL THEN 1 ELSE 0 END) AS paid_orders,
 SUM(CASE WHEN p.payment_rows IS NULL THEN 1 ELSE 0 END) AS missing_payment_orders
FROM Delivered d LEFT JOIN PaymentByOrder p ON p.order_id=d.order_id
GROUP BY d.month_start ORDER BY d.month_start;

/* E1 | Seller ranking by merchandise sales, items and attributed delivered orders. */
WITH SellerSales AS (
 SELECT i.seller_id, s.seller_state, SUM(i.price) AS sales_brl, COUNT_BIG(*) AS item_count,
 COUNT(DISTINCT o.order_id) AS delivered_orders
 FROM dbo.order_items i JOIN dbo.orders o ON o.order_id=i.order_id
 LEFT JOIN dbo.sellers s ON s.seller_id=i.seller_id
 WHERE o.order_status='delivered' AND o.order_purchase_timestamp >= @StartDate AND o.order_purchase_timestamp < @EndDate
 GROUP BY i.seller_id,s.seller_state
)
SELECT *, RANK() OVER(ORDER BY sales_brl DESC) AS sales_rank,
 sales_brl/NULLIF((SELECT SUM(sales_brl) FROM SellerSales),0) AS marketplace_sales_share
FROM SellerSales ORDER BY sales_rank,seller_id;

/* E2 | Seller x complete month sequence, including zero-activity months. */
WITH MonthList AS (
 SELECT CONVERT(date,v.month_start) AS month_start FROM (VALUES
 ('2017-01-01'),('2017-02-01'),('2017-03-01'),('2017-04-01'),('2017-05-01'),('2017-06-01'),('2017-07-01'),('2017-08-01'),('2017-09-01'),('2017-10-01'),('2017-11-01'),('2017-12-01'),
 ('2018-01-01'),('2018-02-01'),('2018-03-01'),('2018-04-01'),('2018-05-01'),('2018-06-01'),('2018-07-01'),('2018-08-01')) v(month_start)
), SellerMonth AS (
 SELECT i.seller_id, DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1) AS month_start,
 SUM(i.price) AS sales_brl, COUNT(DISTINCT o.order_id) AS delivered_orders
 FROM dbo.order_items i JOIN dbo.orders o ON o.order_id=i.order_id
 WHERE o.order_status='delivered' AND o.order_purchase_timestamp >= @StartDate AND o.order_purchase_timestamp < @EndDate
 GROUP BY i.seller_id,DATEFROMPARTS(YEAR(o.order_purchase_timestamp),MONTH(o.order_purchase_timestamp),1)
), Grid AS (
 SELECT s.seller_id,s.seller_state,m.month_start,COALESCE(x.sales_brl,0) AS sales_brl,COALESCE(x.delivered_orders,0) AS delivered_orders
 FROM dbo.sellers s CROSS JOIN MonthList m LEFT JOIN SellerMonth x ON x.seller_id=s.seller_id AND x.month_start=m.month_start
), Trends AS (
 SELECT *, LAG(sales_brl) OVER(PARTITION BY seller_id ORDER BY month_start) AS previous_month_sales_brl,
 CASE WHEN sales_brl=0 THEN NULL ELSE RANK() OVER(PARTITION BY month_start ORDER BY sales_brl DESC) END AS monthly_rank FROM Grid
)
SELECT *, (sales_brl-previous_month_sales_brl)/NULLIF(previous_month_sales_brl,0) AS sales_growth
FROM Trends ORDER BY seller_id,month_start;

/* E3 | Correlated peer mean among active sellers in each seller state. */
WITH SellerSales AS (
 SELECT i.seller_id,s.seller_state,SUM(i.price) AS sales_brl
 FROM dbo.order_items i JOIN dbo.orders o ON o.order_id=i.order_id
 LEFT JOIN dbo.sellers s ON s.seller_id=i.seller_id
 WHERE o.order_status='delivered' AND o.order_purchase_timestamp >= @StartDate AND o.order_purchase_timestamp < @EndDate
 GROUP BY i.seller_id,s.seller_state
)
SELECT a.seller_id,a.seller_state,a.sales_brl,
 (SELECT COUNT_BIG(*) FROM SellerSales b WHERE b.seller_state=a.seller_state) AS peer_seller_count,
 (SELECT AVG(b.sales_brl) FROM SellerSales b WHERE b.seller_state=a.seller_state) AS peer_mean_sales_brl,
 a.sales_brl-(SELECT AVG(b.sales_brl) FROM SellerSales b WHERE b.seller_state=a.seller_state) AS difference_brl,
 CASE WHEN (SELECT COUNT_BIG(*) FROM SellerSales b WHERE b.seller_state=a.seller_state)<5 THEN 'Limited comparison' ELSE 'Peer group >= 5' END AS comparison_flag
FROM SellerSales a ORDER BY a.seller_state,a.sales_brl DESC;

/* E4 | Sales share in the five highest-sales customer states (multi-row IN subquery). */
WITH SellerStateSales AS (
 SELECT i.seller_id,s.seller_state,c.customer_state,SUM(i.price) AS sales_brl
 FROM dbo.order_items i JOIN dbo.orders o ON o.order_id=i.order_id
 JOIN dbo.customers c ON c.customer_id=o.customer_id LEFT JOIN dbo.sellers s ON s.seller_id=i.seller_id
 WHERE o.order_status='delivered' AND o.order_purchase_timestamp >= @StartDate AND o.order_purchase_timestamp < @EndDate
 GROUP BY i.seller_id,s.seller_state,c.customer_state
)
SELECT seller_id,seller_state,SUM(sales_brl) AS total_sales_brl,
 SUM(CASE WHEN customer_state IN (SELECT TOP (5) customer_state FROM SellerStateSales GROUP BY customer_state ORDER BY SUM(sales_brl) DESC) THEN sales_brl ELSE 0 END) AS selected_state_sales_brl,
 SUM(CASE WHEN customer_state IN (SELECT TOP (5) customer_state FROM SellerStateSales GROUP BY customer_state ORDER BY SUM(sales_brl) DESC) THEN sales_brl ELSE 0 END)/NULLIF(SUM(sales_brl),0) AS selected_state_share
FROM SellerStateSales GROUP BY seller_id,seller_state ORDER BY selected_state_share DESC;

/* E5 | Review segments use order-level review as an associated seller signal, not seller causality. */
WITH ReviewRank AS (
 SELECT order_id,review_score,ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY
  CASE WHEN review_answer_timestamp IS NULL THEN 1 ELSE 0 END,review_answer_timestamp DESC,review_creation_date DESC,review_id DESC) AS rn
 FROM dbo.order_reviews WHERE review_score BETWEEN 1 AND 5
), SellerOrders AS (
 SELECT DISTINCT i.seller_id,o.order_id FROM dbo.order_items i JOIN dbo.orders o ON o.order_id=i.order_id
 WHERE o.order_status='delivered' AND o.order_purchase_timestamp >= @StartDate AND o.order_purchase_timestamp < @EndDate
), EligibleSellers AS (SELECT DISTINCT seller_id FROM SellerOrders)
SELECT s.seller_id,
 CASE WHEN EXISTS (SELECT 1 FROM SellerOrders so JOIN ReviewRank r ON r.order_id=so.order_id AND r.rn=1 WHERE so.seller_id=s.seller_id AND r.review_score<=2)
      THEN 'At least one low-rated order'
      WHEN EXISTS (SELECT 1 FROM SellerOrders so JOIN ReviewRank r ON r.order_id=so.order_id AND r.rn=1 WHERE so.seller_id=s.seller_id)
      THEN 'Rated orders; no low rating' ELSE 'No valid reviews' END AS review_segment,
 COUNT(DISTINCT so.order_id) AS eligible_orders,
 COUNT(DISTINCT CASE WHEN r.rn=1 THEN so.order_id END) AS valid_review_orders,
 COUNT(DISTINCT CASE WHEN r.rn=1 AND r.review_score<=2 THEN so.order_id END) AS low_rating_orders
FROM EligibleSellers s JOIN SellerOrders so ON so.seller_id=s.seller_id
LEFT JOIN ReviewRank r ON r.order_id=so.order_id AND r.rn=1
GROUP BY s.seller_id ORDER BY s.seller_id;

/* E6 | Two-sided period comparison. */
WITH PeriodSales AS (
 SELECT i.seller_id,
 SUM(CASE WHEN o.order_purchase_timestamp>='2017-01-01' AND o.order_purchase_timestamp<'2017-07-01' THEN i.price ELSE 0 END) AS sales_2017_h1,
 SUM(CASE WHEN o.order_purchase_timestamp>='2018-01-01' AND o.order_purchase_timestamp<'2018-07-01' THEN i.price ELSE 0 END) AS sales_2018_h1
 FROM dbo.order_items i JOIN dbo.orders o ON o.order_id=i.order_id
 WHERE o.order_status='delivered' AND ((o.order_purchase_timestamp>='2017-01-01' AND o.order_purchase_timestamp<'2017-07-01') OR (o.order_purchase_timestamp>='2018-01-01' AND o.order_purchase_timestamp<'2018-07-01'))
 GROUP BY i.seller_id
)
SELECT s.seller_id,s.seller_state,COALESCE(p.sales_2017_h1,0) AS sales_2017_h1,COALESCE(p.sales_2018_h1,0) AS sales_2018_h1,
 CASE WHEN COALESCE(p.sales_2017_h1,0)>0 AND COALESCE(p.sales_2018_h1,0)>0 THEN 'Active in both'
      WHEN COALESCE(p.sales_2017_h1,0)>0 THEN '2017 only'
      WHEN COALESCE(p.sales_2018_h1,0)>0 THEN '2018 only' ELSE 'No activity in either period' END AS activity_group
FROM dbo.sellers s LEFT JOIN PeriodSales p ON p.seller_id=s.seller_id;

/* E7 | Seller scorecard. Item amounts aggregate to seller-order before review/date outcomes. */
WITH OneReview AS (
 SELECT order_id,review_score,ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY
  CASE WHEN review_answer_timestamp IS NULL THEN 1 ELSE 0 END,review_answer_timestamp DESC,review_creation_date DESC,review_id DESC) AS rn
 FROM dbo.order_reviews WHERE review_score BETWEEN 1 AND 5
), SellerOrderSignals AS (
 SELECT SellerOrderItems.seller_id,SellerOrderItems.order_id,SellerOrderItems.sales_brl,SellerOrderItems.freight_brl,s.seller_state,c.customer_state,
 o.order_delivered_customer_date,o.order_estimated_delivery_date,r.review_score
 FROM (
  -- Derived table grain: one row per seller-order, preventing item rows from multiplying outcome rows.
  SELECT i.seller_id,i.order_id,SUM(i.price) AS sales_brl,SUM(i.freight_value) AS freight_brl
  FROM dbo.order_items i JOIN dbo.orders oi ON oi.order_id=i.order_id
  WHERE oi.order_status='delivered' AND oi.order_purchase_timestamp>=@StartDate AND oi.order_purchase_timestamp<@EndDate
  GROUP BY i.seller_id,i.order_id
 ) AS SellerOrderItems JOIN dbo.orders o ON o.order_id=SellerOrderItems.order_id
 JOIN dbo.sellers s ON s.seller_id=SellerOrderItems.seller_id JOIN dbo.customers c ON c.customer_id=o.customer_id
 LEFT JOIN OneReview r ON r.order_id=o.order_id AND r.rn=1
), SellerScorecard AS (
 SELECT seller_id,seller_state,COUNT(DISTINCT order_id) AS eligible_orders,SUM(sales_brl) AS sales_brl,SUM(freight_brl) AS freight_brl,
 SUM(CASE WHEN order_delivered_customer_date IS NOT NULL AND order_estimated_delivery_date IS NOT NULL AND CONVERT(date,order_delivered_customer_date)>CONVERT(date,order_estimated_delivery_date) THEN 1 ELSE 0 END) AS late_orders,
 SUM(CASE WHEN order_delivered_customer_date IS NOT NULL AND order_estimated_delivery_date IS NOT NULL THEN 1 ELSE 0 END) AS valid_delivery_date_orders,
 SUM(CASE WHEN review_score BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS valid_review_orders,
 SUM(CASE WHEN review_score IN (1,2) THEN 1 ELSE 0 END) AS low_rating_orders
 FROM SellerOrderSignals GROUP BY seller_id,seller_state
)
SELECT *,late_orders/NULLIF(CAST(valid_delivery_date_orders AS decimal(18,6)),0) AS late_delivery_rate,
 freight_brl/NULLIF(sales_brl,0) AS freight_to_sales_ratio,
 valid_review_orders/NULLIF(CAST(eligible_orders AS decimal(18,6)),0) AS review_coverage,
 low_rating_orders/NULLIF(CAST(valid_review_orders AS decimal(18,6)),0) AS low_rating_rate
FROM SellerScorecard WHERE eligible_orders>=30 ORDER BY low_rating_rate DESC,late_delivery_rate DESC;

/* O1 | Seller category breadth and top-category concentration. */
WITH SellerCategory AS (
 SELECT i.seller_id,COALESCE(t.product_category_name_english,p.product_category_name,'Unknown / untranslated') AS category,
 SUM(i.price) AS category_sales_brl
 FROM dbo.order_items i JOIN dbo.orders o ON o.order_id=i.order_id
 LEFT JOIN dbo.products p ON p.product_id=i.product_id LEFT JOIN dbo.category_translation t ON t.product_category_name=p.product_category_name
 WHERE o.order_status='delivered' AND o.order_purchase_timestamp>=@StartDate AND o.order_purchase_timestamp<@EndDate
 GROUP BY i.seller_id,COALESCE(t.product_category_name_english,p.product_category_name,'Unknown / untranslated')
), Ranked AS (
 SELECT *,ROW_NUMBER() OVER(PARTITION BY seller_id ORDER BY category_sales_brl DESC,category) AS category_rank,
 SUM(category_sales_brl) OVER(PARTITION BY seller_id) AS total_sales_brl,
 COUNT(*) OVER(PARTITION BY seller_id) AS category_count
 FROM SellerCategory
), SellerSummary AS (
 SELECT seller_id,MAX(category_count) AS category_count,MAX(total_sales_brl) AS total_sales_brl,
 MAX(CASE WHEN category_rank=1 THEN category END) AS top_category,
 MAX(CASE WHEN category_rank=1 THEN category_sales_brl END)/NULLIF(MAX(total_sales_brl),0) AS top_category_share
 FROM Ranked GROUP BY seller_id
), Breadth AS (
 SELECT *,NTILE(4) OVER(ORDER BY category_count,seller_id) AS breadth_quartile FROM SellerSummary
)
SELECT b.seller_id,s.seller_state,b.category_count,b.total_sales_brl,b.top_category,b.top_category_share,b.breadth_quartile
FROM Breadth b LEFT JOIN dbo.sellers s ON s.seller_id=b.seller_id;

/* O2 | Sales concentration among each seller's five largest unique customers. */
WITH SellerCustomer AS (
 SELECT i.seller_id,c.customer_unique_id,SUM(i.price) AS customer_sales_brl
 FROM dbo.order_items i JOIN dbo.orders o ON o.order_id=i.order_id JOIN dbo.customers c ON c.customer_id=o.customer_id
 WHERE o.order_status='delivered' AND o.order_purchase_timestamp>=@StartDate AND o.order_purchase_timestamp<@EndDate
 GROUP BY i.seller_id,c.customer_unique_id
), Ranked AS (
 SELECT *,ROW_NUMBER() OVER(PARTITION BY seller_id ORDER BY customer_sales_brl DESC,customer_unique_id) AS customer_rank,
 SUM(customer_sales_brl) OVER(PARTITION BY seller_id) AS total_sales_brl,
 COUNT(*) OVER(PARTITION BY seller_id) AS distinct_customers
 FROM SellerCustomer
)
SELECT r.seller_id,s.seller_state,MAX(r.total_sales_brl) AS total_sales_brl,MAX(r.distinct_customers) AS distinct_customers,
 SUM(CASE WHEN r.customer_rank<=5 THEN r.customer_sales_brl ELSE 0 END) AS top_five_customer_sales_brl,
 SUM(CASE WHEN r.customer_rank<=5 THEN r.customer_sales_brl ELSE 0 END)/NULLIF(MAX(r.total_sales_brl),0) AS top_five_customer_share
FROM Ranked r LEFT JOIN dbo.sellers s ON s.seller_id=r.seller_id GROUP BY r.seller_id,s.seller_state;
