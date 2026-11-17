
-- Tabelle für Versicherungsverträge und Schadenhäufigkeit
CREATE TABLE insurance_frequency (
    idpol BIGINT PRIMARY KEY,
    claimnb INTEGER,
    exposure DOUBLE PRECISION,
    vehpower INTEGER,
    vehage INTEGER,
    drivage INTEGER,
    bonusmalus INTEGER,
    vehbrand VARCHAR(20),
    vehgas VARCHAR(20),
    area VARCHAR(5),
    density INTEGER,
    region VARCHAR(10)
);

-- Tabelle für einzelne Schadenbeträge
CREATE TABLE insurance_severity (
    claim_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    idpol BIGINT,
    claimamount NUMERIC(15, 2)
);


-- Vorhandene Tabellen anzeigen
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;


-- Anzahl der importierten Versicherungsverträge
SELECT COUNT(*) AS anzahl_vertraege
FROM insurance_frequency;


-- Länge der Regionsspalte erhöhen

-- Vertrags-ID als Text speichern
ALTER TABLE insurance_frequency
ALTER COLUMN idpol TYPE VARCHAR(50)
USING idpol::VARCHAR(50);


-- Erste zehn Datensätze anzeigen
SELECT *
FROM insurance_frequency
LIMIT 10;


-- Anzahl der importierten Schadenbeträge prüfen
SELECT COUNT(*) AS anzahl_schadenbetraege
FROM insurance_severity;

-- Erste zehn Datensätze anzeigen
SELECT *
FROM insurance_severity
LIMIT 10;


-- Versicherungskennzahlen berechnen
SELECT
    COUNT(*) AS anzahl_vertraege,
    SUM(claimnb) AS anzahl_schaeden,
    ROUND(SUM(exposure)::NUMERIC, 2) AS gesamte_exposition,
    ROUND(
        SUM(claimnb)::NUMERIC
        / NULLIF(SUM(exposure), 0)::NUMERIC * 100,
        2
    ) AS schadenhaeufigkeit_prozent
FROM insurance_frequency;


-- Schadenhöhen und Gesamtschadenkosten analysieren
SELECT
    COUNT(*) AS anzahl_schadenbetraege,
    ROUND(AVG(claimamount), 2) AS durchschnittliche_schadenhoehe,
    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY claimamount)::NUMERIC,
        2
    ) AS mediane_schadenhoehe,
    ROUND(SUM(claimamount), 2) AS gesamte_schadenkosten,
    MAX(claimamount) AS hoechster_schaden
FROM insurance_severity;


-- Übereinstimmung der Vertrags-IDs zwischen beiden Tabellen prüfen
SELECT
    COUNT(*) AS anzahl_schadenbetraege,
    COUNT(f.idpol) AS zugeordnete_schadenbetraege,
    COUNT(*) - COUNT(f.idpol) AS nicht_zugeordnete_schadenbetraege
FROM insurance_severity s
LEFT JOIN insurance_frequency f
    ON s.idpol::TEXT = f.idpol;
	

-- Erweiterte SQL-Analysen mit Window Functions
-- Ranking der Regionen nach Schadenhäufigkeit

WITH regionale_kennzahlen AS (
    SELECT
        region,
        COUNT(*) AS anzahl_vertraege,
        SUM(claimnb) AS anzahl_schaeden,
        SUM(exposure) AS gesamte_exposition,
        SUM(claimnb)::NUMERIC
            / NULLIF(SUM(exposure), 0) * 100
            AS schadenhaeufigkeit_prozent
    FROM insurance_frequency
    GROUP BY region
)
SELECT
    region,
    anzahl_vertraege,
    anzahl_schaeden,
    ROUND(schadenhaeufigkeit_prozent::NUMERIC, 2)
    AS schadenhaeufigkeit_prozent,
    RANK() OVER (
        ORDER BY schadenhaeufigkeit_prozent DESC NULLS LAST
    ) AS risiko_rang
FROM regionale_kennzahlen
ORDER BY risiko_rang, region;


