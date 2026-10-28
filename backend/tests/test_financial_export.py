import importlib.util
import contextlib
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'export-financial-data.py'
spec = importlib.util.spec_from_file_location('financial_export', SCRIPT)
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


def fixture():
    data = {k: [] for k in exporter.FIELDS}
    data['patients'] = [{'id': 'patient-1', 'registration_number': '100', '_current_cycle_id': 'current', 'admission_balances': {'old': {'total': 100, 'paid': 0, 'netPaid': 0, 'due': 100, 'refundDue': 0, 'finalized': True, 'notes': 'PRIVATE-NAME'}}, 'total_paid_amount': '0.00'}]
    data['payments'] = [
        {'id': 'payment-orphan', 'patient_id': 'patient-1', 'cycle_id': 'missing', 'amount': '1200.10', 'type': 'payment', 'transaction_id': 'BANK-REF', 'notes': 'PRIVATE-NAME'},
        {'id': 'payment-null', 'patient_id': 'patient-1', 'cycle_id': None, 'amount': '400.20', 'type': 'payment', 'transaction_id': 'BANK-REF'},
        {'id': 'payment-refund', 'patient_id': 'patient-1', 'cycle_id': 'old', 'amount': '-100.05', 'type': 'refund'},
    ]
    data['patient_attendants'] = [{'id': 'att-1', 'patient_id': 'patient-1', '_person': {'id': 'att-1', 'name': 'PRIVATE-NAME'}}]
    data['attendance_records'] = [{'id': 'daily-1', 'patient_id': 'patient-1', 'kind': 'attendant_attendance', 'attendance_date': '2026-10-23', '_payload': {
        'PRIVATE-NAME': {'attendantName': 'PRIVATE-NAME', 'status': 'Present', 'photoDataUrl': 'SECRET-PHOTO'},
        'att-1': {'attendantId': 'att-1', 'attendantName': 'PRIVATE-NAME', 'status': 'Unmarked'},
    }}]
    return data


class ExportTests(unittest.TestCase):
    def test_sql_is_explicitly_read_only_and_excludes_direct_pii(self):
        sql = exporter.sql()
        self.assertIn('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;', sql)
        self.assertTrue(sql.endswith('ROLLBACK;'))
        self.assertNotRegex(sql, r'(?i)\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE)\b')
        self.assertNotIn('full_name', sql)
        self.assertNotIn('photo_data_url', sql)
        self.assertNotIn('password_hash', sql)
        self.assertNotIn('public.users', sql)

    def test_privacy_exact_money_and_no_date_inference(self):
        data = exporter.Sanitizer(b'k' * 32).records(fixture())
        serialized = exporter.dumps(data)
        self.assertNotIn('PRIVATE-NAME', serialized)
        self.assertNotIn('SECRET-PHOTO', serialized)
        summary = exporter.summarize(data)
        self.assertEqual(str(summary['grand_totals']['net']), '1500.25')
        self.assertEqual(str(summary['grand_totals']['unresolved_net']), '1600.30')
        self.assertEqual(len(summary['issues']['unmatched_explicit_cycle_ids']), 1)
        self.assertEqual(len(summary['issues']['missing_cycle_ids']), 1)
        self.assertTrue(summary['issues']['overlapping_attendant_mark_candidates'][0]['conflicting'])
        self.assertTrue(summary['issues']['duplicate_candidates'])

    def test_tokens_preserve_joins_and_repeat_with_same_key(self):
        first = exporter.Sanitizer(b'k' * 32).records(fixture())
        second = exporter.Sanitizer(b'k' * 32).records(fixture())
        self.assertEqual(exporter.dumps(first), exporter.dumps(second))
        self.assertEqual(first['patients'][0]['id'], first['payments'][0]['patient_id'])
        self.assertIn(first['payments'][2]['cycle_id'], first['patients'][0]['admission_balances'])

    def test_no_real_connection_export_and_schema_failure(self):
        raw = fixture()
        manifest = json.loads(SCRIPT.with_name('production-financial-schema.json').read_text())
        raw['metadata'] = {'transaction_read_only': 'on', 'isolation': 'repeatable read', 'database': 'synthetic'}
        raw['columns'] = [{'table': t, 'column': c, **v} for t, cols in manifest['tables'].items() for c, v in cols.items()]
        raw['columns'] += [{'table': t, 'column': '_not_exported', 'type': 'text'} for t in manifest['all_reference_tables'] if t not in manifest['tables']]
        raw['constraints'] = []
        raw['rls'] = [{'table': t, 'enabled': False, 'forced': False} for t in manifest['all_reference_tables']]
        with tempfile.TemporaryDirectory() as folder:
            args = SimpleNamespace(psql_command='psql', expected_database='synthetic', output_dir=str(Path(folder) / 'output'), key_file=None)
            with patch.object(exporter.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=json.dumps(raw))), contextlib.redirect_stdout(io.StringIO()):
                exporter.export(args)
                first = (Path(args.output_dir) / 'financial-data.json').read_text()
                exporter.export(args)
                self.assertEqual(first, (Path(args.output_dir) / 'financial-data.json').read_text())
                self.assertNotIn('PRIVATE-NAME', first)
                self.assertNotIn('PRIVATE-NAME', (Path(args.output_dir) / 'identity-map.private.json').read_text())
            raw['columns'][0]['type'] = 'wrong'
            with patch.object(exporter.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=json.dumps(raw))):
                with self.assertRaisesRegex(RuntimeError, 'Schema mismatch'):
                    exporter.export(args)

    def test_refuses_command_injection_and_credentials_in_invocation(self):
        for command in ['psql -c DELETE', 'psql --file=another.sql', 'psql postgresql://user:secret@server/db']:
            args = SimpleNamespace(psql_command=command)
            with patch.object(exporter.subprocess, 'run') as run:
                with self.assertRaises(ValueError):
                    exporter.export(args)
                run.assert_not_called()

    def test_docker_exec_retains_sql_stdin_and_compose_disables_tty(self):
        direct = exporter.psql_command('docker exec audit-db psql -U audit -d audit')
        self.assertEqual(direct[:4], ['docker', 'exec', '-i', 'audit-db'])
        compose = exporter.psql_command('docker compose exec postgres psql')
        self.assertEqual(compose[:5], ['docker', 'compose', 'exec', '-T', '--interactive=true'])
        with self.assertRaisesRegex(ValueError, 'TTY'):
            exporter.psql_command('docker exec -it audit-db psql')
        # -t after psql is tuples-only output, not Docker TTY allocation.
        self.assertIn('-i', exporter.psql_command('docker exec audit-db psql -t'))

    def test_json_failures_identify_stage_without_raw_data(self):
        cases = [('', 'psql stdout JSON', 'empty input'),
                 ('PRIVATE-PATIENT-DATA', 'psql stdout JSON', 'line 1, column 1'),
                 ('{', 'schema manifest JSON', 'line 1, column 2'),
                 ('[]', 'psql stdout JSON', 'expected one JSON object'),
                 ('{}\n{}', 'psql stdout JSON', 'line 2, column 1')]
        for value, stage, message in cases:
            with self.assertRaises(RuntimeError) as error:
                exporter.decode_json(value, stage)
            self.assertIn(stage, str(error.exception))
            self.assertIn(message, str(error.exception))
            self.assertNotIn('PRIVATE-PATIENT-DATA', str(error.exception))


if __name__ == '__main__':
    unittest.main()
