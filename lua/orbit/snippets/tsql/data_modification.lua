return {
  {
    "ins",
    "Insert explicit columns",
    [[
INSERT INTO ${1:dbo}.${2:Entity}
(
    ${3:Code},
    ${4:Name},
    ${5:Status}
)
VALUES
(
    ${6:@Code},
    ${7:@Name},
    ${8:@Status}
);
$0
]],
  },

  {
    "insmulti",
    "Insert multiple rows",
    [[
INSERT INTO ${1:dbo}.${2:Entity}
(
    ${3:Code},
    ${4:Name}
)
VALUES
    (${5:N'E001'}, ${6:N'Value A'}),
    (${7:N'E002'}, ${8:N'Value B'}),
    (${9:N'E003'}, ${10:N'Value C'});
$0
]],
  },

  {
    "inssel",
    "Insert from select",
    [[
INSERT INTO ${1:dbo}.${2:EntityArchive}
(
    ${3:EntityId},
    ${4:Code},
    ${5:Name}
)
SELECT
    ${6:e.EntityId},
    ${7:e.Code},
    ${8:e.Name}
FROM ${9:dbo}.${10:Entity} AS ${11:e}
WHERE ${12:e.Status = 0};
$0
]],
  },

  {
    "inso",
    "Insert with output",
    [[
INSERT INTO ${1:dbo}.${2:Entity}
(
    ${3:Code},
    ${4:Name}
)
OUTPUT
    ${5:inserted.EntityId},
    ${6:inserted.Code},
    ${7:inserted.Name}
VALUES
(
    ${8:@Code},
    ${9:@Name}
);
$0
]],
  },

  {
    "upd",
    "Update with alias",
    [[
UPDATE ${1:e}
SET
    ${2:e.Name = @Name},
    ${3:e.UpdatedAt = SYSUTCDATETIME()}
FROM ${4:dbo}.${5:Entity} AS $1
WHERE ${6:e.EntityId = @EntityId};
$0
]],
  },

  {
    "updj",
    "Update with join",
    [[
UPDATE ${1:e}
SET
    ${2:e.Status = 0},
    ${3:e.UpdatedAt = SYSUTCDATETIME()}
FROM ${4:dbo}.${5:Entity} AS $1
INNER JOIN ${6:dbo}.${7:EntityState} AS ${8:s}
    ON ${9:s.EntityId = e.EntityId}
WHERE ${10:s.IsInactive = 1};
$0
]],
  },

  {
    "updo",
    "Update with output",
    [[
UPDATE ${1:e}
SET
    ${2:e.Name = @Name}
OUTPUT
    ${3:deleted.Name AS OldName},
    ${4:inserted.Name AS NewName}
FROM ${5:dbo}.${6:Entity} AS $1
WHERE ${7:e.EntityId = @EntityId};
$0
]],
  },

  {
    "del",
    "Delete with alias",
    [[
DELETE ${1:e}
FROM ${2:dbo}.${3:Entity} AS $1
WHERE ${4:e.EntityId = @EntityId};
$0
]],
  },

  {
    "delj",
    "Delete with join",
    [[
DELETE ${1:r}
FROM ${2:dbo}.${3:RelatedEntity} AS $1
INNER JOIN ${4:dbo}.${5:Entity} AS ${6:e}
    ON ${7:e.EntityId = r.EntityId}
WHERE ${8:e.Status = 0};
$0
]],
  },

  {
    "delo",
    "Delete with output",
    [[
DELETE ${1:e}
OUTPUT
    ${2:deleted.EntityId},
    ${3:deleted.Code},
    ${4:deleted.Name}
FROM ${5:dbo}.${6:Entity} AS $1
WHERE ${7:e.EntityId = @EntityId};
$0
]],
  },

  {
    "upsert",
    "Transactional update then insert",
    [[
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE ${1:e}
    SET
        ${2:e.Name = @Name},
        ${3:e.UpdatedAt = SYSUTCDATETIME()}
    FROM ${4:dbo}.${5:Entity} AS $1
    WHERE ${6:e.Code = @Code};

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO $4.$5
        (
            ${7:Code},
            ${8:Name}
        )
        VALUES
        (
            ${9:@Code},
            ${10:@Name}
        );
    END;

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
}
