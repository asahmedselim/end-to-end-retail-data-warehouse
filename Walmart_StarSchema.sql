-- ============================================================
--  Walmart Star Schema - Full Implementation Script
--  Compatible with: SQL Server (T-SQL)
--  Source Tables  : sales, features, stores
--  Target Schema  : Star Schema (1 Fact + 5 Dimensions)
-- ============================================================

USE Walmart_DB;
GO

-- ============================================================
-- STEP 1: CREATE DIMENSION TABLES
-- ============================================================

-- ------------------------------------------------------------
-- 1.1  Dim_Store
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Store', 'U') IS NOT NULL DROP TABLE dbo.Dim_Store;

CREATE TABLE dbo.Dim_Store (
    store_key       INT           IDENTITY(1,1) PRIMARY KEY,
    store_nbr       INT           NOT NULL,
    store_type      CHAR(1)       NOT NULL,         -- A / B / C
    store_size      INT           NOT NULL,          -- sq ft
    created_at      DATETIME      DEFAULT GETDATE()
);
GO

-- ------------------------------------------------------------
-- 1.2  Dim_Date
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Date', 'U') IS NOT NULL DROP TABLE dbo.Dim_Date;

CREATE TABLE dbo.Dim_Date (
    date_key        INT           PRIMARY KEY,       -- YYYYMMDD format
    full_date       DATE          NOT NULL,
    day_of_week     TINYINT       NOT NULL,          -- 1=Sunday .. 7=Saturday
    day_name        VARCHAR(10)   NOT NULL,
    week_number     TINYINT       NOT NULL,
    month_number    TINYINT       NOT NULL,
    month_name      VARCHAR(10)   NOT NULL,
    quarter_number  TINYINT       NOT NULL,
    year_number     SMALLINT      NOT NULL,
    is_holiday      BIT           NOT NULL DEFAULT 0
);
GO

-- ------------------------------------------------------------
-- 1.3  Dim_Dept
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Dept', 'U') IS NOT NULL DROP TABLE dbo.Dim_Dept;

CREATE TABLE dbo.Dim_Dept (
    dept_key        INT           IDENTITY(1,1) PRIMARY KEY,
    dept_id         INT           NOT NULL UNIQUE,
    dept_name       VARCHAR(100)  NULL          -- can be enriched later
);
GO

-- ------------------------------------------------------------
-- 1.4  Dim_Promotion  (MarkDown promotions from features table)
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Promotion', 'U') IS NOT NULL DROP TABLE dbo.Dim_Promotion;

CREATE TABLE dbo.Dim_Promotion (
    promo_key       INT           IDENTITY(1,1) PRIMARY KEY,
    store_nbr       INT           NOT NULL,
    promo_date      DATE          NOT NULL,
    markdown1       FLOAT         NULL,
    markdown2       FLOAT         NULL,
    markdown3       FLOAT         NULL,
    markdown4       FLOAT         NULL,
    markdown5       FLOAT         NULL,
    has_promotion   BIT           NOT NULL DEFAULT 0  -- 1 = at least one markdown active
);
GO

-- ------------------------------------------------------------
-- 1.5  Dim_Economy  (macro-economic indicators from features table)
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Economy', 'U') IS NOT NULL DROP TABLE dbo.Dim_Economy;

CREATE TABLE dbo.Dim_Economy (
    econ_key            INT       IDENTITY(1,1) PRIMARY KEY,
    store_nbr           INT       NOT NULL,
    econ_date           DATE      NOT NULL,
    temperature         FLOAT     NULL,
    fuel_price          FLOAT     NULL,
    cpi                 FLOAT     NULL,
    unemployment_rate   FLOAT     NULL
);
GO


-- ============================================================
-- STEP 2: CREATE FACT TABLE
-- ============================================================

IF OBJECT_ID('dbo.Fact_Sales', 'U') IS NOT NULL DROP TABLE dbo.Fact_Sales;

