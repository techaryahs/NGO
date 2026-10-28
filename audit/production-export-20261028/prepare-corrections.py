"""Deterministic offline proposals only; never opens a database or identity map."""
import hashlib
import json
from collections import defaultdict
from decimal import Decimal as D
from pathlib import Path
import sys

OUT = Path(__file__).resolve().parent


def build(data, analysis):
    records = data['records']
    patients = {p['id']: p for p in records['patients']}
    stays = defaultdict(list)
    receipts = defaultdict(list)
    for s in records['stays']:
        stays[s['patient_id']].append(s)
    seen = set()
    for r in records['payments']:
        assert r['id'] not in seen, 'Duplicate authoritative payment ID'
        seen.add(r['id'])
        receipts[r['patient_id']].append(r)
    assert len(patients) == 153 and len(seen) == 289 and sum(map(len, stays.values())) == 201
    report = []
    for assessed in analysis['patients']:
        pid = assessed['patient_id']
        p = patients[pid]
        rows = receipts[pid]
        known = set(assessed['cycle_ids'])
        cycle_rows = []
        for cid in sorted(known):
            saved = p['admission_balances'].get(cid)
            explicit = sum((D(r['amount']) for r in rows if r['cycle_id'] == cid), D(0))
            total = D(str(saved['total'])) if saved and saved.get('total') is not None else None
            cycle_rows.append({'cycle_id': cid, 'saved_before': saved, 'saved_after': saved,
                'explicit_allocated_net': explicit,
                'strict_projection_on_saved_charges_only': None if total is None else {
                    'charges': total, 'net': explicit, 'due_candidate': max(D(0), total-explicit),
                    'credit_candidate': max(D(0), explicit-total), 'refund_entitlement': 'not established'},
                'financial_correction': None})
        receipt_rows = []
        for r in sorted(rows, key=lambda r: r['id']):
            valid = r['cycle_id'] is not None and r['cycle_id'] in known
            receipt_rows.append({'receipt_id': r['id'], 'amount_before': r['amount'], 'amount_after': r['amount'],
                'payment_date': r['payment_date'], 'original_cycle_id': r['cycle_id'],
                'proposed_cycle_id': r['cycle_id'], 'proposed_correction': None,
                'classification': 'explicit_known_cycle' if valid else 'review_single_known_cycle' if r['cycle_id'] is None and len(known) == 1 else 'review_unestablished_allocation',
                'original_reference': {k: r.get(k) for k in ('transaction_id_ref', 'receipt_number_ref', 'request_fingerprint_ref')},
                'evidence_needed': None if valid else 'Original receipt/allocation and complete admission history; dates and saved aggregate totals alone are insufficient',
                'snapshot_stay_matches': [s['id'] for s in stays[pid] if r['cycle_id'] is not None and s['snapshot'].get('cycle_id') == r['cycle_id']]})
        stay_rows = []
        for s in sorted(stays[pid], key=lambda s: s['id']):
            original = s['cycle_id']
            snapshot = s['snapshot'].get('cycle_id')
            owners = [cid for cid, b in p['admission_balances'].items() if s['id'] in (b.get('segmentCharges') or {})]
            proposal = owners[0] if original is None and snapshot is None and len(owners) == 1 else None
            conflict = original is not None and snapshot is not None and original != snapshot
            stay_rows.append({'stay_id': s['id'], 'original_cycle_id': original, 'snapshot_cycle_id': snapshot,
                'saved_segment_owners': owners, 'proposed_cycle_id': proposal if proposal else original,
                'proposal': 'metadata_only_unique_saved_segment_owner' if proposal else 'review_conflicting_identities' if conflict else 'none',
                'evidence': 'Exactly one frozen/saved segmentCharges entry identifies this stay' if proposal else None,
                'original_total_cost': s['total_cost'], 'proposed_total_cost': s['total_cost'],
                'execution': 'NOT EXECUTED', 'financial_delta': '0.00'})
        before = sum((D(r['amount']) for r in rows), D(0))
        report.append({'patient_id': pid, 'prior_audit_fingerprint': assessed['prior_audit_fingerprint'],
            'registration_reference': assessed['registration_ref'], 'recorded_findings': assessed['issues'],
            'account_net_before': before, 'account_net_after_proposed_metadata_only': before,
            'unallocated_net_under_strict_resolver': sum((D(r['amount']) for r in rows if r['cycle_id'] is None or r['cycle_id'] not in known), D(0)),
            'receipts': receipt_rows, 'stays': stay_rows, 'cycles': cycle_rows,
            'other_action': {
                'patient_snapshot_arithmetic_conflict': 'Verify original invoice before rebuilding cached amounts; the 800 credit is not a confirmed refund',
                'discharged_with_active_stay': 'Verify actual occupancy/departure; no financial fields establish physical status',
                'conflicting_attendant_representations': 'Use canonical ID-first display; retain all historical source marks',
                'stay_snapshot_cycle_conflict': 'Verify original admission/bed evidence; do not merge charges or redirect receipt',
            }})
    assert len(report) == len(patients)
    proposals = [s for p in report for s in p['stays'] if s['proposal'] == 'metadata_only_unique_saved_segment_owner']
    unallocated = [r for p in report for r in p['receipts'] if r['classification'] != 'explicit_known_cycle']
    net = sum((p['account_net_before'] for p in report), D(0))
    assert net == D('909550.00')
    return {'mode': 'offline_dry_run_no_executable_corrections', 'source_records_sha256': data['metadata']['records_sha256'],
        'safety': 'No SQL, database access, receipt reassignment, charge rewrite, refund or deployment',
        'counts': {'patients': len(report), 'stays': 201, 'receipts': len(seen), 'cycles': sum(len(p['cycles']) for p in report),
            'metadata_only_stay_proposals': len(proposals), 'receipts_requiring_original_allocation_evidence': len(unallocated)},
        'totals': {'ledger_net_before': net, 'ledger_net_after_proposals': net,
            'unallocated_net': sum((p['unallocated_net_under_strict_resolver'] for p in report), D(0)),
            'receipt_reassignment_amount': '0.00', 'charge_correction_amount': '0.00', 'confirmed_refund_authorized': '0.00'},
        'duplicate_review_only': analysis['duplicate_groups'], 'attendance_review_only': analysis['attendance_cases'],
        'recorded_conflicts_review_only': analysis['additional_inconsistencies'],
        'patients': report}


