select EventInfo as 'Blocker Process', count(EventInfo) as 'Blocking Episodes' 
from MetricsOps.dbo.Blocking_Info
group by EventInfo
order by 2 desc