-- =============================================================================
-- fallback.sql
-- Valencia Flood Vulnerability HOL — complete SQL pipeline
-- Generated from notebooks/flood_vulnerability_hol.ipynb
-- =============================================================================

-- 🌊 Spain Flood Vulnerability Solution — Hands-On Lab
-- Snowflake World Tour 2026
--
--
-- In this lab you will build an end-to-end flood vulnerability analysis platform using Snowflake.  
-- By combining Overture Maps building footprints, flood risk indices, and social vulnerability data  
-- you will identify buildings at flood risk across Comunitat Valenciana — one of the most flood-prone regions in the western Mediterranean.
--
-- What You Will Build
-- - A geospatial pipeline identifying buildings within PATRICOVA flood zones
-- - A social vulnerability overlay linking flood exposure to community resilience  
-- - Cortex AI document intelligence to parse Valencia’s Flood Mitigation Plan
-- - A Cortex Agent for natural-language Q&A over flood risk data
-- - An interactive Streamlit dashboard
--
-- Snowflake Features Covered
--
--
-- ⏱ Estimated Time: 90 minutes
--
-- > 📋 Before you start: Make sure you have ACCOUNTADMIN role or equivalent privileges.

-- Lab 1: Environment Setup
--
-- First, we create the database, schema, and warehouse for this lab.  
-- All objects will live in FLOOD_ANALYTICS.FLOOD.
--
-- > 📋 Run each cell: Click ▶ or press Shift+Enter to execute.

-- Setup Database and Warehouse
USE ROLE ACCOUNTADMIN;

CREATE DATABASE  IF NOT EXISTS FLOOD_ANALYTICS;
CREATE SCHEMA    IF NOT EXISTS FLOOD_ANALYTICS.FLOOD;

CREATE WAREHOUSE IF NOT EXISTS FLOOD_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND   = 120
  AUTO_RESUME    = TRUE
  COMMENT        = 'Warehouse for Flood Vulnerability HOL';

USE DATABASE  FLOOD_ANALYTICS;
USE SCHEMA    FLOOD;
USE WAREHOUSE FLOOD_WH;

SELECT CURRENT_DATABASE(), CURRENT_SCHEMA(), CURRENT_WAREHOUSE();

-- Step 1.2 — Install Overture Maps Buildings from Marketplace
--
-- This gives you access to 2.3 billion building footprints worldwide.
--
-- 1. Log in to Snowsight
-- 2. Click Marketplace in the left sidebar
-- 3. Search for "Overture Maps - Buildings"
-- 4. Find the listing by CARTO and click on it
-- 5. Click Get and set the database name to OVERTURE_MAPS_BUILDINGS
-- 6. Select PUBLIC role and click Get again
--
-- > Note: We filter to Comunitat Valenciana using a bounding box (lon −1.53 to 0.53, lat 37.84 to 40.79).

-- Verify Overture Maps Access
SELECT
    ID,
    NAMES['primary']::STRING AS NAME,
    SUBTYPE,
    CLASS,
    HEIGHT,
    NUM_FLOORS,
    BBOX
FROM OVERTURE_MAPS_BUILDINGS.CARTO.BUILDING
WHERE BBOX:xmin >= -1.53
  AND BBOX:xmax <=  0.53
  AND BBOX:ymin >= 37.84
  AND BBOX:ymax <= 40.79
LIMIT 10;

-- Extract Valencia Buildings with H3
-- Extract Valencia buildings + compute H3 indices
-- Expect 3-5 min on MEDIUM warehouse
CREATE OR REPLACE TABLE BUILDINGS_VALENCIA AS
SELECT
    ID,
    NAMES['primary']::STRING                          AS NAME,
    SUBTYPE,
    CLASS,
    HEIGHT,
    NUM_FLOORS,
    GEOMETRY,
    BBOX,
    ST_X(ST_CENTROID(GEOMETRY))                       AS LONGITUDE,
    ST_Y(ST_CENTROID(GEOMETRY))                       AS LATITUDE,
    H3_POINT_TO_CELL_STRING(ST_CENTROID(GEOMETRY), 8) AS H3_INDEX_8,
    H3_POINT_TO_CELL_STRING(ST_CENTROID(GEOMETRY), 6) AS H3_INDEX_6
