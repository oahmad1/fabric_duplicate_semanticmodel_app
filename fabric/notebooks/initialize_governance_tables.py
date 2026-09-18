# Fabric notebook: Initialize Semantic Model Governance Tables
#
# Run this once after provisioning to create empty governance Delta tables.
# The provisioner can also trigger this notebook automatically.

from __future__ import annotations

from pyspark.sql.types import (
    BooleanType,
    DoubleType,
    IntegerType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)


TABLE_SCHEMAS = {
    "semantic_model_scan_runs": StructType(
        [
            StructField("run_id", StringType(), False),
            StructField("started_at_utc", StringType(), True),
            StructField("completed_at_utc", StringType(), True),
            StructField("scan_status", StringType(), False),
            StructField("workspace_count", IntegerType(), True),
            StructField("model_count", IntegerType(), True),
            StructField("finding_count", IntegerType(), True),
            StructField("warning_count", IntegerType(), True),
        ]
    ),
    "semantic_model_inventory": StructType(
        [
            StructField("run_id", StringType(), False),
            StructField("workspace_id", StringType(), False),
            StructField("workspace_name", StringType(), True),
            StructField("model_id", StringType(), False),
            StructField("model_name", StringType(), True),
            StructField("table_count", IntegerType(), True),
            StructField("column_count", IntegerType(), True),
            StructField("measure_count", IntegerType(), True),
            StructField("relationship_count", IntegerType(), True),
            StructField("data_source_count", IntegerType(), True),
            StructField("warning_count", IntegerType(), True),
        ]
    ),
    "semantic_model_objects": StructType(
        [
            StructField("run_id", StringType(), False),
            StructField("workspace_id", StringType(), False),
            StructField("workspace_name", StringType(), True),
            StructField("model_id", StringType(), False),
            StructField("model_name", StringType(), True),
            StructField("object_type", StringType(), False),
            StructField("object_name", StringType(), False),
        ]
    ),
    "semantic_model_findings": StructType(
        [
            StructField("run_id", StringType(), False),
            StructField("finding_id", StringType(), False),
            StructField("classification", StringType(), False),
            StructField("confidence", StringType(), False),
            StructField("duplicate_score", DoubleType(), False),
            StructField("overlap_score", DoubleType(), False),
            StructField("left_workspace_id", StringType(), False),
            StructField("left_workspace_name", StringType(), True),
            StructField("left_model_id", StringType(), False),
            StructField("left_model_name", StringType(), True),
            StructField("right_workspace_id", StringType(), False),
            StructField("right_workspace_name", StringType(), True),
            StructField("right_model_id", StringType(), False),
            StructField("right_model_name", StringType(), True),
            StructField("shared_tables", IntegerType(), True),
            StructField("shared_columns", IntegerType(), True),
            StructField("shared_measures", IntegerType(), True),
            StructField("shared_relationships", IntegerType(), True),
            StructField("shared_data_sources", IntegerType(), True),
            StructField("warnings", StringType(), True),
        ]
    ),
    "semantic_model_common_objects": StructType(
        [
            StructField("run_id", StringType(), False),
            StructField("finding_id", StringType(), False),
            StructField("object_type", StringType(), False),
            StructField("object_name", StringType(), False),
        ]
    ),
    "semantic_model_warnings": StructType(
        [
            StructField("run_id", StringType(), False),
            StructField("workspace_id", StringType(), True),
            StructField("workspace_name", StringType(), True),
            StructField("model_id", StringType(), True),
            StructField("model_name", StringType(), True),
            StructField("stage", StringType(), False),
            StructField("message", StringType(), False),
        ]
    ),
    "config_workspaces": StructType(
        [
            StructField("workspace_id", StringType(), True),
            StructField("workspace_name", StringType(), True),
            StructField("enabled", BooleanType(), False),
            StructField("notes", StringType(), True),
        ]
    ),
}


def table_exists(name: str) -> bool:
    return spark.catalog.tableExists(name)


created = []
existing = []
for table_name, schema in TABLE_SCHEMAS.items():
    if table_exists(table_name):
        existing.append(table_name)
        continue
    spark.createDataFrame([], schema).write.format("delta").mode("overwrite").saveAsTable(table_name)
    created.append(table_name)

print(f"Initialization complete. Created tables: {created}. Existing tables left unchanged: {existing}.")

