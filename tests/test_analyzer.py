from __future__ import annotations

import json
import unittest
from pathlib import Path

from semantic_model_governance import build_signature, common_object_rows, finding_rows, find_matches


ROOT = Path(__file__).resolve().parents[1]
SAMPLE_PATH = ROOT / "samples" / "dummy_semantic_models.json"


class AnalyzerTests(unittest.TestCase):
    def signatures(self):
        payload = json.loads(SAMPLE_PATH.read_text(encoding="utf-8"))
        return [build_signature(model, payload.get("warnings", [])) for model in payload["models"]]

    def test_finds_expected_duplicate_and_overlap_pairs(self):
        matches = find_matches(self.signatures(), min_score=0.60, top=10)
        by_pair = {frozenset((m["left"]["modelId"], m["right"]["modelId"])): m for m in matches}

        self.assertEqual(len(matches), 3)
        self.assertEqual(by_pair[frozenset(("contoso-sales-certified", "contoso-sales-exec-copy"))]["classification"], "likely_duplicate")
        self.assertEqual(by_pair[frozenset(("contoso-sales-certified", "contoso-sales-regional-extended"))]["classification"], "high_overlap")

    def test_unrelated_models_are_not_reported_at_default_threshold(self):
        matches = find_matches(self.signatures(), min_score=0.60, top=10)
        pairs = {frozenset((m["left"]["modelId"], m["right"]["modelId"])) for m in matches}

        self.assertNotIn(frozenset(("contoso-sales-certified", "contoso-hr-headcount")), pairs)
        self.assertNotIn(frozenset(("contoso-sales-certified", "contoso-inventory-operations")), pairs)

    def test_fabric_table_rows_include_common_objects(self):
        matches = find_matches(self.signatures(), min_score=0.60, top=10)
        rows = finding_rows("run-001", matches)
        common_rows = common_object_rows("run-001", matches)

        self.assertEqual(rows[0]["classification"], "likely_duplicate")
        self.assertGreater(rows[0]["shared_tables"], 0)
        self.assertIn(
            {"run_id": "run-001", "finding_id": "run-001-00001", "object_type": "tables", "object_name": "sales"},
            common_rows,
        )


if __name__ == "__main__":
    unittest.main()

