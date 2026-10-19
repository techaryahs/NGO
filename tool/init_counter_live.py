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

# 1. Fetch patients
patients_req = urllib.request.Request(f'{rtdb_url}/patients.json?auth={id_token}')
with urllib.request.urlopen(patients_req, timeout=30) as resp:
    patients_data = json.loads(resp.read().decode())

max_reg = 0
total_patients = 0
valid_regs = 0

for pid, p in (patients_data or {}).items():
    if not isinstance(p, dict):
        continue
    total_patients += 1
    reg = p.get('registrationNumber')
    if reg is None or not str(reg).strip():
        continue
    try:
        val = int(str(reg).strip())
        valid_regs += 1
        if val > max_reg:
            max_reg = val
    except ValueError:
        pass

print(f"Scanned {total_patients} patients; {valid_regs} valid numeric registration numbers.")
print(f"Computed maximum registration number: {max_reg}")

# 2. Check current counter at metadata/stats/registrationNumber
check_req = urllib.request.Request(f'{rtdb_url}/metadata/stats/registrationNumber.json?auth={id_token}')
with urllib.request.urlopen(check_req, timeout=10) as resp:
    curr = resp.read().decode().strip()
    etag = resp.headers.get('ETag')
    print(f"Current counter value: {curr} (ETag: {etag})")

# 3. If counter is null or less than max_reg, initialize it
if curr == 'null' or int(curr) < max_reg:
    print(f"Initializing metadata/stats/registrationNumber to {max_reg}...")
    init_req = urllib.request.Request(
        f'{rtdb_url}/metadata/stats/registrationNumber.json?auth={id_token}',
        data=str(max_reg).encode('utf-8'),
        method='PUT',
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(init_req, timeout=10) as resp:
        result = resp.read().decode().strip()
        print(f"PUT result: {result} (ETag: {resp.headers.get('ETag')})")

# 4. Verify counter
with urllib.request.urlopen(check_req, timeout=10) as resp:
    verified = resp.read().decode().strip()
    etag = resp.headers.get('ETag')
    print(f"Verified counter value: {verified} (ETag: {etag})")
