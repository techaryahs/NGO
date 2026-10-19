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

# 1. Check counter
req_counter = urllib.request.Request(f'{rtdb_url}/metadata/stats/registrationNumber.json?auth={id_token}')
with urllib.request.urlopen(req_counter, timeout=30) as resp:
    val = resp.read().decode()
    print('Current metadata/stats/registrationNumber on live RTDB:', val)

# 2. Check system_counters if any
req_sys = urllib.request.Request(f'{rtdb_url}/system_counters.json?auth={id_token}')
try:
    with urllib.request.urlopen(req_sys, timeout=30) as resp:
        val_sys = resp.read().decode()
        print('Current system_counters on live RTDB:', val_sys)
except Exception as e:
    print('system_counters check:', e)
