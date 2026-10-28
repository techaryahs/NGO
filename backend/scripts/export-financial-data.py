#!/usr/bin/env python3
"""Manual, SELECT-only PostgreSQL financial export. No .env/SSH/network client.

Uses the operator's existing psql/libpq authentication. Raw JSON stays in memory;
only allowlisted pseudonymized records are written. See export-financial-data.md.
"""
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation

SCHEMA_SHA256 = '475841e91cde8c841c22e2484d936dfda1c3ff110d1b9bb5c553d93acab1ccba'
FIELDS = {
    'patients': 'id registration_number admission_date registration_date status discharge_date exit_date room_id bed_ids total_paid_amount current_due_amount refund_due_amount total_refund_due_amount total_refunded_amount admission_balances payment_pending payment_status payment_due_date is_advance_period advance_billed_amount billing_amount_override attendance_charges total_present_days total_absent_days max_stay_days extension_approved extension_days approved_date created_at updated_at version',
    'stays': 'id patient_id room_id room_type cycle_id admission_date duration_days expected_discharge_date completed_at expiry_date total_extended_days attendant_count daily_rate daily_rate_is_manual long_stay_daily_rate cost_override billing_summary total_cost base_cost extra_attendant_cost paid_amount pending_amount extensions status bed_id created_at updated_at',
    'payments': 'id patient_id cycle_id type amount total_amount paid_amount pending_amount payment_status method payment_date receipt_number check_number transaction_id source created_at updated_at request_fingerprint',
    'attendance_records': 'id kind attendance_date patient_id created_at updated_at',
    'patient_attendants': 'id patient_id created_at',
    'rooms': 'id room_type status max_attendants current_attendants total_beds occupied_beds version created_at updated_at',
    'room_beds': 'id room_id status current_patient_id current_stay_id created_at updated_at',
    'sponsorships': 'id patient_id amount sponsorship_date payment_method created_at',
    'pgmigrations': 'id name run_on',
    'system_settings': 'category settings_key settings_value updated_at',
}
MONEY = {'amount', 'total_amount', 'paid_amount', 'pending_amount', 'total_paid_amount', 'current_due_amount', 'refund_due_amount', 'total_refund_due_amount', 'total_refunded_amount', 'advance_billed_amount', 'billing_amount_override', 'attendance_charges', 'daily_rate', 'long_stay_daily_rate', 'cost_override', 'total_cost', 'base_cost', 'extra_attendant_cost'}
PRICING = {'generalRoomBedPrice', 'privateRoomBasePrice', 'privateRoomIncludedAttendants', 'privateRoomExtraAttendantFee', 'generalRoomIncludedAttendants', 'generalRoomDefaultBeds', 'generalRoomMaxAttendants', 'privateRoomMaxAttendants'}
BALANCE_NUMBERS = 'total paid refunded netPaid due refundDue actualPatientPresentDays projectedPatientPresentDays'.split()
BALANCE_FLAGS = 'finalized provisional reconciliationRequired plannedExitConfirmed'.split()
BALANCE_TIMES = 'checkoutAt'.split()


def json_default(value):
    if isinstance(value, Decimal):
        return str(value)
    raise TypeError('Unsupported export value type')


def dumps(value):
    return json.dumps(value, sort_keys=True, indent=2, ensure_ascii=True, default=json_default) + '\n'


def object_map(value):
    return value if isinstance(value, dict) else {}


def array(value):
    return value if isinstance(value, list) else []


def money(value):
    try:
        d = Decimal(str(value))
        if not d.is_finite():
            return None
        return d
    except (InvalidOperation, ValueError, TypeError):
        return None


