import streamlit as st
from snowflake.snowpark.context import get_active_session
import pandas as pd
import pydeck as pdk
import altair as alt
import json

session = get_active_session()

st.set_page_config(page_title="Valencia Flood Vulnerability", page_icon="\U0001F30A", layout="wide")

st.markdown("""
<style>
    .block-container {padding-top: 1.5rem; padding-bottom: 1rem;}
    [data-testid="stMetric"] {
        background: #FFFFFF;
        border: 1px solid #E3E8EE;
        border-radius: 8px;
        padding: 12px 16px;
        box-shadow: 0 1px 4px rgba(0,0,0,0.06);
    }
    [data-testid="stMetricLabel"] {color: #6E7681; font-size: 0.8rem; font-weight: 500;}
    [data-testid="stMetricValue"] {color: #11567F; font-weight: 600;}
    .stTabs [data-baseweb="tab-list"] {gap: 8px;}
    .stTabs [data-baseweb="tab"] {
        background: #F4F7FA;
        border-radius: 8px 8px 0 0;
        padding: 8px 20px;
        border: 1px solid #E3E8EE;
    }
    .stTabs [aria-selected="true"] {
        background: #FFFFFF;
        border-bottom: 2px solid #29B5E8;
    }
    h1 {color: #11567F !important;}
    h2, h3 {color: #11567F !important;}
</style>
""", unsafe_allow_html=True)

st.markdown("# \U0001F30A Valencia Flood Vulnerability Dashboard")
st.markdown("**FEMA NRI \u00b7 CDC SVI \u00b7 Overture Maps Buildings \u00b7 Cortex AI** | *Real-time flood risk intelligence*")
st.markdown("---")

tab1, tab2, tab3, tab4 = st.tabs(["\U0001F4CA Comarca Overview", "\U0001F3E2 Building Explorer", "\U0001F5FA H3 Heatmap", "\U0001F916 AI Insights"])


@st.cache_data(ttl=300)
def load_parish_summary():
    return session.sql("""
        SELECT PARISH, TOTAL_BUILDINGS, BUILDINGS_IN_SFHA, PCT_IN_SFHA,
               AVG_NRI_RISK_SCORE, AVG_SVI_SCORE, AVG_COMPOSITE_SCORE,
               TOTAL_EXPECTED_ANNUAL_LOSS, BUILDING_EXPECTED_ANNUAL_LOSS,
               BUILDINGS_COASTAL_ZONE, BUILDINGS_RIVERINE_ZONE
        FROM FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY
        ORDER BY AVG_COMPOSITE_SCORE DESC
    """).to_pandas()


df_parish = load_parish_summary()

