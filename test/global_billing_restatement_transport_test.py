import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("transport", Path(__file__).resolve().parents[1] / "tool/global_billing_restatement.py")
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)


class MigrationSafetyTests(unittest.TestCase):
    def plan(self, path="patients/p/advanceBilledAmount", value=200):
        return {"updates": {path: value}, "journal": [{"path": path, "oldValue": 100, "newValue": value}],
                "safety": {"unsafePaths": [], "calculatedStayIds": ["s"]}, "engineSha256": {}}

    def test_precise_patch_and_rollback_preserve_source_data(self):
        source = {"patients": {"p": {"advanceBilledAmount": 100, "payments": [{"utr": "immutable"}], "admissionDate": 123}},
                  "attendance": {"day": {"p": "Present"}}}
        plan = self.plan()
        after = transport.assert_safety(source, plan)
        self.assertEqual(after["patients"]["p"]["payments"], source["patients"]["p"]["payments"])
        self.assertEqual(after["attendance"], source["attendance"])
        self.assertEqual(transport.apply_values(after, {entry["path"]: entry["oldValue"] for entry in plan["journal"]}), source)

    def test_whole_objects_and_immutable_fields_are_rejected(self):
        for path in ("patients/p", "stays/s", "payments/p/amount", "stays/s/costOverride", "stays/s/dailyRate",
                     "stays/s/completedAt", "patients/p/payments/p/utr", "attendance/daily/d/p"):
            self.assertFalse(transport.allowed_path(path), path)

    def test_changed_source_or_tampered_journal_cancels_before_write(self):
        with self.assertRaises(RuntimeError):
            transport.assert_safety({"patients": {"p": {"advanceBilledAmount": 90}}}, self.plan())
        plan = self.plan()
        plan["journal"][0]["newValue"] = 300
        with self.assertRaises(RuntimeError):
            transport.assert_safety({"patients": {"p": {"advanceBilledAmount": 100}}}, plan)

    def test_duplicate_stay_aggregation_is_rejected(self):
        plan = self.plan()
        plan["safety"]["calculatedStayIds"].append("s")
        with self.assertRaises(RuntimeError):
            transport.assert_safety({"patients": {"p": {"advanceBilledAmount": 100}}}, plan)

    def test_negative_or_nonfinite_values_are_rejected(self):
        for value in (-1, float("inf"), float("nan")):
            with self.assertRaises(RuntimeError):
                transport.assert_safety({"patients": {"p": {"advanceBilledAmount": 100}}}, self.plan(value=value))

    def test_execution_requires_quiet_window_before_any_network_access(self):
        with self.assertRaises(RuntimeError):
            transport.execute(Path(__file__).parent, False)


if __name__ == "__main__":
    unittest.main()
