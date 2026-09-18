# Deployment Checklist

Use this checklist to roll out the governance App.

## Phase 1: Prepare

- [ ] Create a dedicated Fabric workspace.
- [ ] Create a Lakehouse for governance tables.
- [ ] Confirm the scan identity can read the target workspaces and semantic models.
- [ ] Confirm Execute Queries REST API is enabled in the Power BI tenant.
- [ ] Decide scan scope for pilot workspaces.

## Phase 2: Validate with sample data

- [ ] Import `fabric\notebooks\load_sample_governance_data.py`.
- [ ] Attach the Lakehouse.
- [ ] Install the package in the notebook environment.
- [ ] Run the sample notebook.
- [ ] Confirm governance tables are created.
- [ ] Build or connect the Power BI report to the tables.
- [ ] Confirm sample duplicate findings are visible.

## Phase 3: Enable real scans

- [ ] Import `fabric\notebooks\semantic_model_governance_scan.py`.
- [ ] Configure `config_workspaces` or notebook workspace parameters.
- [ ] Run the scan manually.
- [ ] Review `semantic_model_warnings`.
- [ ] Tune thresholds if needed.
- [ ] Confirm findings and common objects look reasonable.

## Phase 4: Schedule

- [ ] Create a Fabric Data Pipeline.
- [ ] Add a Notebook activity for `semantic_model_governance_scan.py`.
- [ ] Configure retry policy and failure notifications.
- [ ] Schedule the pipeline.
- [ ] Schedule report refresh after the pipeline completes.

## Phase 5: Publish App

- [ ] Finalize report pages.
- [ ] Publish the report in the solution workspace.
- [ ] Create or update the Power BI/Fabric App.
- [ ] Add App audience groups.
- [ ] Add support owner and refresh cadence to the App description.
- [ ] Share the [End-User Guide](end-user-guide.md).

## Phase 6: Operate

- [ ] Review scan health weekly.
- [ ] Review high-confidence duplicate candidates with model owners.
- [ ] Track consolidation decisions.
- [ ] Expand workspace scope after pilot validation.