class Sanitizer:
    def __init__(self, key):
        self.key = key
        self.identity_map = defaultdict(dict)

    def token(self, kind, value, recover=False):
        if value is None:
            return None
        value = str(value)
        token = kind + '_' + hmac.new(self.key, (kind + '\0' + value).encode(), hashlib.sha256).hexdigest()
        if recover:
            self.identity_map[kind][token] = value
        return token

    def identity(self, kind, value):
        return self.token(kind, value, True)

    def category(self, value, allowed):
        if value is None or value in allowed:
            return value
        return self.token('unknown_value', value)

    def mark(self, raw, patient):
        raw = object_map(raw)
        return {
            'attendant_id': self.identity('attendant', raw.get('attendantId')),
            'legacy_name_ref': self.token('attendant_name', patient + '\0' + str(raw['attendantName'])) if raw.get('attendantName') is not None else None,
            'status': self.category(raw.get('status'), {'Present', 'Absent', 'Pending', 'Unmarked'}),
            'cycle_id': self.identity('cycle', raw.get('cycleId')),
            'date': self.temporal(raw.get('date')),
            'timestamp': self.temporal(raw.get('timestamp')),
            'updated_at': self.temporal(raw.get('updatedAt')),
            'source_ref': self.token('attendance_source', raw.get('source')),
        }

    @staticmethod
    def temporal(value):
        # Keep only timestamp/calendar-shaped values; unknown free text is omitted.
        if isinstance(value, (int, Decimal)):
            return value
        if isinstance(value, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}(?:[T ][0-9:.+Z-]+)?', value):
            return value
        return None

    def roster(self, people, patient):
        result = []
        for person in array(people):
            person = object_map(person)
            name = person.get('name')
            result.append({
                'id': self.identity('attendant', person.get('id')),
                'name_ref': self.token('attendant_name', patient + '\0' + str(name)) if name is not None else None,
                'safe_name_ref': self.token('attendant_key', patient + '\0' + re.sub(r'[.#$\[\]/]', '_', str(name))) if name is not None else None,
                'start_date': self.temporal(person.get('startDate')),
                'end_date': self.temporal(person.get('endDate')),
            })
        return result

    def pricing(self, value):
        return {k: money(v) for k, v in object_map(value).items() if k in PRICING}

    def balance(self, raw):
        raw = object_map(raw)
        result = {k: money(raw[k]) for k in BALANCE_NUMBERS if k in raw}
        result.update({k: raw[k] for k in BALANCE_FLAGS if isinstance(raw.get(k), bool)})
        result.update({k: self.temporal(raw[k]) for k in BALANCE_TIMES if k in raw})
        result['cycleId'] = self.identity('cycle', raw.get('cycleId'))
        for k in ('segmentCharges', 'segmentPatientCharges', 'segmentAttendantCharges', 'segmentDays'):
            if k in raw:
                result[k] = {self.identity('stay', sid): money(v) for sid, v in object_map(raw[k]).items()}
        result['pendingAttendance'] = [
            {'day': self.temporal(object_map(p).get('day')),
             'kind': self.category(object_map(p).get('kind'), {'attendance', 'attendant_attendance'}),
             'attendant_ref': self.token('attendant_key', object_map(p).get('attendantId'))}
            for p in array(raw.get('pendingAttendance'))]
        adjustment = object_map(raw.get('checkoutAdjustment'))
        result['checkoutAdjustment'] = {k: money(adjustment[k]) for k in ('amount', 'patientAmount', 'attendantAmount', 'billableDay', 'patientPresentDaysBefore') if k in adjustment}
        result['checkoutAdjustment'].update({k: adjustment[k] for k in ('included', 'includedInTotal', 'includedByOverride') if isinstance(adjustment.get(k), bool)})
        result['checkoutAdjustment'].update({k: self.temporal(adjustment[k]) for k in ('day', 'checkoutAt') if k in adjustment})
        result['checkoutAdjustment']['stayId'] = self.identity('stay', adjustment.get('stayId'))
        result['checkoutAdjustment']['category'] = self.category(adjustment.get('category'), {'general', 'lobby', 'private'})
        allowed = set(BALANCE_NUMBERS + BALANCE_FLAGS + BALANCE_TIMES) | {'cycleId', 'segmentCharges', 'segmentPatientCharges', 'segmentAttendantCharges', 'segmentDays', 'pendingAttendance', 'checkoutAdjustment', 'pricing', 'status', 'pricingBasis', 'days', 'amount', 'admissionId'}
        result['omitted_field_count'] = len(set(raw) - allowed)
        for k in ('days', 'amount'):
            if k in raw:
                result[k] = money(raw[k])
        if 'admissionId' in raw:
            result['admissionId'] = self.identity('cycle', raw['admissionId'])
        return result

    def records(self, raw):
        result = {}
        for table, fields in FIELDS.items():
            result[table] = []
            for record in raw.get(table, []):
                r = {k: record.get(k) for k in fields.split()}
                patient = str(record.get('patient_id', record.get('id', '')))
                if table not in ('system_settings', 'pgmigrations'):
                    r['id_length'] = len(str(r.get('id', '')))
                    r['id'] = self.identity({'patients': 'patient', 'stays': 'stay', 'payments': 'payment', 'attendance_records': 'attendance', 'patient_attendants': 'attendant', 'rooms': 'room', 'room_beds': 'bed', 'sponsorships': 'sponsorship'}[table], r['id'])
                for field, kind in {'patient_id': 'patient', 'current_patient_id': 'patient', 'room_id': 'room', 'bed_id': 'bed', 'current_stay_id': 'stay', 'cycle_id': 'cycle', 'registration_number': 'registration'}.items():
                    if field in r:
                        r[field] = self.identity(kind, r[field])
                for field in MONEY:
                    if field in r:
                        r[field] = money(r[field])
                for field in ('transaction_id', 'receipt_number', 'check_number', 'request_fingerprint'):
                    if field in r:
                        value = r.pop(field)
                        r[field + '_ref'] = self.token(field, value)
                        r[field + '_normalized_ref'] = self.token(field, value.strip().casefold()) if isinstance(value, str) else None
                        r[field + '_length'] = len(value) if isinstance(value, str) else None
                        r[field + '_blank'] = value is None or (isinstance(value, str) and not value.strip())
                        r[field + '_placeholder'] = isinstance(value, str) and value.strip().casefold() in {'manual_online', 'manual', 'na', 'n/a', 'none', 'null', '0', '-'}
                if 'bed_ids' in r:
                    r['bed_ids'] = [self.identity('bed', v) for v in array(r['bed_ids'])]
                if table == 'patients':
                    r['current_cycle_id'] = self.identity('cycle', record.get('_current_cycle_id'))
                    r['admission_balances'] = {self.identity('cycle', k): self.balance(v) for k, v in object_map(r['admission_balances']).items()}
                if table == 'stays':
                    snapshot = object_map(record.get('_snapshot'))
                    r['snapshot'] = {'admissionDate': self.temporal(snapshot.get('admissionDate')), 'cycle_id': self.identity('cycle', snapshot.get('admissionDate')), 'attendants': self.roster(snapshot.get('attendants'), patient), 'transfer_ref': self.token('transfer', snapshot.get('transferFingerprint'))}
                    r['billing_summary'] = {**self.balance(r['billing_summary']), 'pricing': self.pricing(object_map(r['billing_summary']).get('pricing'))}
                    r['extensions'] = [{**{k: money(object_map(v)[k]) for k in ('additionalDays', 'additionalCost', 'priorBillableDays') if k in object_map(v)}, **{k: self.temporal(object_map(v).get(k)) for k in ('date', 'from', 'throughExclusive')}, 'request_ref': self.token('extension', object_map(v).get('requestId'))} for v in array(r['extensions'])]
                if table == 'patient_attendants':
                    r.update(self.roster([record.get('_person')], patient)[0])
                if table == 'attendance_records':
                    payload = object_map(record.get('_payload'))
                    r['patient_mark'] = self.mark(payload, patient) if record['kind'] == 'attendance' else None
                    if record['kind'] == 'attendant_attendance':
                        marks = [(payload.get('attendantId') or payload.get('attendantName'), payload)] if payload.get('attendantId') or payload.get('attendantName') else list(payload.items())
                        r['attendant_marks'] = [{'key_ref': self.token('attendant_key', patient + '\0' + str(key)), 'key_id_ref': self.token('attendant', key), **self.mark(v, patient)} for key, v in marks if isinstance(v, dict)]
                if table == 'system_settings':
                    r['settings_value'] = money(r['settings_value'])
                # Categorical columns are not a back door for free text/PII.
                for field, allowed in {'type': {'payment','refund','credit','reversal'}, 'kind': {'attendance','attendant_attendance'}, 'status': {'active','discharged','completed','cancelled','available','occupied','maintenance','cleaning','reserved'}, 'room_type': {'general','lobby','private'}, 'method': {'cash','ONLINE','online','upi','UPI','bank_transfer','cheque','check','card'}, 'payment_method': {'cash','online','upi','bank_transfer','cheque','card'}, 'payment_status': {'Paid','Partially Paid','Unpaid','Payment Exceeded'}, 'source': {'manual','import','firebase','registration'}}.items():
                    if field in r:
                        r[field] = self.category(r[field], allowed)
                result[table].append(r)
        return result


