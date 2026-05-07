-- ============================================================
-- DIMENSION TABLES
-- ============================================================

-- ---- dim_date ----------------------------------------------
CREATE OR REPLACE TABLE dim_date AS
WITH calendar AS (
    SELECT explode(sequence(DATE '2025-01-01', DATE '2030-12-31',
                            INTERVAL 1 DAY)) AS date
)
SELECT
    CAST(date_format(date, 'yyyyMMdd') AS INT)     AS date_key,
    date                                           AS full_date,
    year(date)                                     AS year,
    quarter(date)                                  AS quarter,
    month(date)                                    AS month_num,
    date_format(date, 'MMMM')                      AS month_name,
    day(date)                                      AS day_of_month,
    dayofweek(date)                                AS day_of_week,
    date_format(date, 'EEEE')                      AS day_name,
    weekofyear(date)                               AS week_of_year,
    CASE WHEN dayofweek(date) IN (1, 7) THEN TRUE
         ELSE FALSE END                            AS is_weekend
FROM calendar;


-- ---- dim_asset ---------------------------------------------
CREATE OR REPLACE TABLE dim_asset AS
SELECT
    ROW_NUMBER() OVER (ORDER BY asset_id) AS asset_key,
    asset_id
FROM (
    SELECT DISTINCT asset_id FROM sim_card_plan_history WHERE asset_id IS NOT NULL
    UNION
    SELECT DISTINCT asset_id FROM profile_installation  WHERE asset_id IS NOT NULL
) a;


-- ---- dim_bundle --------------------------------------------
CREATE OR REPLACE TABLE dim_bundle AS
SELECT
    ROW_NUMBER() OVER (ORDER BY bundle_id) AS bundle_key,
    bundle_id
FROM (
    SELECT DISTINCT bundle_id FROM rate_card             WHERE bundle_id IS NOT NULL
    UNION
    SELECT DISTINCT bundle_id FROM sim_card_plan_history WHERE bundle_id IS NOT NULL
) b;


-- ---- dim_geography -----------------------------------------
CREATE OR REPLACE TABLE dim_geography AS
SELECT
    ROW_NUMBER() OVER (ORDER BY cc1, cc2) AS geo_key,
    cc1,
    cc2
FROM (
    SELECT DISTINCT cc1, cc2 FROM rate_card    WHERE cc1 IS NOT NULL
    UNION
    SELECT DISTINCT cc1, cc2 FROM usage_events WHERE cc1 IS NOT NULL
) g;


-- ---- dim_technology ----------------------------------------
CREATE OR REPLACE TABLE dim_technology AS
SELECT
    ROW_NUMBER() OVER (ORDER BY tech_cd) AS tech_key,
    tech_cd
FROM (
    SELECT DISTINCT UPPER(tech_cd) AS tech_cd FROM rate_card    WHERE tech_cd IS NOT NULL
    UNION
    SELECT DISTINCT UPPER(tech)    AS tech_cd FROM usage_events WHERE tech    IS NOT NULL
) t;


-- ---- dim_source --------------------------------------------
CREATE OR REPLACE TABLE dim_source AS
SELECT
    ROW_NUMBER() OVER (ORDER BY src_nm) AS source_key,
    src_nm
FROM (SELECT DISTINCT src_nm FROM usage_events WHERE src_nm IS NOT NULL) s;


-- ---- dim_profile  (SCD Type 2) -----------------------------
CREATE OR REPLACE TABLE dim_profile AS
SELECT
    ROW_NUMBER() OVER (ORDER BY pid, beg_dttm)        AS profile_key,
    pid,
    asset_id,
    src_cd,
    crt_dttm,
    beg_dttm                                          AS effective_from,
    COALESCE(end_dttm, TIMESTAMP '9999-12-31')        AS effective_to,
    CASE WHEN end_dttm IS NULL THEN TRUE ELSE FALSE END AS is_current
FROM profile_installation;


-- ---- dim_rate  (SCD Type 2) --------------------------------
CREATE OR REPLACE TABLE dim_rate AS
SELECT
    ROW_NUMBER() OVER (ORDER BY bundle_id, cc1, cc2, tech_cd, beg_dttm) AS rate_key,
    bundle_id,
    cc1,
    cc2,
    UPPER(tech_cd)                                    AS tech_cd,
    rt_amt,
    REPLACE(curr_cd, ' ', '')                         AS curr_cd,
    prio_nbr,
    beg_dttm                                          AS effective_from,
    COALESCE(end_dttm, TIMESTAMP '9999-12-31')        AS effective_to,
    CASE WHEN end_dttm IS NULL THEN TRUE ELSE FALSE END AS is_current
