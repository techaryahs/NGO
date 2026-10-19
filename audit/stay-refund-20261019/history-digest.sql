SELECT 'patients' AS entity,count(*) AS rows,md5(coalesce(string_agg(row_to_json(t)::text,'' ORDER BY id),'')) AS digest FROM patients t
UNION ALL SELECT 'stays',count(*),md5(coalesce(string_agg(row_to_json(t)::text,'' ORDER BY id),'')) FROM stays t
UNION ALL SELECT 'payments',count(*),md5(coalesce(string_agg(row_to_json(t)::text,'' ORDER BY id),'')) FROM payments t
UNION ALL SELECT 'attendance',count(*),md5(coalesce(string_agg(row_to_json(t)::text,'' ORDER BY id),'')) FROM attendance_records t;
