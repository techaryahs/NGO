import json
from pathlib import Path

export_path = Path(r"C:\Users\sahil\OneDrive\Desktop\ngo-management-system-new-as-default-rtdb-export.json")

with open(export_path, "r", encoding="utf-8") as f:
    data = json.load(f)

print("Export root keys:", list(data.keys()))
metadata_stats = data.get("metadata", {}).get("stats", {})
system_counters = data.get("system_counters", {})
print("metadata/stats in export:", metadata_stats)
print("system_counters in export:", system_counters)

patients = data.get("patients", {})
total_patients = len(patients)

numeric_regs = []
non_numeric_regs = []
missing_regs = []
counts = {}

for pid, p in patients.items():
    if not isinstance(p, dict):
        continue
    reg = p.get("registrationNumber")
    if reg is None:
        missing_regs.append(pid)
        continue
    reg_str = str(reg).strip()
    if not reg_str:
        missing_regs.append(pid)
        continue
    try:
        val = int(reg_str)
        if val > 0:
            numeric_regs.append((val, pid, p.get("fullName", "")))
            counts[val] = counts.get(val, 0) + 1
        else:
            non_numeric_regs.append((pid, reg))
    except ValueError:
        non_numeric_regs.append((pid, reg))

numeric_regs.sort(key=lambda x: x[0])
duplicates = {k: v for k, v in counts.items() if v > 1}

print("==================================================")
print("ACTUAL DATABASE EXPORT AUDIT REPORT")
print("==================================================")
print(f"Total patient records inspected: {total_patients}")
print(f"Numeric registration numbers count: {len(numeric_regs)}")
print(f"Lowest numeric registration number: {numeric_regs[0][0] if numeric_regs else None} (Patient: {numeric_regs[0][2]})")
print(f"Highest numeric registration number: {numeric_regs[-1][0] if numeric_regs else None} (Patient: {numeric_regs[-1][2]})")
print(f"Duplicate registrations: {duplicates}")
print(f"Malformed/non-numeric registrations: {non_numeric_regs}")
print(f"Missing registration numbers: {len(missing_regs)} (IDs: {missing_regs})")
print(f"metadata/stats/registrationNumber: {metadata_stats.get('registrationNumber')}")
print(f"system_counters/registrationNumber: {system_counters.get('registrationNumber')}")

# Top 15 highest numbers:
print("\nTop 15 highest numeric registrations:")
for val, pid, name in numeric_regs[-15:]:
    print(f"  {val} -> {name} ({pid})")

# Determine established tail and outliers
unique_sorted = sorted(list(set(x[0] for x in numeric_regs)))
outliers = []
established_tail = unique_sorted[-1]
for i in range(len(unique_sorted) - 1, 0, -1):
    curr = unique_sorted[i]
    prev = unique_sorted[i - 1]
    if curr - prev > 300:
        outliers.extend(unique_sorted[i:])
        established_tail = prev
        break

print(f"\nEstablished sequence tail: {established_tail}")
print(f"Outliers: {outliers}")
next_number = established_tail + 1
all_reserved = set(unique_sorted)
while next_number in all_reserved:
    next_number += 1
print(f"Calculated next registration number: {next_number}")
print("==================================================")