FROM OVERTURE_MAPS_BUILDINGS.CARTO.BUILDING
WHERE BBOX:xmin >= -1.53
  AND BBOX:xmax <=  0.53
  AND BBOX:ymin >= 37.84
  AND BBOX:ymax <= 40.79;

SELECT COUNT(*) AS TOTAL_VALENCIA_BUILDINGS FROM BUILDINGS_VALENCIA;

-- Lab 2: Load Flood Risk & Social Vulnerability Data
--
--
-- > No manual upload needed — next cells use `COPY FILES INTO` from the workspace.

-- Create Stage and File Format
CREATE OR REPLACE STAGE FLOOD_DATA_STAGE
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'Stage for flood risk, SVI CSVs and policy PDFs';

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
  TYPE                         = 'CSV'
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  PARSE_HEADER                 = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
  NULL_IF                      = ('', 'NULL', 'None', 'NA', '-999')
  EMPTY_FIELD_AS_NULL          = TRUE;

SHOW STAGES LIKE 'FLOOD_DATA_STAGE';

-- Load Risk Data from Workspace
COPY FILES INTO @FLOOD_DATA_STAGE/comarca/
FROM 'snow://workspace/USER$.PUBLIC."flood_resilience_es"/versions/live/'
FILES=('data/comarca_centroids/Valencia_Comarca_Centroids.csv');

COPY FILES INTO @FLOOD_DATA_STAGE/risk/
FROM 'snow://workspace/USER$.PUBLIC."flood_resilience_es"/versions/live/'
FILES=('data/flood_risk/Flood_Risk_Valencia.csv');

COPY FILES INTO @FLOOD_DATA_STAGE/svi/
FROM 'snow://workspace/USER$.PUBLIC."flood_resilience_es"/versions/live/'
FILES=('data/social_vulnerability/SVI_Valencia.csv');

CREATE OR REPLACE TABLE COMARCA_CENTROIDS (
    COMARCA_CODE STRING, COMARCA STRING, PROVINCE STRING, LATITUDE FLOAT, LONGITUDE FLOAT
);
COPY INTO COMARCA_CENTROIDS FROM @FLOOD_DATA_STAGE/comarca/
FILE_FORMAT = CSV_FORMAT MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE FLOOD_RISK_VALENCIA (
    ZONE_CODE STRING, COMARCA_CODE STRING, COMARCA STRING, PROVINCE STRING,
    RISK_SCORE FLOAT, RISK_RATING STRING, FLUVIAL_RISK_SCORE FLOAT, FLUVIAL_RISK_RATING STRING,
    COASTAL_RISK_SCORE FLOAT, COASTAL_RISK_RATING STRING, DANA_RISK_SCORE FLOAT,
    EXPECTED_ANNUAL_LOSS FLOAT, EAL_BUILDINGS FLOAT
);
COPY INTO FLOOD_RISK_VALENCIA FROM @FLOOD_DATA_STAGE/risk/
FILE_FORMAT = CSV_FORMAT MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE ON_ERROR = 'CONTINUE';

CREATE OR REPLACE TABLE SVI_VALENCIA (
    ZONE_CODE STRING, COMARCA_CODE STRING, COMARCA STRING, PROVINCE STRING,
    POPULATION FLOAT, RPL_SOCIOECONOMIC FLOAT, RPL_DEMOGRAPHICS FLOAT,
    RPL_HOUSING FLOAT, RPL_OVERALL FLOAT, ELDERLY_PCT FLOAT, IMMIGRANT_PCT FLOAT, RENTAL_PCT FLOAT
);
COPY INTO SVI_VALENCIA FROM @FLOOD_DATA_STAGE/svi/
FILE_FORMAT = CSV_FORMAT MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE ON_ERROR = 'CONTINUE';

SELECT 'COMARCA_CENTROIDS' AS TBL, COUNT(*) FROM COMARCA_CENTROIDS
UNION ALL SELECT 'FLOOD_RISK_VALENCIA', COUNT(*) FROM FLOOD_RISK_VALENCIA
UNION ALL SELECT 'SVI_VALENCIA', COUNT(*) FROM SVI_VALENCIA;

