import streamlit as st
import pandas as pd
import plotly.express as px
from sqlalchemy import create_engine

# Konfiguration des Dashboards
st.set_page_config(
    page_title="Insurance Claims & Risk Analytics",
    page_icon="📊",
    layout="wide"
)

# Titel und Beschreibung
st.title("Insurance Claims & Risk Analytics")

st.subheader("Interaktives Versicherungsdashboard")

st.markdown("""
Analyse der Schadenhäufigkeit, Schadenkosten
und regionalen Risikostrukturen im
Kfz-Versicherungsportfolio.
""")

st.divider()

from sqlalchemy.engine import URL

# Verbindung zur PostgreSQL-Datenbank
@st.cache_resource
def get_engine():
    config = st.secrets["postgres"]

    url = URL.create(
        drivername="postgresql+psycopg2",
        username=config["user"],
        password=config["password"],
        host=config["host"],
        port=config["port"],
        database=config["database"]
    )

    return create_engine(url)

# Datenbankverbindung und SQL-Sicht testen
engine = get_engine()

kpi_df = pd.read_sql(
    "SELECT * FROM analytics.v_kpi_summary",
    engine
)

# Deutsche Zahlenformatierung
def format_de(value, decimals=0):
    return f"{value:,.{decimals}f}".replace(
        ",", "X"
    ).replace(".", ",").replace("X", ".")


# Zentrale Versicherungskennzahlen
kpi = kpi_df.iloc[0]

st.header("Portfolioübersicht")

# Erste KPI-Reihe
col1, col2, col3, col4 = st.columns(4)

col1.metric(
    "Versicherungsverträge",
    format_de(kpi["anzahl_vertraege"])
)

col2.metric(
    "Gemeldete Schäden",
    format_de(kpi["anzahl_schaeden"])
)

col3.metric(
    "Erfasste Schadenkosten",
    format_de(kpi["erfasste_schadenkosten"] / 1e6, 2)
    + " Mio. €"
)

col4.metric(
    "Schäden je 100 Expositionsjahre",
    format_de(kpi["schaeden_je_100_expositionsjahre"], 2)
)

# Zweite KPI-Reihe
col5, col6, col7 = st.columns(3)

col5.metric(
    "Gesamte Exposition",
    format_de(kpi["gesamte_exposition"], 2)
)

col6.metric(
    "Durchschnittliche erfasste Schadenhöhe",
    format_de(kpi["durchschnittliche_erfasste_schadenhoehe"], 2)
    + " €"
)

col7.metric(
    "Erfasste Kosten je Expositionsjahr",
    format_de(kpi["erfasste_kosten_je_expositionsjahr"], 2)
    + " €"
)

st.caption(
    "Hinweis: Die Schadenkosten basieren auf den "
    "zugeordneten Schadeneinträgen."
)

st.divider()

# Regionale Risikodaten aus PostgreSQL laden
regional_df = pd.read_sql(
    "SELECT * FROM analytics.v_regional_risk",
    engine
)

# Risikokategorien definieren
regional_df["Risikokategorie"] = regional_df[
    "schaeden_je_100_expositionsjahre"
].apply(
    lambda x: "Hoch" if x > 12
    else "Mittel" if x >= 10
    else "Niedrig"
)

# Interaktive Filter in der Seitenleiste
st.sidebar.header("Filteroptionen")

# Auswahl der Regionen vereinfachen
all_regions = sorted(regional_df["region"].unique())

select_all = st.sidebar.checkbox(
    "Alle Regionen auswählen",
    value=True
)

if select_all:
    selected_regions = all_regions
else:
    selected_regions = st.sidebar.multiselect(
        "Regionen auswählen",
        options=all_regions
    )

selected_risks = st.sidebar.multiselect(
    "Risikokategorie auswählen",
    options=["Hoch", "Mittel", "Niedrig"],
    default=["Hoch", "Mittel", "Niedrig"]
)

# Daten anhand der Auswahl filtern
filtered_df = regional_df[
    (regional_df["region"].isin(selected_regions)) &
    (regional_df["Risikokategorie"].isin(selected_risks))
]


st.header("Regionale Risikoanalyse")

col1, col2 = st.columns(2)

# Schadenhäufigkeit nach Region
fig_frequency = px.bar(
    filtered_df,
    x="schaeden_je_100_expositionsjahre",
    y="region",
    orientation="h",
    color="schaeden_je_100_expositionsjahre",
    color_continuous_scale="RdYlGn_r",
    title="Schadenhäufigkeit nach Region",
    labels={
        "region": "Region",
        "schaeden_je_100_expositionsjahre":
            "Schäden je 100 Expositionsjahre"
    }
)

fig_frequency.update_layout(
    yaxis=dict(categoryorder="total ascending"),
    coloraxis_showscale=False,
    height=650
)

col1.plotly_chart(
    fig_frequency,
    use_container_width=True
)

