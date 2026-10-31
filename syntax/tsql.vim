" Focused legacy syntax fallback for constructs not exposed as useful nodes by
" tree-sitter-sql. Generic SQL highlighting remains owned by Tree-sitter.
if exists("b:current_syntax")
  finish
endif

syntax case ignore

" Shield fallback matches from SQL comments and string literals.
syntax match tsqlLineComment "--.*$" contains=@Spell
syntax region tsqlBlockComment start="/\*" end="\*/" contains=tsqlBlockComment,@Spell
syntax match tsqlStringPrefix "\<N\ze'" nextgroup=tsqlString
syntax region tsqlString start="'" skip="''" end="'"

" SQL Server identifiers and variables that the generic parser recovers only
" partially, or classifies as operators and ordinary identifiers.
syntax region tsqlBracketIdentifier start="\[" skip="\]\]" end="\]"
syntax match tsqlSystemVariable "@@[[:alpha:]_][[:alnum:]_]*"
syntax match tsqlVariable "\%(@\)\@<!@[[:alpha:]_][[:alnum:]_]*"

" T-SQL tokens used by the local conventions and snippets that currently have
" no stable tree-sitter-sql node to capture.
syntax keyword tsqlKeyword ALTER AS BEGIN CASCADE CASE COMMIT CONSTRAINT CREATE
syntax keyword tsqlKeyword ELSE END FOR FOREIGN FROM IF LIKE MAX NEXT NOT NULL
syntax keyword tsqlKeyword OBJECT OFFSET ON ORDER ROLLBACK ROWS UNIQUE USE WHERE
syntax keyword tsqlKeyword APPLY CATCH CLUSTERED DECLARE DENY EXEC EXECUTE
syntax keyword tsqlKeyword FETCH GRANT NOCOUNT OUTPUT PERSISTED PRINT RAISERROR
syntax keyword tsqlKeyword REVOKE THROW TRY XACT_ABORT
syntax keyword tsqlKeyword OPEN SYMMETRIC CLOSE DECRYPTION

syntax keyword tsqlType BIGINT BIT DATE DATETIME2 DECIMAL HIERARCHYID INT
syntax keyword tsqlType NVARCHAR ROWVERSION SQL_VARIANT SYSNAME TINYINT
syntax keyword tsqlType UNIQUEIDENTIFIER VARCHAR

syntax match tsqlBuiltinFunction "\<\%(CAST\|CONVERT\|DENSE_RANK\|ERROR_MESSAGE\|IDENTITY\|ISNULL\|LEAD\|OPENJSON\|QUOTENAME\|SCOPE_IDENTITY\|SYSUTCDATETIME\|XACT_STATE\)\ze\s*("

" GO is a client batch separator, not a T-SQL statement. Match it only when it
" occupies a line, optionally followed by a repeat count or line comment.
syntax match tsqlBatchSeparator "^\s*\zsGO\ze\%\(\s\+\d\+\)\=\s*\%\($\|--\)" nextgroup=tsqlBatchCount skipwhite
syntax match tsqlBatchCount "\d\+" contained

highlight default link tsqlBatchCount Number
highlight default link tsqlBatchSeparator Keyword
highlight default link tsqlBlockComment Comment
highlight default link tsqlBracketIdentifier Identifier
highlight default link tsqlBuiltinFunction Function
highlight default link tsqlKeyword Keyword
highlight default link tsqlLineComment Comment
highlight default link tsqlString String
highlight default link tsqlStringPrefix String
highlight default link tsqlSystemVariable Special
highlight default link tsqlType Type
highlight default link tsqlVariable Identifier

let b:current_syntax = "tsql"