-- Derive PATRICOVA Flood Zones
CREATE OR REPLACE TABLE FLOOD_ZONES AS
SELECT
    ZONE_CODE, COMARCA, COMARCA_CODE,
    CASE
        WHEN FLUVIAL_RISK_RATING IN ('Very High','Relatively High')
             AND COASTAL_RISK_RATING IN ('Very High','Relatively High') THEN 'A1'
        WHEN FLUVIAL_RISK_RATING IN ('Very High','Relatively High') THEN 'A2'
        WHEN FLUVIAL_RISK_RATING = 'Relatively Moderate' THEN 'B'
        ELSE 'C'
    END AS FLOOD_ZONE,
    CASE
        WHEN FLUVIAL_RISK_RATING IN ('Very High','Relatively High')
             AND COASTAL_RISK_RATING IN ('Very High','Relatively High')
            THEN 'Frequent Fluvial + Coastal Flooding'
        WHEN FLUVIAL_RISK_RATING IN ('Very High','Relatively High')
            THEN 'Occasional Flooding'
        WHEN FLUVIAL_RISK_RATING = 'Relatively Moderate'
            THEN 'Geomorphic Flood Risk'
        ELSE 'Low Risk'
    END AS ZONE_DESCRIPTION,
    (FLUVIAL_RISK_RATING IN ('Very High','Relatively High')) AS IN_SFHA,
    FLUVIAL_RISK_SCORE, COASTAL_RISK_SCORE, DANA_RISK_SCORE
FROM FLOOD_RISK_VALENCIA;

SELECT FLOOD_ZONE, COUNT(*) AS ZONES FROM FLOOD_ZONES GROUP BY 1 ORDER BY ZONES DESC;

-- Lab 3: Geospatial Flood Risk Analysis
--
-- Join 2M+ Valencia buildings with flood risk data using H3 hexagonal indexing.
--
-- Composite Vulnerability Score:
-- ```
-- Score = (Risk Score x 40%) + (SVI Overall x 100 x 30%) + (Flood Zone Exposure x 30%)
-- ```
-- Where: A1=100, A2=80, B=40, C=10

-- Create H3 Comarca Map and Risk Profile
-- Map H3 cells to comarcas using nearest centroid
CREATE OR REPLACE TABLE H3_COMARCA_MAP AS
WITH h3_cells AS (SELECT DISTINCT H3_INDEX_6 FROM BUILDINGS_VALENCIA),
h3_with_centroid AS (
    SELECT h.H3_INDEX_6,
        ST_Y(H3_CELL_TO_POINT(h.H3_INDEX_6)) AS H3_LAT,
        ST_X(H3_CELL_TO_POINT(h.H3_INDEX_6)) AS H3_LON
    FROM h3_cells h
)
SELECT hc.H3_INDEX_6, cc.COMARCA_CODE, cc.COMARCA, cc.PROVINCE
FROM h3_with_centroid hc
CROSS JOIN COMARCA_CENTROIDS cc
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY hc.H3_INDEX_6
    ORDER BY HAVERSINE(hc.H3_LAT, hc.H3_LON, cc.LATITUDE, cc.LONGITUDE)
) = 1;

-- Comarca risk profile
CREATE OR REPLACE TABLE COMARCA_RISK_PROFILE AS
SELECT
    r.COMARCA_CODE, r.COMARCA, r.PROVINCE,
    ROUND(AVG(r.RISK_SCORE),2) AS RISK_SCORE, MAX(r.RISK_RATING) AS RISK_RATNG,
    ROUND(AVG(r.FLUVIAL_RISK_SCORE),2) AS FLUVIAL_RISK_SCORE, MAX(r.FLUVIAL_RISK_RATING) AS FLUVIAL_RISK_RATING,
    ROUND(AVG(r.COASTAL_RISK_SCORE),2) AS COASTAL_RISK_SCORE, MAX(r.COASTAL_RISK_RATING) AS COASTAL_RISK_RATING,
    ROUND(AVG(r.DANA_RISK_SCORE),2) AS DANA_RISK_SCORE,
    ROUND(MAX(r.EXPECTED_ANNUAL_LOSS),0) AS EXPECTED_ANNUAL_LOSS,
    ROUND(MAX(r.EAL_BUILDINGS),0) AS EAL_BUILDINGS,
    MAX(fz.FLOOD_ZONE) AS FLOOD_ZONE, MAX(fz.ZONE_DESCRIPTION) AS ZONE_DESCRIPTION,
    MAX(fz.IN_SFHA) AS IN_HIGH_RISK_ZONE,
    ROUND(AVG(s.RPL_OVERALL),3) AS SVI_OVERALL,
    ROUND(AVG(s.RPL_SOCIOECONOMIC),3) AS SVI_SOCIOECONOMIC,
    ROUND(AVG(s.RPL_HOUSING),3) AS SVI_HOUSING,
    ROUND(AVG(s.ELDERLY_PCT),1) AS ELDERLY_PCT,
    ROUND(AVG(s.IMMIGRANT_PCT),1) AS IMMIGRANT_PCT,
    ROUND(AVG(s.POPULATION),0) AS ZONE_POPULATION
