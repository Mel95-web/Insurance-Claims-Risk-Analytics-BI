-- ============================================================
-- Insurance Claims & Risk Analytics | PostgreSQL
-- 05 – Datenexport für das Excel-Reporting
-- ============================================================
-- Voraussetzung: 04_views_analysis.sql ausgeführt.
--
-- Die \copy-Befehle werden mit psql aus dem Hauptordner des Projekts
-- ausgeführt und schreiben CSV-Dateien in den Ordner exports/:
--
--   mkdir -p exports
--   psql -d insurance_analytics -f SQL/05_export.sql
--
-- Alternative in pgAdmin: die jeweilige SELECT-Abfrage ausführen und das
-- Ergebnis über „Save results to file“ als CSV speichern.
--
-- Hinweis für Excel (deutsches Gebietsschema): Die CSV-Dateien verwenden
-- den Punkt als Dezimaltrennzeichen. Beim Import über
-- Daten → Aus Text/CSV das Dateiursprungs-Gebietsschema „Englisch (USA)“ wählen.

\echo 'Export der Portfolio-Kennzahlen'
\copy (SELECT * FROM analytics.v_kpi_summary) TO 'exports/kpi_summary.csv' WITH (FORMAT csv, HEADER true)

\echo 'Export der regionalen Kennzahlen'
\copy (SELECT * FROM analytics.v_regional_risk ORDER BY region) TO 'exports/regional_risk.csv' WITH (FORMAT csv, HEADER true)

\echo 'Export der Kennzahlen nach Risikosegment'
\copy (SELECT * FROM analytics.v_segment_risk ORDER BY merkmal_sortierung, segment_sortierung) TO 'exports/segment_risk.csv' WITH (FORMAT csv, HEADER true)
