-- Change over Time , Trends
SELECT
DATETRUNC(month , order_date) as order_date,
SUM(sales_amount) as total_Sales,
COUNT(DISTINCT customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month , order_date) 
ORDER BY DATETRUNC(month , order_date) 

--Cumulative Analysis
-- Calculate the total sales per month
-- and the running total of sales over time
SELECT
order_date,
total_sales,
SUM(total_sales) OVER (ORDER BY order_date) AS running_total_sales,
AVG(avg_price) OVER (ORDER BY order_date) AS moving_avg_price
FROM
(
SELECT
DATETRUNC(year , order_date) AS order_date,
SUM(sales_amount) AS total_sales,
AVG(price) as avg_price
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(year, order_date)
)t


-- Performance Analysis 
/*  Analyze theyearly performance of products by comparing thier sales
to boththe average sales performance ofthe products and the previous year's sales*/
WITH yearly_product_sales AS(
SELECT
YEAR(f.order_date) AS order_year,
p.product_name,
SUM(f.sales_amount) AS current_sales
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
ON f.product_key = p.product_key
WHERE f.order_date IS NOT NULL
GROUP BY
YEAR(f.order_date),
p.product_name
)

SELECT
order_year,
product_name,
current_sales,
AVG(current_sales) OVER(PARTITION BY product_name) AS avg_sales,
current_sales - AVG(current_sales) OVER(PARTITION BY product_name) AS diff_AVG,
CASE WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above Avg'
     WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below Avg'
     ELSE 'Avg'
END avg_change,
--year-over-year Analysis
LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) py_sales,
CASE WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
     WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
     ELSE 'NO Change'
END py_change
FROM yearly_product_sales
ORDER BY product_name , order_year

-- Part_to_whole Analysis
-- Which category contributes the most to overall sales?
WITH category_sales AS
(
SELECT
category,
SUM(sales_amount) total_sales
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
ON p.product_key = f.product_key
GROUP BY category)

SELECT
category,
total_Sales,
SUM(total_sales) OVER () overall_sales,
CONCAT(ROUND((CAST(total_sales AS FLOAT)/ SUM(total_sales) OVER ())* 100,2) , '%') AS percentage_of_total_sale
FROM category_sales
ORDER BY total_sales DESC

--DATE SEGMENTATION
/* Segments products into cost ranges and 
count how many products fall into each segment */
WITH products_segments AS(
SELECT
product_key,
product_name,
cost,
CASE WHEN cost < 100 THEN 'Below 100'
     WHEN cost BETWEEN 100 AND 500 THEN ' 100-500'
     WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
     ELSE 'Above 1000'
END cost_range
FROM gold.dim_products)

SELECT
cost_range,
COUNt(product_key) AS total_products
FROM products_segments
GROUP BY cost_range 
ORDER BY total_products DESC

/*Group customers into three segments based on thier spending behavior.
 - VIP: at least 12 months of history and spending more than 5000
 - Regular : at least 12 months of history but spending 5000 or less
 - New : lifespan less than 12 months 
And find the total number of customers by each group. */
WITH customer_spending AS(
SELECT
c.customer_key,
SUM(f.sales_amount) AS total_spending,
MIN(order_date) AS first_order,
MAX(order_date) AS last_order,
DATEDIFF (month, MIN(order_date) , MAX(order_date)) AS lifespan
FROM gold.fact_Sales f
LEFT JOIN gold.dim_customers c
ON f.customer_key = c.customer_key
GROUP BY c.customer_key
)
SELECT
customer_segment,
COUNT(customer_key) AS total_customers
FROM(
     SELECT
     customer_key,
     CASE WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
          WHEN lifespan >= 12 AND total_spending <=5000 THEN ' Regular'
          ELSE 'New'
     END customer_segment
     FROM customer_spending) t
     GROUP BY customer_segment
     ORDER BY total_customers