CREATE TABLE dbo.Fact_Sales (
    sale_key        BIGINT        IDENTITY(1,1) PRIMARY KEY,

    -- Foreign Keys
    store_key       INT           NOT NULL,
    date_key        INT           NOT NULL,
    dept_key        INT           NOT NULL,
    promo_key       INT           NULL,
    econ_key        INT           NULL,

    -- Measures
    weekly_sales    FLOAT         NOT NULL,
    is_holiday      BIT           NOT NULL DEFAULT 0,

    -- Constraints
    CONSTRAINT FK_Fact_Store    FOREIGN KEY (store_key)  REFERENCES dbo.Dim_Store(store_key),
    CONSTRAINT FK_Fact_Date     FOREIGN KEY (date_key)   REFERENCES dbo.Dim_Date(date_key),
    CONSTRAINT FK_Fact_Dept     FOREIGN KEY (dept_key)   REFERENCES dbo.Dim_Dept(dept_key),
    CONSTRAINT FK_Fact_Promo    FOREIGN KEY (promo_key)  REFERENCES dbo.Dim_Promotion(promo_key),
    CONSTRAINT FK_Fact_Econ     FOREIGN KEY (econ_key)   REFERENCES dbo.Dim_Economy(econ_key)
);
GO


-- ============================================================
-- STEP 3: LOAD DIMENSION TABLES  (ETL from raw tables)
-- ============================================================

-- ------------------------------------------------------------
-- 3.1  Load Dim_Store  (from raw stores table)
-- ------------------------------------------------------------
INSERT INTO dbo.Dim_Store (store_nbr, store_type, store_size)
SELECT
    Store   AS store_nbr,
    Type    AS store_type,
    Size    AS store_size
FROM dbo.stores
ORDER BY Store;
GO

-- ------------------------------------------------------------
-- 3.2  Load Dim_Date  (derived from all unique dates in sales + features)
-- ------------------------------------------------------------
WITH all_dates AS (
    SELECT CAST([Date] AS DATE) AS d FROM dbo.sales
    UNION
    SELECT CAST([Date] AS DATE) AS d FROM dbo.features
)
INSERT INTO dbo.Dim_Date (
    date_key, full_date, day_of_week, day_name,
    week_number, month_number, month_name,
    quarter_number, year_number, is_holiday
)
SELECT
    CONVERT(INT, FORMAT(d, 'yyyyMMdd'))     AS date_key,
    d                                       AS full_date,
    DATEPART(WEEKDAY, d)                    AS day_of_week,
    DATENAME(WEEKDAY, d)                    AS day_name,
    DATEPART(WEEK, d)                       AS week_number,
    MONTH(d)                                AS month_number,
    DATENAME(MONTH, d)                      AS month_name,
    DATEPART(QUARTER, d)                    AS quarter_number,
    YEAR(d)                                 AS year_number,
    -- Holiday flag from sales table
    ISNULL((
        SELECT TOP 1 CAST(IsHoliday AS BIT)
        FROM dbo.sales s2
        WHERE CAST(s2.[Date] AS DATE) = d
    ), 0)                                   AS is_holiday
FROM all_dates
ORDER BY d;
GO

-- ------------------------------------------------------------
-- 3.3  Load Dim_Dept  (unique departments from sales)
-- ------------------------------------------------------------
INSERT INTO dbo.Dim_Dept (dept_id, dept_name)
SELECT DISTINCT
    Dept            AS dept_id,
    'Dept_' + CAST(Dept AS VARCHAR(10)) AS dept_name   -- placeholder name
FROM dbo.sales
ORDER BY Dept;
GO

-- ------------------------------------------------------------
-- 3.4  Load Dim_Promotion  (from features table)
-- ------------------------------------------------------------
INSERT INTO dbo.Dim_Promotion (
    store_nbr, promo_date,
    markdown1, markdown2, markdown3, markdown4, markdown5,
    has_promotion
)
SELECT
    Store                                               AS store_nbr,
    CAST([Date] AS DATE)                               AS promo_date,
    MarkDown1,
    MarkDown2,
    MarkDown3,
    MarkDown4,
    MarkDown5,
    CASE
        WHEN ISNULL(MarkDown1, 0) > 0
          OR ISNULL(MarkDown2, 0) > 0
          OR ISNULL(MarkDown3, 0) > 0
          OR ISNULL(MarkDown4, 0) > 0
          OR ISNULL(MarkDown5, 0) > 0
        THEN 1 ELSE 0
    END                                                AS has_promotion
