-- Optional Fabric Warehouse schema.
-- The Fabric notebook creates equivalent Delta tables automatically in a Lakehouse.

CREATE TABLE semantic_model_scan_runs (
    run_id VARCHAR(80) NOT NULL,
    started_at_utc DATETIME2 NOT NULL,
    completed_at_utc DATETIME2 NULL,
    scan_status VARCHAR(40) NOT NULL,
    workspace_count INT NULL,
    model_count INT NULL,
    finding_count INT NULL,
    warning_count INT NULL
);

CREATE TABLE semantic_model_inventory (
    run_id VARCHAR(80) NOT NULL,
    workspace_id VARCHAR(80) NOT NULL,
    workspace_name VARCHAR(512) NULL,
    model_id VARCHAR(80) NOT NULL,
    model_name VARCHAR(512) NULL,
    table_count INT NULL,
    column_count INT NULL,
    measure_count INT NULL,
    relationship_count INT NULL,
    data_source_count INT NULL,
    warning_count INT NULL
);

CREATE TABLE semantic_model_objects (
    run_id VARCHAR(80) NOT NULL,
    workspace_id VARCHAR(80) NOT NULL,
    workspace_name VARCHAR(512) NULL,
    model_id VARCHAR(80) NOT NULL,
    model_name VARCHAR(512) NULL,
    object_type VARCHAR(60) NOT NULL,
    object_name VARCHAR(2000) NOT NULL
);

CREATE TABLE semantic_model_findings (
    run_id VARCHAR(80) NOT NULL,
    finding_id VARCHAR(100) NOT NULL,
    classification VARCHAR(60) NOT NULL,
    confidence VARCHAR(40) NOT NULL,
    duplicate_score FLOAT NOT NULL,
    overlap_score FLOAT NOT NULL,
    left_workspace_id VARCHAR(80) NOT NULL,
    left_workspace_name VARCHAR(512) NULL,
    left_model_id VARCHAR(80) NOT NULL,
    left_model_name VARCHAR(512) NULL,
    right_workspace_id VARCHAR(80) NOT NULL,
    right_workspace_name VARCHAR(512) NULL,
    right_model_id VARCHAR(80) NOT NULL,
    right_model_name VARCHAR(512) NULL,
    shared_tables INT NULL,
    shared_columns INT NULL,
    shared_measures INT NULL,
    shared_relationships INT NULL,
    shared_data_sources INT NULL,
    warnings VARCHAR(4000) NULL
);

CREATE TABLE semantic_model_common_objects (
    run_id VARCHAR(80) NOT NULL,
    finding_id VARCHAR(100) NOT NULL,
    object_type VARCHAR(60) NOT NULL,
    object_name VARCHAR(2000) NOT NULL
);

CREATE TABLE semantic_model_warnings (
    run_id VARCHAR(80) NOT NULL,
    workspace_id VARCHAR(80) NULL,
    workspace_name VARCHAR(512) NULL,
    model_id VARCHAR(80) NULL,
    model_name VARCHAR(512) NULL,
    stage VARCHAR(120) NOT NULL,
    message VARCHAR(4000) NOT NULL
);

CREATE TABLE config_workspaces (
    workspace_id VARCHAR(80) NULL,
    workspace_name VARCHAR(512) NULL,
    enabled BIT NOT NULL,
    notes VARCHAR(1000) NULL
);

