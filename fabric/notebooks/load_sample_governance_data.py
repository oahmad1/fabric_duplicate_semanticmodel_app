# Fabric notebook: Load synthetic sample governance data
#
# Use this notebook to validate the Power BI report before connecting to real Fabric metadata.

from __future__ import annotations

import json
from pathlib import Path

from semantic_model_governance import build_signature, common_object_rows, finding_rows, find_matches
from semantic_model_governance.analyzer import utc_now


SAMPLE_FILE = "samples/dummy_semantic_models.json"

with open(SAMPLE_FILE, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

run_id = "sample-" + utc_now().replace(":", "").replace("-", "").replace("Z", "")
models = payload["models"]
warnings = payload.get("warnings", [])
signatures = [build_signature(model, warnings) for model in models]
matches = find_matches(signatures, min_score=0.60, top=0)


def write_table(name: str, rows: list[dict], mode: str = "overwrite") -> None:
    if not rows:
        return
    spark.createDataFrame(rows).write.format("delta").mode(mode).option("overwriteSchema", "true").saveAsTable(name)


inventory_rows = []
object_rows = []
for model in models:
    inventory_rows.append(
        {
            "run_id": run_id,
            "workspace_id": model["workspaceId"],
            "workspace_name": model["workspaceName"],
            "model_id": model["id"],
            "model_name": model["name"],
            "table_count": len(model.get("tables", [])),
            "column_count": len(model.get("columns", [])),
            "measure_count": len(model.get("measures", [])),
            "relationship_count": len(model.get("relationships", [])),
            "data_source_count": len(model.get("dataSources", [])),
            "warning_count": 0,
        }
    )
    for object_type in ("tables", "columns", "measures", "relationships", "dataSources"):
        for value in model.get(object_type, []):
            object_rows.append(
                {
                    "run_id": run_id,
                    "workspace_id": model["workspaceId"],
                    "workspace_name": model["workspaceName"],
                    "model_id": model["id"],
                    "model_name": model["name"],
                    "object_type": object_type,
                    "object_name": json.dumps(value, sort_keys=True),
                }
            )

write_table(
    "semantic_model_scan_runs",
    [
        {
            "run_id": run_id,
            "started_at_utc": utc_now(),
            "completed_at_utc": utc_now(),
            "scan_status": "completed",
            "workspace_count": len({m["workspaceId"] for m in models}),
            "model_count": len(models),
            "finding_count": len(matches),
            "warning_count": 0,
        }
    ],
)
write_table("semantic_model_inventory", inventory_rows)
write_table("semantic_model_objects", object_rows)
write_table("semantic_model_findings", finding_rows(run_id, matches))
write_table("semantic_model_common_objects", common_object_rows(run_id, matches))

print(f"Loaded sample governance data. run_id={run_id}, findings={len(matches)}")