def sql():
    selections = []
    for table, fields in FIELDS.items():
        cols = [f'{c}::text AS {c}' if c in MONEY else c for c in fields.split()]
        if table == 'patients':
            cols += ["trunc(extract(epoch FROM admission_date)*1000)::bigint::text AS _current_cycle_id"]
        elif table == 'stays':
            cols += ["jsonb_build_object('admissionDate',patient_snapshot->'admissionDate','attendants',patient_snapshot->'attendants','transferFingerprint',patient_snapshot->'transferFingerprint') AS _snapshot"]
        elif table == 'attendance_records':
            cols += ['payload AS _payload']
        elif table == 'patient_attendants':
            cols += ["jsonb_build_object('id',id,'name',name) AS _person"]
        where = " WHERE category='pricing' AND settings_key IN (" + ','.join("'" + k + "'" for k in sorted(PRICING)) + ')' if table == 'system_settings' else ''
        selections += [f"'{table}',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.{('settings_key' if table == 'system_settings' else 'id')}),'[]'::jsonb) FROM (SELECT {','.join(cols)} FROM public.{table}{where}) t)"]
    return '\n'.join([
        'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;',
        "SET LOCAL TIME ZONE 'UTC';", "SET LOCAL statement_timeout='120s';",
        "SET LOCAL lock_timeout='5s';", 'SET LOCAL row_security=on;',
        # Never silently accept an RLS-restricted partial financial dataset.
        "SELECT jsonb_build_object('metadata',jsonb_build_object('database',current_database(),'server_version',current_setting('server_version'),'server_address',inet_server_addr(),'server_port',inet_server_port(),'transaction_read_only',current_setting('transaction_read_only'),'isolation',current_setting('transaction_isolation'),'captured_at',transaction_timestamp()),'columns',(SELECT jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,'type',data_type,'max_length',character_maximum_length,'precision',numeric_precision,'scale',numeric_scale)) FROM information_schema.columns WHERE table_schema='public'),'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_object('table',c.relname,'name',con.conname,'type',con.contype,'validated',con.convalidated,'definition',pg_get_constraintdef(con.oid))), '[]'::jsonb) FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public'),'rls',(SELECT jsonb_agg(jsonb_build_object('table',relname,'enabled',relrowsecurity,'forced',relforcerowsecurity)) FROM pg_class JOIN pg_namespace n ON n.oid=relnamespace WHERE n.nspname='public' AND relkind='r')," + ','.join(selections) + ');',
        'ROLLBACK;'])


