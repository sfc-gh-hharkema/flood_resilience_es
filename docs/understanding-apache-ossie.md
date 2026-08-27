# Understanding Apache Ossie (and How It Fits With Snowflake Semantic Views)

*A step-by-step explainer for anyone who has never heard of a "semantic model" before.*

This guide is written for the Valencia Flood Resilience Hands-On Lab. It builds up from first
principles — no prior knowledge of semantic models, Cortex Analyst, or Ossie assumed — and
ends with you generating and storing a real Apache Ossie document for this lab's flood risk
data.

---

## 1. The Problem: Data Has Structure, But Not Meaning

Earlier in this lab you loaded two Valencia-region datasets into Snowflake: a PATRICOVA-based
flood risk index and a social vulnerability index. If you looked at the raw columns, you saw
things like:

```
DANA_RISK_SCORE
FLUVIAL_RISK_SCORE
RPL_SOCIOECONOMIC
COMARCA_CODE
```

A flood risk analyst who works with Comunitat Valenciana data every day knows exactly what
these mean. But hand these column names to a new analyst from outside Spain — or to an AI
agent — with no other context, and you get guesses at best, confidently wrong answers at
worst.

`DANA_RISK_SCORE`, for instance, is not just "some weather number." **DANA** stands for
*Depresión Aislada en Niveles Altos* ("isolated depression at high levels") — a cold-drop
atmospheric phenomenon specific to the Iberian Peninsula that produces sudden, catastrophic
flash flooding. The October 2024 DANA killed over 220 people in the Valencia region. Nothing
in the column name `DANA_RISK_SCORE` tells you any of that — you'd need to already be a
Spanish meteorology or emergency-management expert to know what it means, let alone why it's
scored separately from ordinary river or coastal flooding.

This is not a Valencia-specific problem, and it is not unique to this dataset. **Every**
database has this gap: table and column names describe *structure* (this is a number, this is
a string, this joins to that), but not *business meaning* (this number represents a specific,
regionally significant weather phenomenon with a documented history of mass casualties).

A **semantic model** is the layer that closes this gap.

---

## 2. What Is a Semantic Model?

A semantic model is a description — written down, in a structured and machine-readable way —
of what your data actually *means*, sitting on top of your actual tables and columns.

Think of it like a restaurant menu with a glossary attached. The kitchen has raw ingredients
and preparation steps (your raw tables and SQL). The menu translates that into something a
customer — or now, an AI agent taking orders — can actually understand and act on: "paella
valenciana, saffron rice, rabbit and snails," not "SKU-88213, prep-code-4."

Every semantic model, regardless of which tool implements it, is built from the same handful
of building blocks:

- **Datasets** — a logical table or entity. Example: "buildings," "comarcas."
- **Fields / dimensions** — attributes you can group by or filter on. Example: "PATRICOVA
  flood zone," "comarca name."
- **Metrics / measures** — calculations with a defined aggregation. Example: "total expected
  annual loss," which is always a `SUM()`, never an average.
- **Relationships** — how datasets join to each other. Example: buildings join to comarcas on
  a shared key.

This isn't a new idea invented for AI. BI tools have had "semantic layers" for years — dbt's
Semantic Layer, LookML in Looker, Tableau's published data sources all do a version of this.
What's changed is that AI agents now need this layer just as much as dashboards do: an agent
generating SQL from a natural-language question has exactly the same "what does this column
mean" problem a new human analyst has.

---

## 3. Semantic Models in Snowflake Today: Semantic Views & Cortex Analyst

Snowflake has two closely related ways to define a semantic model, and you've already used
one of them in this lab.

### Semantic Views (the SQL object)

A **Semantic View** is a native Snowflake object, created with `CREATE SEMANTIC VIEW`, that
formally captures the building blocks from Section 2 directly in SQL: `logical_table`
definitions, `dimensions`, `time_dimensions`, `facts`/measures, and relationships between
tables. Once created, tools across Snowflake (including Cortex Analyst) can query it.

### Cortex Analyst YAML (the file-based form)

This lab uses the file-based sibling of the same idea:
[`semantic_model/flood_risk_model.yaml`](../semantic_model/flood_risk_model.yaml). Open it and
you'll recognize the same four building blocks:

```yaml
tables:
  - name: BUILDING_FLOOD_RISK
    dimensions:
      - name: FLOOD_ZONE
        expr: FLOOD_ZONE
        description: >
          PATRICOVA flood zone designation.
          A1 = Frequent fluvial + coastal flooding (no new development),
          A2 = Occasional flooding (elevated ground floor required),
          B  = Geomorphic flood risk (development with conditions),
          C  = Low risk (standard regulations).
        data_type: TEXT
    measures:
      - name: COMPOSITE_VULNERABILITY_SCORE
        expr: AVG(COMPOSITE_VULNERABILITY_SCORE)
        description: >
          Average composite vulnerability score (0-100): flood risk (40%) +
          social vulnerability (30%) + flood zone exposure (30%).
        data_type: NUMBER
        default_aggregation: avg
```

