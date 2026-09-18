# Admin Installation Guide

This guide helps Fabric admins deploy the solution so end users can view duplicate semantic model findings without writing code.

For one-command setup, see [Automated Provisioning](automated-provisioning.md). For a condensed rollout view, use the [Deployment Checklist](deployment-checklist.md).

## Prerequisites

- Fabric workspace where you can create Lakehouses, notebooks, pipelines, semantic models, reports, and Apps.
- Permission to read the workspaces and semantic models you want to scan.
- Power BI tenant setting enabled for Execute Queries REST API.
- A Fabric capacity for scheduled notebook execution.
- Azure CLI installed if using automated provisioning.
- Optional: a service principal or managed identity strategy for production scheduling.

## Recommended path: automated provisioning

Run the provisioning script from a local terminal:

```powershell
git clone https://github.com/oahmad1/fabric_duplicate_semanticmodel_app.git
cd fabric_duplicate_semanticmodel_app

.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -WorkspaceName "Semantic Model Governance" `
  -LakehouseName "SemanticModelGovernanceLH"
```

The script:

1. Runs `az login --allow-no-subscriptions`, optionally with the provided tenant ID.
2. Creates or reuses the Fabric workspace.
3. Creates or reuses the Lakehouse.
4. Creates or updates the sample-data notebook.
5. Creates or updates the scan notebook.
6. Binds both notebooks to the Lakehouse through Fabric notebook metadata.
7. Creates or updates the sample-load and scan Data Pipelines.

After the script completes, trigger the sample-load pipeline, continue at [Step 4: Configure workspace scope](#step-4-configure-workspace-scope), then build the report and publish the App.

## Manual path

Use the manual path when you cannot run local provisioning scripts or when your tenant requires centrally managed workspace creation.

## Step 1: Create the solution workspace

Create a dedicated Fabric workspace, for example:

```text
Semantic Model Governance
```

Recommended workspace contents:

- One Lakehouse for governance tables.
- One Notebook for metadata scan.
- One Pipeline for scheduling.
- One Power BI semantic model and report.
- One published App for end users.

## Step 2: Create the Lakehouse

Create a Lakehouse, for example:

```text
SemanticModelGovernanceLH
```

Attach this Lakehouse to both notebooks:

- `fabric\notebooks\semantic_model_governance_scan.py`
- `fabric\notebooks\load_sample_governance_data.py`

The notebooks create the required Delta tables on first write.

## Step 3: Configure the analyzer package

Create or edit a Fabric Environment and add:

```python
%pip install git+https://github.com/oahmad1/fabric_duplicate_semanticmodel_app.git
```

Attach the Environment to the scan notebook.

## Step 4: Configure workspace scope

For a controlled rollout, start with a small set of workspaces.

Option A: edit notebook parameters:

```python
SCAN_ALL_ACCESSIBLE_WORKSPACES = False
WORKSPACE_IDS = ["00000000-0000-0000-0000-000000000000"]
WORKSPACE_NAMES = []
```

Option B: create a `config_workspaces` table in the Lakehouse with:

| Column | Description |
|---|---|
| `workspace_id` | Preferred stable workspace ID. |
| `workspace_name` | Optional exact workspace name. |
| `enabled` | `true` or `false`. |
| `notes` | Admin notes. |

Use `fabric\lakehouse-schema\config_workspaces.csv` as a starter.

## Step 5: Validate with sample data

Before scanning real semantic models, run:

```text
fabric\notebooks\load_sample_governance_data.py
```

Expected result:

- Governance tables are created.
- Sample inventory rows are written.
- Three sample findings are created.
- The report can be built and validated without tenant API dependencies.

## Step 6: Run the real scan

Run:

```text
fabric\notebooks\semantic_model_governance_scan.py
```

Expected tables:

- `semantic_model_scan_runs`
- `semantic_model_inventory`
- `semantic_model_objects`
- `semantic_model_findings`
- `semantic_model_common_objects`
- `semantic_model_warnings`

## Step 7: Build the report

Follow [Power BI Report Build Guide](../powerbi/report-build-guide.md).

Minimum report pages:

1. Executive Overview
2. Duplicate Candidates
3. Common Objects
4. Model Inventory
5. Scan Health

## Step 8: Schedule the scan

If you used automated provisioning, the scan pipeline already exists as `Semantic Model Governance - Scan`. Open it, test it, then add a schedule.

If you used manual setup, create a Fabric Data Pipeline:

1. Add a Notebook activity.
2. Select `semantic_model_governance_scan.py`.
3. Set retry policy, for example 2 retries.
4. Schedule nightly or weekly.
5. Configure alerts for failure.

Recommended schedule:

- MVP: weekly
- Active governance program: nightly
- Large tenant: split by domain/workspace group and stagger schedules

## Optional: Create a blank report shell

After governance tables exist and you have created or identified the semantic model that points to those tables, rerun the provisioner with:

```powershell
.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -CreateReportShell `
  -ReportSemanticModelId "33333333-3333-3333-3333-333333333333"
```

This creates a blank Power BI report bound to the semantic model. Use [Power BI Report Build Guide](../powerbi/report-build-guide.md) to add the recommended pages and visuals.

## Step 9: Publish the App

In the Fabric workspace:

1. Publish or save the report.
2. Select **Create app** or **Update app**.
3. Add the report to an audience.
4. Grant users access.
5. Add support contact and refresh schedule details.

End users now consume the solution without notebooks or code.

## Ongoing refresh

New semantic model information is populated by the scheduled notebook run:

1. The pipeline starts the scan.
2. The notebook reads configured workspaces.
3. It detects current semantic models and metadata.
4. It writes a new scan run, inventory, findings, common objects, and warnings.
5. The Power BI report refreshes after the notebook completes.

This means the App shows the latest completed scan, not live API results from each user's browser session.
