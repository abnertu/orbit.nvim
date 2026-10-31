return {
  {
    "setvar",
    "Set variable",
    [[
SET ${1:@EntityId} = ${2:1};
$0
]],
  },

  {
    "selectvars",
    "Assign variables from query",
    [[
SELECT
    ${1:@EntityId = e.EntityId},
    ${2:@Name = e.Name}
FROM ${3:dbo}.${4:Entity} AS ${5:e}
WHERE ${6:e.Code = @Code};
$0
]],
  },

  {
    "orderby",
    "Deterministic order by",
    [[
ORDER BY
    ${1:e.CreatedAt DESC},
    ${2:e.EntityId DESC}$0
]],
  },

  {
    "aggregate",
    "Aggregate query",
    [[
SELECT
    COUNT(*) AS ${1:TotalCount},
    COUNT(${2:e.OptionalValue}) AS ${3:NonNullCount},
    SUM(${4:e.Amount}) AS ${5:TotalAmount},
    AVG($4) AS ${6:AverageAmount},
    MIN($4) AS ${7:MinimumAmount},
    MAX($4) AS ${8:MaximumAmount}
FROM ${9:dbo}.${10:Entity} AS ${11:e};
$0
]],
  },

  {
    "isnull",
    "Is null predicate",
    [[
${1:e.OptionalValue} IS NULL$0
]],
  },

  {
    "notnull",
    "Is not null predicate",
    [[
${1:e.OptionalValue} IS NOT NULL$0
]],
  },

  {
    "coalesce",
    "Coalesce expression",
    [[
COALESCE(
    ${1:e.PrimaryValue},
    ${2:e.SecondaryValue},
    ${3:N''}
)$0
]],
  },

  {
    "nullif",
    "Nullif expression",
    [[
${1:TotalAmount} / NULLIF(${2:ItemCount}, 0)$0
]],
  },

  {
    "cast",
    "Cast expression",
    [[
CAST(${1:@Value} AS ${2:INT})$0
]],
  },

  {
    "convert",
    "Convert expression with style",
    [[
CONVERT(${1:VARCHAR(10)}, ${2:@Date}, ${3:23})$0
]],
  },

  {
    "trycast",
    "Try cast expression",
    [[
TRY_CAST(${1:Value} AS ${2:INT})$0
]],
  },

  {
    "concat",
    "Null-safe string concatenation",
    [[
CONCAT(
    ${1:e.Prefix},
    ${2:N' '},
    ${3:e.Name}
)$0
]],
  },

  {
    "denserank",
    "Dense rank rows",
    [[
DENSE_RANK() OVER
(
    ORDER BY ${1:e.Score DESC}
) AS ${2:Ranking}$0
]],
  },

  {
    "lead",
    "Lead value",
    [[
LEAD(${1:e.Amount}) OVER
(
    ORDER BY ${2:e.EntityId}
) AS ${3:NextAmount}$0
]],
  },

  {
    "oapply",
    "Outer apply latest related row",
    [[
OUTER APPLY
(
    SELECT TOP (1)
        ${1:r.RelatedEntityId}
    FROM ${2:dbo}.${3:RelatedEntity} AS ${4:r}
    WHERE ${5:r.EntityId = e.EntityId}
    ORDER BY
        ${6:r.CreatedAt DESC},
        ${7:r.RelatedEntityId DESC}
) AS ${8:x}$0
]],
  },

  {
    "nocount",
    "Enable NOCOUNT",
    [[
SET NOCOUNT ON;
$0
]],
  },

  {
    "xactabort",
    "Enable XACT_ABORT",
    [[
SET XACT_ABORT ON;
$0
]],
  },

  {
    "go",
    "Batch separator",
    [[
GO
$0
]],
  },

  {
    "opensym",
    "Open symmetric key",
    [[
OPEN SYMMETRIC KEY ${1:SYMKEY}
DECRYPTION BY CERTIFICATE ${2:CERT};

$0

CLOSE ALL SYMMETRIC KEYS
]],
  },
}