FROM FLOOD_RISK_VALENCIA r
JOIN FLOOD_ZONES fz ON r.ZONE_CODE = fz.ZONE_CODE
JOIN SVI_VALENCIA s ON r.ZONE_CODE = s.ZONE_CODE
GROUP BY r.COMARCA_CODE, r.COMARCA, r.PROVINCE;

SELECT * FROM COMARCA_RISK_PROFILE ORDER BY RISK_SCORE DESC LIMIT 10;

-- Create Building Flood Risk Table
-- Assign each building to a specific zone within its comarca (not just comarca-level).
-- This distributes buildings across zones using HASH so that PCT_IN_SFHA varies
-- realistically per comarca instead of being 100% or 0%.
CREATE OR REPLACE TABLE BUILDING_FLOOD_RISK AS
WITH zone_numbered AS (
    SELECT
        fz.ZONE_CODE, fz.COMARCA_CODE, fz.COMARCA, fz.FLOOD_ZONE, fz.ZONE_DESCRIPTION, fz.IN_SFHA,
        fz.FLUVIAL_RISK_SCORE, fz.COASTAL_RISK_SCORE, fz.DANA_RISK_SCORE,
        r.RISK_SCORE, r.RISK_RATING,
        r.FLUVIAL_RISK_RATING, r.COASTAL_RISK_RATING,
        r.EXPECTED_ANNUAL_LOSS, r.EAL_BUILDINGS,
        s.RPL_OVERALL AS SVI_OVERALL,
        s.RPL_SOCIOECONOMIC AS SVI_SOCIOECONOMIC,
        s.RPL_HOUSING AS SVI_HOUSING,
        s.ELDERLY_PCT,
        s.IMMIGRANT_PCT,
        s.POPULATION AS ZONE_POPULATION,
        ROW_NUMBER() OVER (PARTITION BY fz.COMARCA_CODE ORDER BY fz.ZONE_CODE) - 1 AS ZONE_IDX,
        COUNT(*) OVER (PARTITION BY fz.COMARCA_CODE) AS ZONE_CNT
    FROM FLOOD_ZONES fz
    JOIN FLOOD_RISK_VALENCIA r ON fz.ZONE_CODE = r.ZONE_CODE
    JOIN SVI_VALENCIA s ON fz.ZONE_CODE = s.ZONE_CODE
),
building_comarca AS (
    SELECT b.*, hcm.COMARCA_CODE, hcm.COMARCA, hcm.PROVINCE
    FROM BUILDINGS_VALENCIA b
    JOIN H3_COMARCA_MAP hcm ON b.H3_INDEX_6 = hcm.H3_INDEX_6
)
SELECT
    bc.ID AS BUILDING_ID, bc.NAME AS BUILDING_NAME, bc.SUBTYPE, bc.CLASS,
    bc.HEIGHT, bc.NUM_FLOORS, bc.LONGITUDE, bc.LATITUDE, bc.H3_INDEX_8, bc.H3_INDEX_6,
    bc.COMARCA_CODE, bc.COMARCA AS PARISH, bc.PROVINCE,
    zn.RISK_SCORE AS NRI_RISK_SCORE, zn.RISK_RATING AS NRI_RISK_RATING,
    zn.FLUVIAL_RISK_SCORE AS INLAND_FLOOD_RISK_SCORE, zn.FLUVIAL_RISK_RATING AS INLAND_FLOOD_RISK_RATING,
    zn.COASTAL_RISK_SCORE, zn.COASTAL_RISK_RATING,
    zn.DANA_RISK_SCORE AS HURRICANE_RISK_SCORE,
    zn.EXPECTED_ANNUAL_LOSS, zn.EAL_BUILDINGS,
    zn.FLOOD_ZONE, zn.ZONE_DESCRIPTION,
    zn.IN_SFHA AS IN_SPECIAL_FLOOD_HAZARD_AREA,
    zn.SVI_OVERALL, zn.SVI_SOCIOECONOMIC, zn.SVI_HOUSING AS SVI_HOUSING_TRANSPORT,
    zn.ELDERLY_PCT AS MOBILE_HOME_PCT, zn.IMMIGRANT_PCT AS NO_VEHICLE_PCT,
    zn.ELDERLY_PCT, zn.ZONE_POPULATION AS TRACT_POPULATION,
    ROUND(
        COALESCE(zn.RISK_SCORE,0)*0.40 + COALESCE(zn.SVI_OVERALL,0)*100*0.30 +
        CASE zn.FLOOD_ZONE WHEN 'A1' THEN 100 WHEN 'A2' THEN 80 WHEN 'B' THEN 40 ELSE 10 END * 0.30
    ,2) AS COMPOSITE_VULNERABILITY_SCORE
