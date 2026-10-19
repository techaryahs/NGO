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
uid = prefs.get('flutter.firebase_user_id')
try:
    with urllib.request.urlopen(f'{rtdb_url}/users/{uid}.json?auth={id_token}') as resp:
        print('User record:', resp.read().decode())
except Exception as e:
    print('User record error:', e)

for path in ['system_counters/registrationNumber', 'metadata/stats/registrationNumber']:
    try:
        c_req = urllib.request.Request(f'{rtdb_url}/{path}.json?auth={id_token}')
        with urllib.request.urlopen(c_req, timeout=10) as resp:
            print(f'{path}: {resp.read().decode().strip()} (ETag: {resp.headers.get("ETag")})')
    except urllib.error.HTTPError as e:
        print(f'{path} error: {e.code} {e.read().decode().strip()}')

# Check patients
patients_req = urllib.request.Request(f'{rtdb_url}/patients.json?auth={id_token}')
try:
    with urllib.request.urlopen(patients_req, timeout=30) as resp:
        patients_data = json.loads(resp.read().decode())
        print('Total patients in live RTDB:', len(patients_data) if isinstance(patients_data, dict) else 0)
        
        numeric_regs = []
        non_numeric_regs = []
        missing_regs = []
        counts = {}
        if isinstance(patients_data, dict):
            for pid, p in patients_data.items():
                if not isinstance(p, dict):
                    continue
                reg = p.get('registrationNumber')
                if reg is None or not str(reg).strip():
                    missing_regs.append(pid)
                    continue
                reg_str = str(reg).strip()
                counts[reg_str] = counts.get(reg_str, 0) + 1
                try:
                    num = int(reg_str)
                    numeric_regs.append(num)
                except ValueError:
                    non_numeric_regs.append((pid, reg_str))
            
            duplicates = {k: v for k, v in counts.items() if v > 1}
            print(f'Numeric registration numbers found: {len(numeric_regs)}')
            print(f'Maximum numeric registration number: {max(numeric_regs) if numeric_regs else "None"}')
            print(f'Duplicate registration numbers found: {duplicates}')
            print(f'Non-numeric registration numbers found: {non_numeric_regs}')
            print(f'Missing registration numbers found: {len(missing_regs)}')
except urllib.error.HTTPError as e:
    print('patients fetch error:', e.code, e.read().decode())
