/***************************************************************
-- Scirpt Name: 04_MGF_BatchModesql.sql
-- This code is copied from
-- https://github.com/Microsoft/sql-server-samples/tree/master/samples/features/intelligent-query-processing

-- Modified by Taiob Ali
-- May 19, 2022

-- Batch mode Memory Grant Feedback

-- See https://aka.ms/IQP for more background

-- Demo scripts: https://aka.ms/IQPDemos 

-- This demo is on SQL Server 2017 and Azure SQL DB

-- Email IntelligentQP@microsoft.com for questions\feedback
*************************************************************/

USE [master];
GO

ALTER DATABASE [WideWorldImportersDW] SET COMPATIBILITY_LEVEL = 140;
GO

USE [WideWorldImportersDW];
GO

ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

/* Intentionally forcing a row underestimate */
CREATE OR ALTER PROCEDURE [FactOrderByLineageKey]
	@LineageKey INT 
AS
SELECT [fo].[Order Key], [fo].[Description] 
FROM [Fact].[Order] AS [fo]
INNER HASH JOIN [Dimension].[Stock Item] AS [si] 
	ON [fo].[Stock Item Key] = [si].[Stock Item Key]
WHERE [fo].[Lineage Key] = @LineageKey
	AND [si].[Lead Time Days] > 0
ORDER BY [fo].[Stock Item Key], [fo].[Order Date Key] DESC
OPTION (MAXDOP 1);
GO

/*
Turn on Actual Execution plan ctrl+M
Compiled and executed using a lineage key that doesn't have rows
Run both at the same time and then run the second one separate
Look at the warning about excessive memory grant
*/
EXEC [FactOrderByLineageKey] 8;
GO

/*
Execute this query a few times - each time looking at 
the plan to see impact on spills, memory grant size, and run time

Description of 'IsMemoryGrantFeedbackAdjusted' values:
https://docs.microsoft.com/en-us/sql/relational-databases/performance/intelligent-query-processing?view=sql-server-ver15#row-mode-memory-grant-feedback
*/

EXEC [FactOrderByLineageKey] 9;
GO

