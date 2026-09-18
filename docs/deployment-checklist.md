# Deployment Checklist

Use this checklist to roll out the governance App.

## Phase 1: Prepare

- [ ] Choose automated provisioning or manual setup.
- [ ] Install Azure CLI if using `scripts\provision-fabric-solution.ps1`.
- [ ] Identify tenant ID and optional Fabric capacity ID.
- [ ] Create or reuse a dedicated Fabric workspace.
- [ ] Create or reuse a Lakehouse for governance tables.
- [ ] Confirm the scan identity can read the target workspaces and semantic models.
- [ ] Confirm Execute Queries REST API is enabled in the Power BI tenant.
- [ ] Decide scan scope for pilot workspaces.

## Phase 1a: Automated provisioning

- [ ] Run `scripts\provision-fabric-solution.ps1`.
- [ ] Confirm the script output includes workspace ID, Lakehouse ID, and notebook IDs.
- [ ] Open the Fabric workspace.
- [ ] Confirm both notebooks are imported.
- [ ] Confirm both notebooks are attached to the Lakehouse.
- [ ] Confirm `Semantic Model Governance - Load Sample Data` pipeline exists.
- [ ] Confirm `Semantic Model Governance - Scan` pipeline exists.

## Phase 2: Validate with sample data

- [ ] Import `fabric\notebooks\load_sample_governance_data.py` if using manual setup.
- [ ] Attach the Lakehouse if using manual setup.
- [ ] Install the package in the notebook environment.
- [ ] Run the sample notebook.
- [ ] If using automated provisioning, trigger the sample-load pipeline instead of running the notebook directly.
- [ ] Confirm governance tables are created.
- [ ] Build or connect the Power BI report to the tables.
- [ ] Confirm sample duplicate findings are visible.

## Phase 3: Enable real scans

- [ ] Import `fabric\notebooks\semantic_model_governance_scan.py`.
- [ ] Configure `config_workspaces` or notebook workspace parameters.
- [ ] Run the scan manually.
- [ ] If using automated provisioning, trigger the scan pipeline instead of running the notebook directly.
- [ ] Review `semantic_model_warnings`.
- [ ] Tune thresholds if needed.
- [ ] Confirm findings and common objects look reasonable.

## Phase 4: Schedule

- [ ] Create a Fabric Data Pipeline if one was not created by the provisioner.
- [ ] Add a Notebook activity for `semantic_model_governance_scan.py` if using manual setup.
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
