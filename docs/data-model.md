# Data Model

The scan notebook writes governance tables that Power BI can consume directly.

## Tables

### semantic_model_scan_runs

One row per scan status event. A run writes a `running` row at start and a `completed` row at finish.

| Column | Description |
|---|---|
| `run_id` | Unique scan run ID. |
| `started_at_utc` | Scan start timestamp. |
| `completed_at_utc` | Scan completion timestamp. |
| `scan_status` | `running`, `completed`, or future statuses. |
| `workspace_count` | Number of workspaces scanned. |
| `model_count` | Number of semantic models inventoried. |
| `finding_count` | Number of findings above threshold. |
| `warning_count` | Number of metadata extraction warnings. |

### semantic_model_inventory

One row per semantic model per run.

| Column | Description |
|---|---|
| `workspace_id`, `workspace_name` | Source workspace. |
| `model_id`, `model_name` | Semantic model identity. |
| `table_count`, `column_count`, `measure_count` | Metadata volume. |
| `relationship_count`, `data_source_count` | Additional similarity signals. |
| `warning_count` | Warning count for this model. |

### semantic_model_findings

One row per duplicate or overlap candidate.

| Column | Description |
|---|---|
| `finding_id` | Unique finding ID within a run. |
| `classification` | `likely_duplicate`, `high_overlap`, or `partial_overlap`. |
| `confidence` | `high`, `medium`, or `low`. |
| `duplicate_score` | Weighted Jaccard similarity. |
| `overlap_score` | Containment-aware overlap score. |
| `left_*`, `right_*` | The two semantic models being compared. |
| `shared_*` | Shared object counts. |
| `warnings` | Concatenated warning text, if any. |

### semantic_model_common_objects

One row per common object per finding.

| Column | Description |
|---|---|
| `finding_id` | Related finding. |
| `object_type` | `tables`, `columns`, `measures`, `relationships`, `dataSources`. |
| `object_name` | Normalized shared object name. |

### semantic_model_warnings

One row per metadata extraction warning.

Warnings do not mean the scan failed. They identify models or metadata surfaces that could not be fully read.

## Recommended relationships

| From | To |
|---|---|
| `semantic_model_scan_runs[run_id]` | `semantic_model_inventory[run_id]` |
| `semantic_model_scan_runs[run_id]` | `semantic_model_findings[run_id]` |
| `semantic_model_findings[finding_id]` | `semantic_model_common_objects[finding_id]` |

