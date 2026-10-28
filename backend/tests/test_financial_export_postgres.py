"""Opt-in Docker-only reproduction; never uses .env or an existing database.

RUN_EXPORT_DOCKER_TESTS=1 NGO_EXPORT_TEST_SCHEMA=/path/to/ngo_schema.sql
python -m unittest discover -s backend/tests -p test_financial_export_postgres.py
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(os.environ.get('RUN_EXPORT_DOCKER_TESTS') == '1', 'Explicit Docker test opt-in required')
class DockerExportTests(unittest.TestCase):
    def test_docker_stdin_failure_and_corrected_export(self):
        def run(args, **kwargs):
            return subprocess.run(args, capture_output=True, text=True, encoding='utf-8', timeout=180, **kwargs)
        created = run(['docker', 'run', '--rm', '-d', '--network', 'none', '--label', 'ngo.export.test=true',
                       '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:16-alpine'])
        self.assertEqual(created.returncode, 0, 'Could not create disposable local test container')
        container = created.stdout.strip()
        self.assertRegex(container, r'^[a-f0-9]{64}$')
        try:
            for _ in range(40):
                if run(['docker', 'exec', container, 'pg_isready', '-U', 'postgres']).returncode == 0:
                    break
                time.sleep(.5)
            else:
                self.fail('Disposable PostgreSQL did not start')
            psql = ['docker', 'exec', container, 'psql', '-U', 'postgres', '-d', 'postgres']
            diagnostic = run(psql + ['-qAt', '-c', 'SELECT json_build_object(\'database\',current_database());'])
            self.assertEqual(json.loads(diagnostic.stdout)['database'], 'postgres')
            # Original bug: successful -c diagnostic, but SQL over stdin is lost.
            broken = run(psql + ['-X', '-qAt', '-w'], input='SELECT json_build_object(\'ok\',true);\n')
            self.assertEqual(broken.returncode, 0)
            self.assertEqual(broken.stdout, '')
            with self.assertRaises(json.JSONDecodeError):
                json.loads(broken.stdout)
            schema = Path(os.environ['NGO_EXPORT_TEST_SCHEMA']).read_text(encoding='utf-8-sig')
            # Only remove newer psql guard meta-commands for image patch-version compatibility.
            schema = re.sub(r'^\\(?:un)?restrict[^\n]*\n', '', schema, flags=re.M)
            setup = run(['docker', 'exec', '-i', container, 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-q'], input=schema)
            self.assertEqual(setup.returncode, 0, 'Supplied schema did not restore in disposable PostgreSQL')
            fixture = """INSERT INTO patients(id,full_name,date_of_birth,gender,contact_number,emergency_contact,emergency_contact_name,medical_condition,admission_date,created_by)
            VALUES('audit-p1','PRIVATE-NAME','2000-01-01','Other','','','','','2026-10-01','synthetic');
            INSERT INTO payments(id,patient_id,cycle_id,amount,payment_date) VALUES('audit-pay','audit-p1','unmatched',1200.10,'2026-10-01');"""
            self.assertEqual(run(['docker','exec','-i',container,'psql','-U','postgres','-v','ON_ERROR_STOP=1','-q'], input=fixture).returncode, 0)
            script = Path(__file__).resolve().parents[1] / 'scripts' / 'export-financial-data.py'
            with tempfile.TemporaryDirectory() as folder:
                result = run([sys.executable, str(script), '--output-dir', str(Path(folder) / 'export'),
                              '--expected-database', 'postgres', '--psql-command', ' '.join(psql)])
                self.assertEqual(result.returncode, 0, result.stderr)
                data_text = (Path(folder) / 'export' / 'financial-data.json').read_text()
                self.assertNotIn('PRIVATE-NAME', data_text)
                data = json.loads(data_text)
                self.assertEqual(data['records']['payments'][0]['amount'], '1200.10')
                self.assertEqual(data['metadata']['transaction_read_only'], 'on')
                self.assertEqual(data['metadata']['isolation'], 'repeatable read')
                self.assertTrue(data['metadata']['server_version'].startswith('16.'))
        finally:
            # Exact ID created above, no host volumes/ports or existing database.
            run(['docker', 'rm', '-f', container])
