return {
  {
    "grantobj",
    "Grant object permission",
    [[
GRANT ${1:EXECUTE}
ON OBJECT::${2:dbo}.${3:CreateEntity}
TO ${4:ApplicationUser};
$0
]],
  },

  {
    "grantschema",
    "Grant schema permission",
    [[
GRANT ${1:EXECUTE}
ON SCHEMA::${2:dbo}
TO ${3:ApplicationUser};
$0
]],
  },

  {
    "revoke",
    "Revoke object permission",
    [[
REVOKE ${1:SELECT}
ON OBJECT::${2:dbo}.${3:Entity}
FROM ${4:ApplicationUser};
$0
]],
  },

  {
    "deny",
    "Deny object permission",
    [[
DENY ${1:DELETE}
ON OBJECT::${2:dbo}.${3:Entity}
TO ${4:ApplicationUser};
$0
]],
  },

  {
    "objif",
    "Check object existence",
    [[
IF OBJECT_ID(N'${1:dbo}.${2:Entity}', N'${3:U}') IS NOT NULL
BEGIN
    ${4:-- Statement.}
END;
$0
]],
  },

  {
    "dropobj",
    "Drop object if it exists",
    [[
DROP ${1:PROCEDURE} IF EXISTS ${2:dbo}.${3:GetEntity};
$0
]],
  },
}