FROM rate_card;


-- ============================================================
-- FACT TABLE
-- ============================================================

CREATE OR REPLACE TABLE fact_usage_events AS

WITH events_clean AS (
    SELECT
        sid, pid, evt_dttm, mb, cc1, cc2,
        UPPER(tech) AS tech,
        apn_nm, src_nm, ld_dttm
    FROM usage_events
    WHERE evt_dttm IS NOT NULL
      AND mb       IS NOT NULL
      AND mb       >= 0
),

events_with_asset AS (
    SELECT e.*, p.asset_id
    FROM events_clean e
    INNER JOIN profile_installation p
      ON  e.pid      = p.pid
      AND e.evt_dttm >= p.beg_dttm
      AND e.evt_dttm <  COALESCE(p.end_dttm, TIMESTAMP '9999-12-31')
),

events_with_bundle AS (
    SELECT ea.*, s.bundle_id
    FROM events_with_asset ea
    INNER JOIN sim_card_plan_history s
      ON  ea.asset_id = s.asset_id
      AND ea.evt_dttm >= s.eff_dttm
      AND ea.evt_dttm <  COALESCE(s.x_dttm, TIMESTAMP '9999-12-31')
),

events_with_rate AS (
    SELECT eb.*,
           r.rt_amt,
           r.curr_cd,
           r.prio_nbr,
           r.tech_cd AS rate_tech,
           ROW_NUMBER() OVER (
               PARTITION BY eb.sid
               ORDER BY
                   CASE WHEN UPPER(r.tech_cd) = eb.tech THEN 0 ELSE 1 END,
                   r.prio_nbr DESC
           ) AS rate_rank
    FROM events_with_bundle eb
    INNER JOIN rate_card r
      ON  eb.bundle_id = r.bundle_id
      AND eb.cc1       = r.cc1
      AND eb.cc2       = r.cc2
      AND (UPPER(r.tech_cd) = eb.tech OR r.tech_cd IS NULL)
      AND eb.evt_dttm >= r.beg_dttm
      AND eb.evt_dttm <  COALESCE(r.end_dttm, TIMESTAMP '9999-12-31')
),

events_priced AS (
    SELECT * FROM events_with_rate WHERE rate_rank = 1
)

SELECT
    e.sid,                                            -- natural key (degenerate)

    -- Foreign keys to dimensions
    dd.date_key,
    dp.profile_key,
    da.asset_key,
    db.bundle_key,
    dg.geo_key,
    dt.tech_key,
    ds.source_key,
    dr.rate_key,

    -- Event-grain attributes
    e.evt_dttm,
    e.apn_nm,
    e.ld_dttm,

    -- Measures
    e.mb,
    e.rt_amt,
    CAST(e.mb * e.rt_amt AS DECIMAL(18, 6))           AS cost,
    REPLACE(e.curr_cd, ' ', '')                       AS curr_cd

FROM events_priced e
LEFT JOIN dim_date       dd ON CAST(date_format(e.evt_dttm, 'yyyyMMdd') AS INT) = dd.date_key
LEFT JOIN dim_profile    dp ON e.pid       = dp.pid
                            AND e.evt_dttm >= dp.effective_from
                            AND e.evt_dttm <  dp.effective_to
LEFT JOIN dim_asset      da ON e.asset_id  = da.asset_id
LEFT JOIN dim_bundle     db ON e.bundle_id = db.bundle_id
LEFT JOIN dim_geography  dg ON e.cc1 = dg.cc1 AND e.cc2 = dg.cc2
LEFT JOIN dim_technology dt ON e.tech      = dt.tech_cd
LEFT JOIN dim_source     ds ON e.src_nm    = ds.src_nm
LEFT JOIN dim_rate       dr ON dr.bundle_id = e.bundle_id
                            AND dr.cc1      = e.cc1
                            AND dr.cc2      = e.cc2
                            AND COALESCE(dr.tech_cd, '__NULL__')
                                = COALESCE(UPPER(e.rate_tech), '__NULL__')
                            AND e.evt_dttm >= dr.effective_from
                            AND e.evt_dttm <  dr.effective_to;