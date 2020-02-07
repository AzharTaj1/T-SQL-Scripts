Exec master.dbo.sp_whoisactive 
	@show_own_spid = 0,
	@show_system_spids = 0,
	@show_sleeping_spids = 1,	-- Default = 1, If 0, bring no sleeping spids. If 1, only bring sleeping spids with an open transaction. If 2, bring all sleeping spids.
	@get_full_inner_text = 1,	-- Default = 0. If 1, get stored proc or running batch, when available. If 0, only get actual statement.
	@get_plans = 1,				-- Default = 0. If 1, get plan based on the request's statement offset. If 2, get entire plan based on the request's plan_handle.
	@get_outer_command = 1,		-- Default = 0. Get the associated outer ad hoc query or stored procedure call.
	@get_transaction_info = 1,	-- Default = 0. If 1, pull transaction log write info and transaction duration.
	@get_task_info = 1,			-- Default = 1. If 0, pull no task related info. If 1, pull top non-CXPACKET wait, giving preference to blockers. If 2, pull all available task-based metrics,
								-- including number of active tasks, current wait stats, physical I/O, context switches and blocker information.
	@get_locks = 0,				-- Default = 0. If 1, get associated locks for each request, aggregated in an XML format.
	@get_avg_time = 1,			-- Default = 0. If 1, get average time for past runs of an active query, based on the combination of plan handle, sql handle and offset.
	@get_additional_info = 1,	-- Default = 0. If 1, get additional non-performance-related info about the session or request, like set options, text_size, 
								-- language, date_format, date_first, etc.
	@find_block_leaders = 1,	-- Default = 0. If 1, walk the blocking chain and count the number of spids blocked by a session. Also sets @get_task_info = 1, if set to 0.
	@sort_order = '[start_time] asc'	-- Default =  '[start_time] ASC'. Other userful options could be reads, CPU, used_memory, etc.