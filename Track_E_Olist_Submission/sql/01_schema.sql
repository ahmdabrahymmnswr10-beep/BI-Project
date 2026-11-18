/* Track E | SQL Server staging schema
   Import each CSV as UTF-8 with header row. Keep raw source rows unchanged.
   Declare constraints only after 02_validation.sql confirms candidate keys. */
IF OBJECT_ID('dbo.customers','U') IS NULL CREATE TABLE dbo.customers (
 customer_id varchar(32) NOT NULL, customer_unique_id varchar(32) NULL,
 customer_zip_code_prefix varchar(8) NULL, customer_city nvarchar(100) NULL, customer_state char(2) NULL);
IF OBJECT_ID('dbo.orders','U') IS NULL CREATE TABLE dbo.orders (
 order_id varchar(32) NOT NULL, customer_id varchar(32) NULL, order_status varchar(24) NULL,
 order_purchase_timestamp datetime2(0) NULL, order_approved_at datetime2(0) NULL,
 order_delivered_carrier_date datetime2(0) NULL, order_delivered_customer_date datetime2(0) NULL,
 order_estimated_delivery_date datetime2(0) NULL);
IF OBJECT_ID('dbo.order_items','U') IS NULL CREATE TABLE dbo.order_items (
 order_id varchar(32) NOT NULL, order_item_id int NOT NULL, product_id varchar(32) NULL, seller_id varchar(32) NULL,
 shipping_limit_date datetime2(0) NULL, price decimal(18,2) NULL, freight_value decimal(18,2) NULL);
IF OBJECT_ID('dbo.order_payments','U') IS NULL CREATE TABLE dbo.order_payments (
 order_id varchar(32) NOT NULL, payment_sequential int NOT NULL, payment_type varchar(32) NULL,
 payment_installments int NULL, payment_value decimal(18,2) NULL);
IF OBJECT_ID('dbo.order_reviews','U') IS NULL CREATE TABLE dbo.order_reviews (
 review_id varchar(32) NOT NULL, order_id varchar(32) NULL, review_score int NULL,
 review_comment_title nvarchar(max) NULL, review_comment_message nvarchar(max) NULL,
 review_creation_date datetime2(0) NULL, review_answer_timestamp datetime2(0) NULL);
IF OBJECT_ID('dbo.sellers','U') IS NULL CREATE TABLE dbo.sellers (
 seller_id varchar(32) NOT NULL, seller_zip_code_prefix varchar(8) NULL,
 seller_city nvarchar(100) NULL, seller_state char(2) NULL);
IF OBJECT_ID('dbo.products','U') IS NULL CREATE TABLE dbo.products (
 product_id varchar(32) NOT NULL, product_category_name nvarchar(100) NULL,
 product_name_lenght int NULL, product_description_lenght int NULL, product_photos_qty int NULL,
 product_weight_g int NULL, product_length_cm int NULL, product_height_cm int NULL, product_width_cm int NULL);
IF OBJECT_ID('dbo.category_translation','U') IS NULL CREATE TABLE dbo.category_translation (
 product_category_name nvarchar(100) NOT NULL, product_category_name_english nvarchar(100) NULL);