# ── TAB 1: Comarca Overview ────────────────────────────────────────────────────
with tab1:
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Comarcas", f"{len(df_parish)}")
    col2.metric("Total Buildings", f"{df_parish['TOTAL_BUILDINGS'].sum():,.0f}")
    col3.metric("In Flood Zones", f"{df_parish['BUILDINGS_IN_SFHA'].sum():,.0f}")
    col4.metric("Region-wide Annual Loss", f"€{df_parish['TOTAL_EXPECTED_ANNUAL_LOSS'].sum():,.0f}")

    st.markdown("")

    left, right = st.columns([1.2, 1])

    with left:
        chart_data = df_parish.head(15).copy()
        bar = alt.Chart(chart_data).mark_bar(
            cornerRadiusTopLeft=4, cornerRadiusTopRight=4,
            color=alt.Gradient(gradient="linear", stops=[
                alt.GradientStop(color="#E4584F", offset=0),
                alt.GradientStop(color="#29B5E8", offset=1)
            ], x1=0, x2=0, y1=1, y2=0)
        ).encode(
            x=alt.X("PARISH:N", sort="-y", title=None, axis=alt.Axis(labelAngle=-45, labelFontSize=10)),
            y=alt.Y("PCT_IN_SFHA:Q", title="% Buildings in Flood Zone"),
            tooltip=[
                alt.Tooltip("PARISH:N", title="Comarca"),
                alt.Tooltip("PCT_IN_SFHA:Q", title="% in Flood Zone", format=".1f"),
                alt.Tooltip("TOTAL_BUILDINGS:Q", title="Total Buildings", format=","),
            ]
        ).properties(height=350, title="Top 15 Comarcas by Flood Zone Exposure")

        st.altair_chart(bar, use_container_width=True)

    with right:
        scatter = alt.Chart(df_parish).mark_circle(opacity=0.7).encode(
            x=alt.X("AVG_NRI_RISK_SCORE:Q", title="NRI Risk Score"),
            y=alt.Y("AVG_SVI_SCORE:Q", title="Social Vulnerability Index"),
            size=alt.Size("TOTAL_BUILDINGS:Q", title="Buildings", scale=alt.Scale(range=[40, 400])),
            color=alt.Color("AVG_COMPOSITE_SCORE:Q", title="Composite Score",
                            scale=alt.Scale(range=["#29B5E8", "#11567F", "#E4584F"])),
            tooltip=[
                alt.Tooltip("PARISH:N"),
                alt.Tooltip("AVG_COMPOSITE_SCORE:Q", format=".1f", title="Composite"),
                alt.Tooltip("AVG_NRI_RISK_SCORE:Q", format=".1f", title="NRI"),
                alt.Tooltip("AVG_SVI_SCORE:Q", format=".3f", title="SVI"),
            ]
        ).properties(height=350, title="Risk vs Vulnerability (bubble = building count)")

        st.altair_chart(scatter, use_container_width=True)

    st.dataframe(
        df_parish.rename(columns={
            "PARISH": "Comarca", "TOTAL_BUILDINGS": "Buildings",
            "BUILDINGS_IN_SFHA": "In Flood Zone", "PCT_IN_SFHA": "% Flood Zone",
            "AVG_NRI_RISK_SCORE": "NRI Score", "AVG_SVI_SCORE": "SVI",
            "AVG_COMPOSITE_SCORE": "Composite", "TOTAL_EXPECTED_ANNUAL_LOSS": "Annual Loss",
        }).drop(columns=["BUILDING_EXPECTED_ANNUAL_LOSS", "BUILDINGS_COASTAL_ZONE", "BUILDINGS_RIVERINE_ZONE"]),
        use_container_width=True, height=350
    )