FROM dbo.features
ORDER BY Store, [Date];
GO

-- ------------------------------------------------------------
-- 3.5  Load Dim_Economy  (from features table)
-- ------------------------------------------------------------
INSERT INTO dbo.Dim_Economy (
    store_nbr, econ_date,
    temperature, fuel_price,
    cpi, unemployment_rate
)
SELECT
    Store                   AS store_nbr,
    CAST([Date] AS DATE)   AS econ_date,
    Temperature,
    Fuel_Price,
    CPI,
    Unemployment
FROM dbo.features
ORDER BY Store, [Date];
GO


-- ============================================================
-- STEP 4: LOAD FACT TABLE
-- ============================================================
INSERT INTO dbo.Fact_Sales (
    store_key, date_key, dept_key,
    promo_key, econ_key,
    weekly_sales, is_holiday
)
SELECT
    ds.store_key,
    dd.date_key,
    ddept.dept_key,
    dp.promo_key,
    de.econ_key,
    s.Weekly_Sales                      AS weekly_sales,
    CAST(s.IsHoliday AS BIT)           AS is_holiday
FROM dbo.sales s
-- Join Dim_Store
INNER JOIN dbo.Dim_Store ds
    ON ds.store_nbr = s.Store
-- Join Dim_Date
INNER JOIN dbo.Dim_Date dd
    ON dd.date_key = CONVERT(INT, FORMAT(CAST(s.[Date] AS DATE), 'yyyyMMdd'))
-- Join Dim_Dept
INNER JOIN dbo.Dim_Dept ddept
    ON ddept.dept_id = s.Dept
-- Join Dim_Promotion (optional - LEFT JOIN)
LEFT JOIN dbo.Dim_Promotion dp
    ON dp.store_nbr = s.Store
    AND dp.promo_date = CAST(s.[Date] AS DATE)
-- Join Dim_Economy (optional - LEFT JOIN)
LEFT JOIN dbo.Dim_Economy de
    ON de.store_nbr = s.Store
    AND de.econ_date = CAST(s.[Date] AS DATE);
GO


-- ============================================================
-- STEP 5: VERIFY - Row counts after load
-- ============================================================
SELECT 'Dim_Store'      AS [Table], COUNT(*) AS [Rows] FROM dbo.Dim_Store
UNION ALL
SELECT 'Dim_Date',       COUNT(*) FROM dbo.Dim_Date
UNION ALL
SELECT 'Dim_Dept',       COUNT(*) FROM dbo.Dim_Dept
UNION ALL
SELECT 'Dim_Promotion',  COUNT(*) FROM dbo.Dim_Promotion
UNION ALL
SELECT 'Dim_Economy',    COUNT(*) FROM dbo.Dim_Economy
UNION ALL
SELECT 'Fact_Sales',     COUNT(*) FROM dbo.Fact_Sales;
GO


-- ============================================================
-- STEP 6: SAMPLE ANALYTICAL QUERIES
-- ============================================================

-- Q1: Total weekly sales per store per year
SELECT
    ds.store_nbr,
    ds.store_type,
    dd.year_number,
    SUM(f.weekly_sales)    AS total_sales
FROM dbo.Fact_Sales f
JOIN dbo.Dim_Store ds ON f.store_key = ds.store_key
JOIN dbo.Dim_Date  dd ON f.date_key  = dd.date_key
GROUP BY ds.store_nbr, ds.store_type, dd.year_number
ORDER BY ds.store_nbr, dd.year_number;
GO

-- Q2: Holiday vs non-holiday sales comparison
SELECT
    dd.year_number,
    f.is_holiday,
    SUM(f.weekly_sales)    AS total_sales,
    COUNT(*)               AS num_records
FROM dbo.Fact_Sales f
JOIN dbo.Dim_Date dd ON f.date_key = dd.date_key
GROUP BY dd.year_number, f.is_holiday
ORDER BY dd.year_number, f.is_holiday;
GO

-- Q3: Top 10 departments by total sales
SELECT TOP 10
    ddept.dept_id