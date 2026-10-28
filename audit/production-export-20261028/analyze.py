"""Offline analysis of the two supplied production exports; no connection/key access."""
import csv
import hashlib
import importlib.util
import json
from collections import Counter, defaultdict
from datetime import datetime
from decimal import Decimal as D
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
DATA = Path(r'C:\Users\sahil\Desktop\financial-data.json')
SUMMARY = Path(r'C:\Users\sahil\Desktop\financial-summary.json')
ZERO = D(0)


def dump(x):
    return json.dumps(x, sort_keys=True, indent=2, default=str) + '\n'


def numeric(x):
    if isinstance(x, dict): return {k: numeric(v) for k, v in x.items()}
    if isinstance(x, list): return [numeric(v) for v in x]
    if isinstance(x, str) and re.fullmatch(r'-?\d+(?:\.\d+)?', x): return D(x)
    return x


def main():
    raw = json.loads(DATA.read_text(encoding='utf-8-sig'), parse_float=D)
    summary = json.loads(SUMMARY.read_text(encoding='utf-8-sig'), parse_float=D)
    records = raw['records']
    encoded = json.dumps(records, sort_keys=True, indent=2, ensure_ascii=True, default=str) + '\n'
    assert hashlib.sha256(encoded.encode()).hexdigest() == raw['metadata']['records_sha256']
    r = numeric(records)
    spec = importlib.util.spec_from_file_location('exporter', ROOT / 'backend/scripts/export-financial-data.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    repeated = module.summarize(r)
    # Prefix candidates are calculated outside summarize() by the exporter;
    # raw identifiers are intentionally unavailable here. Do not recreate them.
    for key in ('counts', 'grand_totals', 'account_totals'):
        assert dump(repeated[key]) == dump(summary[key]), key
    for key, value in repeated['issues'].items():
        assert dump(value) == dump(summary['issues'][key]), key
    ps = {p['id']: p for p in r['patients']}
    payments = defaultdict(list); stays = defaultdict(list)
    for table in ('patients', 'payments', 'stays', 'attendance_records', 'patient_attendants', 'rooms', 'room_beds'):
        assert len(r[table]) == len({v['id'] for v in r[table]}), table
    for a in r['payments']: payments[a['patient_id']].append(a)
    for a in r['stays']: stays[a['patient_id']].append(a)
    known = {pid: {p['current_cycle_id'], *p['admission_balances']} | {s['cycle_id'] or s['snapshot']['cycle_id'] for s in stays[pid] if s['status'] != 'cancelled' and (s['cycle_id'] or s['snapshot']['cycle_id'])} for pid, p in ps.items()}
    labels = {}
    # Prior audit fingerprints, not decoded registrations or proof of identity.
    for label, ms in [('5157',1791716975040),('5219',1791262760158),('5149',1787892000000),('5255',1792580400000),('5251',1792135800000)]:
        candidates = [p for p in ps.values() if round(datetime.fromisoformat(p['admission_date']).timestamp()*1000) == ms]
        assert len(candidates) == 1
        labels[candidates[0]['id']] = label
    issue_by_patient = defaultdict(set)
    details = []
    cycle_rows = []
    for pid, p in ps.items():
        rows = payments[pid]
        explicit = defaultdict(D)
        null = [a for a in rows if a['cycle_id'] is None]
        orphan = [a for a in rows if a['cycle_id'] is not None and a['cycle_id'] not in known[pid]]
        for a in rows:
            if a['cycle_id'] in known[pid]: explicit[a['cycle_id']] += a['amount']
        for cid in sorted(known[pid]):
            b = p['admission_balances'].get(cid)
            simulated = explicit[cid] + (sum((a['amount'] for a in null),ZERO) if len(known[pid]) == 1 else ZERO)
            cycle_rows.append({'patient_id': pid, 'cycle_id': cid, 'saved_balance_present': b is not None,
                'saved_total': b.get('total') if b else None, 'saved_net': b.get('netPaid') if b else None,
                'explicit_net': explicit[cid], 'local_resolver_net': simulated,
                'saved_due': b.get('due') if b else None, 'saved_refund': b.get('refundDue') if b else None,
                'frozen_or_legacy_history': p['status']=='discharged' or cid != p['current_cycle_id'] or bool(b and b.get('finalized')),
                'provisional': b.get('provisional') if b else None})
        if orphan: issue_by_patient[pid].add('unmatched_explicit_receipt')
        if null and len(known[pid]) > 1: issue_by_patient[pid].add('ambiguous_legacy_receipts')
        for a in stays[pid]:
            if a['status']=='active' and p['status']=='discharged': issue_by_patient[pid].add('discharged_with_active_stay')
            if a['cycle_id'] and a['snapshot']['cycle_id'] and a['cycle_id'] != a['snapshot']['cycle_id']:
                issue_by_patient[pid].add('stay_snapshot_cycle_conflict')
                details.append({'kind':'stay_snapshot_cycle_conflict','patient_id':pid,'stay_id':a['id'],'explicit_cycle':a['cycle_id'],'snapshot_cycle':a['snapshot']['cycle_id'],'total_cost':a['total_cost']})
        billed = p['billing_amount_override'] if p['billing_amount_override'] is not None else p['advance_billed_amount']+p['attendance_charges']
        if p['current_due_amount'] != max(ZERO,billed-p['total_paid_amount']) or p['refund_due_amount'] != max(ZERO,p['total_paid_amount']-billed):
            issue_by_patient[pid].add('patient_snapshot_arithmetic_conflict')
            details.append({'kind':'patient_snapshot_arithmetic_conflict','patient_id':pid,'stored_billed':billed,'stored_current_paid':p['total_paid_amount'],'stored_due':p['current_due_amount'],'stored_refund':p['refund_due_amount'],'formula_due':max(ZERO,billed-p['total_paid_amount']),'formula_credit':max(ZERO,p['total_paid_amount']-billed),'refund_entitlement':'not established'})
    classifications = {}
    for kind in ('saved_cycle_ledger_discrepancies', 'patient_current_cycle_discrepancies'):
        classified=[]
        for item in summary['issues'][kind]:
            pid=item['patient_id'];p=ps[pid];cid=item.get('cycle_id',p['current_cycle_id'])
            null=[a for a in payments[pid] if a['cycle_id'] is None]
            explicit=sum((a['amount'] for a in payments[pid] if a['cycle_id']==cid),ZERO)
            local=explicit+(sum((a['amount'] for a in null),ZERO) if len(known[pid])==1 else ZERO)
            stored=D(item.get('saved_net_paid',p['total_paid_amount']))
            reason='single_known_cycle_legacy_receipts_exactly_explain' if stored==local else 'multi_cycle_allocation_unproven' if null and len(known[pid])>1 else 'other_difference'
            classified.append({**item,'classification':reason,'local_resolver_net':local})
        classifications[kind]=classified
    unique_duplicates={}
    for d in summary['issues']['duplicate_candidates']:
        key=tuple(sorted(d['payment_ids']))
        unique_duplicates.setdefault(key,[]).append(d['field'])
    by_payment={v['id']:v for v in r['payments']}
    duplicate_rows=[]
    for ids, fields in unique_duplicates.items():
        tx=[by_payment[i] for i in ids]
        for a in tx: issue_by_patient[a['patient_id']].add('duplicate_reference_candidate')
        duplicate_rows.append({'payment_ids':ids,'fields':fields,'patients':sorted({a['patient_id'] for a in tx}),'placeholder':any(a['transaction_id_placeholder'] for a in tx),'same_amount_and_timestamp':len({(a['amount'],a['payment_date']) for a in tx})==1,'amounts':[a['amount'] for a in tx],'dates':[a['payment_date'] for a in tx],'confirmed_duplicate':False})
    att_by_id={a['id']:a for a in r['attendance_records']}
    attendance_rows=[]
    for item in summary['issues']['overlapping_attendant_mark_candidates']:
        a=att_by_id[item['attendance_id']];issue_by_patient[a['patient_id']].add('overlapping_attendant_marks')
        attendance_rows.append({**item,'patient_id':a['patient_id'],'date':a['attendance_date']})
    unresolved_stays=[]
    for sid in summary['issues']['unresolved_stay_cycles']:
        a=next(a for a in r['stays'] if a['id']==sid);p=ps[a['patient_id']]
        owners=[cid for cid,b in p['admission_balances'].items() if sid in b.get('segmentCharges',{})]
        t=lambda value: datetime.fromisoformat(value).timestamp()
        current_branch=t(a['created_at']) >= t(p['admission_date'])-60 or t(a['admission_date'])==t(p['registration_date'] or p['admission_date'])
        # This is evaluation of existing code, not evidence authorizing allocation.
        assert current_branch, 'Unmodeled local stay fallback requires separate review'
        if owners: assert owners == [p['current_cycle_id']]
        unresolved_stays.append({'stay_id':sid,'patient_id':p['id'],'saved_segment_owner_cycles':owners,'local_code_fallback':'current cycle branch; not persisted evidence','classification':'saved_balance_identifies_one_owner' if len(owners)==1 else 'no_unique_saved_owner'})
        if len(owners)!=1: issue_by_patient[p['id']].add('stay_cycle_evidence_incomplete')
    absent_snapshots=[]
    for item in summary['issues']['account_vs_saved_cycle_discrepancies']:
        p=ps[item['patient_id']]
        absent_snapshots.append({**item,'classification':'no_saved_admission_balances_not_evidence_of_omitted_receipts' if not p['admission_balances'] else 'unmatched_receipt_omitted_from_saved_balances'})
        if not p['admission_balances']: issue_by_patient[p['id']].add('saved_history_absent')
    patient_rows=[]
    for pid,p in ps.items():
        rows=payments[pid];net=sum((a['amount'] for a in rows),ZERO)
        explicit=sum((a['amount'] for a in rows if a['cycle_id'] in known[pid]),ZERO)
        null=sum((a['amount'] for a in rows if a['cycle_id'] is None),ZERO)
        orphan=sum((a['amount'] for a in rows if a['cycle_id'] and a['cycle_id'] not in known[pid]),ZERO)
        assert net==explicit+null+orphan
        issues=sorted(issue_by_patient[pid])
        confirmed={'unmatched_explicit_receipt','stay_snapshot_cycle_conflict','discharged_with_active_stay','patient_snapshot_arithmetic_conflict','overlapping_attendant_marks'} & set(issues)
        category='CONFIRMED_RECORDED_INCONSISTENCY' if confirmed else 'REVIEW_REQUIRED' if issues else 'RECORDED_TOTALS_CONSISTENT_FINAL_CHARGES_UNVERIFIED'
        patient_rows.append({'patient_id':pid,'registration_ref':p['registration_number'],'prior_audit_fingerprint':labels.get(pid),
            'status':p['status'],'category':category,'issues':issues,'payments':len(rows),'refunds':sum(a['amount']<0 for a in rows),
            'stays':len(stays[pid]),'active_stays':sum(a['status']=='active' for a in stays[pid]),'known_cycles':len(known[pid]),
            'received':sum((max(ZERO,a['amount']) for a in rows),ZERO),'refunded':sum((max(ZERO,-a['amount']) for a in rows),ZERO),
            'net':net,'explicit_net':explicit,'missing_cycle_net':null,'unknown_cycle_net':orphan,
            'local_resolver_unallocated_net':orphan+(null if len(known[pid])>1 else ZERO),
            'stored_current_paid':p['total_paid_amount'],'stored_current_bill':p['advance_billed_amount']+p['attendance_charges'],
            'stored_current_due':p['current_due_amount'],'stored_current_refund':p['refund_due_amount'],
            'saved_cycles':len(p['admission_balances']),'charge_verdict':'not independently certified; frozen charges preserved',
            'payment_ids':[a['id'] for a in rows],'stay_ids':[a['id'] for a in stays[pid]],'cycle_ids':sorted(known[pid])})
    result={'inputs':{'data_sha256':hashlib.sha256(DATA.read_bytes()).hexdigest(),'summary_sha256':hashlib.sha256(SUMMARY.read_bytes()).hexdigest()},'metadata':raw['metadata'],
        'verification':'Full inputs parsed; record hash, counts, grand/account totals and all reproducible summary issue lists match.',
        'counts':summary['counts'],'saved_balances':len([b for p in ps.values() for b in p['admission_balances']]),'derived_known_cycle_groups':len(cycle_rows),
        'grand_totals':summary['grand_totals'],'categories':dict(Counter(p['category'] for p in patient_rows)),
        'classifications':classifications,'account_snapshot_cases':absent_snapshots,'duplicate_groups':duplicate_rows,'stay_cycle_cases':unresolved_stays,
        'attendance_cases':attendance_rows,'additional_inconsistencies':details,'patients':patient_rows,'cycles':cycle_rows,
        'identity_limitation':'Registrations are HMAC tokens. Named-case links are unique prior-audit admission fingerprints, not decoded registrations. No key/map accessed.',
        'allocation_rule':'Local resolver simulation is reported separately from explicit evidence. No receipt is reassigned. Dates are not used to allocate receipts.'}
    (OUT/'analysis.json').write_text(dump(result),encoding='utf-8')
    flags=[]
    for kind,items in classifications.items():
        for i in items:
            flags.append({'flag':kind,'patient_id':i['patient_id'],'cycle_id':i.get('cycle_id',ps[i['patient_id']]['current_cycle_id']),
                'saved_net':i.get('saved_net_paid',i.get('saved_current_paid')),'explicit_net':i['explicitly_matched_net'],
                'local_resolver_net':i['local_resolver_net'],'classification':i['classification']})
    assert len(flags)==114
    with (OUT/'flag-classification.csv').open('w',newline='',encoding='utf-8') as f:
        writer=csv.DictWriter(f,fieldnames=list(flags[0]));writer.writeheader();writer.writerows(flags)
    for name,rows in [('patients',patient_rows),('cycles',cycle_rows)]:
        with (OUT/(name+'.csv')).open('w',newline='',encoding='utf-8') as f:
            w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader()
            for row in rows:w.writerow({k:json.dumps(v) if isinstance(v,list) else v for k,v in row.items()})
    lines=['# Production export: complete patient ledger comparison','',
        'Offline analysis only. No application code or production record changed.',
        'Snapshot: '+raw['metadata']['captured_at']+'; PostgreSQL '+raw['metadata']['server_version']+'; database '+raw['metadata']['database']+'.',
        result['verification'],'',result['identity_limitation'],'',
        '153 patient rows below. These classifications assess recorded consistency, not entitlement to refunds or correctness of every frozen daily charge. Full identifiers and receipt/stay/cycle lists are in patients.csv and analysis.json.','',
        '| Patient pseudonym | Prior fingerprint | State | Payments/refunds | Net | Missing-cycle / unmatched | Classification | Findings |',
        '|---|---|---|---:|---:|---:|---|---|']
    for p in patient_rows:
        lines.append('| '+ ' | '.join([p['patient_id'],p['prior_audit_fingerprint'] or '',p['status'],f"{p['payments']}/{p['refunds']}",str(p['net']),f"{p['missing_cycle_net']} / {p['unknown_cycle_net']}",p['category'],', '.join(p['issues']) or 'Recorded ledger comparison agrees; final charge unverified'])+' |')
    (OUT/'patient-report.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(dump({'categories':result['categories'],'saved_balances':result['saved_balances'],'derived_cycle_groups':len(cycle_rows),'classifications':{k:dict(Counter(i['classification'] for i in v)) for k,v in classifications.items()},'all_patients':len(patient_rows),'all_receipts':sum(p['payments'] for p in patient_rows),'local_unallocated_total':sum(p['local_resolver_unallocated_net'] for p in patient_rows)}))


if __name__=='__main__': main()
