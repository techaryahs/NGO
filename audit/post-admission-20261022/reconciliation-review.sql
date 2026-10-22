-- Read-only candidate report. Run only by an authorized operator after backup.
-- A match is a review candidate, not permission to change an invoice or receipt.
SELECT p.id AS patient_id, s.id AS stay_id, s.cycle_id,
       a.id AS attendant_id, a.created_at AS roster_record_created_at,
       s.admission_date AS stay_started_at,
       p.admission_balances -> COALESCE(s.cycle_id, (extract(epoch FROM p.admission_date)*1000)::bigint::text)
           ->> 'finalized' AS invoice_finalized
FROM patients p
JOIN stays s ON s.patient_id=p.id AND s.status='active'
JOIN patient_attendants a ON a.patient_id=p.id
WHERE NOT EXISTS (
  SELECT 1 FROM jsonb_array_elements(COALESCE(s.patient_snapshot->'attendants','[]'::jsonb)) person
  WHERE person->>'id'=a.id
)
ORDER BY p.id,s.id,a.id;

-- Duplicate references can be legitimate historical split receipts. Do not
-- delete or merge these rows automatically, and never infer received money
-- from an outstanding balance or from the user's attempted collection.
SELECT patient_id, transaction_id, count(*) AS receipt_count,
       array_agg(id ORDER BY payment_date,id) AS receipt_ids,
       sum(amount) AS recorded_amount
FROM payments
WHERE NULLIF(trim(transaction_id),'') IS NOT NULL
GROUP BY patient_id,transaction_id
HAVING count(*)>1
ORDER BY patient_id,transaction_id;
