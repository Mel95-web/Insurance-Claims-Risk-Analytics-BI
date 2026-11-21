-- ============================================================
-- Insurance Claims & Risk Analytics | PostgreSQL
-- 02 – Datenqualität und Abgleich der Vertrags-IDs
-- ============================================================
-- Voraussetzung: 01_create_tables.sql ausgeführt und CSV-Daten importiert.
-- Das Skript enthält ausschließlich Abfragen und verändert keine Daten.


-- Vorhandene Tabellen anzeigen
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;


-- Erste zehn Datensätze anzeigen
SELECT *
FROM insurance_frequency
LIMIT 10;

SELECT *
FROM insurance_severity
LIMIT 10;


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


-- Übereinstimmung der Vertrags-IDs zwischen beiden Tabellen prüfen
SELECT
    COUNT(*) AS anzahl_schadenbetraege,
    COUNT(f.idpol) AS zugeordnete_schadenbetraege,
    COUNT(*) - COUNT(f.idpol) AS nicht_zugeordnete_schadenbetraege
FROM insurance_severity s
LEFT JOIN insurance_frequency f
    ON s.idpol::TEXT = f.idpol;


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


-- Plausibilität: Exposition über einem Jahr und hohe Schadenanzahlen

SELECT
    COUNT(*) FILTER (WHERE exposure > 1) AS vertraege_exposition_ueber_1,
    MAX(exposure) AS maximale_exposition,
    COUNT(*) FILTER (WHERE claimnb > 4) AS vertraege_mehr_als_4_schaeden,
    MAX(claimnb) AS maximale_schadenanzahl
FROM insurance_frequency;


-- Interpretation:
-- 1.224 Verträge weisen eine Exposition über einem Jahr auf
-- (maximal 2,01), 9 Verträge mehr als vier Schäden.
-- Die Werte werden dokumentiert, aber nicht verändert
-- (siehe Notebook, Abschnitt 1.6).
