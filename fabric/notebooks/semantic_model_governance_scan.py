# Fabric notebook: Semantic Model Governance Scan
#
# Admin setup:
# 1. Create or select a Fabric workspace for this solution.
# 2. Create a Lakehouse and attach it to this notebook.
# 3. Optional but recommended: create a Fabric Environment and install this repo:
#    %pip install git+https://github.com/oahmad1/fabric_duplicate_semanticmodel_app.git
# 4. Configure WORKSPACE_NAMES or create config_workspaces in the Lakehouse.
# 5. Schedule this notebook through a Fabric Data Pipeline.

from __future__ import annotations

import json
import time
import urllib.parse
from typing import Any, Mapping

import requests
from pyspark.sql import SparkSession

from semantic_model_governance import build_signature, common_object_rows, finding_rows, find_matches
from semantic_model_governance.analyzer import utc_now


PBI_API = "https://api.powerbi.com/v1.0/myorg"

SCAN_ALL_ACCESSIBLE_WORKSPACES = False
WORKSPACE_IDS: list[str] = []
WORKSPACE_NAMES: list[str] = []

MIN_SCORE = 0.60
DUPLICATE_THRESHOLD = 0.85
OVERLAP_THRESHOLD = 0.65
COMMON_OBJECT_LIMIT = 50
REQUEST_DELAY_SECONDS = 0.10

DAX_METADATA_QUERIES = {
    "tables": """
EVALUATE
SELECTCOLUMNS(
    INFO.VIEW.TABLES(),
    "Name", [Name],
    "IsHidden", [IsHidden]
)
ORDER BY [Name]
""".strip(),
    "columns": """
EVALUATE
SELECTCOLUMNS(
    INFO.VIEW.COLUMNS(),
    "Table", [Table],
    "Name", [Name],
    "DataType", [DataType],
    "IsHidden", [IsHidden]
)
ORDER BY [Table], [Name]
""".strip(),
    "measures": """
EVALUATE
SELECTCOLUMNS(
    INFO.VIEW.MEASURES(),
    "Table", [Table],
    "Name", [Name],
    "Expression", [Expression],
    "FormatString", [FormatString],
    "IsHidden", [IsHidden]
)
ORDER BY [Table], [Name]
""".strip(),
    "relationships": """
EVALUATE
SELECTCOLUMNS(
    INFO.VIEW.RELATIONSHIPS(),
    "FromTable", [FromTable],
    "FromColumn", [FromColumn],
    "ToTable", [ToTable],
    "ToColumn", [ToColumn],
    "Cardinality", [Cardinality],
    "CrossFilteringBehavior", [CrossFilteringBehavior],
    "IsActive", [IsActive]
)
""".strip(),
}


def get_powerbi_token() -> str:
    try:
        return notebookutils.credentials.getToken("pbi")  # type: ignore[name-defined]
    except Exception:
        pass

    try:
        from notebookutils import mssparkutils  # type: ignore

        return mssparkutils.credentials.getToken("pbi")
    except Exception as exc:
        raise RuntimeError(
            "Could not acquire a Power BI token. Run this in a Fabric notebook or configure a supported token provider."
        ) from exc


def quote(value: str) -> str:
    return urllib.parse.quote(value, safe="")


def api_request(method: str, url: str, token: str, body: Mapping[str, Any] | None = None) -> Any:
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    response = requests.request(method, url, headers=headers, json=body, timeout=120)
    if response.status_code >= 400:
        raise RuntimeError(f"{method} {url} failed with HTTP {response.status_code}: {response.text[:500]}")
    if not response.text:
        return {}
    return response.json()


def collection(url: str, token: str) -> list[Mapping[str, Any]]:
    values: list[Mapping[str, Any]] = []
    next_url: str | None = url
    while next_url:
        payload = api_request("GET", next_url, token)
        values.extend(payload.get("value", []))
        next_url = payload.get("@odata.nextLink")
    return values


