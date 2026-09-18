# Fabric Duplicate Semantic Model Governance App

This repository is a Fabric solution accelerator for identifying duplicate and overlapping Power BI semantic models, storing the results in Fabric tables, and presenting the findings through a Power BI report published as an App.

It is designed for a no-code end-user experience: users open the App in Fabric or Power BI, filter the results, and review duplicate candidates. Fabric admins own the scheduled scan and data refresh.

## What this provides

- A reusable analyzer engine for scoring duplicate and overlapping semantic models.
- A Fabric notebook that scans configured workspaces and writes results to Lakehouse tables.
- A synthetic sample-data notebook so admins can validate the report before scanning real workspaces.
- Lakehouse/Warehouse table schema guidance.
- Power BI report design guidance and starter DAX measures.
- Admin installation, operations, security, troubleshooting, and end-user guides.

## How data stays current

Admins schedule a Fabric Data Pipeline that runs the scan notebook. The notebook lists the configured workspaces, extracts semantic model metadata, calculates duplicate and overlap findings, and appends the latest results to governance tables. The Power BI report reads those tables, so end users simply open the App and see the latest completed scan.

End users do not write code, run notebooks, handle JSON, or use command-line tools.

## Architecture

```text
Power BI / Fabric APIs
        |
        v
Scheduled Fabric Pipeline
        |
        v
Fabric Notebook
        |
        v
Lakehouse or Warehouse tables
        |
        v
Power BI semantic model and report
        |
        v
Power BI / Fabric App for end users
```

## Repository layout

| Path | Purpose |
|---|---|
| `src\semantic_model_governance` | Reusable analyzer package. |
| `fabric\notebooks\semantic_model_governance_scan.py` | Scheduled scan notebook for Fabric. |
| `fabric\notebooks\load_sample_governance_data.py` | Sample data notebook for report validation. |
| `fabric\lakehouse-schema` | Table schema and workspace config starter. |
| `powerbi` | Report build guide and starter DAX measures. |
| `docs` | Admin, user, architecture, security, operations, and troubleshooting docs. |
| `docs\deployment-checklist.md` | Step-by-step rollout checklist. |
| `samples` | Synthetic semantic model metadata for local testing. |
| `tests` | Unit tests for the analyzer package. |

## Quick start for Fabric admins

1. Create a Fabric workspace for the solution.
2. Create a Lakehouse named for your governance data, for example `SemanticModelGovernanceLH`.
3. Import `fabric\notebooks\semantic_model_governance_scan.py`.
4. Attach the Lakehouse to the notebook.
5. Install the analyzer package in a Fabric Environment:

```python
%pip install git+https://github.com/oahmad1/fabric_duplicate_semanticmodel_app.git
```

6. Configure workspace scope using `config_workspaces` or notebook parameters.
7. Run the notebook once manually.
8. Build the Power BI report using `powerbi\report-build-guide.md`.
9. Schedule the notebook through a Fabric Data Pipeline.
10. Publish the report as an App for end users.

Detailed setup: [Admin Installation Guide](docs/admin-installation-guide.md)

## End-user experience

End users do not run Python, open JSON, or use command-line tools. They open the published App and use report filters to answer:

- Which semantic models are likely duplicates?
- Which models have high overlap and may need consolidation review?
- Which tables, columns, and measures are common between model pairs?
- Which workspaces have the highest semantic model overlap?
- Which findings are new or unresolved?

End-user guide: [Using the Governance App](docs/end-user-guide.md)

## Local validation

```powershell
git clone https://github.com/oahmad1/fabric_duplicate_semanticmodel_app.git
cd fabric_duplicate_semanticmodel_app
python -m unittest discover -s tests
```

## Relationship to the analyzer baseline

The baseline analyzer repo remains available as a CLI/file-output implementation:

https://github.com/oahmad1/fabric_duplicate_semanticmodel_analyzer

This repo builds on the same scoring concept and adds Fabric tables, scheduled scan guidance, and Power BI App consumption.