-- Interpretation:
-- Die Analyse umfasst 21 Regionen.
-- Mithilfe der Window Function RANK() werden
-- die Regionen nach ihrer Schadenhäufigkeit
-- absteigend eingestuft.
--
-- Die Schadenhäufigkeit berücksichtigt die
-- gesamte Versicherungsexposition und wird
-- als Anzahl der Schäden je 100 Expositionsjahre
-- dargestellt.
--
-- Die Ergebnisse zeigen regionale Unterschiede.
-- Für eine belastbare Risikobewertung müssen
-- jedoch auch die Exposition und die
-- Zusammensetzung der Versicherten berücksichtigt
-- werden.


-- Anteil der Regionen an der Gesamtschadenzahl
-- Window Function: SUM() OVER()

WITH regionale_schaeden AS (
    SELECT
        region,
        COUNT(*) AS anzahl_vertraege,
        SUM(claimnb) AS anzahl_schaeden
    FROM insurance_frequency
    GROUP BY region
)
SELECT
    region,
    anzahl_vertraege,
    anzahl_schaeden,
    SUM(anzahl_schaeden) OVER ()
        AS gesamte_schaeden,
    ROUND(
        anzahl_schaeden::NUMERIC * 100
        / NULLIF(SUM(anzahl_schaeden) OVER (), 0),
        2
    ) AS anteil_schaeden_prozent
FROM regionale_schaeden
ORDER BY anteil_schaeden_prozent DESC;


-- Interpretation:
-- Die Analyse zeigt den Anteil jeder Region
-- an der Gesamtzahl von 36.102 Schäden.
--
-- Die Region Centre weist mit 25,49 %
-- den höchsten Anteil an allen Schäden auf.
--
-- Ein hoher Anteil an der Gesamtschadenzahl
-- bedeutet jedoch nicht automatisch eine
-- hohe Schadenhäufigkeit.
--
-- Für die Risikobewertung ist daher die
-- Schadenhäufigkeit unter Berücksichtigung
-- der Versicherungsexposition entscheidend.
--
-- Die Window Function SUM() OVER () ermöglicht
-- die Berechnung des Gesamtwerts, ohne die
-- einzelnen Regionen zusammenzufassen.


-- Erweiterte Datenqualitätsprüfung
-- Prüfung der IDpol-Eindeutigkeit

SELECT
    'insurance_frequency' AS tabelle,
    COUNT(*) AS anzahl_zeilen,
    COUNT(DISTINCT idpol) AS eindeutige_ids,
    COUNT(*) - COUNT(DISTINCT idpol)
        AS zusaetzliche_id_vorkommen,
    COUNT(*) FILTER (WHERE idpol IS NULL)
        AS fehlende_ids
FROM insurance_frequency

UNION ALL

SELECT
    'insurance_severity' AS tabelle,
    COUNT(*) AS anzahl_zeilen,
    COUNT(DISTINCT idpol) AS eindeutige_ids,
    COUNT(*) - COUNT(DISTINCT idpol)
        AS zusaetzliche_id_vorkommen,
    COUNT(*) FILTER (WHERE idpol IS NULL)
        AS fehlende_ids
FROM insurance_severity;


-- Interpretation:
-- Die Tabelle insurance_frequency enthält
-- 678.013 Datensätze mit eindeutigen Vertrags-IDs.
--
-- In insurance_severity liegen 26.639 Einträge
-- für 24.950 unterschiedliche Vertrags-IDs vor.
--
-- Die 1.689 zusätzlichen ID-Vorkommen sind
-- nicht automatisch als Datenfehler zu bewerten,
-- da einem Vertrag mehrere Schäden
-- zugeordnet sein können.
--
-- In beiden Tabellen fehlen keine Vertrags-IDs.
--
-- Vor der Zusammenführung der Tabellen muss
-- geprüft werden, ob alle IDs korrekt zugeordnet
-- werden können und keine unerwünschte
-- Vervielfachung von Vertragsdaten entsteht.


-- Beispiele nicht zugeordneter Vertrags-IDs

SELECT
    s.idpol,
    COUNT(*) AS anzahl_schadeneintraege,
    ROUND(SUM(s.claimamount)::NUMERIC, 2)
        AS gesamte_schadenkosten