# Erfasste Schadenkosten nach Region
fig_cost = px.bar(
    filtered_df,
    x="erfasste_schadenkosten",
    y="region",
    orientation="h",
    color_discrete_sequence=["#3478B8"],
    title="Erfasste Schadenkosten nach Region",
    labels={
        "region": "Region",
        "erfasste_schadenkosten": "Schadenkosten (€)"
    }
)

fig_cost.update_layout(
    yaxis=dict(categoryorder="total ascending"),
    height=650
)

col2.plotly_chart(
    fig_cost,
    use_container_width=True
)

st.divider()

# Wirtschaftliche Risikoanalyse

st.header("Wirtschaftliche Risikoanalyse")

# Erfasste Schadenkosten je Expositionsjahr berechnen
economic_df = filtered_df.copy()

economic_df["kosten_je_expositionsjahr"] = (
    economic_df["erfasste_schadenkosten"]
    / economic_df["gesamte_exposition"].replace(0, float("nan"))
)

col1, col2 = st.columns(2)

# Durchschnittliche erfasste Schadenhöhe
with col1:

    fig_severity = px.bar(
        economic_df.sort_values(
            "durchschnittliche_erfasste_schadenhoehe"
        ),
        x="durchschnittliche_erfasste_schadenhoehe",
        y="region",
        orientation="h",
        title="Durchschnittliche erfasste Schadenhöhe",
        color_discrete_sequence=["#8055A5"],
        labels={
            "durchschnittliche_erfasste_schadenhoehe":
                "Durchschnittliche Schadenhöhe (€)",
            "region": "Region"
        },
        height=650
    )

    st.plotly_chart(fig_severity, use_container_width=True)

# Erfasste Schadenkosten je Expositionsjahr
with col2:

    fig_exposure_cost = px.bar(
        economic_df.sort_values("kosten_je_expositionsjahr"),
        x="kosten_je_expositionsjahr",
        y="region",
        orientation="h",
        title="Erfasste Schadenkosten je Expositionsjahr",
        color_discrete_sequence=["#E69F35"],
        labels={
            "kosten_je_expositionsjahr":
                "Kosten je Expositionsjahr (€)",
            "region": "Region"
        },
        height=650
    )

    st.plotly_chart(fig_exposure_cost, use_container_width=True)

st.caption(
    "Die Kostenkennzahlen basieren ausschließlich "
    "auf den zugeordneten Schadeneinträgen."
)

st.divider()


# Datenqualität und Datenabdeckung

st.header("Datenqualität und Datenabdeckung")

st.write(
    "Überwachung der Vollständigkeit und "
    "Verlässlichkeit der Versicherungsdaten."
)

# Schadenverträge ohne Kostenangabe
missing_costs = int(
    kpi_df.iloc[0]["schadenvertraege_ohne_kostenangabe"]
)

col1, col2 = st.columns(2)

with col1:
    st.metric(
        "Analysierte Verträge",
        f"{int(kpi_df.iloc[0]['anzahl_vertraege']):,}".replace(",", ".")
    )

with col2:
    st.metric(
        "Schadenverträge ohne Kostenangabe",
        f"{missing_costs:,}".replace(",", ".")
    )

# Hinweise zur Datenqualität
st.warning(
    "Nicht für alle Verträge mit gemeldeten Schäden "
    "liegen Schadenkosten vor. Die finanziellen "
    "Kennzahlen sind daher nur eingeschränkt "
    "interpretierbar."
)

st.info(
    "Fehlende Schadenkosten wurden nicht durch "
    "Nullwerte ersetzt."
)

st.divider()


# Management Insights und Handlungsempfehlungen

st.header("Management Insights")

st.subheader("Zentrale Erkenntnisse")

st.markdown("""
- **Corse:** Höchste Schadenhäufigkeit im Portfolio.
- **Champagne-Ardenne:** Höchste durchschnittliche 
  erfasste Schadenhöhe und höchste erfasste 
  Schadenkosten je Expositionsjahr.
- **Centre:** Höchste erfasste Gesamtschadenkosten 
  trotz vergleichsweise niedriger Schadenhäufigkeit.
- **Datenqualität:** Fehlende Schadenkosten begrenzen 
  die Aussagekraft der finanziellen Risikoanalyse.
""")

st.subheader("Handlungsempfehlungen")

st.markdown("""
- Regionale Risikostrukturen regelmäßig überwachen.
- Risikoadäquate Tarifanpassungen prüfen.
- Regionen mit hohen Schadenkosten gezielt untersuchen.
- Die Vollständigkeit der Schadendaten verbessern.
- Statistische Risikomodelle zur Unterstützung 
  datenbasierter Entscheidungen einsetzen.
""")

st.caption(
    "Die Erkenntnisse beziehen sich auf das "
    "Gesamtportfolio und sind unabhängig von den Filtern."
)

st.divider()

# Projektinformationen

st.caption(
    "Insurance Claims & Risk Analytics | "
    "Python · PostgreSQL · Excel · Streamlit · Plotly"
)