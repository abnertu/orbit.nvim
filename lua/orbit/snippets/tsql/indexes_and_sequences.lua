return {
  {
    "idx",
    "Create nonclustered index",
    [[
CREATE INDEX IX_${1:Entity}_${2:Name}
ON ${3:dbo}.$1($2);
$0
]],
  },

  {
    "idxcomp",
    "Create composite index",
    [[
CREATE INDEX IX_${1:Entity}_${2:Status}_${3:CreatedAt}
ON ${4:dbo}.$1
(
    $2,
    $3
);
$0
]],
  },

  {
    "idxinc",
    "Create index with included columns",
    [[
CREATE INDEX IX_${1:Entity}_${2:Status}
ON ${3:dbo}.$1($2)
INCLUDE
(
    ${4:Code},
    ${5:Name},
    ${6:CreatedAt}
);
$0
]],
  },

  {
    "idxuniq",
    "Create unique index",
    [[
CREATE UNIQUE INDEX UX_${1:Entity}_${2:Code}
ON ${3:dbo}.$1($2);
$0
]],
  },

  {
    "idxfilter",
    "Create filtered index",
    [[
CREATE INDEX IX_${1:Entity}_${2:Active}
ON ${3:dbo}.$1(${4:Code})
WHERE ${5:Status = 1};
$0
]],
  },

  {
    "cseq",
    "Create sequence",
    [[
CREATE SEQUENCE ${1:dbo}.${2:EntityIdSequence}
    AS ${3:BIGINT}
    START WITH ${4:1}
    INCREMENT BY ${5:1};
$0
]],
  },
}
