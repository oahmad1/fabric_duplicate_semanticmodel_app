# End-User Guide

This guide is for users who open the published Fabric or Power BI App.

## What you can do

Use the App to identify semantic models that may be duplicates or high-overlap copies.

You can:

- View top duplicate candidates.
- Filter by workspace, model, classification, and confidence.
- See shared tables, columns, and measures for each finding.
- Export findings for review.
- Track scan health and metadata coverage.

## How to use the App

1. Open the published App.
2. Start on the **Executive Overview** page.
3. Review counts for likely duplicates and high-overlap findings.
4. Open **Duplicate Candidates**.
5. Filter to your workspace or model.
6. Select a finding.
7. Open **Common Objects** to see why the models were flagged.
8. Work with model owners before consolidating or retiring any model.

## How to interpret classifications

| Classification | Meaning |
|---|---|
| `likely_duplicate` | Strong candidate for consolidation review. The models have very similar metadata. |
| `high_overlap` | One model may have been copied and extended, or both may come from the same pattern. |
| `partial_overlap` | Shared objects exist, but manual review is needed. |

## What not to assume

A finding does not mean a model should be deleted. Before taking action, review:

- Report dependencies.
- Owner approval.
- Certification or endorsement.
- Refresh reliability.
- Usage and adoption.
- Business criticality.

## Common objects

The App shows common:

- tables
- columns
- measures

These explain why the models were flagged and help owners decide whether consolidation is appropriate.