def summarize(data):
    issues = defaultdict(list)
    for kind in ('unmatched_explicit_cycle_ids', 'missing_cycle_ids', 'unresolved_stay_cycles', 'duplicate_candidates', 'missing_relationships', 'invalid_amounts', 'type_sign_conflicts', 'saved_cycle_ledger_discrepancies', 'saved_balance_arithmetic_discrepancies', 'account_vs_saved_cycle_discrepancies', 'patient_current_cycle_discrepancies', 'active_stays_for_discharged_patients', 'overlapping_attendant_mark_candidates'):
        issues[kind] = []
    patients = {p['id']: p for p in data['patients']}
    stays = {s['id']: s for s in data['stays']}
    rooms = {r['id'] for r in data['rooms']}
    known = {pid: {p['current_cycle_id'], *p['admission_balances'].keys()} for pid, p in patients.items()}
    for s in stays.values():
        if s['patient_id'] not in patients:
            issues['missing_relationships'].append({'table': 'stays', 'id': s['id'], 'relation': 'patient'})
        elif s['status'] != 'cancelled':
            cycle = s.get('cycle_id') or s.get('snapshot', {}).get('cycle_id')
            if cycle:
                known[s['patient_id']].add(cycle)
            else:
                issues['unresolved_stay_cycles'].append(s['id'])
        if s['room_id'] not in rooms:
            issues['missing_relationships'].append({'table': 'stays', 'id': s['id'], 'relation': 'room'})
        if s['status'] == 'active' and s['patient_id'] in patients and patients[s['patient_id']]['status'] == 'discharged':
            issues['active_stays_for_discharged_patients'].append(s['id'])
    totals = defaultdict(lambda: {'received': Decimal(0), 'refunded': Decimal(0), 'net': Decimal(0), 'unresolved_net': Decimal(0)})
    allocated = defaultdict(Decimal)
    for r in data['payments']:
        pid, cid, amount = r['patient_id'], r['cycle_id'], r['amount']
        if pid not in patients:
            issues['missing_relationships'].append({'table': 'payments', 'id': r['id'], 'relation': 'patient'})
        if amount is None:
            issues['invalid_amounts'].append(r['id'])
            continue
        totals[pid]['received'] += max(amount, Decimal(0))
        totals[pid]['refunded'] += max(-amount, Decimal(0))
        totals[pid]['net'] += amount
        if cid is None or cid not in known.get(pid, set()):
            kind = 'missing_cycle_ids' if cid is None else 'unmatched_explicit_cycle_ids'
            issues[kind].append({'patient_id': pid, 'payment_id': r['id'], 'cycle_id': cid, 'amount': amount, 'known_cycle_count': len(known.get(pid, set())), 'allocation': 'unresolved; no timestamp inference'})
            totals[pid]['unresolved_net'] += amount
        else:
            allocated[pid, cid] += amount
        if (r['type'] == 'refund' and amount >= 0) or (r['type'] == 'payment' and amount <= 0):
            issues['type_sign_conflicts'].append(r['id'])
    for table in ('stays', 'attendance_records', 'patient_attendants', 'sponsorships'):
        for r in data[table]:
            if r.get('patient_id') is not None and r['patient_id'] not in patients and table != 'stays':
                issues['missing_relationships'].append({'table': table, 'id': r['id'], 'relation': 'patient'})
    for field in ('id', 'transaction_id_ref', 'receipt_number_ref', 'request_fingerprint_ref', 'transaction_id_normalized_ref', 'receipt_number_normalized_ref'):
        groups = defaultdict(list)
        for r in data['payments']:
            original_field = field.replace('_normalized_ref', '').replace('_ref', '')
            if r.get(field) and not r.get(original_field + '_blank', False):
                groups[r[field]].append(r['id'])
        issues['duplicate_candidates'].extend({'field': field, 'payment_ids': ids, 'confirmed_duplicate': False} for ids in groups.values() if len(ids) > 1)
    for pid, p in patients.items():
        saved_net = Decimal(0)
        for cid, b in p['admission_balances'].items():
            net = b.get('netPaid')
            if net is not None:
                saved_net += net
                if net != allocated[pid, cid]:
                    issues['saved_cycle_ledger_discrepancies'].append({'patient_id': pid, 'cycle_id': cid, 'saved_net_paid': net, 'explicitly_matched_net': allocated[pid, cid], 'requires_review': True})
            if all(b.get(k) is not None for k in ('total', 'netPaid', 'due', 'refundDue')):
                if b['due'] != max(Decimal(0), b['total'] - b['netPaid']) or b['refundDue'] != max(Decimal(0), b['netPaid'] - b['total']):
                    issues['saved_balance_arithmetic_discrepancies'].append({'patient_id': pid, 'cycle_id': cid})
        if saved_net != totals[pid]['net']:
            issues['account_vs_saved_cycle_discrepancies'].append({'patient_id': pid, 'ledger_net': totals[pid]['net'], 'saved_cycle_net': saved_net})
        # total_paid_amount is current-cycle, not lifetime account receipts.
        if p['total_paid_amount'] != allocated[pid, p['current_cycle_id']]:
            issues['patient_current_cycle_discrepancies'].append({'patient_id': pid, 'saved_current_paid': p['total_paid_amount'], 'explicitly_matched_net': allocated[pid, p['current_cycle_id']]})
    beds = {r['id'] for r in data['room_beds']}
    for r in data['room_beds']:
        for field, targets in [('room_id', rooms), ('current_patient_id', patients), ('current_stay_id', stays)]:
            if r[field] is not None and r[field] not in targets:
                issues['missing_relationships'].append({'table': 'room_beds', 'id': r['id'], 'relation': field})
    for s in stays.values():
        if s.get('bed_id') is not None and s['bed_id'] not in beds:
            issues['missing_relationships'].append({'table': 'stays', 'id': s['id'], 'relation': 'bed'})
    # Compare retained stable identities with legacy aliases without choosing a
    # winning mark. Conflicts require the original roster and cycle evidence.
    aliases = defaultdict(lambda: defaultdict(set))
    for p in data['patient_attendants']:
        if p.get('name_ref'):
            aliases[p['patient_id']][p['name_ref']].add(p['id'])
        if p.get('safe_name_ref'):
            aliases[p['patient_id']][p['safe_name_ref']].add(p['id'])
    for s in stays.values():
        for p in s.get('snapshot', {}).get('attendants', []):
            if p.get('id'):
                for field in ('name_ref', 'safe_name_ref'):
                    if p.get(field):
                        aliases[s['patient_id']][p[field]].add(p['id'])
    for r in data['attendance_records']:
        groups = defaultdict(list)
        for mark in r.get('attendant_marks', []):
            candidates = aliases[r['patient_id']].get(mark.get('legacy_name_ref'), set()) | aliases[r['patient_id']].get(mark.get('key_ref'), set())
            identity = mark.get('attendant_id') or (next(iter(candidates)) if len(candidates) == 1 else mark['key_id_ref'])
            groups[identity].append(mark['status'])
        for identity, marks in groups.items():
            if len(marks) > 1:
                issues['overlapping_attendant_mark_candidates'].append({'attendance_id': r['id'], 'attendant_ref': identity, 'statuses': marks, 'conflicting': len(set(marks)) > 1})
    grand = {k: sum((v[k] for v in totals.values()), Decimal(0)) for k in ('received','refunded','net','unresolved_net')}
    return {'mode': 'read-only export; no proposed corrections', 'counts': {k: len(v) for k, v in data.items()}, 'issue_counts': {k: len(v) for k, v in issues.items()}, 'grand_totals': grand, 'account_totals': dict(totals), 'issues': dict(issues), 'limitations': [
        'Cycle identifiers have no FK and there is no admissions/allocation-history table in the supplied schema.',
        'Every missing cycle ID is reported unresolved, including single-candidate cases; no intended allocation is asserted.',
        'Saved/frozen charges are exported, never repriced. Differences from saved balances are candidates, not confirmed losses/refunds.',
        'No separate reversal/credit linkage is defined by this schema. Signed amounts and types are preserved; no refund is authorized.',
        'Nested JSON is allowlisted. Unknown fields and free-text notes are excluded and may require on-server manual review.',
        'This export is not a recoverable database backup and does not prove the operator selected the intended production database.',
    ]}


