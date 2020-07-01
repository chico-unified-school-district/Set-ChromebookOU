SELECT  
[DRA].[ST] as [userType],

[DRI].[SR] AS [Serial Number],

[DRI].[BC] AS [BarCode],

CONVERT(VARCHAR(10),[DRA].[DT],101) AS [Issued],

CONVERT(VARCHAR(10),[DRA].[RD],101) AS [Returned]

FROM (SELECT [DRA].* FROM DRA WHERE DEL = 0)

       DRA LEFT JOIN (SELECT [DRI].* FROM DRI WHERE DEL = 0) DRI ON [DRI].[RID] = [DRA].[RID] AND [DRI].[RIN] = [DRA].[RIN]

where DRA.RD is NUll

AND

DRA.RID = 1

AND

DRI.DEL <> 1

--AND
--DRA.ST = 'T'
--convert(date, DRA.DT) >= DATEADD (day, -3, convert(date,GETDATE()))