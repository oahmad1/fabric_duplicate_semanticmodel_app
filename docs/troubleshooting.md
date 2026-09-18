# Troubleshooting

| Issue | Likely cause | Resolution |
|---|---|---|
| No workspaces found | Workspace scope is empty or identity lacks access | Populate `config_workspaces` or set `WORKSPACE_IDS`; verify access in Fabric. |
| Execute Queries API warning | Tenant setting disabled or model permission missing | Ask Power BI admin to enable Execute Queries REST API and verify model access. |
| Data source warning | Identity cannot read data source metadata | Continue; scoring still works but confidence may be lower. |
| No findings | Models may not overlap or threshold is too high | Lower `MIN_SCORE` for exploration, then tune back up. |
| Many false positives | Generic shared dimensions dominate | Raise thresholds or review weighting in `src\semantic_model_governance\analyzer.py`. |
| Notebook import fails | Analyzer package not installed in Fabric Environment | Run `%pip install git+https://github.com/oahmad1/fabric_duplicate_semanticmodel_app.git` or attach an Environment with the package. |
| Report shows old data | Report refresh is not aligned with scan schedule | Refresh semantic model after scan completion or schedule refresh after pipeline. |

