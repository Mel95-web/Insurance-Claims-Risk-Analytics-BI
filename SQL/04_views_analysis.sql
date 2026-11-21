-- ============================================================
-- Insurance Claims & Risk Analytics | PostgreSQL
-- 04 – Analytische Sichten (Views) und SQL-Analysen
-- ============================================================
-- Voraussetzung: 03_star_schema.sql ausgeführt.
-- Die Sichten werden mit CREATE OR REPLACE angelegt und können
-- jederzeit neu erstellt werden.


-- ============================================
-- Portfolio-Kennzahlen
-- ============================================

-- Versicherungskennzahlen berechnen
SELECT
    COUNT(*) AS anzahl_vertraege,
    SUM(claimnb) AS anzahl_schaeden,
    ROUND(SUM(exposure)::NUMERIC, 2) AS gesamte_exposition,
    ROUND(
        SUM(claimnb)::NUMERIC
        / NULLIF(SUM(exposure), 0)::NUMERIC * 100,
        2
    ) AS schaeden_je_100_expositionsjahre
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


-- ============================================
-- Erweiterte SQL-Analysen mit Window Functions
-- ============================================

-- Ranking der Regionen nach Schadenhäufigkeit

WITH regionale_kennzahlen AS (
    SELECT
        region,
        COUNT(*) AS anzahl_vertraege,
        SUM(claimnb) AS anzahl_schaeden,
        SUM(exposure) AS gesamte_exposition,
        SUM(claimnb)::NUMERIC
            / NULLIF(SUM(exposure), 0) * 100
            AS schaeden_je_100_expositionsjahre
    FROM insurance_frequency
    GROUP BY region
)
SELECT
    region,
    anzahl_vertraege,
    anzahl_schaeden,
    ROUND(schaeden_je_100_expositionsjahre::NUMERIC, 2)
    AS schaeden_je_100_expositionsjahre,
    RANK() OVER (
        ORDER BY schaeden_je_100_expositionsjahre DESC NULLS LAST
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
-- (Grundlage des Streamlit-Dashboards und des Excel-Blatts „Regionen“)

CREATE OR REPLACE VIEW analytics.v_regional_risk AS

WITH groesster_schaden AS (
    -- Größter einzelner Schadenbetrag je Region
    SELECT
        f.region,
        MAX(s.claimamount) AS groesster_einzelschaden
    FROM public.insurance_severity s
    JOIN public.insurance_frequency f
        ON s.idpol::TEXT = f.idpol
    GROUP BY f.region
)

SELECT
    v.region,

    COUNT(*) AS anzahl_vertraege,

    SUM(v.claimnb) AS anzahl_schaeden,

    ROUND(SUM(v.exposure)::NUMERIC, 2)
        AS gesamte_exposition,

    ROUND(
        (SUM(v.claimnb) * 100.0
        / NULLIF(SUM(v.exposure), 0))::NUMERIC, 2
    ) AS schaeden_je_100_expositionsjahre,

    SUM(v.claimamount)
        AS erfasste_schadenkosten,

    ROUND(
        SUM(v.claimamount)
        / NULLIF(SUM(v.recorded_claims), 0), 2
    ) AS durchschnittliche_erfasste_schadenhoehe,

    SUM(v.recorded_claims)
        AS erfasste_schadenbetraege,

    MAX(g.groesster_einzelschaden)
        AS groesster_einzelschaden

FROM analytics.v_insurance v
LEFT JOIN groesster_schaden g
    ON v.region = g.region
GROUP BY v.region;


-- Überprüfung der regionalen Sicht

SELECT *
FROM analytics.v_regional_risk
ORDER BY schaeden_je_100_expositionsjahre DESC;


-- Kennzahlen nach Risikosegment
-- (Fahreralter, Bonus-Malus und Fahrzeugalter; Grundlage des
-- Excel-Blatts „Segmente“)

CREATE OR REPLACE VIEW analytics.v_segment_risk AS

WITH segmente AS (

    SELECT
        1 AS merkmal_sortierung,
        'Fahreralter' AS merkmal,
        CASE
            WHEN drivage <= 25 THEN '18–25'
            WHEN drivage <= 35 THEN '26–35'
            WHEN drivage <= 45 THEN '36–45'
            WHEN drivage <= 55 THEN '46–55'
            WHEN drivage <= 65 THEN '56–65'
            ELSE '66+'
        END AS segment,
        CASE
            WHEN drivage <= 25 THEN 1
            WHEN drivage <= 35 THEN 2
            WHEN drivage <= 45 THEN 3
            WHEN drivage <= 55 THEN 4
            WHEN drivage <= 65 THEN 5
            ELSE 6
        END AS segment_sortierung,
        claimnb, exposure, claimamount, recorded_claims
    FROM analytics.v_insurance

    UNION ALL

    SELECT
        2,
        'Bonus-Malus',
        CASE
            WHEN bonusmalus <= 50 THEN '50'
            WHEN bonusmalus <= 75 THEN '51–75'
            WHEN bonusmalus <= 100 THEN '76–100'
            WHEN bonusmalus <= 125 THEN '101–125'
            WHEN bonusmalus <= 150 THEN '126–150'
            ELSE '151+'
        END,
        CASE
            WHEN bonusmalus <= 50 THEN 1
            WHEN bonusmalus <= 75 THEN 2
            WHEN bonusmalus <= 100 THEN 3
            WHEN bonusmalus <= 125 THEN 4
            WHEN bonusmalus <= 150 THEN 5
            ELSE 6
        END,
        claimnb, exposure, claimamount, recorded_claims
    FROM analytics.v_insurance

    UNION ALL

    SELECT
        3,
        'Fahrzeugalter',
        CASE
            WHEN vehage <= 1 THEN '0–1'
            WHEN vehage <= 3 THEN '2–3'
            WHEN vehage <= 5 THEN '4–5'
            WHEN vehage <= 10 THEN '6–10'
            WHEN vehage <= 20 THEN '11–20'
            ELSE '21+'
        END,
        CASE
            WHEN vehage <= 1 THEN 1
            WHEN vehage <= 3 THEN 2
            WHEN vehage <= 5 THEN 3
            WHEN vehage <= 10 THEN 4
            WHEN vehage <= 20 THEN 5
            ELSE 6
        END,
        claimnb, exposure, claimamount, recorded_claims
    FROM analytics.v_insurance
)

SELECT
    merkmal,
    segment,
    merkmal_sortierung,
    segment_sortierung,

    COUNT(*) AS anzahl_vertraege,

    ROUND(SUM(exposure)::NUMERIC, 2)
        AS gesamte_exposition,

    SUM(claimnb) AS anzahl_schaeden,

    SUM(recorded_claims) AS erfasste_schadenbetraege,

    ROUND(
        SUM(claimamount)
        / NULLIF(SUM(recorded_claims), 0), 2
    ) AS durchschnittliche_erfasste_schadenhoehe,

    ROUND(
        SUM(claimamount)
        / NULLIF(SUM(exposure)::NUMERIC, 0), 2
    ) AS erfasste_kosten_je_expositionsjahr,

    ROUND(
        (SUM(claimnb) * 100.0
        / NULLIF(SUM(exposure), 0))::NUMERIC, 2
    ) AS schaeden_je_100_expositionsjahre

FROM segmente
GROUP BY merkmal, segment, merkmal_sortierung, segment_sortierung;


-- Überprüfung der Segment-Sicht

SELECT *
FROM analytics.v_segment_risk
ORDER BY merkmal_sortierung, segment_sortierung;


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
-- Excel-Auswertungen und das Streamlit-Dashboard.
