return {
  {
    "cview",
    "Create or alter view",
    [[
CREATE OR ALTER VIEW ${1:dbo}.${2:v_Entity}
AS
    SELECT
        ${3:e.EntityId},
        ${4:e.Code},
        ${5:e.Name},
        ${6:e.CreatedAt}
    FROM ${7:dbo}.${8:Entity} AS ${9:e}
    WHERE ${10:e.Status = 1};
GO
$0
]],
  },

  {
    "cprocr",
    "Create read-only stored procedure",
    [[
CREATE OR ALTER PROCEDURE ${1:dbo}.${2:GetEntity}
    ${3:@EntityId BIGINT}
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ${4:e.EntityId},
        ${5:e.Code},
        ${6:e.Name},
        ${7:e.Status}
    FROM ${8:dbo}.${9:Entity} AS ${10:e}
    WHERE ${11:e.EntityId = @EntityId};
END;
GO
$0
]],
  },

  {
    "cprocw",
    "Create transactional stored procedure",
    [[
CREATE OR ALTER PROCEDURE ${1:dbo}.${2:ProcessEntity}
    ${3:@EntityId BIGINT}
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        ${4:-- Database unit of work.}

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        THROW;
    END CATCH;
END;
GO
$0
]],
  },

  {
    "cproco",
    "Create stored procedure with output parameter",
    [[
CREATE OR ALTER PROCEDURE ${1:dbo}.${2:CreateEntity}
    ${3:@Code NVARCHAR(50)},
    ${4:@Name NVARCHAR(100)},
    ${5:@EntityId BIGINT OUTPUT}
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    INSERT INTO ${6:dbo}.${7:Entity}
    (
        ${8:Code},
        ${9:Name}
    )
    VALUES
    (
        ${10:@Code},
        ${11:@Name}
    );

    SET ${12:@EntityId} = CONVERT(BIGINT, SCOPE_IDENTITY());
END;
GO
$0
]],
  },

  {
    "cfunc",
    "Create scalar function",
    [[
CREATE OR ALTER FUNCTION ${1:dbo}.${2:FormatEntityName}
(
    ${3:@Prefix NVARCHAR(50)},
    ${4:@Name NVARCHAR(100)}
)
RETURNS ${5:NVARCHAR(151)}
AS
BEGIN
    RETURN ${6:CONCAT(@Prefix, N' ', @Name)};
END;
GO
$0
]],
  },

  {
    "citvf",
    "Create inline table-valued function",
    [[
CREATE OR ALTER FUNCTION ${1:dbo}.${2:GetEntitiesByStatus}
(
    ${3:@Status TINYINT}
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        ${4:e.EntityId},
        ${5:e.Code},
        ${6:e.Name},
        ${7:e.CreatedAt}
    FROM ${8:dbo}.${9:Entity} AS ${10:e}
    WHERE ${11:e.Status = @Status}
);
GO
$0
]],
  },

  {
    "ctrig",
    "Create or alter set-based trigger",
    [[
CREATE OR ALTER TRIGGER ${1:dbo}.${2:TR_Entity_Update}
ON ${3:dbo}.${4:Entity}
AFTER ${5:UPDATE}
AS
BEGIN
    SET NOCOUNT ON;

    ${6:-- Handle all rows in inserted and deleted with set-based logic.}
END;
GO
$0
]],
  },
}
