# Operations Guide

## Recommended operating model

| Role | Responsibility |
|---|---|
| Fabric admin | Owns provisioning, workspace, schedule, permissions, and scan health. |
| BI COE | Reviews findings, coordinates model owners, tracks remediation. |
| Model owners | Validate whether findings are true duplicates and approve changes. |
| End users | Consume the published App and review assigned findings. |

## Provisioning updates

Use `scripts\provision-fabric-solution.ps1` when deploying a new environment or refreshing notebook and pipeline definitions. The script reuses existing resources by display name and updates notebook and pipeline definitions in place.

Before rerunning in production:

- Confirm the target workspace and Lakehouse names are correct.
- Confirm any customized notebook code has been committed back to source control.
- Confirm any customized pipeline definition has been committed back to source control.
- Use explicit workspace IDs for scan scope when possible.

## Triggering and scheduling

After provisioning:

1. Trigger `Semantic Model Governance - Load Sample Data` to validate tables and report design.
2. Trigger `Semantic Model Governance - Scan` for real metadata collection.
3. Schedule `Semantic Model Governance - Scan` after pilot validation.
4. Schedule the Power BI report refresh after the scan pipeline completes.

## Scheduling

Start with a weekly scan. Move to nightly once the workspace scope and runtime are understood.

For large tenants:

- Use multiple config tables by domain.
- Schedule scans at different times.
- Keep thresholds conservative.
- Monitor warning volume.

## Threshold management

Default thresholds:

| Setting | Default |
|---|---:|
| `MIN_SCORE` | 0.60 |
| `DUPLICATE_THRESHOLD` | 0.85 |
| `OVERLAP_THRESHOLD` | 0.65 |

Increase thresholds to reduce false positives. Decrease thresholds for exploratory reviews.

## Run monitoring

Monitor:

- latest completed run timestamp
- warning count
- model count trend
- finding count trend
- failed pipeline activities

## Governance workflow

1. Review top `likely_duplicate` findings.
2. Identify authoritative model.
3. Review report dependencies and usage.
4. Coordinate with model owners.
5. Migrate reports where appropriate.
6. Retire duplicates only after approval.
7. Track resolved findings outside this MVP, or extend the schema with a remediation table.