FROM building_comarca bc
JOIN zone_numbered zn
  ON bc.COMARCA_CODE = zn.COMARCA_CODE
  AND ABS(HASH(bc.ID)) % zn.ZONE_CNT = zn.ZONE_IDX;

SELECT COUNT(*) AS TOTAL_ROWS FROM BUILDING_FLOOD_RISK;

-- Comarca Flood Summary
CREATE OR REPLACE TABLE PARISH_FLOOD_SUMMARY AS
SELECT
    PARISH, COUNT(*) AS TOTAL_BUILDINGS,
    COUNT(CASE WHEN IN_SPECIAL_FLOOD_HAZARD_AREA THEN 1 END) AS BUILDINGS_IN_SFHA,
    ROUND(COUNT(CASE WHEN IN_SPECIAL_FLOOD_HAZARD_AREA THEN 1 END)*100.0/COUNT(*),1) AS PCT_IN_SFHA,
    ROUND(AVG(NRI_RISK_SCORE),2) AS AVG_NRI_RISK_SCORE,
    ROUND(AVG(SVI_OVERALL),3) AS AVG_SVI_SCORE,
    ROUND(AVG(COMPOSITE_VULNERABILITY_SCORE),2) AS AVG_COMPOSITE_SCORE,
    ROUND(MAX(EXPECTED_ANNUAL_LOSS),0) AS TOTAL_EXPECTED_ANNUAL_LOSS,
    ROUND(MAX(EAL_BUILDINGS),0) AS BUILDING_EXPECTED_ANNUAL_LOSS,
    COUNT(CASE WHEN FLOOD_ZONE='A1' THEN 1 END) AS BUILDINGS_COASTAL_ZONE,
    COUNT(CASE WHEN FLOOD_ZONE='A2' THEN 1 END) AS BUILDINGS_RIVERINE_ZONE
FROM BUILDING_FLOOD_RISK GROUP BY PARISH ORDER BY AVG_COMPOSITE_SCORE DESC;

SELECT * FROM PARISH_FLOOD_SUMMARY LIMIT 10;

-- H3 Risk Heatmap
CREATE OR REPLACE TABLE H3_FLOOD_RISK_MAP AS
SELECT
    H3_INDEX_6,
    ST_ASWKT(H3_CELL_TO_BOUNDARY(H3_INDEX_6)) AS HEX_BOUNDARY_WKT,
    COUNT(*) AS BUILDING_COUNT,
    COUNT(CASE WHEN IN_SPECIAL_FLOOD_HAZARD_AREA THEN 1 END) AS BUILDINGS_AT_RISK,
    ROUND(AVG(COMPOSITE_VULNERABILITY_SCORE),2) AS AVG_VULNERABILITY,
    ROUND(AVG(NRI_RISK_SCORE),2) AS AVG_NRI_SCORE,
    ROUND(AVG(SVI_OVERALL),3) AS AVG_SVI,
    ROUND(SUM(EXPECTED_ANNUAL_LOSS),0) AS TOTAL_EAL,
    MAX(PARISH) AS PRIMARY_PARISH
FROM BUILDING_FLOOD_RISK GROUP BY H3_INDEX_6 HAVING COUNT(*)>=10
ORDER BY AVG_VULNERABILITY DESC;

SELECT H3_INDEX_6, PRIMARY_PARISH, BUILDING_COUNT, AVG_VULNERABILITY
FROM H3_FLOOD_RISK_MAP LIMIT 10;

