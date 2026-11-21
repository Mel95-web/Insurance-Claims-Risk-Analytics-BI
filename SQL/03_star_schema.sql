-- ============================================================
-- Insurance Claims & Risk Analytics | PostgreSQL
-- 03 – Data Warehouse: Sternschema (Star Schema)
-- ============================================================
-- Voraussetzung: 01_create_tables.sql ausgeführt und CSV-Daten importiert.
-- Das Skript kann mehrfach ausgeführt werden: Tabellen werden nur
-- angelegt, wenn sie fehlen, und vorhandene Zeilen werden nicht doppelt
-- eingefügt (ON CONFLICT DO NOTHING).

-- Separates Schema für analytische Datenmodelle
CREATE SCHEMA IF NOT EXISTS analytics;


-- ============================================
-- Dimensionstabellen
-- ============================================

-- Dimension: Region

CREATE TABLE IF NOT EXISTS analytics.dim_region (
    region_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    region VARCHAR(100) NOT NULL UNIQUE
);

INSERT INTO analytics.dim_region (region)
SELECT DISTINCT region
FROM public.insurance_frequency
WHERE region IS NOT NULL
ORDER BY region
ON CONFLICT (region) DO NOTHING;


-- Dimension: Fahrerprofil

CREATE TABLE IF NOT EXISTS analytics.dim_driver (
    driver_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    drivage INTEGER NOT NULL UNIQUE
);

INSERT INTO analytics.dim_driver (drivage)
SELECT DISTINCT drivage
FROM public.insurance_frequency
WHERE drivage IS NOT NULL
ORDER BY drivage
ON CONFLICT (drivage) DO NOTHING;


-- Dimension: Fahrzeugprofil

CREATE TABLE IF NOT EXISTS analytics.dim_vehicle (
    vehicle_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehage INTEGER NOT NULL,
    vehpower INTEGER NOT NULL,
    vehbrand VARCHAR(50) NOT NULL,
    vehgas VARCHAR(50) NOT NULL,
    UNIQUE (vehage, vehpower, vehbrand, vehgas)
);

INSERT INTO analytics.dim_vehicle (
    vehage, vehpower, vehbrand, vehgas
)
SELECT DISTINCT vehage, vehpower, vehbrand, vehgas
FROM public.insurance_frequency
ON CONFLICT (vehage, vehpower, vehbrand, vehgas) DO NOTHING;


-- Dimension: Wohngebiet und Bevölkerungsdichte

CREATE TABLE IF NOT EXISTS analytics.dim_area (
    area_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    area VARCHAR(10) NOT NULL,
    density INTEGER NOT NULL,
    UNIQUE (area, density)
);

INSERT INTO analytics.dim_area (area, density)
SELECT DISTINCT area, density
FROM public.insurance_frequency
ON CONFLICT (area, density) DO NOTHING;


-- Dimension: Bonus-Malus-System

CREATE TABLE IF NOT EXISTS analytics.dim_bonusmalus (
    bonusmalus_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bonusmalus INTEGER NOT NULL UNIQUE
);

INSERT INTO analytics.dim_bonusmalus (bonusmalus)
SELECT DISTINCT bonusmalus
FROM public.insurance_frequency
WHERE bonusmalus IS NOT NULL
ORDER BY bonusmalus
ON CONFLICT (bonusmalus) DO NOTHING;


-- Überprüfung aller Dimensionstabellen

SELECT 'dim_region' AS dimension,
       COUNT(*) AS anzahl
FROM analytics.dim_region

UNION ALL

SELECT 'dim_driver', COUNT(*)
FROM analytics.dim_driver

UNION ALL

SELECT 'dim_vehicle', COUNT(*)
FROM analytics.dim_vehicle

UNION ALL

SELECT 'dim_area', COUNT(*)
FROM analytics.dim_area

UNION ALL

SELECT 'dim_bonusmalus', COUNT(*)
FROM analytics.dim_bonusmalus;


-- ============================================
-- Faktentabelle
-- ============================================

