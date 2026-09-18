"""Reusable scoring logic for duplicate semantic model governance."""

from __future__ import annotations

import datetime as dt
import itertools
import re
from dataclasses import dataclass
from typing import Any, Iterable, Mapping, Sequence


DIMENSIONS = (
    ("tables", 0.20),
    ("columns", 0.25),
    ("measure_names", 0.10),
    ("measure_expressions", 0.15),
    ("relationships", 0.15),
    ("data_sources", 0.15),
)

SENSITIVE_KEY_RE = re.compile(r"(password|secret|token|credential|key|sas|connectionstring)", re.I)


@dataclass(frozen=True)
class ModelSignature:
    workspace_id: str
    workspace_name: str
    model_id: str
    model_name: str
    tables: frozenset[str]
    columns: frozenset[str]
    measure_names: frozenset[str]
    measure_expressions: frozenset[str]
    relationships: frozenset[str]
    data_sources: frozenset[str]
    warnings: tuple[str, ...]

    def object_count(self) -> int:
        return (
            len(self.tables)
            + len(self.columns)
            + len(self.measure_names)
            + len(self.measure_expressions)
            + len(self.relationships)
        )


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def clean_key(key: Any) -> str:
    text = str(key).strip()
    if text.startswith("[") and text.endswith("]"):
        return text[1:-1]
    return text


def normalize_text(value: Any) -> str:
    text = "" if value is None else str(value)
    return re.sub(r"\s+", " ", text.strip()).casefold()


def normalize_identifier(value: Any) -> str:
    text = normalize_text(value)
    text = text.strip("'\"[]")
    return re.sub(r"\s+", " ", text)


def normalize_dax(expression: Any) -> str:
    text = "" if expression is None else str(expression)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//.*?$", " ", text, flags=re.M)
    text = re.sub(r"\s+", " ", text.strip()).casefold()
    text = re.sub(r"\s*([,=+\-*/(){}\[\]:<>])\s*", r"\1", text)
    return text


def get_value(row: Any, *names: str) -> Any:
    if isinstance(row, str):
        return row
    if not isinstance(row, Mapping):
        return None
    indexed = {clean_key(key).casefold(): value for key, value in row.items()}
    for name in names:
        value = indexed.get(clean_key(name).casefold())
        if value not in (None, ""):
            return value
    return None


def list_value(model: Mapping[str, Any], *names: str) -> list[Any]:
    indexed = {clean_key(key).casefold(): value for key, value in model.items()}
    for name in names:
        value = indexed.get(clean_key(name).casefold())
        if value is None:
            continue
        return value if isinstance(value, list) else [value]
    return []


def table_signature(row: Any) -> str | None:
    normalized = normalize_identifier(get_value(row, "Name", "Table", "TableName", "tableName"))
    return normalized or None


def column_signature(row: Any) -> str | None:
    if isinstance(row, str):
        return normalize_identifier(row) or None
    table = normalize_identifier(get_value(row, "Table", "TableName", "tableName"))
    name = normalize_identifier(get_value(row, "Name", "Column", "ColumnName", "columnName"))
    data_type = normalize_identifier(get_value(row, "DataType", "Type", "dataType"))
    if not name:
        return None
    return f"{table}[{name}]|{data_type}" if table else f"{name}|{data_type}"


def measure_name_signature(row: Any) -> str | None:
    if isinstance(row, str):
        return normalize_identifier(row) or None
    table = normalize_identifier(get_value(row, "Table", "TableName", "tableName"))
    name = normalize_identifier(get_value(row, "Name", "Measure", "MeasureName", "measureName"))
    if not name:
        return None
    return f"{table}[{name}]" if table else name


def measure_expression_signature(row: Any) -> str | None:
    expression = normalize_dax(get_value(row, "Expression", "Dax", "DAX", "formula"))
    return expression or None


def relationship_signature(row: Any) -> str | None:
    if isinstance(row, str):
        return normalize_identifier(row) or None
    left_table = normalize_identifier(get_value(row, "FromTable", "From Table", "fromTable"))
    left_column = normalize_identifier(get_value(row, "FromColumn", "From Column", "fromColumn"))
    right_table = normalize_identifier(get_value(row, "ToTable", "To Table", "toTable"))
    right_column = normalize_identifier(get_value(row, "ToColumn", "To Column", "toColumn"))
    if not (left_table and left_column and right_table and right_column):
        return None
    left = f"{left_table}[{left_column}]"
    right = f"{right_table}[{right_column}]"
    endpoints = sorted((left, right))
    cardinality = normalize_identifier(get_value(row, "Cardinality", "RelationshipCardinality"))
    active = normalize_identifier(get_value(row, "IsActive", "Active"))
    return f"{endpoints[0]}--{endpoints[1]}|{cardinality}|{active}"


