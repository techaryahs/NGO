"""Controlled RTDB restatement transport. Credentials never enter reports."""
import argparse
import concurrent.futures
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sqlite3
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BRANCHES = ("patients", "stays", "attendance", "attendant_attendance",
            "payments", "paymentHistory", "rooms", "admin_settings/pricing")


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False).encode("utf-8")).hexdigest()


def write_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)


class Database:
    def __init__(self):
        config = {}
        for line in (ROOT / ".env").read_text(encoding="utf-8-sig").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip().strip("\"'")
        self.project = config["FIREBASE_PROJECT_ID"]
        self.url = config["FIREBASE_DATABASE_URL"].rstrip("/")
        parsed = urllib.parse.urlparse(self.url)
        if (self.project != "ngo-management-system-new-as" or parsed.scheme != "https" or
                not (parsed.hostname or "").startswith(self.project + "-default-rtdb.") or
                not (parsed.hostname or "").endswith((".firebaseio.com", ".firebasedatabase.app")) or
                parsed.query or parsed.fragment or parsed.path not in ("", "/")):
            raise RuntimeError("Unexpected production database configuration")
        prefs_path = Path(os.environ["APPDATA"]) / "com.example/ngo/shared_preferences.json"
        prefs = json.loads(prefs_path.read_text(encoding="utf-8"))
        self.account = prefs.get("flutter.firebase_user_id")
        refresh = prefs.get("flutter.firebase_refresh_token")
        if not refresh or not self.account:
            raise RuntimeError("No authenticated application session available")
        request = urllib.request.Request(
            "https://securetoken.googleapis.com/v1/token?" +
            urllib.parse.urlencode({"key": config["FIREBASE_API_KEY"]}),
            data=urllib.parse.urlencode({"grant_type": "refresh_token", "refresh_token": refresh}).encode(),
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                token_data = json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Authentication failed (HTTP {error.code}); no writes performed") from None
        self.token = token_data["id_token"]
        if token_data["user_id"] != self.account:
            raise RuntimeError("Refreshed session does not match the cache account")

    def request(self, path, method="GET", payload=None):
        request = urllib.request.Request(
            self.url + "/" + path + ".json?" + urllib.parse.urlencode({"auth": self.token}),
            data=None if payload is None else json.dumps(payload, allow_nan=False).encode(),
            headers={"Content-Type": "application/json"}, method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"RTDB {method} {path or '/'} failed (HTTP {error.code})") from None
        except urllib.error.URLError:
            raise RuntimeError(f"RTDB {method} network failure; verify any write outcome before retrying") from None

    def snapshot(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            values = list(pool.map(self.request, BRANCHES))
        result = dict(zip(BRANCHES, values))
        result["capturedAt"] = dt.datetime.now().astimezone().isoformat()
        return result


def inventory(backup):
    backup = backup.resolve(strict=True)
    backup_hash = hashlib.sha256(backup.read_bytes()).hexdigest()
    database = Database()
    role = database.request("users/" + database.account)
    if not isinstance(role, dict) or role.get("role") not in ("admin", "staff"):
        raise RuntimeError("Application session cannot reconcile billing")
    snapshot = database.snapshot()
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    directory = ROOT / "migration_reports" / ("global_billing_restatement_" + stamp)
    directory.mkdir(parents=True, exist_ok=False)
    write_json(directory / "source_snapshot.json", snapshot)
    write_json(directory / "metadata.json", {
        "project": database.project, "backupPath": str(backup), "backupSha256": backup_hash,
        "capturedAt": snapshot["capturedAt"],
        "branchHashes": {path: digest(snapshot[path]) for path in BRANCHES},
    })
    patients = snapshot["patients"] or {}
    stays = snapshot["stays"] or {}
    fields = {}
    for collection, records in (("patients", patients), ("stays", stays)):
        for record in records.values():
            for key in record:
                fields[collection + "/" + key] = fields.get(collection + "/" + key, 0) + 1
    print(json.dumps({"directory": str(directory), "patients": len(patients),
                      "stays": len(stays), "fieldInventory": fields}, indent=2))
    return directory


def allowed_path(path):
    parts = path.split("/")
    patient = {"advanceBilledAmount", "attendanceCharges", "totalPaidAmount", "currentDueAmount",
               "refundDueAmount", "totalRefundDueAmount", "totalRefundedAmount", "paymentPending",
               "paymentStatus", "totalPresentDays", "totalAbsentDays"}
    summary = {"cycleId", "total", "paid", "refunded", "netPaid", "due", "refundDue", "status"}
    if len(parts) < 3 or any(not part for part in parts):
        return False
    if parts[0] == "patients" and parts[2] in patient:
        return len(parts) == 3
    if parts[0] == "stays" and parts[2] in {"totalCost", "billableDays", "baseCost", "extraAttendantCost"}:
        return len(parts) == 3
    suffix = None
    if parts[0] == "patients" and parts[2] == "admissionBalances" and len(parts) >= 5:
        suffix = parts[4:]
    if parts[0] == "stays" and parts[2] == "billingSummary" and len(parts) >= 4:
        suffix = parts[3:]
    return bool(suffix and ((len(suffix) == 1 and suffix[0] in summary) or
                           (len(suffix) == 2 and suffix[0] in {"segmentCharges", "segmentDays"})))


def apply_values(source, updates):
    result = json.loads(json.dumps(source))
    for path, value in updates.items():
        parts = path.split("/")
        parent = result
        for key in parts[:-1]:
            parent = parent.setdefault(key, {})
            if not isinstance(parent, dict):
                raise RuntimeError(f"Cannot patch non-object at {path}")
        if value is None:
            parent.pop(parts[-1], None)
        else:
            parent[parts[-1]] = value
    return result


def get_value(source, path):
    value = source
    for key in path.split("/"):
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def assert_safety(source, plan):
    updates = plan["updates"]
    if len(updates) != len(plan["journal"]):
        raise RuntimeError("Journal and payload differ")
    if plan["safety"]["unsafePaths"]:
        raise RuntimeError("Unsafe paths in plan")
    journal_paths = set()
    for item in plan["journal"]:
        path = item["path"]
        if not allowed_path(path) or path in journal_paths:
            raise RuntimeError("Unsafe or duplicate journal path: " + path)
        journal_paths.add(path)
        if get_value(source, path) != item["oldValue"] or updates.get(path) != item["newValue"]:
            raise RuntimeError("Journal does not match calculation snapshot")
    if set(updates) != journal_paths:
        raise RuntimeError("Unjournaled update")
    paths = sorted(updates)
    for previous, current in zip(paths, paths[1:]):
        if current.startswith(previous + "/"):
            raise RuntimeError("Overlapping object/field writes")
    ids = plan["safety"]["calculatedStayIds"]
    if len(ids) != len(set(ids)):
        raise RuntimeError("Duplicate stay aggregation")
    for path, expected in plan["engineSha256"].items():
        if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != expected:
            raise RuntimeError("Production engine changed since dry run")
    for path, value in updates.items():
        if isinstance(value, (int, float)) and not isinstance(value, bool) and (not math.isfinite(value) or value < 0):
            raise RuntimeError("Negative or nonfinite derived value: " + path)
    return apply_values(source, updates)


def run_calculation(source_path, report_path):
    subprocess.run(["dart.bat", "run", "tool/global_billing_restatement.dart",
                    str(source_path), str(report_path)], cwd=ROOT, check=True)
    return json.loads(report_path.read_text(encoding="utf-8"))


def prepare(directory):
    directory = directory.resolve(strict=True)
    source = json.loads((directory / "source_snapshot.json").read_text(encoding="utf-8"))
    report_path = directory / "dry_run.json"
    plan = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else run_calculation(directory / "source_snapshot.json", report_path)
    expected = assert_safety(source, plan)
    # Simulate the complete patch and a second real-engine pass before any write.
    simulated = directory / "simulated_snapshot.json"
    write_json(simulated, expected)
    second = run_calculation(simulated, directory / "simulated_second_pass.json")
    if second["updates"]:
        raise RuntimeError("Dry run is not idempotent")
    metadata = json.loads((directory / "metadata.json").read_text(encoding="utf-8"))
    if hashlib.sha256(Path(metadata["backupPath"]).read_bytes()).hexdigest() != metadata["backupSha256"]:
        raise RuntimeError("Original backup changed")
    write_json(directory / "change_journal.json", {
        "backupSha256": metadata["backupSha256"], "sourceBranchHashes": metadata["branchHashes"],
        "engineSha256": plan["engineSha256"], "asOf": plan["asOf"],
        "changes": plan["journal"],
        "rollbackPatch": {item["path"]: item["oldValue"] for item in plan["journal"]},
        "forwardPatchSha256": digest(plan["updates"]),
    })
    summary = plan["summary"]
    lines = ["Global billing restatement — dry run", "", json.dumps(summary, indent=2), "",
             "Manual review / preserved fields:"]
    for record in plan["blocked"]:
        lines.append(f"- {record['collection']}/{record['id']}" +
                     (f"/{record['field']}" if record.get("field") else "") +
                     (f" (cycle {record['cycleId']})" if record.get("cycleId") else "") +
                     ": " + record["reason"])
    (directory / "summary.txt").write_text("\n".join(lines), encoding="utf-8")
    write_json(directory / "prepared.json", {
        "dryRunSafetyPassed": True, "simulatedSecondPassDifferences": 0,
        "payloadSha256": digest(plan["updates"]), "reportSha256": digest(plan),
    })
    print("Prepared: safety invariants passed; simulated second pass has ZERO differences.")


def execute(directory, quiet_window):
    directory = directory.resolve(strict=True)
    if not quiet_window:
        raise RuntimeError("A confirmed quiet window is required for multipath PATCH")
    if (directory / "apply_intent.json").exists():
        raise RuntimeError("Apply was already attempted; verify its outcome instead of retrying")
    source = json.loads((directory / "source_snapshot.json").read_text(encoding="utf-8"))
    plan = json.loads((directory / "dry_run.json").read_text(encoding="utf-8"))
    prepared = json.loads((directory / "prepared.json").read_text(encoding="utf-8"))
    if prepared["reportSha256"] != digest(plan):
        raise RuntimeError("Prepared report was modified")
    assert_safety(source, plan)
    database = Database()
    live = database.snapshot()
    if any(live[path] != source[path] for path in BRANCHES):
        write_json(directory / "aborted_stale_snapshot.json", {"reason": "Live data changed after dry run", "changedBranches": [path for path in BRANCHES if live[path] != source[path]]})
        raise RuntimeError("Live data changed after dry run; no production write")
    metadata = json.loads((directory / "metadata.json").read_text(encoding="utf-8"))
    if hashlib.sha256(Path(metadata["backupPath"]).read_bytes()).hexdigest() != metadata["backupSha256"]:
        raise RuntimeError("Original backup changed")
    write_json(directory / "apply_intent.json", {
        "confirmedQuietWindow": True, "startedAt": dt.datetime.now().astimezone().isoformat(),
        "changedFields": len(plan["updates"]), "payloadSha256": digest(plan["updates"]),
        "writeRequests": 1 if plan["updates"] else 0,
    })
    if plan["updates"]:
        database.request("", method="PATCH", payload=plan["updates"])
    verify(directory, database)


def verify(directory, database=None):
    directory = directory.resolve(strict=True)
    database = database or Database()
    source = json.loads((directory / "source_snapshot.json").read_text(encoding="utf-8"))
    plan = json.loads((directory / "dry_run.json").read_text(encoding="utf-8"))
    expected = assert_safety(source, plan)
    actual = database.snapshot()
    mismatch = [path for path in BRANCHES if actual[path] != expected[path]]
    if mismatch:
        write_json(directory / "verification_failed.json", {"mismatchedBranches": mismatch})
        raise RuntimeError("Post-write data differs from the journal; verification failed")
    actual["calculationAsOf"] = source["capturedAt"]
    post_file = directory / "post_snapshot.json"
    write_json(post_file, actual)
    second = run_calculation(post_file, directory / "second_reconciliation.json")
    if second["updates"]:
        raise RuntimeError("Second complete reconciliation has remaining differences")
    metadata = json.loads((directory / "metadata.json").read_text(encoding="utf-8"))
    if hashlib.sha256(Path(metadata["backupPath"]).read_bytes()).hexdigest() != metadata["backupSha256"]:
        raise RuntimeError("Original backup changed")
    write_json(directory / "verification.json", {
        "status": "verified", "allTargetedValuesMatch": True,
        "paymentsUnchanged": actual["payments"] == source["payments"],
        "paymentHistoryUnchanged": actual["paymentHistory"] == source["paymentHistory"],
        "embeddedPaymentsUnchanged": all(actual["patients"][pid].get("payments") == value.get("payments") for pid, value in source["patients"].items()),
        "attendanceUnchanged": actual["attendance"] == source["attendance"] and actual["attendant_attendance"] == source["attendant_attendance"],
        "sourceAndManualFieldsUnchanged": True,
        "unrelatedPathsUnchanged": True, "originalBackupUnchanged": True,
        "secondReconciliationChangedFields": len(second["updates"]),
        "secondReconciliationChangedRecords": second["summary"]["changedRecords"],
        "afterBranchHashes": {path: digest(actual[path]) for path in BRANCHES},
    })
    print("Production verification passed. Second complete reconciliation: ZERO differences.")


def refresh_cache(directory):
    directory = directory.resolve(strict=True)
    verification = json.loads((directory / "verification.json").read_text(encoding="utf-8"))
    if verification["status"] != "verified" or verification["secondReconciliationChangedFields"] != 0:
        raise RuntimeError("Cache cannot be updated before verified RTDB reconciliation")
    cache_path = Path(os.environ["APPDATA"]) / "com.example/ngo/ngo_management/persistent_cache.sqlite"
    if not cache_path.exists():
        write_json(directory / "cache_verification.json", {"status": "no local cache file; RTDB will hydrate it"})
        return
    # SQLite's backup API produces a consistent additional rollback snapshot.
    with sqlite3.connect(cache_path) as connection, sqlite3.connect(directory / "cache_before.sqlite") as backup:
        connection.backup(backup)
    prefs = json.loads((Path(os.environ["APPDATA"]) / "com.example/ngo/shared_preferences.json").read_text(encoding="utf-8"))
    environment = os.environ.copy()
    environment["NGO_RESTATEMENT_DIRECTORY"] = str(directory)
    environment["NGO_RESTATEMENT_CACHE_FILE"] = str(cache_path)
    environment["NGO_RESTATEMENT_CACHE_ACCOUNT"] = prefs["flutter.firebase_user_id"]
    subprocess.run(["flutter.bat", "test", "tool/restatement_cache_refresh.dart", "--reporter", "expanded"],
                   cwd=ROOT, env=environment, check=True)
    plan = json.loads((directory / "dry_run.json").read_text(encoding="utf-8"))
    targets = set("/".join(path.split("/")[:2]) for path in plan["updates"])
    account = prefs["flutter.firebase_user_id"]
    with sqlite3.connect(directory / "cache_before.sqlite") as before, sqlite3.connect(cache_path) as after:
        tables = [row[0] for row in before.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        for table in tables:
            # Names come from SQLite itself, never from user input.
            quoted = '"' + table.replace('"', '""') + '"'
            old_rows = before.execute(f"SELECT * FROM {quoted}").fetchall()
            new_rows = after.execute(f"SELECT * FROM {quoted}").fetchall()
            columns = [item[1] for item in before.execute(f"PRAGMA table_info({quoted})")]
            if table not in ("cached_patients", "cached_stays"):
                if old_rows != new_rows:
                    raise RuntimeError("Unrelated cache table changed: " + table)
                continue
            keys = (columns.index("account_id"), columns.index("id"))
            old_by_key = {(row[keys[0]], row[keys[1]]): row for row in old_rows}
            new_by_key = {(row[keys[0]], row[keys[1]]): row for row in new_rows}
            if set(old_by_key) != set(new_by_key):
                raise RuntimeError("Cache rows were added or removed unexpectedly")
            collection = "patients" if table == "cached_patients" else "stays"
            for key, row in old_by_key.items():
                if key[0] != account or f"{collection}/{key[1]}" not in targets:
                    if row != new_by_key[key]:
                        raise RuntimeError("Unrelated cache row or account partition changed")
    write_json(directory / "cache_integrity.json", {"status": "verified",
        "unrelatedTablesUnchanged": True, "otherAccountPartitionsUnchanged": True,
        "unchangedRowsPreserved": True, "noRowsAddedOrDeleted": True})


def finalize(directory):
    directory = directory.resolve(strict=True)
    plan = json.loads((directory / "dry_run.json").read_text(encoding="utf-8"))
    verification = json.loads((directory / "verification.json").read_text(encoding="utf-8"))
    cache = json.loads((directory / "cache_verification.json").read_text(encoding="utf-8"))
    integrity_file = directory / "cache_integrity.json"
    integrity = json.loads(integrity_file.read_text(encoding="utf-8")) if integrity_file.exists() else None
    validation = json.loads((directory / "validation_results.json").read_text(encoding="utf-8"))
    if (verification["status"] != "verified" or verification["secondReconciliationChangedFields"] != 0 or
            not validation["flutterTestPassed"] or not validation["windowsReleaseBuildPassed"] or
            validation["analysisErrors"] != 0):
        raise RuntimeError("Cannot finalize an unverified migration or failing validation")
    live = Database().snapshot()
    verified_source = json.loads((directory / "post_snapshot.json").read_text(encoding="utf-8"))
    if any(live[path] != verified_source[path] for path in BRANCHES):
        raise RuntimeError("Live data changed after verification; cannot finalize unchanged state")
    metadata = json.loads((directory / "metadata.json").read_text(encoding="utf-8"))
    if hashlib.sha256(Path(metadata["backupPath"]).read_bytes()).hexdigest() != metadata["backupSha256"]:
        raise RuntimeError("Original backup changed")
    final_live_check = {"status": "verified", "checkedAt": live["capturedAt"],
                        "allVerifiedBranchesStillMatch": True, "originalBackupUnchanged": True}
    write_json(directory / "final_live_check.json", final_live_check)
    source = json.loads((directory / "source_snapshot.json").read_text(encoding="utf-8"))
    manual_review = []
    for record in plan["blocked"]:
        raw = source[record["collection"]][record["id"]]
        fields = ("patientId", "admissionDate", "registrationDate", "completedAt", "updatedAt", "status", "cycleId")
        if record.get("field") in ("baseCost", "extraAttendantCost"):
            fields = ("dailyRate", "dailyRateIsManual", "longStayDailyRate", "costOverride")
        if record.get("field") in ("paidAmount", "pendingAmount"):
            fields = (record["field"], "cycleId")
        manual_review.append({**record, "sourceFacts": {field: raw.get(field) for field in fields}})
    write_json(directory / "final_report.json", {
        "status": "verified_deterministic_records_reconciled_with_explicit_blocks",
        "summary": plan["summary"], "verification": verification,
        "cache": cache, "cacheIntegrity": integrity, "validation": validation,
        "finalLiveCheck": final_live_check,
        "manualReview": manual_review,
        "dryRunReport": str(directory / "dry_run.json"),
        "changeJournal": str(directory / "change_journal.json"),
    })
    text = ["Global production billing restatement — verified deterministic records", "",
            json.dumps(plan["summary"], indent=2), "", "Verification:", json.dumps(verification, indent=2),
            "", "Validation:", json.dumps(validation, indent=2), "", "Records/fields requiring manual review:"]
    text += [f"{record['collection']}/{record['id']}" +
             (f"/{record['field']}" if record.get("field") else "") + ": " + record["reason"]
             + " Source: " + json.dumps(record["sourceFacts"])
             for record in manual_review]
    (directory / "final_summary.txt").write_text("\n".join(text), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["inventory", "prepare", "execute", "verify", "cache", "finalize"])
    parser.add_argument("--backup", type=Path)
    parser.add_argument("--directory", type=Path)
    parser.add_argument("--quiet-window-confirmed", action="store_true")
    args = parser.parse_args()
    if args.mode == "inventory":
        if args.backup is None:
            parser.error("--backup is required")
        inventory(args.backup)
    else:
        if args.directory is None:
            parser.error("--directory is required")
        if args.mode == "execute":
            execute(args.directory, args.quiet_window_confirmed)
        else:
            {"prepare": prepare, "verify": verify, "cache": refresh_cache, "finalize": finalize}[args.mode](args.directory)


if __name__ == "__main__":
    main()