def normalize_response_rows(rows: list[Mapping[str, Any]]) -> list[dict[str, Any]]:
    normalized = []
    for row in rows:
        normalized.append({str(key).strip("[]"): value for key, value in row.items()})
    return normalized


def execute_dax(token: str, workspace_id: str, dataset_id: str, query: str) -> list[dict[str, Any]]:
    payload = {"queries": [{"query": query}], "serializerSettings": {"includeNulls": True}}
    response = api_request("POST", f"{PBI_API}/groups/{quote(workspace_id)}/datasets/{quote(dataset_id)}/executeQueries", token, payload)
    results = response.get("results", [])
    if not results or not results[0].get("tables"):
        return []
    return normalize_response_rows(results[0]["tables"][0].get("rows", []))


def table_exists(name: str) -> bool:
    return spark.catalog.tableExists(name)


def configured_workspaces_from_table() -> tuple[list[str], list[str]]:
    if not table_exists("config_workspaces"):
        return WORKSPACE_IDS, WORKSPACE_NAMES

    rows = spark.table("config_workspaces").where("enabled = true").collect()
    ids = [row["workspace_id"] for row in rows if row["workspace_id"]]
    names = [row["workspace_name"] for row in rows if row["workspace_name"]]
    return ids or WORKSPACE_IDS, names or WORKSPACE_NAMES


def workspace_matches(workspace: Mapping[str, Any], workspace_names: list[str]) -> bool:
    if not workspace_names:
        return True
    return str(workspace.get("name", "")).casefold() in {name.casefold() for name in workspace_names}


def resolve_workspaces(token: str, workspace_ids: list[str], workspace_names: list[str]) -> list[Mapping[str, Any]]:
    if SCAN_ALL_ACCESSIBLE_WORKSPACES:
        return collection(f"{PBI_API}/groups?$top=5000", token)

    if workspace_ids:
        resolved = []
        for workspace_id in workspace_ids:
            resolved.append(api_request("GET", f"{PBI_API}/groups/{quote(workspace_id)}", token))
        return resolved

    if workspace_names:
        all_workspaces = collection(f"{PBI_API}/groups?$top=5000", token)
        return [workspace for workspace in all_workspaces if workspace_matches(workspace, workspace_names)]

    raise RuntimeError("No workspace scope configured. Add rows to config_workspaces or set WORKSPACE_IDS/WORKSPACE_NAMES.")


def warning(run_id: str, workspace: Mapping[str, Any], dataset: Mapping[str, Any] | None, stage: str, message: str) -> dict[str, str]:
    return {
        "run_id": run_id,
        "workspace_id": str(workspace.get("id", "")),
        "workspace_name": str(workspace.get("name", "")),
        "model_id": str(dataset.get("id", "")) if dataset else "",
        "model_name": str(dataset.get("name", "")) if dataset else "",
        "stage": stage,
        "message": message,
    }


def extract_model_metadata(run_id: str, token: str, workspace: Mapping[str, Any], dataset: Mapping[str, Any], warnings: list[dict[str, str]]) -> dict[str, Any]:
    workspace_id = str(workspace["id"])
    workspace_name = str(workspace.get("name", workspace_id))
    model = {
        "workspaceId": workspace_id,
        "workspaceName": workspace_name,
        "id": str(dataset["id"]),
        "name": str(dataset.get("name", dataset["id"])),
        "dataset": dataset,
        "tables": [],
        "columns": [],
        "measures": [],
        "relationships": [],
        "dataSources": [],
    }

    for section, dax in DAX_METADATA_QUERIES.items():
        try:
            model[section] = execute_dax(token, workspace_id, model["id"], dax)
        except Exception as exc:
            warnings.append(warning(run_id, workspace, dataset, f"dax:{section}", str(exc)))

    try:
        data_sources = api_request("GET", f"{PBI_API}/groups/{quote(workspace_id)}/datasets/{quote(model['id'])}/datasources", token)
        model["dataSources"] = data_sources.get("value", [])
    except Exception as exc:
        warnings.append(warning(run_id, workspace, dataset, "datasources", str(exc)))

    return model