`FLOOD_ZONE` is a **dimension** — you group and filter by it.
`COMPOSITE_VULNERABILITY_SCORE` is a **measure** — it has a defined aggregation (`avg`) so
that no matter who asks for it, it's calculated consistently.

The file also defines **verified queries** — a Snowflake-specific enrichment on top of the
core semantic model concept:

```yaml
verified_queries:
  - name: most_vulnerable_comarcas
    question: "Which comarcas have the highest composite flood vulnerability score?"
    sql: |
      SELECT PARISH, AVG_COMPOSITE_SCORE, ...
```

A verified query is a pre-approved question/SQL pair. It exists purely to make Cortex Analyst
more reliable: instead of generating SQL from scratch every time, Cortex Analyst can recognize
"which comarcas are most vulnerable" as matching this verified pattern and answer with
confidence.

This is what lets Cortex Analyst turn a plain-English (or Spanish) question into correct,
governed SQL — because the meaning of every column and calculation was defined once, here, by
a human who understood the data.

> **Note:** you'll notice the underlying column is still literally named `PARISH` even though
> it holds a *comarca* name — that's a naming artifact carried over from the original
> US-Louisiana version of this lab, where the equivalent concept was a parish (Louisiana's
> county-equivalent). It's a good real-world example of exactly the kind of mismatch a good
> semantic model description — and Ossie's richer `ai_context` — should call out explicitly,
> which we'll do in Section 7.

---

## 4. Enter Apache Ossie: Why an Open Standard?

Everything in Section 3 is **Snowflake-specific**. That's fine if Snowflake is the only place
this business logic ever needs to live. But most organizations don't work that way — the same
team might also use dbt, Tableau, or another AI assistant, and each of those tools has its own
proprietary way to define "what does `FLOOD_ZONE` mean." Redefine it in five tools, and you get
five slightly different definitions that drift out of sync the moment someone updates one but
forgets the other four.