def psql_command(invocation):
    command = shlex.split(invocation)
    if not command or any('postgres://' in c or 'postgresql://' in c or 'password=' in c.lower() for c in command):
        raise ValueError('Use existing libpq authentication; do not put credentials or URLs in command arguments')
    if any(c in {'-c', '--command', '-f', '--file'} or c.startswith(('--command=', '--file=')) for c in command):
        raise ValueError('psql invocation must not include another SQL command or file')
    # A -c diagnostic does not need stdin, but this export sends SQL over stdin.
    # docker exec without -i succeeds while discarding that input and emits no
    # JSON. Compose exec additionally needs TTY disabled to keep stdout clean.
    if Path(command[0]).name.lower() in {'docker', 'docker.exe'} and 'exec' in command:
        index = command.index('exec')
        psql_index = next((i for i, arg in enumerate(command) if Path(arg).name.lower() in {'psql', 'psql.exe'}), len(command))
        options = command[index + 1:psql_index]
        if '--interactive=false' in options:
            raise ValueError('psql invocation: SQL stdin requires interactive input; remove --interactive=false')
        if 'compose' in command[:index]:
            command[index + 1:index + 1] = ['-T', '--interactive=true']
        else:
            if any(c in {'-t', '-it', '-ti', '--tty'} or c.startswith('--tty=') for c in options):
                raise ValueError('psql invocation: Docker exec must not allocate a TTY; use -i without -t')
            command[index + 1:index + 1] = ['-i']
    return command + ['-X', '-q', '-A', '-t', '-P', 'pager=off', '-P', 'footer=off', '-v', 'ON_ERROR_STOP=1', '-w']


