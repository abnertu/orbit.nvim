; extends

; These nodes are recognized by tree-sitter-sql but are not captured by its
; upstream highlights query. ENABLE and DISABLE are used by SQL Server index
; and trigger statements.
[
  (keyword_enable)
  (keyword_disable)
] @keyword

; SQL Server TOP is currently parsed as a function invocation. Correct the
; semantic capture without treating every identifier named "top" as a keyword.
((invocation
  (object_reference
    name: (identifier) @keyword))
  (#vim-match? @keyword "\\c^top$")
  (#set! priority 110))

; SET options remain object references inside an error-recovery node. Keep the
; correction limited to the options orbit.nvim's T-SQL conventions generate.
((ERROR
  (keyword_set)
  (object_reference
    name: (identifier) @keyword))
  (#vim-match? @keyword "\\c^nocount$")
  (#set! priority 110))

((ERROR
  (keyword_set)
  (object_reference
    name: (identifier) @keyword))
  (#vim-match? @keyword "\\c^xact_abort$")
  (#set! priority 110))

; Refine stable SQL Server constructs that the generic query can only classify
; as ordinary calls, fields, or custom types. Lexical recovery for the same
; constructs remains in syntax/tsql.vim when these nodes disappear in ERRORs.
((cast
  name: (keyword_cast) @function.builtin)
  (#set! priority 110))

((invocation
  (object_reference
    !schema
    name: (identifier) @function.builtin))
  (#vim-match? @function.builtin "\\c\\v^(convert|dense_rank|error_message|identity|isnull|lead|openjson|quotename|scope_identity|sysutcdatetime|xact_state)$")
  (#set! priority 110))

((field
  name: (identifier) @variable)
  (#lua-match? @variable "^@[A-Za-z_][A-Za-z0-9_]*$")
  (#set! priority 110))

((unary_expression
  operator: (op_unary_other) @_tsql_system_variable_operator
  operand: (field
    name: (identifier))) @variable.builtin
  (#eq? @_tsql_system_variable_operator "@@")
  (#set! priority 110))

((column_definition
  custom_type: (object_reference
    !schema
    name: (identifier) @type.builtin))
  (#vim-match? @type.builtin "\\c\\v^(hierarchyid|rowversion|sql_variant|sysname|uniqueidentifier)$")
  (#set! priority 110))

((cast
  custom_type: (object_reference
    !schema
    name: (identifier) @type.builtin))
  (#vim-match? @type.builtin "\\c\\v^(hierarchyid|rowversion|sql_variant|sysname|uniqueidentifier)$")
  (#set! priority 110))