FROM insurance_severity s
LEFT JOIN insurance_frequency f
    ON s.idpol::TEXT = f.idpol
WHERE f.idpol IS NULL
GROUP BY s.idpol
ORDER BY anzahl_schadeneintraege DESC, s.idpol
LIMIT 10;


-- Prüfung auffälliger Vertrags-IDs
-- Suche nach ähnlichen IDs in insurance_frequency

SELECT
    idpol,
    claimnb,
    exposure,
    region
FROM insurance_frequency
WHERE idpol LIKE '226251%'
   OR idpol LIKE '228213%'
   OR idpol LIKE '222753%'
   OR idpol LIKE '222036%'
   OR idpol LIKE '227784%'
   OR idpol LIKE '228677%'
ORDER BY idpol
LIMIT 50;


-- Prüfung der sechs auffälligen Vertrags-IDs
-- Exakter Vergleich zwischen beiden Tabellen

WITH auffaellige_ids AS (
    SELECT unnest(ARRAY[
        '2262511',
        '2282134',
        '2227533',
        '2220367',
        '2277846',
        '2286775'
    ]) AS idpol
)
SELECT
    a.idpol,
    COUNT(DISTINCT f.idpol) AS treffer_frequency,
    COUNT(s.idpol) AS eintraege_severity
FROM auffaellige_ids a
LEFT JOIN insurance_frequency f
    ON a.idpol = f.idpol
LEFT JOIN insurance_severity s
    ON a.idpol = s.idpol::TEXT
GROUP BY a.idpol
ORDER BY a.idpol;

-- ============================================
-- Data Warehouse: Sternschema (Star Schema)
-- ============================================

-- Separates Schema für analytische Datenmodelle

CREATE SCHEMA IF NOT EXISTS analytics;


-- Dimension: Region

CREATE TABLE analytics.dim_region (
    region_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    region VARCHAR(50) NOT NULL UNIQUE
);


-- Befüllung der Regionsdimension

INSERT INTO analytics.dim_region (region)
SELECT DISTINCT region
FROM public.insurance_frequency
WHERE region IS NOT NULL
ORDER BY region;


-- Überprüfung der Regionsdimension

SELECT *
FROM analytics.dim_region
ORDER BY region_id;


-- ============================================
-- Erstellung weiterer Dimensionstabellen
-- ============================================

-- Dimension: Fahrerprofil

CREATE TABLE analytics.dim_driver (
    driver_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    drivage INTEGER NOT NULL UNIQUE
);

INSERT INTO analytics.dim_driver (drivage)
SELECT DISTINCT drivage
FROM public.insurance_frequency
WHERE drivage IS NOT NULL
ORDER BY drivage;


-- Dimension: Fahrzeugprofil

