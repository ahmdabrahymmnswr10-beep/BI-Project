/* Track E | Data checks. Run after CSV import; retain outputs in the report appendix. */
SELECT 'customers' AS table_name, COUNT_BIG(*) AS source_rows FROM dbo.customers UNION ALL
SELECT 'orders', COUNT_BIG(*) FROM dbo.orders UNION ALL
SELECT 'order_items', COUNT_BIG(*) FROM dbo.order_items UNION ALL
SELECT 'order_payments', COUNT_BIG(*) FROM dbo.order_payments UNION ALL
SELECT 'order_reviews', COUNT_BIG(*) FROM dbo.order_reviews UNION ALL
SELECT 'sellers', COUNT_BIG(*) FROM dbo.sellers UNION ALL
SELECT 'products', COUNT_BIG(*) FROM dbo.products UNION ALL
SELECT 'category_translation', COUNT_BIG(*) FROM dbo.category_translation;

-- Candidate-key duplicates; an empty result means no duplicate key groups.
SELECT customer_id, COUNT_BIG(*) AS n FROM dbo.customers GROUP BY customer_id HAVING COUNT_BIG(*) > 1;
SELECT order_id, COUNT_BIG(*) AS n FROM dbo.orders GROUP BY order_id HAVING COUNT_BIG(*) > 1;
SELECT order_id, order_item_id, COUNT_BIG(*) AS n FROM dbo.order_items GROUP BY order_id, order_item_id HAVING COUNT_BIG(*) > 1;
SELECT order_id, payment_sequential, COUNT_BIG(*) AS n FROM dbo.order_payments GROUP BY order_id, payment_sequential HAVING COUNT_BIG(*) > 1;
SELECT seller_id, COUNT_BIG(*) AS n FROM dbo.sellers GROUP BY seller_id HAVING COUNT_BIG(*) > 1;
SELECT product_id, COUNT_BIG(*) AS n FROM dbo.products GROUP BY product_id HAVING COUNT_BIG(*) > 1;
SELECT product_category_name, COUNT_BIG(*) AS n FROM dbo.category_translation GROUP BY product_category_name HAVING COUNT_BIG(*) > 1;
-- Multiple reviews per order are expected; report the number of affected orders.
SELECT COUNT_BIG(*) AS orders_with_multiple_reviews FROM
 (SELECT order_id FROM dbo.order_reviews GROUP BY order_id HAVING COUNT_BIG(*) > 1) d;

-- Null, invalid score, impossible value and date profiles.
SELECT COUNT_BIG(*) AS missing_customer_state FROM dbo.customers WHERE customer_state IS NULL;
SELECT COUNT_BIG(*) AS invalid_review_scores FROM dbo.order_reviews WHERE review_score NOT BETWEEN 1 AND 5 OR review_score IS NULL;
SELECT COUNT_BIG(*) AS negative_price_rows FROM dbo.order_items WHERE price < 0;
SELECT COUNT_BIG(*) AS negative_freight_rows FROM dbo.order_items WHERE freight_value < 0;
SELECT MIN(order_purchase_timestamp) AS first_purchase, MAX(order_purchase_timestamp) AS last_purchase FROM dbo.orders;

-- Unmatched foreign-key checks before analytical joins.
SELECT COUNT_BIG(*) AS orders_without_customer FROM dbo.orders o LEFT JOIN dbo.customers c ON c.customer_id=o.customer_id WHERE c.customer_id IS NULL;
SELECT COUNT_BIG(*) AS items_without_order FROM dbo.order_items i LEFT JOIN dbo.orders o ON o.order_id=i.order_id WHERE o.order_id IS NULL;
SELECT COUNT_BIG(*) AS items_without_seller FROM dbo.order_items i LEFT JOIN dbo.sellers s ON s.seller_id=i.seller_id WHERE s.seller_id IS NULL;
SELECT COUNT_BIG(*) AS items_without_product FROM dbo.order_items i LEFT JOIN dbo.products p ON p.product_id=i.product_id WHERE p.product_id IS NULL;
SELECT COUNT_BIG(*) AS reviews_without_order FROM dbo.order_reviews r LEFT JOIN dbo.orders o ON o.order_id=r.order_id WHERE o.order_id IS NULL;
SELECT COUNT_BIG(*) AS payments_without_order FROM dbo.order_payments p LEFT JOIN dbo.orders o ON o.order_id=p.order_id WHERE o.order_id IS NULL;
