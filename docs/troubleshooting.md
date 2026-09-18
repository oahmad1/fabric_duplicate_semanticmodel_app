# Troubleshooting

| Issue | Likely cause | Resolution |
|---|---|---|
| No workspaces found | Workspace scope is empty or identity lacks access | Populate `config_workspaces` or set `WORKSPACE_IDS`; verify access in Fabric. |
| Execute Queries API warning | Tenant setting disabled or model permission missing | Ask Power BI admin to enable Execute Queries REST API and verify model access. |
| Data source warning | Identity cannot read data source metadata | Continue; scoring still works but confidence may be lower. |
| Provisioning script cannot find `az` | Azure CLI is not installed or not on PATH | Install Azure CLI, reopen the terminal, and rerun the script. |
| Workspace creation fails | Missing Fabric workspace creation permission or capacity requirement | Ask a Fabric admin to create the workspace or pass `-CapacityId` if your tenant requires capacity assignment on create. |
| Lakehouse creation fails | Workspace is not on a Fabric capacity or identity lacks item creation rights | Assign capacity to the workspace and verify Lakehouse creation permissions. |
| Notebook imports but is not attached to Lakehouse | Tenant behavior changed or import metadata was ignored | Open the notebook in Fabric and attach the Lakehouse manually; then rerun or update the notebook definition. |
| Pipeline creation fails | Identity lacks Data Pipeline authoring permission or pipeline definition API is blocked | Create the pipeline manually with a Notebook activity, or rerun the script with `-SkipPipelines`. |
| Initialization run fails | Workspace is not on capacity, Spark pool is unavailable, or package environment is missing | Run the initialization notebook manually in Fabric, or rerun provisioning with `-SkipInitializationRun` and initialize tables later. |
| Semantic model creation fails | Governance tables do not exist, Direct Lake/TMDL validation failed, or identity lacks semantic model authoring rights | Run the initialization pipeline, confirm tables exist, then rerun provisioning without `-SkipSemanticModel`. |
| Report clone fails | Missing `TemplateReportId`, invalid template report ID, missing Build permission on target model, or insufficient report clone permissions | Create a template report once, confirm the template IDs, then rerun with `-TemplateReportWorkspaceId` and `-TemplateReportId`. |
| No findings | Models may not overlap or threshold is too high | Lower `MIN_SCORE` for exploration, then tune back up. |
| Many false positives | Generic shared dimensions dominate | Raise thresholds or review weighting in `src\semantic_model_governance\analyzer.py`. |
| Notebook import fails | Analyzer package not installed in Fabric Environment | Run `%pip install git+https://github.com/oahmad1/fabric_duplicate_semanticmodel_app.git` or attach an Environment with the package. |
| Report shows old data | Report refresh is not aligned with scan schedule | Refresh semantic model after scan completion or schedule refresh after pipeline. |