CREATE TABLE analytics.dim_vehicle (
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
FROM public.insurance_frequency;


-- Dimension: Wohngebiet und Bevölkerungsdichte

CREATE TABLE analytics.dim_area (
    area_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    area VARCHAR(10) NOT NULL,
    density INTEGER NOT NULL,
    UNIQUE (area, density)
);

INSERT INTO analytics.dim_area (area, density)
SELECT DISTINCT area, density
FROM public.insurance_frequency;


-- Dimension: Bonus-Malus-System

CREATE TABLE analytics.dim_bonusmalus (
    bonusmalus_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bonusmalus INTEGER NOT NULL UNIQUE
);

INSERT INTO analytics.dim_bonusmalus (bonusmalus)
SELECT DISTINCT bonusmalus
FROM public.insurance_frequency
WHERE bonusmalus IS NOT NULL
ORDER BY bonusmalus;



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
-- Erstellung der Faktentabelle
-- ============================================

-- Granularität: Ein Datensatz pro Versicherungsvertrag

CREATE TABLE analytics.fact_insurance (
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
-- um eine Vervielfachung der Vertragsdaten zu vermeiden

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
    ON f.idpol = s.idpol;


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


-- ============================================
-- Analytische SQL-Sichten (Views)
-- ============================================

-- Zentrale Sicht für Business Intelligence

CREATE OR REPLACE VIEW analytics.v_insurance AS

SELECT
    f.idpol,
    r.region,
    d.drivage,
    v.vehage,
    v.vehpower,
    v.vehbrand,
    v.vehgas,
    a.area,
    a.density,
    b.bonusmalus,
    f.claimnb,
    f.exposure,
    f.claimamount,
    f.recorded_claims

FROM analytics.fact_insurance f

JOIN analytics.dim_region r
    ON f.region_id = r.region_id

JOIN analytics.dim_driver d
    ON f.driver_id = d.driver_id

JOIN analytics.dim_vehicle v
    ON f.vehicle_id = v.vehicle_id

JOIN analytics.dim_area a
    ON f.area_id = a.area_id

JOIN analytics.dim_bonusmalus b
    ON f.bonusmalus_id = b.bonusmalus_id;


-- Überprüfung der analytischen Sicht

SELECT *
FROM analytics.v_insurance
LIMIT 10;



-- Zentrale Versicherungskennzahlen

CREATE OR REPLACE VIEW analytics.v_kpi_summary AS

SELECT
    COUNT(*) AS anzahl_vertraege,

    SUM(claimnb) AS anzahl_schaeden,

    ROUND(SUM(exposure)::NUMERIC, 2)
        AS gesamte_exposition,

    ROUND(
        (SUM(claimnb) * 100.0
        / NULLIF(SUM(exposure), 0))::NUMERIC, 2
    ) AS schaeden_je_100_expositionsjahre,

    SUM(claimamount)
        AS erfasste_schadenkosten,

    ROUND(
        SUM(claimamount)
        / NULLIF(SUM(recorded_claims), 0), 2
    ) AS durchschnittliche_erfasste_schadenhoehe,

    ROUND(
        SUM(claimamount)
        / NULLIF(SUM(exposure)::NUMERIC, 0), 2
    ) AS erfasste_kosten_je_expositionsjahr,

    COUNT(*) FILTER (
        WHERE claimnb > 0 AND claimamount IS NULL
    ) AS schadenvertraege_ohne_kostenangabe

FROM analytics.fact_insurance;


-- Überprüfung der KPI-Sicht

SELECT *
FROM analytics.v_kpi_summary;


-- Regionale Risiko- und Kostenkennzahlen

CREATE OR REPLACE VIEW analytics.v_regional_risk AS

SELECT
    region,

    COUNT(*) AS anzahl_vertraege,

    SUM(claimnb) AS anzahl_schaeden,

    ROUND(SUM(exposure)::NUMERIC, 2)
        AS gesamte_exposition,

    ROUND(
        (SUM(claimnb) * 100.0
        / NULLIF(SUM(exposure), 0))::NUMERIC, 2
    ) AS schaeden_je_100_expositionsjahre,

    SUM(claimamount)
        AS erfasste_schadenkosten,

    ROUND(
        SUM(claimamount)
        / NULLIF(SUM(recorded_claims), 0), 2
    ) AS durchschnittliche_erfasste_schadenhoehe

FROM analytics.v_insurance
GROUP BY region;


-- Überprüfung der regionalen Sicht

SELECT *
FROM analytics.v_regional_risk
ORDER BY schaeden_je_100_expositionsjahre DESC;



-- Interpretation:
-- Die analytischen Sichten ermöglichen einen
-- standardisierten Zugriff auf das Sternschema.
--
-- Die durchschnittliche Schadenhäufigkeit beträgt
-- 10,07 Schäden je 100 Expositionsjahre.
--
-- Corse weist mit 13,99 die höchste beobachtete
-- regionale Schadenhäufigkeit auf.
--
-- Die zugeordneten Schadenkosten belaufen sich
-- auf rund 59,91 Millionen Euro.
--
-- Aufgrund unvollständiger Schadenkostendaten
-- sind die Kostenkennzahlen mit Vorsicht zu interpretieren.
--
-- Die SQL-Sichten dienen als Datenbasis für
-- Excel-Auswertungen und interaktive BI-Dashboards.


-- ============================================
-- Datenexport für Excel Business Intelligence
-- ============================================

SELECT *
FROM analytics.v_regional_risk
ORDER BY region;