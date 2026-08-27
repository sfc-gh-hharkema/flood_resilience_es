# Spain Flood Vulnerability Solution — Snowflake Summit 2026 HOL

An end-to-end flood vulnerability analysis platform built on Snowflake, combining open geospatial data from Overture Maps, flood risk indices, and social vulnerability data to identify at-risk buildings across Comunitat Valenciana (Spain).

## What You Will Build

- A geospatial pipeline identifying **2M+ Valencia buildings** within PATRICOVA flood zones
- A **social vulnerability overlay** linking flood exposure to community resilience
- **Cortex AI document intelligence** to parse Valencia's Flood Mitigation Plan
- A **Cortex Agent** that answers questions using both structured data AND policy documents
- An interactive **Streamlit dashboard** with map visualizations and AI Q&A

## Snowflake Features Covered

| Feature | Purpose |
|---|---|
| Snowflake Marketplace | Overture Maps Buildings (2.3B global footprints) |
| Geospatial + H3 Functions | Spatial joins, hexagonal risk mapping |
| Internal Stages | Loading flood risk + social vulnerability CSV data |
| Cortex PARSE_DOCUMENT | Extracting text from flood policy PDFs |
| Cortex Search | Semantic search over policy documents |
| Cortex COMPLETE | AI-generated risk summaries |
| Cortex Agent | Unified Q&A over structured data + unstructured documents |
| Streamlit in Snowflake | Interactive 4-tab vulnerability dashboard |
| Dynamic Tables | Auto-refreshing risk alert pipeline |
| Apache Ossie | Open, portable semantic model interchange format |

> **New to semantic models?** Read [`docs/understanding-apache-ossie.md`](docs/understanding-apache-ossie.md) for a from-scratch explainer covering semantic models, Snowflake Semantic Views/Cortex Analyst, and Apache Ossie — no prior knowledge assumed.

---

## Repository Structure

```
flood-resilience/
├── notebooks/
│   └── flood_vulnerability_hol.ipynb       ← Main HOL notebook (Labs 1-8)
├── streamlit/
│   ├── .streamlit/
│   │   └── config.toml                    ← Snowflake brand theme
│   ├── flood_dashboard.py                 ← Streamlit app (pydeck maps + altair charts)
│   └── environment.yml                    ← Package dependencies
├── semantic_model/
│   └── flood_risk_model.yaml              ← Semantic model for Cortex Analyst
├── agent/
│   ├── flood_risk_agent_spec.json         ← Cortex Agent spec
│   └── create_agent.sql                   ← SQL to create the agent
├── data/
│   ├── flood_risk/
│   │   └── Flood_Risk_Valencia.csv        ← Synthetic flood risk index (~80 zones)
│   ├── social_vulnerability/
│   │   └── SVI_Valencia.csv               ← Synthetic social vulnerability (~80 zones)
│   ├── comarca_centroids/
│   │   └── Valencia_Comarca_Centroids.csv ← 34 comarca centroids (lat/lon)
│   └── policy_docs/
│       ├── Valencia_Flood_Mitigation_Plan_2024_Intro.pdf
│       └── Valencia_Flood_Mitigation_Plan_2024_Strategies.pdf
├── docs/
│   └── understanding-apache-ossie.md      ← Semantic models & Apache Ossie explainer
```

---

## Quick Start (Step by Step)

### Prerequisites

- Snowflake account with **ACCOUNTADMIN** role (trial accounts work)
- A web browser (Chrome recommended)

---

### Step 1 — Install Overture Maps Buildings from Marketplace

