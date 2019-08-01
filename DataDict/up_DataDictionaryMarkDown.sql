/*
*	Purpose: Generates a data dictionary for all tables with a minimum count of rows
*/
CREATE PROCEDURE [dbo].[up_DataDictionaryMarkDown]
	@minRowCount INT = 5,
	@schema nvarchar(10)=N'dbo'
AS
	BEGIN
		SET NOCOUNT ON

		DECLARE @TableName NVARCHAR(35),
				@count BIGINT,
				@sql NVARCHAR(MAX);


		-- Table filter
		DECLARE Tbls CURSOR
		FOR
			SELECT DISTINCT TABLE_NAME
			FROM INFORMATION_SCHEMA.COLUMNS
			WHERE TABLE_SCHEMA = @schema
				AND TABLE_NAME NOT LIKE 'vw_%'
				AND TABLE_NAME NOT LIKE '%migration%'
				AND TABLE_NAME NOT LIKE '%refactorlog%'

		OPEN Tbls

		PRINT ''

		FETCH NEXT FROM Tbls
		INTO @TableName

		WHILE @@fetch_status = 0
		BEGIN

			-- Get row count
			SET @sql = N'SELECT @count = count(*) FROM ' + @TableName

			EXEC sp_executesql @sql,
							   N'@count BIGINT OUTPUT',
							   @count OUTPUT;
			
			-- Move on if less than min row count
			IF (@count < @minRowCount)
				FETCH NEXT FROM Tbls INTO @TableName

			PRINT '**' + @TableName + '**'
			PRINT ''

			PRINT 'Row count: ' + CAST(@count AS VARCHAR)

			PRINT ''
			--Set up the Column Headers for the Table
			PRINT '|Column Name|Description|InPrimaryKey|IsForeignKey|DataType|Length|Nullable|Computed|Default Value|'
			PRINT '|--|--|--|--|--|--|--|--|--|'

			--Get the Table Data
			SELECT '| ' + CAST(clmns.name AS VARCHAR(35)) + ' | ' + CASE
																	   WHEN ISNULL(idxcol.index_column_id, 0) = 0 THEN ' '
																	   ELSE ' PK '
																   END +
				' | ' + CASE
						   WHEN ISNULL((
								   SELECT TOP 1 1
								   FROM sys.foreign_key_columns AS fkclmn
								   WHERE fkclmn.parent_column_id = clmns.column_id
									   AND fkclmn.parent_object_id = clmns.object_id
							   ), 0) = 0 THEN ' '
						   ELSE ' FK '
					   END +
				' | ' + CAST(udt.name AS CHAR(15)) +
				' | ' + CAST(CAST(CASE
					WHEN typ.name IN (N'nchar', N'nvarchar') AND clmns.max_length <> -1 THEN clmns.max_length / 2
					ELSE clmns.max_length
				END AS INT) AS VARCHAR(20)) +
				' | ' + CASE
						   WHEN clmns.is_nullable = 1 THEN ' nullable '
						   ELSE ' '
					   END +
				' | ' + CASE
						   WHEN clmns.is_computed = 1 THEN ' computed '
						   ELSE ' '
					   END +
				' | ' + ISNULL(CAST(cnstr.definition AS VARCHAR(20)), ' ') + ' | '
			FROM sys.tables AS tbl
			INNER JOIN sys.all_columns AS clmns ON clmns.object_id = tbl.object_id
			LEFT OUTER JOIN sys.indexes AS idx ON idx.object_id = clmns.object_id
				AND 1 = idx.is_primary_key
			LEFT OUTER JOIN sys.index_columns AS idxcol ON idxcol.index_id = idx.index_id
				AND idxcol.column_id = clmns.column_id
				AND idxcol.object_id = clmns.object_id
				AND 0 = idxcol.is_included_column
			LEFT OUTER JOIN sys.types AS udt ON udt.user_type_id = clmns.user_type_id
			LEFT OUTER JOIN sys.types AS typ ON typ.user_type_id = clmns.system_type_id
				AND typ.user_type_id = typ.system_type_id
			LEFT JOIN sys.default_constraints AS cnstr ON cnstr.object_id = clmns.default_object_id
			LEFT OUTER JOIN sys.extended_properties exprop ON exprop.major_id = clmns.object_id
				AND exprop.minor_id = clmns.column_id
			WHERE tbl.name = @TableName
				AND tbl.schema_id = 1 -- TODO: This doesn't work with @schema parameter
			ORDER BY clmns.column_id ASC


			FETCH NEXT FROM Tbls INTO @TableName
		END



		CLOSE Tbls
		DEALLOCATE Tbls
		RETURN 0
	END