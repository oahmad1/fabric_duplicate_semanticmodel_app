# Semantic Model Automation

The provisioner creates or updates a Direct Lake semantic model over the standardized governance tables.

## Why this works

The notebooks always write the same table contract:

- `semantic_model_scan_runs`
- `semantic_model_inventory`
- `semantic_model_objects`
- `semantic_model_findings`
- `semantic_model_common_objects`
- `semantic_model_warnings`

Because the output is standardized, the provisioner can generate a TMDL semantic model definition instead of asking admins to manually model the tables.

## What gets created

Default semantic model name:

```text
Semantic Model Governance Semantic Model
```

The semantic model includes:

- Direct Lake table definitions for the governance tables.
- Measures for finding counts, likely duplicates, high-overlap findings, warnings, model counts, workspace counts, and average/max scores.
- Relationships from scan runs to inventory/findings/warnings.
- Relationship from findings to common objects.

## Initialization dependency

The provisioner imports an initialization notebook and runs it by default unless `-SkipInitializationRun` is used.

The initialization notebook creates empty Delta tables when they do not exist. Existing tables are left unchanged. This gives the Direct Lake semantic model a stable schema before real scan data arrives.

## Refresh behavior

Direct Lake models do not import data like Import-mode models. After the scan pipeline writes new rows to the Lakehouse, users refresh the semantic model/report metadata view in Fabric or Power BI so the App reflects the latest completed scan.

## Skipping semantic model creation

Use this only for advanced customization:

```powershell
.\scripts\provision-fabric-solution.ps1 -SkipSemanticModel
```

If you skip semantic model creation, report creation is also skipped because there is no generated model to bind to.