-- Granularität: Ein Datensatz pro Versicherungsvertrag

CREATE TABLE IF NOT EXISTS analytics.fact_insurance (
    idpol VARCHAR(50) PRIMARY KEY,

    region_id INTEGER NOT NULL
        REFERENCES analytics.dim_region(region_id),

    driver_id INTEGER NOT NULL
        REFERENCES analytics.dim_driver(driver_id),

    vehicle_id INTEGER NOT NULL
        REFERENCES analytics.dim_vehicle(vehicle_id),

    area_id INTEGER NOT NULL
        REFERENCES analytics.dim_area(area_id),

    bonusmalus_id INTEGER NOT NULL
        REFERENCES analytics.dim_bonusmalus(bonusmalus_id),

    claimnb INTEGER,
    exposure DOUBLE PRECISION,
    claimamount NUMERIC(18, 2),
    recorded_claims INTEGER NOT NULL
);


-- Befüllung der Faktentabelle
-- Schadenkosten zunächst je Vertrag aggregieren,
-- um eine Vervielfachung der Vertragsdaten zu vermeiden.
-- Verträge ohne Schaden erhalten Kosten von 0 €;
-- Verträge mit Schaden, aber ohne erfassten Betrag behalten NULL.

WITH severity_aggregiert AS (
    SELECT
        idpol::TEXT AS idpol,
        SUM(claimamount) AS claimamount,
        COUNT(*) AS recorded_claims
    FROM public.insurance_severity
    GROUP BY idpol
)

INSERT INTO analytics.fact_insurance (
    idpol,
    region_id,
    driver_id,
    vehicle_id,
    area_id,
    bonusmalus_id,
    claimnb,
    exposure,
    claimamount,
    recorded_claims
)

SELECT
    f.idpol,
    r.region_id,
    d.driver_id,
    v.vehicle_id,
    a.area_id,
    b.bonusmalus_id,
    f.claimnb,
    f.exposure,
    CASE
        WHEN s.idpol IS NULL AND f.claimnb = 0 THEN 0
        ELSE s.claimamount
    END,
    COALESCE(s.recorded_claims, 0)

FROM public.insurance_frequency f

LEFT JOIN analytics.dim_region r
    ON f.region = r.region

LEFT JOIN analytics.dim_driver d
    ON f.drivage = d.drivage

LEFT JOIN analytics.dim_vehicle v
    ON f.vehage = v.vehage
    AND f.vehpower = v.vehpower
    AND f.vehbrand = v.vehbrand
    AND f.vehgas = v.vehgas

LEFT JOIN analytics.dim_area a
    ON f.area = a.area
    AND f.density = a.density

LEFT JOIN analytics.dim_bonusmalus b
    ON f.bonusmalus = b.bonusmalus

LEFT JOIN severity_aggregiert s
    ON f.idpol = s.idpol

ON CONFLICT (idpol) DO NOTHING;


-- Validierung der Faktentabelle

SELECT
    COUNT(*) AS anzahl_vertraege,
    COUNT(DISTINCT idpol) AS eindeutige_vertraege,
    SUM(claimnb) AS anzahl_schaeden,
    ROUND(SUM(exposure)::NUMERIC, 2) AS exposition,
    SUM(claimamount) AS erfasste_schadenkosten,
    SUM(recorded_claims) AS zugeordnete_schadeneintraege
FROM analytics.fact_insurance;

-- Interpretation:
-- Das Sternschema besteht aus einer Faktentabelle
-- und fünf Dimensionstabellen.
--
-- Alle 678.013 Versicherungsverträge wurden
-- vollständig und ohne Duplikate übernommen.
--
-- Die Faktentabelle enthält 36.102 gemeldete Schäden
-- und 26.444 zugeordnete Schadeneinträge.
--
-- Die nicht zugeordneten Schadeneinträge werden
-- bei den vertragsbezogenen Kostenanalysen nicht berücksichtigt.
--
-- Das Datenmodell bildet die Grundlage für
-- Business Intelligence und interaktive Dashboards.