# ── TAB 2: Building Explorer ──────────────────────────────────────────────────
with tab2:
    col_a, col_b, col_c = st.columns([1, 1, 1])
    with col_a:
        parishes = ["(All)"] + sorted(df_parish["PARISH"].dropna().tolist())
        selected_parish = st.selectbox("Comarca", parishes)
    with col_b:
        risk_threshold = st.slider("Min Vulnerability Score", 0, 100, 60, step=5)
    with col_c:
        max_buildings = st.select_slider("Max buildings on map", options=[100, 250, 500, 1000], value=500)

    @st.cache_data(ttl=60)
    def load_buildings_geo(parish, threshold, limit):
        where_parish = f"AND r.PARISH = '{parish}'" if parish != "(All)" else ""
        return session.sql(f"""
            SELECT r.BUILDING_NAME, r.CLASS, r.FLOOD_ZONE, r.PARISH,
                   r.COMPOSITE_VULNERABILITY_SCORE, r.NRI_RISK_SCORE,
                   r.SVI_OVERALL, r.EXPECTED_ANNUAL_LOSS,
                   r.LATITUDE, r.LONGITUDE,
                   ST_ASGEOJSON(b.GEOMETRY) AS GEOJSON
            FROM FLOOD_ANALYTICS.FLOOD.BUILDING_FLOOD_RISK r
            JOIN FLOOD_ANALYTICS.FLOOD.BUILDINGS_VALENCIA b ON r.BUILDING_ID = b.ID
            WHERE r.COMPOSITE_VULNERABILITY_SCORE >= {threshold}
              {where_parish}
            ORDER BY r.COMPOSITE_VULNERABILITY_SCORE DESC
            LIMIT {limit}
        """).to_pandas()

    df_bldg = load_buildings_geo(selected_parish, risk_threshold, max_buildings)
    label = f"in {selected_parish}" if selected_parish != "(All)" else "region-wide"

    m1, m2, m3 = st.columns(3)
    m1.metric(f"Buildings {label}", f"{len(df_bldg):,}")
    if not df_bldg.empty:
        m2.metric("Avg Vulnerability", f"{df_bldg['COMPOSITE_VULNERABILITY_SCORE'].mean():.1f}")
        m3.metric("Max Vulnerability", f"{df_bldg['COMPOSITE_VULNERABILITY_SCORE'].max():.1f}")

    if not df_bldg.empty and "GEOJSON" in df_bldg.columns:
        geo_df = df_bldg.dropna(subset=["GEOJSON"]).copy()
        if not geo_df.empty:
            geo_df["coordinates"] = geo_df["GEOJSON"].apply(lambda g: json.loads(g)["coordinates"])
            geo_df["color_r"] = (geo_df["COMPOSITE_VULNERABILITY_SCORE"] / 100 * 255).clip(0, 255).astype(int)
            geo_df["color_g"] = ((1 - geo_df["COMPOSITE_VULNERABILITY_SCORE"] / 100) * 200).clip(0, 255).astype(int)
            geo_df["name"] = geo_df["BUILDING_NAME"].fillna("Unknown")
            geo_df["vuln"] = geo_df["COMPOSITE_VULNERABILITY_SCORE"].round(1)
            geo_df["zone"] = geo_df["FLOOD_ZONE"].fillna("N/A")
            geo_df["bclass"] = geo_df["CLASS"].fillna("N/A")
            geo_df["par"] = geo_df["PARISH"].fillna("N/A")

            polygon_layer = pdk.Layer(
                "PolygonLayer",
                geo_df[["coordinates", "color_r", "color_g", "name", "vuln", "zone", "bclass", "par"]],
                get_polygon="coordinates",
                get_fill_color="[color_r, color_g, 60, 200]",
                get_line_color=[255, 255, 255, 100],
                line_width_min_pixels=1,
                pickable=True,
                auto_highlight=True,
                highlight_color=[41, 181, 232, 160],
                extruded=False,
            )

            view = pdk.ViewState(
                latitude=geo_df["LATITUDE"].mean(),
                longitude=geo_df["LONGITUDE"].mean(),
                zoom=12,
                pitch=0,
                bearing=0,
            )

            tooltip = {
                "text": "Building: {name}\nClass: {bclass}\nComarca: {par}\nFlood Zone: {zone}\nVulnerability: {vuln}",
                "style": {"backgroundColor": "#11567F", "color": "#FFFFFF",
                          "fontSize": "12px", "borderRadius": "8px", "border": "1px solid #29B5E8"},
            }

            st.pydeck_chart(pdk.Deck(
                layers=[polygon_layer],
                initial_view_state=view,
                tooltip=tooltip,
                map_style="mapbox://styles/mapbox/dark-v10",
            ))

    if not df_bldg.empty:
        vuln_hist = alt.Chart(df_bldg).mark_bar(
            cornerRadiusTopLeft=3, cornerRadiusTopRight=3
        ).encode(
            x=alt.X("COMPOSITE_VULNERABILITY_SCORE:Q", bin=alt.Bin(maxbins=20), title="Vulnerability Score"),
            y=alt.Y("count():Q", title="Building Count"),
            color=alt.Color("COMPOSITE_VULNERABILITY_SCORE:Q", bin=alt.Bin(maxbins=20),
                            scale=alt.Scale(range=["#29B5E8", "#11567F", "#E4584F"]), legend=None),
        ).properties(height=200, title="Vulnerability Score Distribution")

        st.altair_chart(vuln_hist, use_container_width=True)

        st.dataframe(
            df_bldg.head(200).rename(columns={
                "BUILDING_NAME": "Name", "CLASS": "Type", "FLOOD_ZONE": "Zone",
                "COMPOSITE_VULNERABILITY_SCORE": "Vuln Score", "NRI_RISK_SCORE": "NRI",
                "SVI_OVERALL": "SVI", "EXPECTED_ANNUAL_LOSS": "Annual Loss", "PARISH": "Comarca"
            }).drop(columns=["ZONE_DESCRIPTION", "LATITUDE", "LONGITUDE", "GEOJSON"], errors="ignore"),
            use_container_width=True, height=300
        )
    else:
        st.info("No buildings found matching the selected criteria. Try lowering the threshold.")