def decode_json(text, stage):
    if not text.strip():
        hint = ' SQL stdin produced no result; check the Docker exec stdin path.' if stage == 'psql stdout JSON' else ''
        raise RuntimeError(stage + ': empty input.' + hint)
    try:
        value = json.loads(text, parse_float=Decimal)
    except json.JSONDecodeError as exc:
        raise RuntimeError('%s: invalid JSON at line %d, column %d (output omitted).' %
                           (stage, exc.lineno, exc.colno)) from None
    if not isinstance(value, dict):
        raise RuntimeError(stage + ': expected one JSON object; output omitted.')
    return value


def export(args):
    # No .env loader; psql uses the operator's already authorized libpq context.
    command = psql_command(args.psql_command)
    result = subprocess.run(command, input=sql(), capture_output=True, text=True,
                            encoding='utf-8', timeout=180)
    if result.returncode:
        # PostgreSQL errors may echo raw values: never copy stderr into a report.
        raise RuntimeError('psql failed (exit %s). Inspect connection/permissions locally; no raw stderr was written.' % result.returncode)
    raw = decode_json(result.stdout, 'psql stdout JSON')
    if not isinstance(raw.get('metadata'), dict) or any(not isinstance(raw.get(k), list) for k in ('columns', 'constraints', 'rls', *FIELDS)):
        raise RuntimeError('psql result shape: required metadata/record arrays are missing; output omitted.')
    if any(not isinstance(r, dict) or not {'table', 'column', 'type'}.issubset(r) for r in raw['columns']) or any(not isinstance(r, dict) or not {'table', 'enabled', 'forced'}.issubset(r) for r in raw['rls']):
        raise RuntimeError('psql result shape: malformed column/RLS metadata; output omitted.')
    if raw['metadata'].get('transaction_read_only') != 'on' or raw['metadata'].get('isolation') != 'repeatable read':
        raise RuntimeError('Required read-only repeatable-read snapshot not confirmed')
    if args.expected_database and raw['metadata'].get('database') != args.expected_database:
        raise RuntimeError('Database identity differs from --expected-database; no files written')
    expected = decode_json(Path(__file__).with_name('production-financial-schema.json').read_text(encoding='utf-8-sig'), 'schema manifest JSON')
    if not isinstance(expected.get('tables'), dict) or not isinstance(expected.get('all_reference_tables'), list):
        raise RuntimeError('schema manifest shape: required tables/inventory missing; no export written.')
    actual = {(c['table'], c['column']): c for c in raw['columns']}
    if {r['table'] for r in raw['rls']} != set(expected['all_reference_tables']):
        raise RuntimeError('Visible table inventory differs from supplied schema; inspect schema/permissions before exporting')
    for table, columns in expected['tables'].items():
        for column, spec in columns.items():
            found = actual.get((table, column))
            if found is None or any(found.get(k) != v for k, v in spec.items()):
                raise RuntimeError('Schema mismatch for %s.%s; no export written' % (table, column))
    relevant = set(FIELDS)
    if any(r['table'] in relevant and (r['enabled'] or r['forced']) for r in raw['rls']):
        raise RuntimeError('RLS enabled on financial tables; cannot certify complete visibility; no export written')
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name != 'nt' and output.stat().st_mode & 0o077:
        raise RuntimeError('Output directory must be private (chmod 700)')
    keyfile = Path(args.key_file) if args.key_file else output / 'pseudonym.key.private'
    if keyfile.exists():
        if os.name != 'nt' and keyfile.stat().st_mode & 0o077:
            raise RuntimeError('Pseudonym key must be private (chmod 600)')
        key = keyfile.read_bytes()
    else:
        key = secrets.token_bytes(32)
        with keyfile.open('xb') as f:
            os.chmod(keyfile, 0o600)
            f.write(key)
    if len(key) != 32:
        raise ValueError('Pseudonym key must contain exactly 32 random bytes')
    sanitizer = Sanitizer(key)
    data = sanitizer.records(raw)
    summary = summarize(data)
    receipt_ids = sorted(str(r['id']) for r in raw['payments'])
    summary['issues']['payment_id_prefix_candidates'] = [
        {'shorter': sanitizer.identity('payment', left), 'longer': sanitizer.identity('payment', right)}
        for left, right in zip(receipt_ids, receipt_ids[1:])
        if len(left) >= 8 and right != left and right.startswith(left)]
    summary['issue_counts']['payment_id_prefix_candidates'] = len(summary['issues']['payment_id_prefix_candidates'])
    record_hash = hashlib.sha256(dumps(data).encode()).hexdigest()
    metadata = {**raw['metadata'], 'schema_reference_sha256': SCHEMA_SHA256, 'records_sha256': record_hash, 'format_version': 1, 'identity_scheme': 'HMAC-SHA256; reuse private key for comparisons', 'constraints': raw['constraints'], 'columns': raw['columns']}
    files = {'financial-data.json': {'metadata': metadata, 'records': data}, 'financial-summary.json': summary,
             'identity-map.private.json': dict(sanitizer.identity_map)}
    for name, value in files.items():
        target = output / name
        # Private, atomic publication; no raw database JSON is written.
        temporary = output / (name + '.tmp')
        with temporary.open('w', encoding='utf-8') as f:
            os.chmod(temporary, 0o600)
            f.write(dumps(value))
        temporary.replace(target)
    print(dumps({'output_directory': str(output), 'counts': summary['counts'], 'issue_counts': summary['issue_counts'], 'records_sha256': record_hash, 'read_only': True}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--psql-command', default='psql', help='Existing psql invocation, optionally prefixed with docker compose exec -T; no shell evaluation')
    parser.add_argument('--expected-database', help='Optional explicit identity guard; use the database name verified by the operator')
    parser.add_argument('--key-file', help='Reuse an existing 32-byte key for stable cross-run pseudonyms')
    args = parser.parse_args()
    try:
        export(args)
    except Exception as exc:
        # Do not include connection objects, SQL data, paths from subprocess errors,
        # JSON input excerpts, or credentials in a failure report.
        safe = str(exc) if isinstance(exc, (RuntimeError, ValueError)) and not isinstance(exc, json.JSONDecodeError) else type(exc).__name__
        print('Export failed: ' + safe, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