/* 
===================================================================================
Customer Report--
Purpose :
        - This Report concolidates key customer metrics and behaviors

Highlights
   1. Gathers essential fields such as names ,ages and transaction details.
   2. Segment customers into categories ( VIP , Regular, New) and age groups.
   3. Aggregates customers-level metrices:
       - total orders
       - total sales
       - total products
       - lifespan (in months)
   4. Calculates valuable KPIS:
       - recency (months since last order)
       - average order value
       - average monthly spend
=====================================================================================
*/
CREATE VIEW gold.report_customers AS
WITH base_query AS(
/* ------------------------------------------------------------------
1) Base Query : Retrives core colums from tables
--------------------------------------------------------------------- */
SELECT
f.order_number,
f.product_key,
f.order_date,
f.sales_amount,
f.quantity,
c.customer_key,
c.customer_number,
CONCAT(c.first_name, ' ' , c.last_name) AS customer_name,
DATEDIFF(year, c.birthdate , GETDATE()) age
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
ON c.customer_key = f.customer_key
WHERE order_date IS NOT NULL 
),
customer_aggregation AS
(
SELECT
   customer_key,
   customer_number,
   customer_name,
   age,
   COUNT(DISTINCT order_number) AS total_orders,
   SUM(sales_amount) AS total_sales,
   SUM(quantity)AS total_quanity,
   COUNT(DISTINCT product_key) AS total_products,
   MAX(order_date) AS last_order_Date,
   DATEDIFF(month , MIN(order_date) , MAx(order_date)) AS lifespan

FROM base_query
GROUP BY
    customer_key,
    customer_name,
    customer_number,
    age
)
-- Segment customers into categories  
SELECT
customer_key,
customer_name,
customer_number,
age,
CASE 
    WHEN age < 20 THEN 'Under 20'
    WHEN age between 20 and 29 THEN '20-29'
    WHEN age between 30 and 39 THEN '30-39'
    WHEN age between 40 and 49 THEN '40-49'
    ELSE '50 and above'
END AS age_group,
CASE 
     WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
     WHEN lifespan >= 12 AND total_sales <=5000 THEN ' Regular'
     ELSE 'New'
END customer_segment,
total_orders,
total_sales,
total_quanity,
total_products,
last_order_Date,
lifespan,

-- Compuate average order value (AVO)
CASE WHEN total_sales = 0 THEN 0
     ELSE total_sales / total_orders
END AS avg_order_value,

-- Compuate average monthly spend
CASE WHEN lifespan = 0 THEN total_sales
     ELSE total_Sales / lifespan
END AS avg_monthly_spend
FROM customer_aggregation
  
 -- Report_customers
SELECT
age_group,
COUNT(customer_number) AS total_Customers,
SUM(total_sales) total_Sales
FROM gold.report_customers
GROUP BY age_group


/* 
=================================================================================================
Product Report
Purpose : 
   - This report consolidates key product metrics and behaviors.

Highlights:
   1. Gathers essential fields such as product name , category , subcategory, and cost.
   2. Segments products by revenue to identity High- Performers, Mid-Range , or Low-Performers.
   3. Aggregates product-level metrics:
     - total orders
     - total sales
     - total quantity sold
     - total customers(unique)
     - lifespan(in months)
   4. CAlculates valuable KPIs:
     - recency (months since last sale)
     - average order revenue (AOP)
     - average monthly revenue
======================================================================================================
*/

CREATE VIEW gold.report_products AS
WITH base_query AS (
/*------------------------------------------------------------------------------
1) Base Query: Retrivers core columns from fact_Saels and dim_products
--------------------------------------------------------------------------------- */
SELECT
    f.order_number,
    f.order_date,
    f.customer_key,
    f.sales_amount,
    f.quantity,
    p.product_name,
    p.product_key,
    p.category,
    p.subcategory,
    p.cost
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
   ON f.product_key = p.product_key
WHERE f.order_date IS NOT NULL --only consider valid sales dates
) ,

product_aggregations AS (
/*----------------------------------------------------------------------------
2) Products Aggregations : Summarizes key metrices at the product level
---------------------------------------------------------------------------- */
SELECT
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    DATEDIFF(MONTH , MIN(order_date) , MAX(order_date)) AS lifespan,
    MAX(order_date) AS last_sale_date,
    COUNT(DISTINCT order_number) AS total_orders,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
    ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity , 0)), 1) AS avg_selling_price
FROM base_query

GROUP BY
    product_key,
    product_name,
    category,
    subcategory,
    cost
)

/*--------------------------------------------------------------------
3) Final Query : Combines all product result into one output
----------------------------------------------------------------------*/
SELECT
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    last_sale_date,
    DATEDIFF(MONTH, last_sale_date , GETDATE()) AS recency_in_months,
    CASE 
       WHEN total_sales > 50000 THEN 'High-performer'
       WHEN total_sales >= 10000 THEN 'Mid-Range'
       ELSE 'Low-performer'
    END AS product_segment, 
    lifespan,
    total_orders,
    total_sales,
    total_quantity,
    total_customers,
    avg_selling_price,
     -- Average Order Revenue (AOR)
    CASE
        WHEN total_orders = 0 THEN 0
        ELSE total_sales / total_orders
    END AS avg_order_revenue,

    -- Average Monthly Revenue
    CASE
       WHEN lifespan = 0 THEN total_sales
       ELSE total_sales / lifespan
    END AS avg_monthly_revenue
FROM product_aggregations

-- Report products
SELECT 
*
FROM gold.report_products 