# ── TAB 3: H3 Heatmap ────────────────────────────────────────────────────────
with tab3:
    st.markdown("Each hexagon is an **H3 resolution-6 cell** (~36 km\u00b2). Height and colour reflect average vulnerability.")

    @st.cache_data(ttl=300)
    def load_h3():
        return session.sql("""
            SELECT H3_INDEX_6, BUILDING_COUNT, BUILDINGS_AT_RISK,
                   AVG_VULNERABILITY, AVG_NRI_SCORE, AVG_SVI, TOTAL_EAL, PRIMARY_PARISH
            FROM FLOOD_ANALYTICS.FLOOD.H3_FLOOD_RISK_MAP
            ORDER BY AVG_VULNERABILITY DESC
            LIMIT 500
        """).to_pandas()

    df_h3 = load_h3()

    if not df_h3.empty:
        df_h3["COLOR_R"] = (df_h3["AVG_VULNERABILITY"] / 100 * 255).clip(0, 255).astype(int)
        df_h3["COLOR_G"] = ((1 - df_h3["AVG_VULNERABILITY"] / 100) * 180).clip(0, 255).astype(int)
        df_h3["COLOR_B"] = 60

        layer = pdk.Layer(
            "H3HexagonLayer",
            df_h3,
            get_hexagon="H3_INDEX_6",
            get_fill_color="[COLOR_R, COLOR_G, COLOR_B, 180]",
            extruded=False,
            pickable=True,
            auto_highlight=True,
        )

        view_state = pdk.ViewState(latitude=39.4, longitude=-0.5, zoom=7, pitch=0, bearing=0)

        tooltip = {
            "text": "Parish: {PRIMARY_PARISH}\nVulnerability: {AVG_VULNERABILITY}\nBuildings: {BUILDING_COUNT}\nAt Risk: {BUILDINGS_AT_RISK}\nAnnual Loss: ${TOTAL_EAL}",
            "style": {"backgroundColor": "#11567F", "color": "#FFFFFF",
                      "fontSize": "12px", "borderRadius": "8px"},
        }

        st.pydeck_chart(pdk.Deck(
            layers=[layer],
            initial_view_state=view_state,
            tooltip=tooltip,
            map_style="mapbox://styles/mapbox/dark-v10",
        ))

    st.markdown("---")
    c1, c2 = st.columns(2)

    with c1:
        if not df_h3.empty:
            df_h3["Risk Level"] = pd.cut(
                df_h3["AVG_VULNERABILITY"], bins=[0, 25, 50, 75, 100],
                labels=["Low", "Moderate", "High", "Critical"]
            )
            donut = alt.Chart(df_h3).mark_arc(innerRadius=50, cornerRadius=4).encode(
                theta=alt.Theta("count():Q"),
                color=alt.Color("Risk Level:N",
                                scale=alt.Scale(domain=["Low", "Moderate", "High", "Critical"],
                                                range=["#29B5E8", "#FFB647", "#11567F", "#E4584F"])),
                tooltip=["Risk Level:N", "count():Q"]
            ).properties(height=250, title="Hex Risk Distribution")
            st.altair_chart(donut, use_container_width=True)

    with c2:
        st.markdown("**Top 10 Highest-Risk Hexagons**")
        st.dataframe(
            df_h3.head(10)[["H3_INDEX_6", "PRIMARY_PARISH", "BUILDING_COUNT",
                            "BUILDINGS_AT_RISK", "AVG_VULNERABILITY", "TOTAL_EAL"]].rename(columns={
                "H3_INDEX_6": "H3 Cell", "PRIMARY_PARISH": "Parish",
                "BUILDING_COUNT": "Buildings", "BUILDINGS_AT_RISK": "At Risk",
                "AVG_VULNERABILITY": "Vuln", "TOTAL_EAL": "Annual Loss"
            }),
            use_container_width=True, height=300
        )


