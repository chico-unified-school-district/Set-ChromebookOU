SELECT
-- TOP 10
--[DRA].[RID] as RID,

[STU].[GR] as [userGrade],
[DRA].[ST] as [userType],
[DRI].[SR] AS [sn],
[DRI].[BC] AS [barCode],
CONVERT(VARCHAR(10),[DRA].[DT],101) AS [issued],
CONVERT(VARCHAR(10),[DRA].[RD],101) AS [returned]
FROM (SELECT STU.*
  FROM STU
  WHERE DEL = 0 and TG = '' )
 STU RIGHT JOIN ((SELECT [DRA].*
  FROM DRA
  WHERE DEL = 0)
 DRA LEFT JOIN (SELECT [DRI].*
  FROM DRI
  WHERE DEL = 0)
 DRI ON [DRI].[RID] = [DRA].[RID] AND [DRI].[RIN] = [DRA].[RIN]) ON [STU].[ID] = [DRA].[ID]

WHERE

DRA.DD IS NULL
 AND DRA.RD IS NUll
 --AND DRA.RID IN (1,3,4,6)
 AND DRA.RID IN (1)
 AND DRI.DEL <> 1
 AND convert(date, DRA.DT) >= DATEADD (day, -1, convert(date,GETDATE()))