def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r'C:\Users\sahil\Desktop\financial-data.json')
    data = json.loads(source.read_text(encoding='utf-8-sig'), parse_float=D)
    analysis = json.loads((OUT/'analysis.json').read_text(encoding='utf-8'), parse_float=D)
    canonical = json.dumps(data['records'], sort_keys=True, indent=2, ensure_ascii=True, default=str)+'\n'
    assert hashlib.sha256(canonical.encode()).hexdigest() == data['metadata']['records_sha256'], 'Snapshot hash mismatch'
    result = build(data, analysis)
    target = OUT/'historical-dry-run.json'
    target.write_text(json.dumps(result, sort_keys=True, indent=2, default=str)+'\n', encoding='utf-8')
    lines = ['# Historical reconciliation dry run', '',
        'Offline proposals from the completed export. No historical corrections were executed.', '',
        'All original receipt IDs, references, amounts, dates, cycle references and frozen charges are retained in historical-dry-run.json.', '',
        f"Examined {result['counts']['patients']} patients, 201 stays, 289 receipts and {result['counts']['cycles']} known cycle groups.", '',
        f"{result['counts']['metadata_only_stay_proposals']} missing stay cycle fields have exactly one saved segment owner. These are metadata-only proposals, with zero financial delta. The shared read resolver can use that evidence without a historical write.", '',
        'All 80 unestablished receipt associations (79 missing plus one unmatched explicit) remain unallocated: 189,200.00. This includes the 67 single-known-cycle receipts / 165,600.00; one remaining cycle and aggregate agreement do not prove complete admission history.', '',
        'The strict resolver can differ from a saved allocation without establishing that the saved allocation was wrong. Candidate due/credit arithmetic in the JSON uses frozen totals only and authorizes no collection or refund.', '',
        'Ledger net before and after every proposal: 909,550.00. No receipt is reassigned, merged or removed. All frozen charges remain unchanged.', '',
        '5157: retain both explicit stay groups and their 1,200.00 frozen charges. The unmatched 1,200.00 receipt matches both snapshots; original admission/placement evidence must establish the authoritative cycle and whether both charges are valid.', '',
        '5219: all three untagged receipts / 6,800.00 require original allocation evidence (4,400.00 is a subset). The saved 2,200.00 refund is not authorized.', '',
        'The 800.00 stored-field conflict requires original invoice evidence. Both active-stay/discharged-label conflicts require occupancy evidence. 5255 needs canonical display resolution, preserving conflicting source marks. 5251 remains unexplained because neither screenshot response was saved in this export.', '',
        'The ten duplicate-reference groups remain candidates. No source payment ID duplicates exist; placeholder/split references must not be deduplicated automatically.', '',
        '| Patient pseudonym | Prior fingerprint | Findings | Receipt allocation review | Metadata-only proposals |',
        '|---|---|---|---:|---:|']
    for p in result['patients']:
        lines.append(f"| {p['patient_id']} | {p['prior_audit_fingerprint'] or ''} | {', '.join(p['recorded_findings']) or 'No recorded inconsistency established'} | {p['unallocated_net_under_strict_resolver']} | {sum(s['proposal']=='metadata_only_unique_saved_segment_owner' for s in p['stays'])} |")
    lines += ['', 'Before any eventual correction: verify production identity and revision, create and restore-test an independent backup, review this dry run against original private evidence, require operator/reason and change history, execute a tested transactional/idempotent migration, compare before/after frozen totals and rerun. No such migration is executed or authorized by this artifact.', '']
    (OUT/'historical-dry-run.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({'counts': result['counts'], 'totals': result['totals']}, default=str))


if __name__ == '__main__':
    main()