1. Log in to **Snowsight** (https://app.snowflake.com)
2. Click **Marketplace** in the left sidebar
3. Search for **"Overture Maps - Buildings"**
4. Find the listing by **CARTO** and click on it
5. Click **Get** and set the database name to **`OVERTURE_MAPS_BUILDINGS`**
6. Select **PUBLIC** role and click **Get** again

> **How to verify:** Go to **Data → Databases**. You should see `OVERTURE_MAPS_BUILDINGS` listed.

---

### Step 2 — Create a Git Workspace

1. In Snowsight, click **Projects** → **Workspaces**
2. Click **+** → **Git Workspace**
3. Set the **Repository URL** and create an API integration named `FLOODS`
4. Name the workspace `flood-resilience`
5. Open `notebooks/flood_vulnerability_hol.ipynb` and connect to a service

---

### Step 3 — Run the Notebook

Run cells top to bottom. Each lab section is marked with a heading.

| Lab | What it does | Time |
|---|---|---|
| Lab 1 | Setup database/warehouse + extract Valencia buildings | 3-5 min |
| Lab 2 | Load flood risk + social vulnerability data | 1 min |
| Lab 3 | Build flood risk tables + comarca summary | 2-4 min |
| Lab 4 | Dynamic table for real-time alerts | 1 min |
| Lab 5 | Upload policy PDFs + Cortex AI document intelligence | 2 min |
| Lab 7 | Streamlit dashboard + Cortex Agent deployment | 2 min |
| Lab 7D | Export semantic model to Apache Ossie | 3-5 min |

> **Total runtime:** ~15-20 minutes on a MEDIUM warehouse.

---

### Step 4 — Use the Dashboard

**4 tabs:**

| Tab | Content |
|---|---|
| Comarca Overview | Altair bar chart of flood zone exposure + bubble scatter |
| Building Explorer | Pydeck PolygonLayer with building footprints by vulnerability |
| H3 Heatmap | Pydeck H3HexagonLayer 2D hexagonal vulnerability heatmap |
| AI Insights | Ask Cortex AI any question about flood risk |

**Try these questions in the AI Insights tab:**
- *"Which comarca has the highest percentage of buildings in flood zones?"*
- *"What is the total expected annual loss for the top 5 most vulnerable comarcas?"*
- *"How does social vulnerability correlate with flood exposure?"*

---

### Step 5 — Use the Cortex Agent

The agent combines **structured data** + **unstructured policy documents**:

| Question | Tools Used |
|---|---|
| *"Which 5 comarcas have the highest flood vulnerability?"* | Structured data |
| *"What does the plan say about the barranco del Poyo project?"* | Policy docs |
| *"Which comarcas are most at risk and what EU funds are available?"* | Both tools |
| *"What happened during the 2024 DANA?"* | Policy docs |

---

## Data Sources

| Dataset | Source | License |
|---|---|---|
| Overture Maps Buildings | CARTO / Overture Maps Foundation | ODbL |
| Flood Risk Index | Synthetic (based on PATRICOVA zones) | N/A |
| Social Vulnerability Index | Synthetic (based on INE indicators) | N/A |
| Valencia Flood Mitigation Plan | Placeholder (English) | N/A |

---

## Architecture

```
MARKETPLACE              STAGES                     CORTEX AI
Overture Maps     →   Flood Risk CSV         →   PARSE_DOCUMENT
Buildings         →   SVI CSV                →   Cortex Search
                  →   Policy PDFs            →   Cortex COMPLETE
        ↓                  ↓                          ↓
              FLOOD_ANALYTICS.FLOOD schema
        ┌──────────────────────────────────┐
        │ BUILDINGS_VALENCIA               │
        │ FLOOD_RISK_VALENCIA  SVI_VALENCIA│
        │ BUILDING_FLOOD_RISK              │
        │ PARISH_FLOOD_SUMMARY             │
        │ H3_FLOOD_RISK_MAP                │
        │ FLOOD_RISK_ALERTS (Dynamic TBL)  │
        └──────────────────────────────────┘
                          ↓
              ┌────────────────────────┐
              │   CORTEX AGENT         │
              │   (FLOOD_RISK_AGENT)   │
              │                        │
              │  Tool 1: Analyst       │
              │  (structured SQL)      │
              │                        │
              │  Tool 2: Search        │
              │  (policy documents)    │
              └────────────────────────┘
                          ↓
              STREAMLIT DASHBOARD
              SNOWFLAKE INTELLIGENCE
```

---

## Lab Overview

| Lab | Topic | Time |
|---|---|---|
| 1 | Environment setup + Overture Buildings extraction | 10 min |
| 2 | Load flood risk + social vulnerability data | 10 min |
| 3 | Geospatial flood risk analysis (H3 spatial joins) | 20 min |
| 4 | Dynamic Tables for automated risk alerts | 10 min |
| 5 | Cortex AI — parse policy PDFs + semantic search | 20 min |
| 7 | Streamlit dashboard + Cortex Agent deployment | 10 min |
| 7D | Export semantic model to Apache Ossie | 10 min |
| 8 | Cleanup (optional) | — |

**Total: ~100 minutes**

---

*Built for Snowflake Summit 2026 | Data: Overture Maps / CARTO · Synthetic Flood Risk · Synthetic SVI · Valencia Flood Plan*