def data_source_signature(row: Any) -> str | None:
    if isinstance(row, str):
        return normalize_text(row) or None
    if not isinstance(row, Mapping):
        return None

    parts: list[str] = []
    for key in ("datasourceType", "type", "kind"):
        value = get_value(row, key)
        if value:
            parts.append(f"{key}={normalize_text(value)}")

    details = get_value(row, "connectionDetails", "ConnectionDetails")
    if isinstance(details, Mapping):
        for key in ("server", "database", "url", "path", "account", "domain", "workspaceId", "lakehouseId"):
            value = get_value(details, key)
            if value:
                parts.append(f"{key}={normalize_text(value)}")

    for key in ("server", "database", "url", "path"):
        if SENSITIVE_KEY_RE.search(key):
            continue
        value = get_value(row, key)
        if value:
            parts.append(f"{key}={normalize_text(value)}")

    return "|".join(sorted(set(parts))) or None


def signatures(rows: Iterable[Any], converter) -> frozenset[str]:
    values = {converted for row in rows if (converted := converter(row))}
    return frozenset(values)


def model_warnings(model: Mapping[str, Any], global_warnings: Sequence[Mapping[str, Any]]) -> tuple[str, ...]:
    model_id = normalize_text(get_value(model, "id", "modelId", "datasetId"))
    local = [str(warning) for warning in list_value(model, "warnings")]
    matched = []
    for warning in global_warnings:
        warning_model_id = normalize_text(get_value(warning, "modelId", "datasetId", "id"))
        if warning_model_id and warning_model_id == model_id:
            stage = get_value(warning, "stage") or "metadata"
            message = get_value(warning, "message") or warning
            matched.append(f"{stage}: {message}")
    return tuple(local + matched)


def build_signature(model: Mapping[str, Any], global_warnings: Sequence[Mapping[str, Any]] = ()) -> ModelSignature:
    measures = list_value(model, "measures", "Measures")
    model_id = str(get_value(model, "id", "modelId", "datasetId", "artifactId") or "")
    workspace_id = str(get_value(model, "workspaceId", "groupId") or "")
    return ModelSignature(
        workspace_id=workspace_id,
        workspace_name=str(get_value(model, "workspaceName", "groupName") or workspace_id),
        model_id=model_id,
        model_name=str(get_value(model, "name", "displayName", "datasetName") or model_id),
        tables=signatures(list_value(model, "tables", "Tables"), table_signature),
        columns=signatures(list_value(model, "columns", "Columns"), column_signature),
        measure_names=signatures(measures, measure_name_signature),
        measure_expressions=signatures(measures, measure_expression_signature),
        relationships=signatures(list_value(model, "relationships", "Relationships"), relationship_signature),
        data_sources=signatures(list_value(model, "dataSources", "datasources", "DataSources"), data_source_signature),
        warnings=model_warnings(model, global_warnings),
    )


def jaccard(left: frozenset[str], right: frozenset[str]) -> float | None:
    if not left and not right:
        return None
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


def containment(left: frozenset[str], right: frozenset[str]) -> float | None:
    if not left and not right:
        return None
    if not left or not right:
        return 0.0
    return len(left & right) / min(len(left), len(right))


def round_score(value: float | None) -> float | None:
    return None if value is None else round(value, 4)


def weighted_score(dimensions: Mapping[str, Mapping[str, float | int | None]], metric: str) -> float:
    numerator = 0.0
    denominator = 0.0
    for name, weight in DIMENSIONS:
        value = dimensions[name][metric]
        if value is None:
            continue
        numerator += weight * float(value)
        denominator += weight
    return numerator / denominator if denominator else 0.0


def display_column(value: str) -> str:
    column, separator, data_type = value.partition("|")
    return f"{column} ({data_type})" if separator and data_type else column


def common_set_payload(values: Iterable[str], limit: int, formatter=str) -> dict[str, Any]:
    sorted_values = sorted(values)
    omitted = 0
    if limit > 0:
        omitted = max(0, len(sorted_values) - limit)
        sorted_values = sorted_values[:limit]
    return {"items": [formatter(value) for value in sorted_values], "omitted": omitted}


def common_objects(left: ModelSignature, right: ModelSignature, limit: int) -> dict[str, dict[str, Any]]:
    return {
        "tables": common_set_payload(left.tables & right.tables, limit),
        "columns": common_set_payload(left.columns & right.columns, limit, display_column),
        "measures": common_set_payload(left.measure_names & right.measure_names, limit),
        "measureExpressions": common_set_payload(left.measure_expressions & right.measure_expressions, limit),
        "relationships": common_set_payload(left.relationships & right.relationships, limit),
        "dataSources": common_set_payload(left.data_sources & right.data_sources, limit),
    }