**Apache Ossie** is an open, vendor-neutral interchange format that solves exactly this
problem. It's currently incubating at the Apache Software Foundation
([ossie.apache.org](https://ossie.apache.org/)), with Snowflake as a co-founding, primary
contributor alongside 50+ other organizations including Databricks.

Ossie's stated goals:

- **Standardization** — one shared vocabulary for "dataset," "field," "metric," across tools.
- **Extensibility** — vendors can still attach their own proprietary metadata via
  `custom_extensions`, without breaking compatibility for everyone else.
- **Interoperability** — a semantic model defined once can move between AI and BI tools
  without hand-translating it each time.

A useful analogy: Ossie is to semantic models what **Parquet is to tabular data**, or what
**GeoJSON is to spatial data**. Nobody argues you shouldn't also use a database's native
storage format — Parquet exists so that different tools can read and write the *same file*
without agreeing on everything else. Ossie plays that role for semantic models.

---

## 5. How Ossie Relates to Snowflake Semantic Views

This is the single most important thing to take away from this document:

> **Ossie is a complement, not a replacement.** You still build and use a Snowflake Semantic
> View or Cortex Analyst YAML file — that's what makes Cortex Analyst work inside Snowflake.
> Ossie is an *additional*, portable representation of that same underlying model.

Every concept you already learned in Section 3 has a direct Ossie equivalent:

| Snowflake concept | Ossie equivalent |
|---|---|
| `logical_table` (Semantic View) / a `tables:` entry (Cortex Analyst YAML) | `OSIDataset` |
| a column / `time_dimension` | `OSIField` (with `dimension.is_time`) |
| a measure / fact | `OSIMetric` |
| a relationship / join | `OSIRelationship` |
| the whole Cortex Analyst YAML file | `OSIDocument` (tagged with the `SNOWFLAKE` dialect and vendor extension) |

There are two practical reasons you'd generate an Ossie document from a Snowflake model:

1. **Export / portability** — the same business logic defined for Cortex Analyst becomes
   readable by any other Ossie-compatible tool, with no manual re-definition. This matters
   even more for a regional dataset like this one — a PATRICOVA-based Valencia model is only
   useful to other Spanish regional planning tools if it's portable in the first place.
2. **Enrichment** — Ossie's `ai_context` field is richer than Cortex Analyst's plain
   `description` string. It supports structured `instructions`, `synonyms`, and `examples` —
   which is exactly what's needed to solve the opaque-column problem from Section 1. More on
   this next.

---

## 6. Anatomy of an Ossie Document

An Ossie document is a nested structure. Here's the shape, using this lab's simpler table,
`PARISH_FLOOD_SUMMARY` (recall from Section 3: despite the name, this holds one row per
*comarca*), as the running example:

```
OSIDocument                          (version, dialects, vendors)
  └── semantic_model: [OSISemanticModel]     (name: flood_risk_model)
        ├── datasets: [OSIDataset]           (name: PARISH_FLOOD_SUMMARY)
        │     └── fields: [OSIField]         (name: PARISH)
        ├── relationships: [OSIRelationship]
        └── metrics: [OSIMetric]             (name: TOTAL_EXPECTED_ANNUAL_LOSS)
```

In YAML, one dataset and one metric look like this — annotated inline:

```yaml
version: 0.2.0.dev0
dialects: [SNOWFLAKE]
semantic_model:
  - name: flood_risk_model
    datasets:
      - name: PARISH_FLOOD_SUMMARY
        source: FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY   # fully qualified table
        primary_key: [PARISH]
        fields:
          - name: PARISH
            expression:
              dialects:
                - dialect: SNOWFLAKE          # <- which SQL dialect this expression is written in
                  expression: PARISH
            datatype: String                  # <- portable logical type, not a Snowflake type
            description: Valencia comarca name (administrative district; column name is a legacy artifact from the source template — it is NOT a religious parish)
    metrics:
      - name: TOTAL_EXPECTED_ANNUAL_LOSS
        expression:
          dialects:
            - dialect: SNOWFLAKE
              expression: SUM(TOTAL_EXPECTED_ANNUAL_LOSS)
        datatype: Decimal
        description: Total expected annual loss in euros (€) from flood hazards, region-wide.
```

Every `expression` is wrapped in a `dialects:` list rather than a single string — this is what
makes Ossie portable. The same field could carry both a `SNOWFLAKE` expression and a
`BIGQUERY` or `ANSI_SQL` expression side by side, for tools that need it. Note also the
explicit `"in euros (€)"` in the description — currency is another thing that's easy to leave
implicit and easy to get wrong across regions.

---

## 7. The `ai_context` Superpower: Before and After

Cortex Analyst YAML gives you one field for documentation: `description`, a plain string.
Ossie gives you `ai_context`, which can be either a simple string **or** a structured object
with `instructions`, `synonyms`, and `examples`. This is where the opaque-column problem from
Section 1 actually gets solved.

Take `DANA_RISK_SCORE` — one of the most opaque columns in the Valencia flood risk dataset,
and the one most likely to confuse a non-Spanish-speaking analyst or a general-purpose AI
agent.

**Before** (a bare column, Cortex Analyst style):

```yaml
- name: DANA_RISK_SCORE
  data_type: NUMBER
```

An agent — or a human — sees a number with a cryptic name and no way to know it refers to a
specific, historically catastrophic weather phenomenon rather than a generic "storm" score.

**After** (Ossie, with structured `ai_context`):

```yaml
- name: DANA_RISK_SCORE
  datatype: Decimal
  description: >
    Risk score (0-100) for DANA-driven flash flooding — a cold-drop atmospheric
    phenomenon specific to the Iberian Peninsula.
  ai_context:
    instructions: >
      DANA stands for "Depresión Aislada en Niveles Altos" (isolated depression at high
      levels) — an atmospheric cutoff-low system that produces sudden, extreme rainfall
      and flash flooding, distinct from ordinary fluvial or coastal flooding. The October
      2024 DANA caused over 220 deaths in the Valencia region and is the primary
      historical reference point for this score. Do not conflate this with generic storm
      or hurricane risk — DANA events are a distinct meteorological category unique to
      this region.
    synonyms:
      - "cold drop risk"
      - "gota fría risk"
      - "flash flood risk (DANA)"
    examples:
      - "Which comarcas have the highest DANA risk score?"
      - "How does DANA risk compare to fluvial flood risk in this comarca?"
  custom_extensions:
    - vendor_name: COMMON
      data: '{"region": "Comunitat Valenciana", "reference_event": "October 2024 DANA"}'
```

Now an agent reading this document knows not just what the column is called, but what it
*means*, what historical event grounds it, and what it should never be confused with. This is
the entire value proposition of Ossie in one example: the same rigor Cortex Analyst applies to
dimensions and measures, extended with richer, more structured context — and portable to any
tool that reads Ossie documents.

The same treatment applies to `COMARCA_CODE` (Spain's INE administrative encoding — first two
digits are the province, e.g. `46` for Valencia, `03` for Alicante, `12` for Castellón; the
remaining three digits number the comarca) and to the mislabeled `PARISH` column mentioned in
Section 3, where `ai_context.instructions` can explicitly flag the naming mismatch so an agent
doesn't describe results using the wrong administrative term.

---

## 8. Hands-On: Generate and Store an Ossie Document

This is Lab 7D in the notebook. The steps below mirror what you'll run there.

1. **Install the Ossie Python package** (Pydantic v2 models for constructing and validating
   documents):
   ```python
   %pip install apache-ossie --quiet
   ```

2. **Construct the document** in Python, using the same tables you already built:
   ```python
   from ossie import (
       OSIDocument, OSISemanticModel, OSIDataset, OSIField,
       OSIMetric, OSIRelationship, OSIExpression, OSIDialectExpression,
       OSIDialect, OSIDataType, OSIAIContextObject,
   )

   comarca_dataset = OSIDataset(
       name="PARISH_FLOOD_SUMMARY",
       source="FLOOD_ANALYTICS.FLOOD.PARISH_FLOOD_SUMMARY",
       primary_key=["PARISH"],
       fields=[
           OSIField(
               name="PARISH",
               expression=OSIExpression(dialects=[
                   OSIDialectExpression(dialect=OSIDialect.SNOWFLAKE, expression="PARISH")
               ]),
               datatype=OSIDataType.STRING,
               description=(
                   "Valencia comarca name (administrative district). Column name is a "
                   "legacy artifact from the source template — not a religious parish."
               ),
           ),
       ],
   )

   doc = OSIDocument(
       dialects=[OSIDialect.SNOWFLAKE],
       semantic_model=[
           OSISemanticModel(
               name="flood_risk_model",
               description="Valencia flood vulnerability analysis model.",
               datasets=[comarca_dataset],
           )
       ],
   )
   ```

3. **Serialize and write** the document:
   ```python
   with open("flood_risk_model.osi.yaml", "w") as f:
       f.write(doc.to_osi_yaml())
   ```

4. **Upload to a Snowflake stage** alongside the Cortex Analyst semantic model:
   ```sql
   PUT file://flood_risk_model.osi.yaml @FLOOD_ANALYTICS.FLOOD.FLOOD_DATA_STAGE/ossie/ OVERWRITE=TRUE;
   ```

5. **Verify**:
   ```sql
   LIST @FLOOD_ANALYTICS.FLOOD.FLOOD_DATA_STAGE/ossie/;
   ```

You now have two representations of the same business logic living side by side: the Cortex
Analyst YAML that powers this lab's agent, and an open, portable Ossie document that could be
handed to any other Ossie-compatible tool without redefining a single column — including the
DANA methodology and the comarca-naming caveat, both spelled out in full.

---

## 9. Glossary

| Term | Meaning |
|---|---|
| **Semantic model** | A structured, machine-readable description of what your data means — datasets, fields, metrics, relationships — sitting on top of raw tables. |
| **Dimension** | An attribute you group or filter by (e.g., PATRICOVA flood zone, comarca). |
| **Measure / metric** | A calculation with a defined aggregation (e.g., total expected annual loss = `SUM()`). |
| **Semantic View** | Snowflake's native SQL object for defining a semantic model (`CREATE SEMANTIC VIEW`). |
| **Cortex Analyst** | Snowflake's natural-language-to-SQL service, powered by a semantic model (YAML or Semantic View). |
| **Verified query** | A pre-approved question/SQL pair used to ground Cortex Analyst's answers. |
| **Apache Ossie** | An open, Apache-Incubator semantic model interchange format; complements (does not replace) Snowflake's native semantic model tools. |
| **`OSIDocument`** | The root object of an Ossie file. |
| **`ai_context`** | Ossie's structured field for AI-facing documentation: `instructions`, `synonyms`, `examples`. |
| **Dialect** | The SQL flavor an expression is written in (e.g., `SNOWFLAKE`, `ANSI_SQL`, `BIGQUERY`) — Ossie expressions can carry more than one. |
| **DANA** | *Depresión Aislada en Niveles Altos* — a cold-drop atmospheric phenomenon causing severe flash flooding on the Iberian Peninsula. |
| **PATRICOVA** | *Plan de Acción Territorial de carácter Sectorial sobre Prevención del Riesgo de Inundación en la Comunitat Valenciana* — the Valencian regional flood-risk zoning plan (zones A1/A2/B/C). |
| **Comarca** | A traditional Spanish administrative/geographic subdivision grouping several municipalities — the Valencian equivalent of a US county. |

## References

- Apache Ossie spec: [github.com/apache/ossie](https://github.com/apache/ossie)
- Apache Ossie website: [ossie.apache.org](https://ossie.apache.org/)
- Ossie Python package: `apache-ossie` on PyPI
- Snowflake Semantic Views documentation: see Snowsight docs for `CREATE SEMANTIC VIEW`
- This lab's semantic model: [`semantic_model/flood_risk_model.yaml`](../semantic_model/flood_risk_model.yaml)