-- Lab 4: Dynamic Tables
--
-- Dynamic Tables automatically refresh when source data changes.

-- Dynamic Table: Flood Risk Alerts
CREATE OR REPLACE DYNAMIC TABLE FLOOD_RISK_ALERTS
  TARGET_LAG = '1 hour' WAREHOUSE = FLOOD_WH
AS
SELECT
    PARISH, COMARCA_CODE, COUNT(*) AS BUILDINGS_AT_RISK,
    ROUND(AVG(COMPOSITE_VULNERABILITY_SCORE),2) AS AVG_VULNERABILITY_SCORE,
    ROUND(SUM(EAL_BUILDINGS),0) AS TOTAL_BUILDING_EAL,
    ROUND(AVG(SVI_OVERALL),3) AS AVG_SVI_SCORE,
    COUNT(CASE WHEN CLASS IN ('hospital','clinic','fire_station','school') THEN 1 END) AS CRITICAL_INFRA_COUNT,
    CASE
        WHEN AVG(COMPOSITE_VULNERABILITY_SCORE)>=70 THEN 'CRITICAL'
        WHEN AVG(COMPOSITE_VULNERABILITY_SCORE)>=50 THEN 'HIGH'
        WHEN AVG(COMPOSITE_VULNERABILITY_SCORE)>=30 THEN 'MODERATE'
        ELSE 'LOW'
    END AS RISK_LEVEL,
    CURRENT_TIMESTAMP() AS LAST_CALCULATED
FROM BUILDING_FLOOD_RISK WHERE IN_SPECIAL_FLOOD_HAZARD_AREA = TRUE
GROUP BY PARISH, COMARCA_CODE;

SELECT RISK_LEVEL, COUNT(*) AS CNT FROM FLOOD_RISK_ALERTS GROUP BY 1 ORDER BY CNT DESC;

-- Lab 5: Cortex AI — Policy Document Intelligence
--
-- PDF files:
-- - `Valencia_Flood_Mitigation_Plan_2024_Intro.pdf`
-- - `Valencia_Flood_Mitigation_Plan_2024_Strategies.pdf`

-- Upload and Parse Policy PDFs
CREATE OR REPLACE STAGE FLOOD_POLICY_DOCS
  DIRECTORY = (ENABLE = TRUE) ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

COPY FILES INTO @FLOOD_POLICY_DOCS/
FROM 'snow://workspace/USER$.PUBLIC."flood_resilience_es"/versions/live/'
FILES=('data/policy_docs/Valencia_Flood_Mitigation_Plan_2024_Intro.pdf',
       'data/policy_docs/Valencia_Flood_Mitigation_Plan_2024_Strategies.pdf');

ALTER STAGE FLOOD_POLICY_DOCS REFRESH;

CREATE OR REPLACE TABLE PARSED_POLICY_DOCS AS
SELECT
    RELATIVE_PATH AS FILE_NAME, SIZE AS FILE_SIZE_BYTES,
    SNOWFLAKE.CORTEX.PARSE_DOCUMENT(@FLOOD_POLICY_DOCS, RELATIVE_PATH) AS PARSED_CONTENT,
    PARSED_CONTENT:content::STRING AS FULL_TEXT, CURRENT_TIMESTAMP() AS PARSED_AT
FROM DIRECTORY(@FLOOD_POLICY_DOCS) WHERE RELATIVE_PATH LIKE '%.pdf';

CREATE OR REPLACE TABLE POLICY_DOC_CHUNKS AS
SELECT FILE_NAME, chunk.INDEX AS CHUNK_INDEX,
    TRIM(chunk.VALUE::STRING) AS CHUNK_TEXT, LENGTH(TRIM(chunk.VALUE::STRING)) AS CHUNK_LENGTH
FROM PARSED_POLICY_DOCS,
    LATERAL FLATTEN(INPUT => SPLIT(FULL_TEXT, '\n\n')) AS chunk
WHERE LENGTH(TRIM(chunk.VALUE::STRING)) > 80;

SELECT FILE_NAME, COUNT(*) AS CHUNKS FROM POLICY_DOC_CHUNKS GROUP BY FILE_NAME;

-- Create Cortex Search Service
CREATE OR REPLACE CORTEX SEARCH SERVICE FLOOD_POLICY_SEARCH
  ON CHUNK_TEXT
  ATTRIBUTES FILE_NAME, CHUNK_INDEX
  WAREHOUSE = FLOOD_WH
  TARGET_LAG = '1 day'
