# Architecture

The solution separates metadata collection, duplicate scoring, storage, and end-user consumption.

## Components

| Component | Role |
|---|---|
| Fabric workspace | Hosts the Lakehouse, notebook, pipeline, semantic model, report, and App. |
| Provisioning script | Automates workspace, Lakehouse, notebook, Data Pipeline, and optional report-shell creation through Azure CLI, Fabric REST APIs, and Power BI REST APIs. |
| Lakehouse or Warehouse | Stores scan runs, inventory, findings, common objects, and warnings. |
| Fabric notebook | Reads Power BI/Fabric metadata, calculates scores, and writes Delta tables. |
| Fabric Data Pipeline | Schedules the notebook and provides operational monitoring. |
| Power BI semantic model | Models the governance tables for reporting. |
| Power BI report | Presents duplicate findings, common objects, and scan health. |
| Power BI/Fabric App | Provides the no-code installable user experience. |

## Data flow

```text
0. Admin runs the provisioning script or creates the Fabric items manually.
1. Scheduled pipeline starts scan notebook.
2. Notebook reads workspace configuration.
3. Notebook lists semantic models in configured workspaces.
4. Notebook extracts metadata with DAX INFO.VIEW.* and Power BI data source APIs.
5. Analyzer compares every model pair in scope.
6. Notebook writes results to governance tables.
7. Report refreshes from governance tables.
8. Users open the published App and review results.
```

## Provisioned control plane

The automated provisioner creates these items up front:

- workspace
- Lakehouse
- sample data notebook
- semantic model scan notebook
- sample-load Data Pipeline
- scan Data Pipeline

The full visual Power BI report is built after the first sample or real run creates governance tables. The provisioner can create a blank report shell when an existing semantic model ID is supplied.

## Why precomputed results

Precomputed results make the end-user experience simple and reliable. Users do not need API permissions, Python, notebooks, or JSON files. They only need access to the published App.

The tradeoff is freshness: the report reflects the latest completed scan. For most governance use cases, nightly or weekly scans are enough.

## When to consider a custom app later

Start with this solution accelerator first. Consider a custom Fabric workload or web app later if you need:

- Interactive "compare now" buttons.
- Per-user delegated API calls at runtime.
- Complex remediation workflows.
- Embedded approvals or task assignment.
- Marketplace-style packaging beyond a Power BI App.
