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

# Fetch all patients
req2 = urllib.request.Request(f'{rtdb_url}/patients.json?auth={id_token}')
with urllib.request.urlopen(req2, timeout=30) as resp:
    patients = json.loads(resp.read().decode())

records = []
non_numeric = []
missing = []
for pid, p in (patients or {}).items():
    if not isinstance(p, dict):
        continue
    reg = p.get('registrationNumber')
    name = p.get('fullName')
    created = p.get('createdAt')
    adm = p.get('admissionDate')
    notes = p.get('notes')
    
    if reg is None or not str(reg).strip():
        missing.append((pid, name, p))
        continue
    try:
        num = int(str(reg).strip())
        records.append({'id': pid, 'name': name, 'reg': num, 'created': created, 'adm': adm, 'p': p})
    except ValueError:
        non_numeric.append((pid, name, reg))

records.sort(key=lambda x: x['reg'])

print(f"Total patient records examined: {len(patients)}")
print(f"Numeric registrations: {len(records)}")
print(f"Non-numeric registrations: {len(non_numeric)}: {non_numeric}")
print(f"Missing registrations: {len(missing)}")

print("\n--- All distinct registration numbers (sorted) ---")
regs = [r['reg'] for r in records]
print(regs)

print("\n--- Top 15 highest registration numbers ---")
for r in records[-15:]:
    print(f"Reg: {r['reg']}, Name: {r['name']}, AdmDate: {r['adm']}, CreatedAt: {r['created']}")

print("\n--- Check for 8959 ---")
for r in records:
    if r['reg'] == 8959:
        print(f"Found 8959: Name={r['name']}, ID={r['id']}, AdmDate={r['adm']}, CreatedAt={r['created']}")

# Check duplicates
counts = {}
for r in records:
    counts[r['reg']] = counts.get(r['reg'], 0) + 1
duplicates = {k: v for k, v in counts.items() if v > 1}
print(f"Duplicates: {duplicates}")

# Sequence continuity analysis
print("\n--- Sequence Analysis in 5000 range ---")
fives = [r['reg'] for r in records if 5000 <= r['reg'] < 6000]
print(f"Count in 5000-5999: {len(fives)}")
print(f"Min in 5000s: {min(fives) if fives else None}")
print(f"Max in 5000s: {max(fives) if fives else None}")

# Check any numbers above 5500
above_5500 = [r for r in records if r['reg'] > 5500]
print(f"Records with reg > 5500: {[ (r['reg'], r['name']) for r in above_5500 ]}")

print("\n--- Detailed records for 5215..5226 ---")
for r in records:
    if 5215 <= r['reg'] <= 5226:
        p = r['p']
        print(f"Reg: {r['reg']} | Name: {r['name']} | Cond: {p.get('medicalCondition')} | Notes: {p.get('notes')}")

print("\n--- Detailed record for Lata (8959) ---")
for r in records:
    if r['reg'] == 8959:
        p = r['p']
        print(f"Reg: 8959 | ID: {r['id']} | Name: {r['name']} | createdBy: {p.get('createdBy')} | createdAt: {p.get('createdAt')} | admDate: {p.get('admissionDate')}")

