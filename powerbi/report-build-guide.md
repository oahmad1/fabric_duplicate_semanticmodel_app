# Power BI Report Build Guide

This solution is intended to be consumed through a Power BI report published as an App from the Fabric workspace.

## Data source

Connect the report to the Lakehouse SQL endpoint or Fabric Warehouse that contains these tables:

- `semantic_model_scan_runs`
- `semantic_model_inventory`
- `semantic_model_findings`
- `semantic_model_common_objects`
- `semantic_model_warnings`

## Recommended report pages

### 1. Executive Overview

Purpose: show the governance backlog at a glance.

Visuals:

- Cards: `Finding Count`, `Likely Duplicate Count`, `High Overlap Count`, `Models Scanned`, `Warnings`
- Bar chart: findings by `classification`
- Bar chart: findings by `left_workspace_name`
- Table: top findings sorted by `duplicate_score` and `overlap_score`

### 2. Duplicate Candidates

Purpose: help owners prioritize consolidation reviews.

Visuals:

- Slicers: scan run, classification, confidence, workspace, model
- Table columns:
  - classification
  - confidence
  - duplicate_score
  - overlap_score
  - left_workspace_name
  - left_model_name
  - right_workspace_name
  - right_model_name
  - shared_tables
  - shared_columns
  - shared_measures
  - warnings

### 3. Common Objects

Purpose: show why two models were flagged.

Visuals:

- Finding slicer using `finding_id`
- Matrix:
  - rows: `object_type`, `object_name`
  - values: count of rows
- Detail table filtered to the selected finding

### 4. Model Inventory

Purpose: show scan coverage and metadata volume.

Visuals:

- Table by workspace/model with table, column, measure, relationship, and data source counts.
- Warning count by model.

### 5. Scan Health

Purpose: help admins monitor the scheduled job.

Visuals:

- Scan run history table.
- Warning table.
- Trend line of model count and finding count by run.

## Relationships

Create these relationships:

| From | To | Cardinality |
|---|---|---|
| `semantic_model_scan_runs[run_id]` | `semantic_model_findings[run_id]` | One-to-many |
| `semantic_model_scan_runs[run_id]` | `semantic_model_inventory[run_id]` | One-to-many |
| `semantic_model_findings[finding_id]` | `semantic_model_common_objects[finding_id]` | One-to-many |

Use `powerbi\measures.dax` for starter measures.

## App publishing

After building the report:

1. Publish the report to the same Fabric workspace as the Lakehouse/Warehouse.
2. In the workspace, select **Create app** or **Update app**.
3. Add the report to the app audience.
4. Grant the audience access to the app.
5. Document the refresh schedule and support owner in the app description.

