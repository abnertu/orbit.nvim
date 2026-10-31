return {
  {
    "fk",
    "Named foreign key constraint",
    [[
CONSTRAINT FK_${1:RelatedEntity}_${2:Entity}
    FOREIGN KEY (${2}Id)
    REFERENCES ${3:dbo}.$2(${2}Id)$0
]],
  },

  {
    "checkcon",
    "Named check constraint",
    [[
CONSTRAINT CK_${1:Entity}_${2:Status}
    CHECK ($2 IN (${3:0, 1, 2}))$0
]],
  },

  {
    "defaultcon",
    "Named default constraint",
    [[
${1:Status} ${2:TINYINT} NOT NULL
    CONSTRAINT DF_${3:Entity}_$1
    DEFAULT (${4:1})$0
]],
  },

  {
    "computed",
    "Persisted computed column",
    [[
${1:TotalAmount} AS
    (${2:Quantity * UnitPrice}) PERSISTED$0
]],
  },

  {
    "utccol",
    "UTC timestamp column",
    [[
${1:CreatedAt} DATETIME2(3) NOT NULL
    CONSTRAINT DF_${2:Entity}_$1
    DEFAULT (SYSUTCDATETIME())$0
]],
  },

  {
    "nextseq",
    "Get next sequence value",
    [[
SELECT NEXT VALUE FOR ${1:dbo}.${2:EntityIdSequence};
$0
]],
  },
}