AS (SELECT CHUNK_TEXT, FILE_NAME, CHUNK_INDEX FROM POLICY_DOC_CHUNKS);

SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'FLOOD_ANALYTICS.FLOOD.FLOOD_POLICY_SEARCH',
    '{"query": "What projects are planned for the Xuquer river?", "columns": ["CHUNK_TEXT","FILE_NAME"], "limit": 3}'
)) AS SEARCH_RESULTS;

-- Cortex AI Executive Summary
SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', CONCAT(
    'You are a senior flood risk analyst for Valencia Emergency Management. ',
    'Based on the comarca-level flood risk data below, write a 3-paragraph executive summary.\n\n',
    'COMARCA RISK DATA (top 15):\n',
    (SELECT LISTAGG(PARISH||': composite='||AVG_COMPOSITE_SCORE||', SVI='||AVG_SVI_SCORE||
        ', '||PCT_IN_SFHA||'% in flood zone, loss='||TOTAL_EXPECTED_ANNUAL_LOSS||' EUR', '\n')
     FROM (SELECT * FROM PARISH_FLOOD_SUMMARY ORDER BY AVG_COMPOSITE_SCORE DESC LIMIT 15))
)) AS EXECUTIVE_SUMMARY;

-- Lab 6: Deploy Streamlit Dashboard and Cortex Agent

-- Deploy Streamlit Dashboard
CREATE OR REPLACE STAGE FLOOD_ANALYTICS.FLOOD.STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE) ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

COPY FILES INTO @FLOOD_ANALYTICS.FLOOD.STREAMLIT_STAGE/
FROM 'snow://workspace/USER$.PUBLIC."flood_resilience_es"/versions/live/'
FILES=('streamlit/flood_dashboard.py', 'streamlit/environment.yml', 'streamlit/.streamlit/config.toml');

CREATE OR REPLACE STREAMLIT FLOOD_ANALYTICS.FLOOD.FLOOD_VULNERABILITY_DASHBOARD
  ROOT_LOCATION = '@FLOOD_ANALYTICS.FLOOD.STREAMLIT_STAGE/streamlit'
  MAIN_FILE = 'flood_dashboard.py' QUERY_WAREHOUSE = FLOOD_WH
  TITLE = 'Valencia Flood Vulnerability Dashboard';

-- Deploy Cortex Agent
COPY FILES INTO @FLOOD_ANALYTICS.FLOOD.FLOOD_DATA_STAGE/
FROM 'snow://workspace/USER$.PUBLIC."flood_resilience_es"/versions/live/'
FILES=('semantic_model/flood_risk_model.yaml');

CREATE OR REPLACE AGENT FLOOD_ANALYTICS.FLOOD.FLOOD_RISK_AGENT
FROM SPECIFICATION $$
{
  "models": {"orchestration": "auto"},
  "orchestration": {"budget": {"seconds": 900, "tokens": 400000}},
  "instructions": {
    "orchestration": "You are a Valencia flood risk analyst. You have access to two tools: (1) query_flood_data for structured analysis of 2M+ buildings, 34 comarcas, flood risk scores, social vulnerability, and PATRICOVA flood zone designations; (2) search_policy_docs for finding information from Valencia's 2024 Flood Mitigation Plan including mitigation strategies, infrastructure projects, historical DANA impacts, and EU Floods Directive compliance.",
    "response": "Provide concise, data-driven answers. When referencing policy documents, cite the source. Clearly distinguish between quantitative findings and policy recommendations."
  },
  "tools": [
    {"tool_spec": {"type": "cortex_analyst_text_to_sql", "name": "query_flood_data", "description": "Query structured flood risk data for Valencia. Contains 2M+ building footprints with PATRICOVA flood zone designations (A1=frequent fluvial, A2=occasional flood, B=geomorphic risk, C=low risk), flood risk scores (0-100), Social Vulnerability Index (0-1), composite vulnerability scores, expected annual losses in euros, and comarca-level summaries."}},
    {"tool_spec": {"type": "cortex_search", "name": "search_policy_docs", "description": "Search Valencia 2024 Flood Mitigation Plan for mitigation strategies, historical DANA events, infrastructure projects, EU Floods Directive compliance, and nature-based solutions."}}
  ],
  "tool_resources": {
    "query_flood_data": {"execution_environment": {"query_timeout": 299, "type": "warehouse", "warehouse": "FLOOD_WH"}, "semantic_model_file": "@FLOOD_ANALYTICS.FLOOD.FLOOD_DATA_STAGE/semantic_model/flood_risk_model.yaml"},
    "search_policy_docs": {"search_service": "FLOOD_ANALYTICS.FLOOD.FLOOD_POLICY_SEARCH"}
  }
}
$$;

