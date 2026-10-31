return {
  {
    "dynsql",
    "Parameterized dynamic SQL",
    [[
DECLARE @Sql NVARCHAR(MAX);

SET @Sql = N'
    SELECT
        ${1:e.EntityId},
        ${2:e.Name}
    FROM ${3:dbo}.${4:Entity} AS ${5:e}
    WHERE ${6:e.Status = @Status}
        AND ${7:e.Name LIKE @NamePattern};
';

EXEC sys.sp_executesql
    @Sql,
    N'
        ${8:@Status TINYINT},
        ${9:@NamePattern NVARCHAR(200)}
    ',
    ${10:@Status = @Status},
    ${11:@NamePattern = @NamePattern};
$0
]],
  },

  {
    "dynident",
    "Dynamic SQL with whitelisted identifier",
    [[
IF ${1:@SortColumn} NOT IN
(
    ${2:N'EntityId'},
    ${3:N'Name'},
    ${4:N'CreatedAt'}
)
BEGIN
    THROW ${5:50001}, ${6:'Invalid sort column.'}, 1;
END;

DECLARE @Sql NVARCHAR(MAX);

SET @Sql = N'
    SELECT
        ${7:EntityId},
        ${8:Name},
        ${9:CreatedAt}
    FROM ${10:dbo}.${11:Entity}
    ORDER BY ' + QUOTENAME($1) + N';
';

EXEC sys.sp_executesql @Sql;
$0
]],
  },
}