def object_inventory_rows(run_id: str, model: Mapping[str, Any]) -> list[dict[str, Any]]:
    rows = []
    base = {
        "run_id": run_id,
        "workspace_id": model["workspaceId"],
        "workspace_name": model["workspaceName"],
        "model_id": model["id"],
        "model_name": model["name"],
    }
    for object_type, values in (
        ("tables", model.get("tables", [])),
        ("columns", model.get("columns", [])),
        ("measures", model.get("measures", [])),
        ("relationships", model.get("relationships", [])),
        ("dataSources", model.get("dataSources", [])),
    ):
        for value in values:
            rows.append({**base, "object_type": object_type, "object_name": json.dumps(value, sort_keys=True)})
    return rows


def model_inventory_row(run_id: str, model: Mapping[str, Any], warning_count: int) -> dict[str, Any]:
    return {
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
        "warning_count": warning_count,
    }


def write_table(name: str, rows: list[dict[str, Any]], mode: str = "append") -> None:
    if not rows:
        return
    spark.createDataFrame(rows).write.format("delta").mode(mode).option("mergeSchema", "true").saveAsTable(name)


def run_scan() -> str:
    run_id = utc_now().replace(":", "").replace("-", "").replace("Z", "")
    started_at = utc_now()
    token = get_powerbi_token()
    workspace_ids, workspace_names = configured_workspaces_from_table()
    warnings: list[dict[str, str]] = []
    models: list[dict[str, Any]] = []

    write_table(
        "semantic_model_scan_runs",
        [{"run_id": run_id, "started_at_utc": started_at, "completed_at_utc": None, "scan_status": "running"}],
    )

    workspaces = resolve_workspaces(token, workspace_ids, workspace_names)
    for workspace in workspaces:
        workspace_id = str(workspace["id"])
        try:
            datasets = collection(f"{PBI_API}/groups/{quote(workspace_id)}/datasets", token)
        except Exception as exc:
            warnings.append(warning(run_id, workspace, None, "datasets", str(exc)))
            continue

        for dataset in datasets:
            model = extract_model_metadata(run_id, token, workspace, dataset, warnings)
            models.append(model)
            if REQUEST_DELAY_SECONDS:
                time.sleep(REQUEST_DELAY_SECONDS)

    signatures = [build_signature(model, warnings) for model in models]
    matches = find_matches(
        signatures,
        min_score=MIN_SCORE,
        duplicate_threshold=DUPLICATE_THRESHOLD,
        overlap_threshold=OVERLAP_THRESHOLD,
        common_limit=COMMON_OBJECT_LIMIT,
    )

    warning_counts = {}
    for item in warnings:
        key = item.get("model_id", "")
        warning_counts[key] = warning_counts.get(key, 0) + 1

    write_table("semantic_model_inventory", [model_inventory_row(run_id, model, warning_counts.get(model["id"], 0)) for model in models])
    write_table("semantic_model_objects", [row for model in models for row in object_inventory_rows(run_id, model)])
    write_table("semantic_model_findings", finding_rows(run_id, matches))
    write_table("semantic_model_common_objects", common_object_rows(run_id, matches))
    write_table("semantic_model_warnings", warnings)
    write_table(
        "semantic_model_scan_runs",
        [
            {
                "run_id": run_id,
                "started_at_utc": started_at,
                "completed_at_utc": utc_now(),
                "scan_status": "completed",
                "workspace_count": len(workspaces),
                "model_count": len(models),
                "finding_count": len(matches),
                "warning_count": len(warnings),
            }
        ],
    )
    return run_id


run_id = run_scan()
print(f"Semantic model governance scan completed. run_id={run_id}")

