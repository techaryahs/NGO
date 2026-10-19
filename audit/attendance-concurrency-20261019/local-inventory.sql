SELECT current_database(),current_setting('server_version');
SELECT 'attendance' AS entity,count(*) AS count,md5(coalesce(string_agg(row_to_json(a)::text,'' ORDER BY id),'')) AS digest FROM attendance_records a
UNION ALL SELECT 'payments',count(*),md5(coalesce(string_agg(row_to_json(p)::text,'' ORDER BY id),'')) FROM payments p
UNION ALL SELECT 'stays',count(*),md5(coalesce(string_agg(row_to_json(s)::text,'' ORDER BY id),'')) FROM stays s;
SELECT kind,count(*) AS auto_rows,min(attendance_date),max(attendance_date) FROM attendance_records WHERE payload->>'source'='automatic_registration_period' GROUP BY kind;
