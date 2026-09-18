# Automated Provisioning

Use `scripts\provision-fabric-solution.ps1` to create or reuse the Fabric workspace, create or reuse the Lakehouse, import the notebooks, create Data Pipelines, initialize governance tables, and create the Direct Lake semantic model.

The script uses Azure CLI, Fabric REST APIs, and Power BI REST APIs. It does not ask users to paste Fabric credentials. Users authenticate through `az login`, optionally scoped to a tenant ID.

## What the script creates

| Resource | Behavior |
|---|---|
| Fabric workspace | Reuses an existing workspace with the same name, or creates one. |
| Lakehouse | Reuses an existing Lakehouse with the same name, or creates one. |
| Initialization notebook | Creates or updates `Initialize Governance Tables`. |
| Sample data notebook | Creates or updates `Load Sample Governance Data`. |
| Scan notebook | Creates or updates `Semantic Model Governance Scan`. |
| Notebook Lakehouse binding | Adds `metadata.dependencies.lakehouse` so the notebooks are bound to the created/reused Lakehouse. |
| Initialization pipeline | Creates or updates `Semantic Model Governance - Initialize Tables`. |
| Sample-load pipeline | Creates or updates `Semantic Model Governance - Load Sample Data`. |
| Scan pipeline | Creates or updates `Semantic Model Governance - Scan`. |
| Semantic model | Creates or updates `Semantic Model Governance Semantic Model` using Direct Lake TMDL. |
| Report | Optional. Clones and rebinds a template report when `-TemplateReportId` is supplied. |

The script does not invent a full visual report layout from scratch or publish the App. If you maintain a template report, the script can clone and bind it automatically.

## Prerequisites

- Azure CLI installed.
- Fabric tenant access.
- Permission to create Fabric workspaces, or access to an existing workspace with the requested name.
- Permission to create Lakehouses, Notebooks, Data Pipelines, and semantic models in that workspace.
- Fabric capacity assigned to the workspace, or a `-CapacityId` supplied during workspace creation if your tenant requires it.
- Optional: Build permission on a template semantic model/report if using report clone automation.

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

## Report template cloning

After you create a report template once, future deployments can clone and bind it to the generated semantic model:

```powershell
.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -TemplateReportWorkspaceId "11111111-1111-1111-1111-111111111111" `
  -TemplateReportId "22222222-2222-2222-2222-222222222222"
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
| `InitializeNotebookName` | No | Imported initialization notebook name. |
| `ScanNotebookName` | No | Imported scan notebook name. |
| `SampleNotebookName` | No | Imported sample-data notebook name. |
| `InitializePipelineName` | No | Initialization pipeline name. |
| `ScanPipelineName` | No | Scan pipeline name. |
| `SamplePipelineName` | No | Sample-load pipeline name. |
| `SemanticModelName` | No | Generated governance semantic model name. |
| `ReportName` | No | Cloned report name. |
| `TemplateReportId` | No | Existing report ID to clone and bind to the generated semantic model. |
| `TemplateReportWorkspaceId` | No | Workspace ID containing the template report. Defaults to the target workspace. |
| `CapacityId` | No | Capacity ID used when creating a new workspace. |
| `InitialScanWorkspaceId` | No | Workspace IDs to preconfigure in the scan notebook. Repeatable. |
| `InitialScanWorkspaceName` | No | Workspace names to preconfigure in the scan notebook. Repeatable. |
| `ScanAllAccessibleWorkspaces` | No | Preconfigures the scan notebook to scan all workspaces visible to the scan identity. Use carefully. |
| `SkipPipelines` | No | Skips creating or updating Data Pipelines. |
| `SkipInitializationRun` | No | Skips running the initialization notebook during provisioning. |
| `SkipSemanticModel` | No | Skips generated Direct Lake semantic model creation. |
| `SkipReport` | No | Skips optional report template clone. |
| `SkipLogin` | No | Skips `az login`; useful when already authenticated or running in controlled automation. |

## After provisioning

1. Open the created/reused Fabric workspace.
2. Confirm the Lakehouse, notebooks, pipelines, and semantic model exist.
3. Trigger `Semantic Model Governance - Load Sample Data` to validate sample output.
4. Refresh the generated semantic model/report.
5. Build the first report using [Power BI Report Build Guide](../powerbi/report-build-guide.md), or clone a template with `-TemplateReportId`.
6. Configure real scan scope if you did not pass it during provisioning.
7. Trigger `Semantic Model Governance - Scan`.
8. Schedule `Semantic Model Governance - Scan` through Fabric.
9. Publish the report as a Power BI/Fabric App.

## Notes and limitations

- The script creates and imports core Fabric items plus Data Pipelines and the Direct Lake semantic model.
- Full visual report automation uses report template cloning. Create the template once, then pass `-TemplateReportId` for future deployments.
- The notebooks are imported with default Lakehouse metadata. If a tenant changes notebook metadata behavior, verify the Lakehouse attachment in Fabric before running.
- For production, use an approved automation identity. Do not run scheduled scans under a personal account.