# ── TAB 4: AI Insights ───────────────────────────────────────────────────────
with tab4:
    st.markdown("Ask questions about Valencia flood vulnerability. Powered by **Snowflake Cortex AI**.")

    suggestions = [
        "Which comarca has the highest percentage of buildings in flood zones?",
        "What is the total expected annual loss for the top 5 most vulnerable comarcas?",
        "How does social vulnerability correlate with flood exposure?",
        "Which comarcas should be prioritised for emergency preparedness?",
    ]

    cols = st.columns(2)
    for i, q in enumerate(suggestions):
        with cols[i % 2]:
            st.markdown(f"*\U0001F4AC {q}*")

    user_question = st.text_input("Your question:", placeholder="e.g. Which parish has the most critical infrastructure at risk?")

    if st.button("Ask AI", type="primary") and user_question:
        safe_q = user_question.replace("'", "''")
        with st.spinner("Analysing with Cortex AI..."):
            result = session.sql(f"""
                SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', CONCAT(
                    'You are a Valencia flood risk expert. Answer concisely.\\n\\n',
                    'COMARCA DATA:\\n',
                    (SELECT LISTAGG(PARISH||': composite='||AVG_COMPOSITE_SCORE||
                        ', SVI='||AVG_SVI_SCORE||', '||PCT_IN_SFHA||'% in flood zone'||
                        ', loss=$'||TOTAL_EXPECTED_ANNUAL_LOSS, '\\n')
                     FROM (SELECT * FROM FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY
                           ORDER BY AVG_COMPOSITE_SCORE DESC LIMIT 20)),
                    '\\n\\nQUESTION: {safe_q}\\nANSWER:')) AS ANSWER
            """).to_pandas()
            st.success("**AI Response:**")
            st.write(result["ANSWER"].iloc[0])

    st.markdown("---")

    @st.cache_data(ttl=300)
    def load_kpis():
        return session.sql("""
            SELECT
              (SELECT PARISH FROM FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY ORDER BY AVG_COMPOSITE_SCORE DESC LIMIT 1) AS MOST_VULNERABLE,
              (SELECT PARISH FROM FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY ORDER BY PCT_IN_SFHA DESC LIMIT 1) AS MOST_IN_FLOOD_ZONE,
              (SELECT PARISH FROM FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY ORDER BY AVG_SVI_SCORE DESC LIMIT 1) AS HIGHEST_SVI,
              (SELECT PARISH FROM FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY ORDER BY TOTAL_EXPECTED_ANNUAL_LOSS DESC LIMIT 1) AS HIGHEST_EAL,
              (SELECT ROUND(SUM(TOTAL_EXPECTED_ANNUAL_LOSS),0) FROM FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY) AS STATEWIDE_EAL,
              (SELECT SUM(BUILDINGS_IN_SFHA) FROM FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY) AS TOTAL_SFHA_BLDGS
        """).to_pandas()

    kpis = load_kpis()
    k1, k2, k3 = st.columns(3)
    k4, k5, k6 = st.columns(3)
    k1.metric("Most Vulnerable Parish", kpis["MOST_VULNERABLE"].iloc[0])
    k2.metric("Most in Flood Zone", kpis["MOST_IN_FLOOD_ZONE"].iloc[0])
    k3.metric("Highest Social Vulnerability", kpis["HIGHEST_SVI"].iloc[0])
    k4.metric("Highest Annual Loss", kpis["HIGHEST_EAL"].iloc[0])
    k5.metric("Region-wide Annual Loss", f"€{kpis['STATEWIDE_EAL'].iloc[0]:,.0f}")
    k6.metric("Buildings in Flood Zones", f"{int(kpis['TOTAL_SFHA_BLDGS'].iloc[0]):,}")
