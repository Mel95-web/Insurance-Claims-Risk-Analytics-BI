-- ============================================================
-- Insurance Claims & Risk Analytics | PostgreSQL
-- 01 – Tabellen für die unveränderten CSV-Quelldaten
-- ============================================================
-- Ausführungsreihenfolge: 01 → 02 → 03 → 04 → 05
-- Das Skript kann mehrfach ausgeführt werden (IF NOT EXISTS).

-- Tabelle für Versicherungsverträge und Schadenhäufigkeit
-- Die Vertrags-ID wird als Text gespeichert; Schadenbeträge werden
-- in den folgenden Skripten über idpol::TEXT zugeordnet.
CREATE TABLE IF NOT EXISTS insurance_frequency (
    idpol VARCHAR(50) PRIMARY KEY,
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
    region VARCHAR(100)
);

-- Tabelle für einzelne Schadenbeträge
CREATE TABLE IF NOT EXISTS insurance_severity (
    claim_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    idpol BIGINT,
    claimamount NUMERIC(15, 2)
);

-- Importhinweise (z. B. über pgAdmin oder psql):
-- insurance_frequency: CSV mit Kopfzeile, Trennzeichen Komma (,).
-- insurance_severity: CSV mit Kopfzeile, Trennzeichen Semikolon (;).
-- Für insurance_severity nur (idpol, claimamount) importieren;
-- claim_id wird automatisch erzeugt.
--
-- Beispiel mit psql (Pfade anpassen):
-- \copy insurance_frequency FROM 'data_raw/freMTPL2freq.csv' WITH (FORMAT csv, HEADER true)
-- \copy insurance_severity (idpol, claimamount) FROM 'data_raw/freMTPL2sev.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';')
--
-- Keine Fremdschlüsselbedingung auf insurance_severity.idpol:
-- 195 Schadenbeträge besitzen keine Zuordnung in insurance_frequency.

-- Kontrolle des Imports
SELECT
    (SELECT COUNT(*) FROM insurance_frequency) AS anzahl_vertraege,
    (SELECT COUNT(*) FROM insurance_severity) AS anzahl_schadenbetraege;
