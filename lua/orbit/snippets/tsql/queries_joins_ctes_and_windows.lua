return {
  {
    "sel",
    "Select explicit columns",
    [[
SELECT
    ${1:e.EntityId},
    ${2:e.Code},
    ${3:e.Name}
FROM ${4:dbo}.${5:Entity} AS ${6:e}
WHERE ${7:e.EntityId = @EntityId}
ORDER BY
    ${8:e.EntityId};
$0
]],
  },

  {
    "seld",
    "Select distinct values",
    [[
SELECT DISTINCT
    ${1:e.Category}
FROM ${2:dbo}.${3:Entity} AS ${4:e};
$0
]],
  },

  {
    "seltop",
    "Select deterministic top rows",
    [[
SELECT TOP (${1:10})
    ${2:e.EntityId},
    ${3:e.Name}
FROM ${4:dbo}.${5:Entity} AS ${6:e}
ORDER BY
    ${7:e.EntityId DESC};
$0
]],
  },

  {
    "selpage",
    "Select with offset pagination",
    [[
DECLARE @Page INT = ${1:1};
DECLARE @PageSize INT = ${2:20};

SELECT
    ${3:e.EntityId},
    ${4:e.Name}
FROM ${5:dbo}.${6:Entity} AS ${7:e}
WHERE ${8:e.Status = @Status}
ORDER BY
    ${9:e.EntityId}
OFFSET (@Page - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;
$0
]],
  },

  {
    "drange",
    "Half-open date range predicate",
    [[
WHERE ${1:e.CreatedAt} >= ${2:@StartAt}
    AND $1 < ${3:@EndAt}$0
]],
  },

  {
    "case",
    "Searched case expression",
    [[
CASE
    WHEN ${1:Score >= 90} THEN ${2:N'A'}
    WHEN ${3:Score >= 80} THEN ${4:N'B'}
    ELSE ${5:N'F'}
END$0
]],
  },

  {
    "ijoin",
    "Inner join",
    [[
INNER JOIN ${1:dbo}.${2:RelatedEntity} AS ${3:r}
    ON ${4:r.EntityId = e.EntityId}$0
]],
  },

  {
    "ljoin",
    "Left join",
    [[
LEFT JOIN ${1:dbo}.${2:RelatedEntity} AS ${3:r}
    ON ${4:r.EntityId = e.EntityId}$0
]],
  },

  {
    "fjoin",
    "Full outer join",
    [[
FULL OUTER JOIN ${1:dbo}.${2:TargetEntity} AS ${3:t}
    ON ${4:t.EntityId = s.EntityId}$0
]],
  },

  {
    "xjoin",
    "Cross join",
    [[
CROSS JOIN ${1:dbo}.${2:Period} AS ${3:p}$0
]],
  },

  {
    "xapply",
    "Cross apply latest related row",
    [[
CROSS APPLY
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
    "exists",
    "Where exists",
    [[
WHERE EXISTS
(
    SELECT 1
    FROM ${1:dbo}.${2:RelatedEntity} AS ${3:r}
    WHERE ${4:r.EntityId = e.EntityId}
)$0
]],
  },

  {
    "nexists",
    "Where not exists",
    [[
WHERE NOT EXISTS
(
    SELECT 1
    FROM ${1:dbo}.${2:RelatedEntity} AS ${3:r}
    WHERE ${4:r.EntityId = e.EntityId}
)$0
]],
  },

  {
    "groupby",
    "Grouped aggregate query",
    [[
SELECT
    ${1:r.EntityId},
    ${2:COUNT(*) AS RelatedCount}
FROM ${3:dbo}.${4:RelatedEntity} AS ${5:r}
WHERE ${6:r.Status = @Status}
GROUP BY
    ${7:r.EntityId}
HAVING ${8:COUNT(*) >= 1}
ORDER BY
    ${9:RelatedCount DESC};
$0
]],
  },

  {
    "cte",
    "Common table expression",
    [[
;WITH ${1:ActiveEntity} AS
(
    SELECT
        ${2:e.EntityId},
        ${3:e.Name}
    FROM ${4:dbo}.${5:Entity} AS ${6:e}
    WHERE ${7:e.Status = 1}
)
SELECT
    ${8:e.EntityId},
    ${9:e.Name}
FROM $1 AS ${10:e};
$0
]],
  },

  {
    "mcte",
    "Multiple common table expressions",
    [[
;WITH ${1:ActiveEntity} AS
(
    SELECT
        ${2:e.EntityId},
        ${3:e.Name}
    FROM ${4:dbo}.${5:Entity} AS ${6:e}
    WHERE ${7:e.Status = 1}
),
${8:RelatedCount} AS
(
    SELECT
        ${9:r.EntityId},
        ${10:COUNT(*) AS RelatedCount}
    FROM ${11:dbo}.${12:RelatedEntity} AS ${13:r}
    GROUP BY
        ${14:r.EntityId}
)
SELECT
    ${15:e.EntityId},
    ${16:e.Name},
    ${17:ISNULL(r.RelatedCount, 0) AS RelatedCount}
FROM $1 AS ${18:e}
LEFT JOIN $8 AS ${19:r}
    ON ${20:r.EntityId = e.EntityId};
$0
]],
  },

  {
    "rcte",
    "Recursive common table expression",
    [[
;WITH ${1:EntityTree} AS
(
    SELECT
        ${2:e.EntityId},
        ${3:e.ParentEntityId},
        ${4:e.Name},
        0 AS [Level]
    FROM ${5:dbo}.${6:HierarchicalEntity} AS ${7:e}
    WHERE ${8:e.ParentEntityId IS NULL}

    UNION ALL

    SELECT
        ${9:e.EntityId},
        ${10:e.ParentEntityId},
        ${11:e.Name},
        p.[Level] + 1
    FROM ${12:dbo}.${13:HierarchicalEntity} AS ${14:e}
    INNER JOIN $1 AS ${15:p}
        ON ${16:p.EntityId = e.ParentEntityId}
)
SELECT
    ${17:EntityId},
    ${18:ParentEntityId},
    ${19:Name},
    ${20:[Level]}
FROM $1;
$0
]],
  },

  {
    "subq",
    "Subquery predicate",
    [[
WHERE ${1:e.EntityId} IN
(
    SELECT ${2:r.EntityId}
    FROM ${3:dbo}.${4:RelatedEntity} AS ${5:r}
    WHERE ${6:r.Status = @Status}
)$0
]],
  },

  {
    "derived",
    "Derived table",
    [[
SELECT
    ${1:x.EntityId},
    ${2:x.RelatedCount}
FROM
(
    SELECT
        ${3:r.EntityId},
        ${4:COUNT(*) AS RelatedCount}
    FROM ${5:dbo}.${6:RelatedEntity} AS ${7:r}
    GROUP BY
        ${8:r.EntityId}
) AS ${9:x}
WHERE ${10:x.RelatedCount >= 3};
$0
]],
  },

  {
    "union",
    "Union queries",
    [[
SELECT
    ${1:s.EntityId}
FROM ${2:dbo}.${3:SourceEntity} AS ${4:s}

UNION

SELECT
    ${5:t.EntityId}
FROM ${6:dbo}.${7:TargetEntity} AS ${8:t};
$0
]],
  },

  {
    "unionall",
    "Union all queries",
    [[
SELECT
    ${1:s.EntityId}
FROM ${2:dbo}.${3:SourceEntity} AS ${4:s}

UNION ALL

SELECT
    ${5:t.EntityId}
FROM ${6:dbo}.${7:TargetEntity} AS ${8:t};
$0
]],
  },

  {
    "intersect",
    "Intersect queries",
    [[
SELECT
    ${1:s.EntityId}
FROM ${2:dbo}.${3:SourceEntity} AS ${4:s}

INTERSECT

SELECT
    ${5:t.EntityId}
FROM ${6:dbo}.${7:TargetEntity} AS ${8:t};
$0
]],
  },

  {
    "except",
    "Except queries",
    [[
SELECT
    ${1:s.EntityId}
FROM ${2:dbo}.${3:SourceEntity} AS ${4:s}

EXCEPT

SELECT
    ${5:t.EntityId}
FROM ${6:dbo}.${7:TargetEntity} AS ${8:t};
$0
]],
  },

  {
    "rownum",
    "Row number",
    [[
ROW_NUMBER() OVER
(
    ORDER BY ${1:e.EntityId}
) AS ${2:RowNo}$0
]],
  },

  {
    "rowpart",
    "Latest row per group",
    [[
;WITH ${1:RankedEntity} AS
(
    SELECT
        ${2:r.RelatedEntityId},
        ${3:r.EntityId},
        ${4:r.CreatedAt},
        ROW_NUMBER() OVER
        (
            PARTITION BY ${5:r.EntityId}
            ORDER BY
                ${6:r.CreatedAt DESC},
                ${7:r.RelatedEntityId DESC}
        ) AS RowNo
    FROM ${8:dbo}.${9:RelatedEntity} AS ${10:r}
)
SELECT
    ${11:r.RelatedEntityId},
    ${12:r.EntityId},
    ${13:r.CreatedAt}
FROM $1 AS ${14:r}
WHERE ${15:r.RowNo = 1};
$0
]],
  },

  {
    "rank",
    "Rank rows",
    [[
RANK() OVER
(
    ORDER BY ${1:e.Score DESC}
) AS ${2:Ranking}$0
]],
  },

  {
    "lag",
    "Lag value",
    [[
LAG(${1:e.Amount}) OVER
(
    ORDER BY ${2:e.EntityId}
) AS ${3:PreviousAmount}$0
]],
  },
}
