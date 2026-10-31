return {
  {
    "cdb",
    "Create database",
    [[
CREATE DATABASE ${1:ApplicationDatabase};
GO

USE $1;
GO
$0
]],
  },

  {
    "cschema",
    "Create schema",
    [[
CREATE SCHEMA ${1:app};
GO
$0
]],
  },

  {
    "ctable",
    "Create table",
    [[
CREATE TABLE ${1:dbo}.${2:Entity}
(
    ${2}Id BIGINT IDENTITY(1, 1) NOT NULL,

    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(100) NOT NULL,

    Status TINYINT NOT NULL
        CONSTRAINT DF_${2}_Status
        DEFAULT (1),

    CreatedAt DATETIME2(3) NOT NULL
        CONSTRAINT DF_${2}_CreatedAt
        DEFAULT (SYSUTCDATETIME()),

    UpdatedAt DATETIME2(3) NULL,

    CONSTRAINT PK_$2
        PRIMARY KEY CLUSTERED (${2}Id),

    CONSTRAINT UQ_${2}_Code
        UNIQUE (Code)
);
$0
]],
  },

  {
    "ctablefk",
    "Create table with foreign key",
    [[
CREATE TABLE ${1:dbo}.${2:RelatedEntity}
(
    ${2}Id BIGINT IDENTITY(1, 1) NOT NULL,
    ${3:Entity}Id BIGINT NOT NULL,

    CreatedAt DATETIME2(3) NOT NULL
        CONSTRAINT DF_${2}_CreatedAt
        DEFAULT (SYSUTCDATETIME()),

    CONSTRAINT PK_$2
        PRIMARY KEY (${2}Id),

    CONSTRAINT FK_${2}_$3
        FOREIGN KEY (${3}Id)
        REFERENCES ${4:dbo}.${3}(${3}Id)
);
$0
]],
  },

  {
    "altaddcol",
    "Alter table add column",
    [[
ALTER TABLE ${1:dbo}.${2:Entity}
ADD ${3:Notes} ${4:NVARCHAR(500)} ${5:NULL};
$0
]],
  },

  {
    "altcol",
    "Alter table alter column",
    [[
ALTER TABLE ${1:dbo}.${2:Entity}
ALTER COLUMN ${3:Name} ${4:NVARCHAR(200)} ${5:NOT NULL};
$0
]],
  },

  {
    "altdropcol",
    "Alter table drop column",
    [[
ALTER TABLE ${1:dbo}.${2:Entity}
DROP COLUMN ${3:Notes};
$0
]],
  },

  {
    "altaddcon",
    "Alter table add constraint",
    [[
ALTER TABLE ${1:dbo}.${2:Entity}
ADD CONSTRAINT ${3:UQ_Entity_Name}
    ${4:UNIQUE (Name)};
$0
]],
  },

  {
    "altdropcon",
    "Alter table drop constraint",
    [[
ALTER TABLE ${1:dbo}.${2:Entity}
DROP CONSTRAINT ${3:UQ_Entity_Name};
$0
]],
  },

  {
    "droptable",
    "Drop table if it exists",
    [[
DROP TABLE IF EXISTS ${1:dbo}.${2:Entity};
$0
]],
  },

  {
    "truncate",
    "Truncate table",
    [[
TRUNCATE TABLE ${1:dbo}.${2:EntityLog};
$0
]],
  },
}
