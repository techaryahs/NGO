import os
import json
import urllib.request
import urllib.parse
import time
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

# 1. Fetch current counter state with ETag
counter_url = f'{rtdb_url}/metadata/stats/registrationNumber.json?auth={id_token}'
req_get = urllib.request.Request(counter_url)
req_get.add_header('X-Firebase-ETag', 'true')

with urllib.request.urlopen(req_get, timeout=30) as resp:
    val = resp.read().decode()
    etag = resp.headers.get('ETag', '').strip('"')
    print(f'Current live counter value: {val}, ETag: {etag}')

# 2. Reconcile to canonical established tail 5226 (so next allocation is 5227)
payload = {
    'current': 5226,
    'updatedAt': int(time.time() * 1000),
    'source': 'patients_database_sequence',
    'reconciledFromOutlier': 8960
}

req_put = urllib.request.Request(
    counter_url,
    data=json.dumps(payload).encode('utf-8'),
    method='PUT'
)
req_put.add_header('Content-Type', 'application/json')
if etag:
    req_put.add_header('if-match', etag)

with urllib.request.urlopen(req_put, timeout=30) as resp:
    result = resp.read().decode()
    print(f'Successfully updated live counter to canonical established tail:')
    print(result)

# 3. Read back and verify
req_verify = urllib.request.Request(counter_url)
with urllib.request.urlopen(req_verify, timeout=30) as resp:
    verified = resp.read().decode()
    print(f'Verified live counter value: {verified}')