def confidence(left: ModelSignature, right: ModelSignature, dimensions: Mapping[str, Mapping[str, float | int | None]]) -> str:
    known_dimensions = sum(1 for name, _ in DIMENSIONS if dimensions[name]["jaccard"] is not None)
    minimum_objects = min(left.object_count(), right.object_count())
    has_warnings = bool(left.warnings or right.warnings)
    if known_dimensions >= 5 and minimum_objects >= 10 and not has_warnings:
        return "high"
    if known_dimensions >= 3 and minimum_objects >= 5:
        return "medium"
    return "low"


def model_ref(model: ModelSignature) -> dict[str, str]:
    return {
        "workspaceName": model.workspace_name,
        "workspaceId": model.workspace_id,
        "modelName": model.model_name,
        "modelId": model.model_id,
    }


def compare_pair(
    left: ModelSignature,
    right: ModelSignature,
    duplicate_threshold: float = 0.85,
    overlap_threshold: float = 0.65,
    common_limit: int = 25,
) -> dict[str, Any]:
    dimension_sets = {
        "tables": (left.tables, right.tables),
        "columns": (left.columns, right.columns),
        "measure_names": (left.measure_names, right.measure_names),
        "measure_expressions": (left.measure_expressions, right.measure_expressions),
        "relationships": (left.relationships, right.relationships),
        "data_sources": (left.data_sources, right.data_sources),
    }
    dimensions: dict[str, dict[str, float | int | None]] = {}
    for name, (left_set, right_set) in dimension_sets.items():
        dimensions[name] = {
            "jaccard": round_score(jaccard(left_set, right_set)),
            "containment": round_score(containment(left_set, right_set)),
            "shared": len(left_set & right_set),
            "left": len(left_set),
            "right": len(right_set),
        }

    duplicate_score = weighted_score(dimensions, "jaccard")
    containment_score = weighted_score(dimensions, "containment")
    overlap_score = max(duplicate_score, containment_score * 0.95)

    if duplicate_score >= duplicate_threshold:
        classification = "likely_duplicate"
    elif duplicate_score >= overlap_threshold or overlap_score >= overlap_threshold:
        classification = "high_overlap"
    else:
        classification = "partial_overlap"

    common = common_objects(left, right, common_limit)
    return {
        "left": model_ref(left),
        "right": model_ref(right),
        "classification": classification,
        "confidence": confidence(left, right, dimensions),
        "duplicateScore": round(duplicate_score, 4),
        "overlapScore": round(overlap_score, 4),
        "dimensions": dimensions,
        "commonObjects": common,
        "warnings": list(left.warnings + right.warnings),
    }


def find_matches(
    models: Sequence[ModelSignature],
    min_score: float = 0.60,
    duplicate_threshold: float = 0.85,
    overlap_threshold: float = 0.65,
    common_limit: int = 25,
    top: int = 0,
) -> list[dict[str, Any]]:
    matches = []
    for left, right in itertools.combinations(models, 2):
        result = compare_pair(left, right, duplicate_threshold, overlap_threshold, common_limit)
        if max(result["duplicateScore"], result["overlapScore"]) >= min_score:
            matches.append(result)
    matches.sort(key=lambda item: (item["classification"] != "likely_duplicate", -item["duplicateScore"], -item["overlapScore"]))
    return matches if top <= 0 else matches[:top]


def finding_rows(run_id: str, matches: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for index, match in enumerate(matches, start=1):
        dims = match["dimensions"]
        rows.append(
            {
                "run_id": run_id,
                "finding_id": f"{run_id}-{index:05d}",
                "classification": match["classification"],
                "confidence": match["confidence"],
                "duplicate_score": float(match["duplicateScore"]),
                "overlap_score": float(match["overlapScore"]),
                "left_workspace_id": match["left"]["workspaceId"],
                "left_workspace_name": match["left"]["workspaceName"],
                "left_model_id": match["left"]["modelId"],
                "left_model_name": match["left"]["modelName"],
                "right_workspace_id": match["right"]["workspaceId"],
                "right_workspace_name": match["right"]["workspaceName"],
                "right_model_id": match["right"]["modelId"],
                "right_model_name": match["right"]["modelName"],
                "shared_tables": int(dims["tables"]["shared"]),
                "shared_columns": int(dims["columns"]["shared"]),
                "shared_measures": int(dims["measure_names"]["shared"]),
                "shared_relationships": int(dims["relationships"]["shared"]),
                "shared_data_sources": int(dims["data_sources"]["shared"]),
                "warnings": " | ".join(match.get("warnings", [])),
            }
        )
    return rows


def common_object_rows(run_id: str, matches: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for index, match in enumerate(matches, start=1):
        finding_id = f"{run_id}-{index:05d}"
        for object_type, payload in match["commonObjects"].items():
            for value in payload.get("items", []):
                rows.append(
                    {
                        "run_id": run_id,
                        "finding_id": finding_id,
                        "object_type": object_type,
                        "object_name": value,
                    }
                )
    return rows

