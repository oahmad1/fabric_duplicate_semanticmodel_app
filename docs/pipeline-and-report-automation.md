# Pipeline and Report Automation

The provisioner automates the repeatable Fabric control-plane items:

- Fabric workspace
- Lakehouse
- initialization notebook
- sample-data notebook
- real scan notebook
- Direct Lake semantic model
- initialization Data Pipeline
- sample-load Data Pipeline
- scan Data Pipeline

It can also clone and rebind a Power BI template report when you provide a template report ID.

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
| Initialization notebook | `Initialize Governance Tables` |
| Sample data notebook | `Load Sample Governance Data` |
| Scan notebook | `Semantic Model Governance Scan` |
| Semantic model | `Semantic Model Governance Semantic Model` |
| Initialization pipeline | `Semantic Model Governance - Initialize Tables` |
| Sample-load pipeline | `Semantic Model Governance - Load Sample Data` |
| Scan pipeline | `Semantic Model Governance - Scan` |

The initialization notebook creates empty governance tables if they do not already exist. Existing tables are left unchanged.

## Optional report-template automation

The script can clone an existing Power BI report template and bind it to the generated governance semantic model.

```powershell
.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -TemplateReportWorkspaceId "11111111-1111-1111-1111-111111111111" `
  -TemplateReportId "22222222-2222-2222-2222-222222222222"
```

This is useful after you create a standard report once and want future deployments to be repeatable.

## Why a template report is still needed

The semantic model is generated automatically because the schema is standardized. A full report layout is a separate authored artifact. In production, create the report once from the generated semantic model, then use that report as the template for future automated deployments.

This avoids brittle handcrafted PBIR visual JSON while still enabling repeatable report deployment through the supported Power BI clone and rebind API.

## Recommended admin flow

1. Run `scripts\provision-fabric-solution.ps1`.
2. Open the solution workspace.
3. Confirm the generated semantic model exists.
4. Trigger `Semantic Model Governance - Load Sample Data`.
5. Refresh the semantic model/report.
6. Build or clone the report from `powerbi\report-build-guide.md`.
7. Trigger `Semantic Model Governance - Scan`.
8. Refresh the semantic model/report.
9. Schedule `Semantic Model Governance - Scan`.
10. Publish or update the Power BI/Fabric App.