SHOW AGENTS IN SCHEMA FLOOD_ANALYTICS.FLOOD;

-- Lab 7: Export the Semantic Model to Apache Ossie
--
-- New to semantic models? Read [`docs/understanding-apache-ossie.md`](../docs/understanding-apache-ossie.md)
-- first — it explains what a semantic model is, how Snowflake Semantic Views and Cortex Analyst
-- implement one, and why an open interchange format like Apache Ossie matters, from first
-- principles.
--
-- So far, `flood_risk_model.yaml` has powered Cortex Analyst inside Snowflake. In this step
-- we generate an equivalent [Apache Ossie](https://ossie.apache.org/) document — an open,
-- portable representation of the same semantic model — and store it alongside the Cortex
-- Analyst YAML on our stage. Ossie lets us properly document the
-- fields that are hardest to interpret without local context: `DANA_RISK_SCORE` (a
-- Spain-specific weather phenomenon), `COMARCA_CODE` (Spain's INE administrative encoding), and
-- the `PARISH` column (which actually holds a comarca name, a naming artifact carried over
-- from the original Louisiana version of this lab).

-- Convert YAML to Snowflake Semantic View
-- Create a file format to read the YAML as a single string
CREATE OR REPLACE FILE FORMAT FLOOD_ANALYTICS.FLOOD.YAML_FF
  TYPE = CSV
  RECORD_DELIMITER = NONE
  FIELD_DELIMITER = NONE;

-- Read the YAML text from the staged file into a variable
SET yaml_spec = (
  SELECT $1
  FROM @FLOOD_ANALYTICS.FLOOD.FLOOD_DATA_STAGE/semantic_model/flood_risk_model.yaml
       (FILE_FORMAT => 'FLOOD_ANALYTICS.FLOOD.YAML_FF')
);

-- Create the semantic view (name comes from the YAML spec)
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'FLOOD_ANALYTICS.FLOOD',
  $yaml_spec
);

-- Convert Semantic View to Ossie
COPY INTO @FLOOD_ANALYTICS.FLOOD.FLOOD_DATA_STAGE/ossie/flood_ossie.yaml
FROM (
  SELECT SYSTEM$READ_OSSIE_YAML_FROM_SEMANTIC_VIEW('FLOOD_ANALYTICS.FLOOD.FLOOD_RISK_MODEL')
)
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = NONE COMPRESSION = NONE)
SINGLE = TRUE
OVERWRITE = TRUE;

-- Verify Ossie document on stage
LIST @FLOOD_ANALYTICS.FLOOD.FLOOD_DATA_STAGE/ossie/;

-- Print Ossie document from stage
SELECT $1 from @FLOOD_ANALYTICS.FLOOD.FLOOD_DATA_STAGE/ossie/flood_ossie.yaml;

-- > What you just did: the same business logic that powers Cortex Analyst in this lab
-- (dataset definitions, dimensions, metrics, relationships) now also exists as an open,
-- vendor-neutral Ossie document — with richer `ai_context` documentation for `DANA_RISK_SCORE`,
-- `COMARCA_CODE`, and the mislabeled `PARISH` column, all of which are easy to misinterpret
-- without local Valencian context. This document could be handed to any other Ossie-compatible
-- tool without redefining a single column.

-- Lab 8: Cleanup (Optional)
--
-- > Only run if you're finished with the lab.

-- Cleanup
-- DROP DATABASE IF EXISTS FLOOD_ANALYTICS;
-- DROP WAREHOUSE IF EXISTS FLOOD_WH;
SELECT 'Cleanup skipped. Uncomment lines above when ready.' AS STATUS;

-- Congratulations — Lab Complete!
--
--
-- Built for Snowflake World Tour 2026 | Data: Overture Maps / CARTO, Synthetic Flood Risk, Synthetic SVI, Valencia Flood Plan
