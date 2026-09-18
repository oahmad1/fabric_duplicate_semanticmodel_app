# Pipeline and Report Automation

The provisioner automates the Fabric items that can be created safely before governance tables contain data:

- Fabric workspace
- Lakehouse
- sample-data notebook
- real scan notebook
- sample-load Data Pipeline
- scan Data Pipeline

It can also create a blank Power BI report shell when you provide an existing semantic model ID.

## What is fully automated

Run:

```powershell
.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -WorkspaceName "Semantic Model Governance" `
  -LakehouseName "SemanticModelGovernanceLH"
```

This creates or reuses:

| Fabric item | Default name |
|---|---|
| Workspace | `Semantic Model Governance` |
| Lakehouse | `SemanticModelGovernanceLH` |
| Sample data notebook | `Load Sample Governance Data` |
| Scan notebook | `Semantic Model Governance Scan` |
| Sample-load pipeline | `Semantic Model Governance - Load Sample Data` |
| Scan pipeline | `Semantic Model Governance - Scan` |

After this, an admin can open Fabric and trigger either pipeline without importing notebooks manually.

## Optional report-shell automation

The script can create a blank Power BI report shell if you already have the semantic model ID that should back the report.

```powershell
.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -CreateReportShell `
  -ReportSemanticModelId "33333333-3333-3333-3333-333333333333"
```

This is useful after governance tables exist and you have created or identified the Power BI semantic model that points to those tables.

## Why the visual report is not fully one-click yet

The fully designed report depends on the semantic model fields generated after the first sample or real scan run. In this version, the script creates the backend Fabric assets and pipelines, then admins build or connect the report using the provided report guide and starter DAX measures.

This keeps the provisioning reliable while avoiding brittle report-definition deployment against a semantic model that may not exist yet.

## Recommended admin flow

1. Run `scripts\provision-fabric-solution.ps1`.
2. Open the solution workspace.
3. Trigger `Semantic Model Governance - Load Sample Data`.
4. Build the report from `powerbi\report-build-guide.md` and `powerbi\measures.dax`.
5. Trigger `Semantic Model Governance - Scan`.
6. Refresh the report.
7. Schedule `Semantic Model Governance - Scan`.
8. Publish or update the Power BI/Fabric App.

