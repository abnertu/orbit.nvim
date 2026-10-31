return {
  {
    "declare",
    "Declare variable",
    [[
DECLARE ${1:@EntityId} ${2:BIGINT}${3: = 1};
$0
]],
  },

  {
    "ifelse",
    "If else block",
    [[
IF ${1:@Status = 1}
BEGIN
    ${2:-- True branch.}
END
ELSE
BEGIN
    ${3:-- False branch.}
END;
$0
]],
  },

  {
    "ifexists",
    "If exists block",
    [[
IF EXISTS
(
    SELECT 1
    FROM ${1:dbo}.${2:Entity} AS ${3:e}
    WHERE ${4:e.EntityId = @EntityId}
)
BEGIN
    ${5:-- Statement.}
END;
$0
]],
  },

  {
    "while",
    "While loop",
    [[
DECLARE ${1:@Index} INT = ${2:1};

WHILE $1 <= ${3:10}
BEGIN
    ${4:PRINT @Index;}

    SET $1 += 1;
END;
$0
]],
  },

  {
    "temptable",
    "Create and use temporary table",
    [[
CREATE TABLE #${1:Entity}
(
    ${2:EntityId BIGINT NOT NULL},
    ${3:Name NVARCHAR(100) NOT NULL}
);

INSERT INTO #$1
(
    ${4:EntityId},
    ${5:Name}
)
SELECT
    ${6:e.EntityId},
    ${7:e.Name}
FROM ${8:dbo}.${9:Entity} AS ${10:e};

SELECT
    ${11:EntityId},
    ${12:Name}
FROM #$1;

DROP TABLE IF EXISTS #$1;
$0
]],
  },

  {
    "selinto",
    "Select into temporary table",
    [[
SELECT
    ${1:e.EntityId},
    ${2:e.Name}
INTO #${3:Entity}
FROM ${4:dbo}.${5:Entity} AS ${6:e}
WHERE ${7:e.Status = 1};
$0
]],
  },

  {
    "tablevar",
    "Declare and populate table variable",
    [[
DECLARE @${1:Entity} TABLE
(
    ${2:EntityId BIGINT NOT NULL},
    ${3:Name NVARCHAR(100) NOT NULL}
);

INSERT INTO @$1
(
    ${4:EntityId},
    ${5:Name}
)
SELECT
    ${6:e.EntityId},
    ${7:e.Name}
FROM ${8:dbo}.${9:Entity} AS ${10:e};
$0
]],
  },

  {
    "txn",
    "Transaction with error handling",
    [[
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    ${1:-- Database unit of work.}

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;
$0
]],
  },

  {
    "trycatch",
    "Try catch block",
    [[
BEGIN TRY
    ${1:-- Statement.}
END TRY
BEGIN CATCH
    THROW;
END CATCH;
$0
]],
  },

  {
    "throw",
    "Throw custom error",
    [[
IF ${1:@EntityId IS NULL}
BEGIN
    THROW ${2:50001}, ${3:'EntityId is required.'}, ${4:1};
END;
$0
]],
  },
}
