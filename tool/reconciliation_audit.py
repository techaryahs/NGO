import os
import json
import urllib.request
import urllib.parse
from pathlib import Path

ROOT = Path(r'C:\Users\sahil\OneDrive\Desktop\NGO')
config = {}
for line in (ROOT / '.env').read_text(encoding='utf-8-sig').splitlines():
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, v = line.split('=', 1)
        config[k.strip()] = v.strip().strip('"\'')

prefs_path = Path(os.environ['APPDATA']) / 'com.example/ngo/shared_preferences.json'
prefs = json.loads(prefs_path.read_text(encoding='utf-8'))
refresh = prefs.get('flutter.firebase_refresh_token')

req = urllib.request.Request(
    'https://securetoken.googleapis.com/v1/token?' + urllib.parse.urlencode({'key': config['FIREBASE_API_KEY']}),
    data=urllib.parse.urlencode({'grant_type': 'refresh_token', 'refresh_token': refresh}).encode(),
    method='POST',
)
with urllib.request.urlopen(req, timeout=30) as resp:
    token_data = json.loads(resp.read().decode())
    id_token = token_data['id_token']

rtdb_url = config['FIREBASE_DATABASE_URL'].rstrip('/')

# READ-ONLY fetch of /patients
req2 = urllib.request.Request(f'{rtdb_url}/patients.json?auth={id_token}')
with urllib.request.urlopen(req2, timeout=30) as resp:
    patients = json.loads(resp.read().decode())

total_examined = 0
valid_numbers = []
nonnumeric_missing_count = 0
counts = {}

for pid, p in (patients or {}).items():
    if not isinstance(p, dict):
        continue
    total_examined += 1
    reg = p.get('registrationNumber')
    if reg is None or not str(reg).strip():
        nonnumeric_missing_count += 1
        continue
    try:
        num = int(str(reg).strip())
        valid_numbers.append(num)
        counts[num] = counts.get(num, 0) + 1
    except ValueError:
        nonnumeric_missing_count += 1

numeric_count = len(valid_numbers)
unique_sorted = sorted(list(set(valid_numbers)))
min_number = unique_sorted[0] if unique_sorted else 0
max_number = unique_sorted[-1] if unique_sorted else 0

# Duplicate check
duplicates = {k: v for k, v in counts.items() if v > 1}

# Sequence continuity & outlier analysis
outliers = []
established_tail = unique_sorted[-1] if unique_sorted else 0

for i in range(len(unique_sorted) - 1, 0, -1):
    curr = unique_sorted[i]
    prev = unique_sorted[i - 1]
    gap = curr - prev
    elements_above = len(unique_sorted) - i
    if gap > 100 and elements_above <= max(3, len(unique_sorted) * 0.05):
        outliers.extend(unique_sorted[i:])
        established_tail = prev
        break

outliers = sorted(outliers)

# Calculate next registration number (skipping any reserved numbers)
reserved_set = set(valid_numbers)
proposed_next = established_tail + 1
while proposed_next in reserved_set:
    proposed_next += 1

print("==================================================")
print("READ-ONLY RECONCILIATION AUDIT (ACTUAL RTDB)")
print("==================================================")
print(f"- total patient records examined: {total_examined}")
print(f"- numeric registration count: {numeric_count}")
print(f"- nonnumeric/missing registration count: {nonnumeric_missing_count}")
print(f"- minimum registration number: {min_number}")
print(f"- maximum registration number: {max_number}")
print(f"- established sequence tail: {established_tail}")
print(f"- isolated/outlier numbers: {outliers}")
print(f"- duplicate registration numbers: {duplicates}")
print(f"- proposed persisted counter value: {established_tail}")
print(f"- proposed next registration number: {proposed_next}")
print("==================================================")

# Also check for export fixture (if cut at 5217)
fixture_numbers = [x for x in valid_numbers if x <= 5217 or x in outliers]
f_unique_sorted = sorted(list(set(fixture_numbers)))
f_outliers = []
f_tail = f_unique_sorted[-1]
for i in range(len(f_unique_sorted) - 1, 0, -1):
    curr = f_unique_sorted[i]
    prev = f_unique_sorted[i - 1]
    gap = curr - prev
    elements_above = len(f_unique_sorted) - i
    if gap > 100 and elements_above <= max(3, len(f_unique_sorted) * 0.05):
        f_outliers.extend(f_unique_sorted[i:])
        f_tail = prev
        break
f_reserved = set(fixture_numbers)
f_next = f_tail + 1
while f_next in f_reserved:
    f_next += 1

print("\nIF EVALUATED ON OCT 5 EXPORT FIXTURE (TAIL AT 5217):")
print(f"- established sequence tail: {f_tail}")
print(f"- proposed next number: {f_next}")
print(f"- isolated outlier: {sorted(f_outliers)}")
