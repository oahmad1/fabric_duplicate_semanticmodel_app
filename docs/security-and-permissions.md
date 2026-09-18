# Security and Permissions

## Read-only design

This solution reads semantic model metadata and writes governance results to its own Fabric tables. It does not modify, delete, rename, endorse, certify, refresh, or publish semantic models.

## Required access

The scan identity needs:

- Access to the configured Fabric workspaces.
- Permission to read semantic model metadata.
- Permission to call the Power BI Execute Queries REST API.
- Permission to read semantic model data source metadata when available.
- Write access to the solution Lakehouse or Warehouse.

## End-user access

End users only need access to the published App/report. They do not need direct access to the scan notebook or metadata export tables unless your governance process requires it.

## Data sensitivity

Governance tables can include:

- workspace names
- semantic model names
- table names
- column names
- measure names and expressions
- relationship shapes
- data source identifiers

Treat these outputs as internal metadata. Do not publish raw tables outside approved locations.

## Production identity

For production, prefer a dedicated service principal, managed identity, or approved automation identity over a personal user account. Validate the identity has only the permissions required for the configured scan scope.

