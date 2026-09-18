# Automated Provisioning

Use `scripts\provision-fabric-solution.ps1` to create or reuse the Fabric workspace, create or reuse the Lakehouse, import the solution notebooks, and create the Data Pipelines.

The script uses Azure CLI and Fabric REST APIs. It does not ask users to paste Fabric credentials. Users authenticate through `az login`, optionally scoped to a tenant ID.

## What the script creates

| Resource | Behavior |
|---|---|
| Fabric workspace | Reuses an existing workspace with the same name, or creates one. |
| Lakehouse | Reuses an existing Lakehouse with the same name, or creates one. |
| Sample data notebook | Creates or updates `Load Sample Governance Data`. |
| Scan notebook | Creates or updates `Semantic Model Governance Scan`. |
| Notebook Lakehouse binding | Adds `metadata.dependencies.lakehouse` so the notebooks are bound to the created/reused Lakehouse. |
| Sample-load pipeline | Creates or updates `Semantic Model Governance - Load Sample Data`. |
| Scan pipeline | Creates or updates `Semantic Model Governance - Scan`. |
| Report shell | Optional. Creates a blank Power BI report when `-CreateReportShell` and `-ReportSemanticModelId` are supplied. |

The script does not build the full visual Power BI report, publish the App, or schedule the pipeline. Those steps are still completed in Fabric after provisioning.

## Prerequisites

- Azure CLI installed.
- Fabric tenant access.
- Permission to create Fabric workspaces, or access to an existing workspace with the requested name.
- Permission to create Lakehouses and Notebooks in that workspace.
- Fabric capacity assigned to the workspace, or a `-CapacityId` supplied during workspace creation if your tenant requires it.

## Basic usage

```powershell
git clone https://github.com/oahmad1/fabric_duplicate_semanticmodel_app.git
cd fabric_duplicate_semanticmodel_app

.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000"
```

## Recommended pilot usage

Use a dedicated workspace name and configure the first scan scope at import time.

```powershell
.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -WorkspaceName "Semantic Model Governance" `
  -LakehouseName "SemanticModelGovernanceLH" `
  -InitialScanWorkspaceName "Finance Analytics" `
  -InitialScanWorkspaceName "Sales BI"
```

If you know workspace IDs, prefer IDs:

```powershell
.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -InitialScanWorkspaceId "00000000-0000-0000-0000-000000000000" `
  -InitialScanWorkspaceId "11111111-1111-1111-1111-111111111111"
```

## Capacity-aware setup

If the workspace must be created on a specific Fabric capacity:

```powershell
.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -CapacityId "22222222-2222-2222-2222-222222222222"
```

If the workspace already exists, the script reuses it. Assign capacity in Fabric if the existing workspace is not capacity-backed.

## Script parameters

| Parameter | Required | Description |
|---|---|---|
| `TenantId` | No | Tenant ID passed to `az login --tenant`. |
| `WorkspaceName` | No | Solution workspace name. Default: `Semantic Model Governance`. |
| `LakehouseName` | No | Governance Lakehouse name. Default: `SemanticModelGovernanceLH`. |
| `ScanNotebookName` | No | Imported scan notebook name. |
| `SampleNotebookName` | No | Imported sample-data notebook name. |
| `CapacityId` | No | Capacity ID used when creating a new workspace. |
| `InitialScanWorkspaceId` | No | Workspace IDs to preconfigure in the scan notebook. Repeatable. |
| `InitialScanWorkspaceName` | No | Workspace names to preconfigure in the scan notebook. Repeatable. |
| `ScanAllAccessibleWorkspaces` | No | Preconfigures the scan notebook to scan all workspaces visible to the scan identity. Use carefully. |
| `SkipPipelines` | No | Skips creating or updating Data Pipelines. |
| `CreateReportShell` | No | Creates a blank Power BI report bound to `ReportSemanticModelId`. |
| `ReportSemanticModelId` | No | Semantic model ID used for optional report-shell creation. |
| `ReportName` | No | Optional report shell name. |
| `SkipLogin` | No | Skips `az login`; useful when already authenticated or running in controlled automation. |

## After provisioning

1. Open the created/reused Fabric workspace.
2. Confirm the Lakehouse and two notebooks exist.
3. Trigger `Semantic Model Governance - Load Sample Data` first to validate table creation.
4. Build the Power BI report using [Power BI Report Build Guide](../powerbi/report-build-guide.md).
5. Configure real scan scope if you did not pass it during provisioning.
6. Trigger `Semantic Model Governance - Scan`.
7. Schedule `Semantic Model Governance - Scan` through Fabric.
8. Publish the report as a Power BI/Fabric App.

## Notes and limitations

- The script creates and imports core Fabric items plus Data Pipelines. It does not create the full report layout automatically in this version.
- Optional report-shell creation requires an existing semantic model ID.
- The notebooks are imported with default Lakehouse metadata. If a tenant changes notebook metadata behavior, verify the Lakehouse attachment in Fabric before running.
- For production, use an approved automation identity. Do not run scheduled scans under a personal account.
