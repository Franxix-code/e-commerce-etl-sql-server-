/* =====================================================================
   File     : 01_running_queries.sql
   Purpose  : Shows what is running right now, what it waits for and which statement it executes. Run in a second window when a load seems stuck.
   ===================================================================== */

SELECT 
	r.session_id, r.status, r.wait_type, r.wait_time / 1000 AS wait_s,
	r.blocking_session_id, r.cpu_time / 1000 AS cpu_s, r.logical_reads,
	SUBSTRING(t.text, 
			(r.statement_start_offset / 2) + 1, 
			((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END - r.statement_start_offset) / 2) + 1) AS running_statement
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID AND r.database_id = DB_ID();;
