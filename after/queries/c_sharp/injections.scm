; extends

; JetBrains-style language injection comments:
; // language=sql
; var query = "SELECT * FROM users";
; Keep matches independent: injection.combined merges unrelated literals.
; Interpolation expressions act as placeholders so the SQL remains parseable.
; Strings requiring C# escape decoding are skipped because injection ranges
; cannot represent their runtime text accurately.

((comment) @_injection_comment
  .
  [
    (local_declaration_statement
      (variable_declaration
        (variable_declarator
          [
            (string_literal
              (string_literal_content) @injection.content) @_sql_string
            (raw_string_literal
              (raw_string_content) @injection.content) @_sql_string
          ])))
    (field_declaration
      (variable_declaration
        (variable_declarator
          [
            (string_literal
              (string_literal_content) @injection.content) @_sql_string
            (raw_string_literal
              (raw_string_content) @injection.content) @_sql_string
          ])))
  ]
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-comment-injection-enabled? @_injection_comment)
  (#set! injection.language "sql"))

((comment) @_injection_comment
  .
  [
    (local_declaration_statement
      (variable_declaration
        (variable_declarator
          (verbatim_string_literal) @injection.content) @_sql_string))
    (field_declaration
      (variable_declaration
        (variable_declarator
          (verbatim_string_literal) @injection.content) @_sql_string))
  ]
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-comment-injection-enabled? @_injection_comment)
  (#offset! @injection.content 0 2 0 -1)
  (#set! injection.language "sql"))

((comment) @_injection_comment
  .
  [
    (local_declaration_statement
      (variable_declaration
        (variable_declarator
          (interpolated_string_expression
            [
              (string_content) @injection.content
              (interpolation
                (interpolation_brace)
                .
                (_) @injection.content)
            ]+) @_sql_string)))
    (field_declaration
      (variable_declaration
        (variable_declarator
          (interpolated_string_expression
            [
              (string_content) @injection.content
              (interpolation
                (interpolation_brace)
                .
                (_) @injection.content)
            ]+) @_sql_string)))
  ]
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-comment-injection-enabled? @_injection_comment)
  (#set! injection.language "sql")
  (#set! injection.include-children))

((comment) @_injection_comment
  .
  (expression_statement
    (assignment_expression
      right: [
        (string_literal
          (string_literal_content) @injection.content) @_sql_string
        (raw_string_literal
          (raw_string_content) @injection.content) @_sql_string
      ]))
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-comment-injection-enabled? @_injection_comment)
  (#set! injection.language "sql"))

((comment) @_injection_comment
  .
  (expression_statement
    (assignment_expression
      right: (verbatim_string_literal) @injection.content) @_sql_string)
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-comment-injection-enabled? @_injection_comment)
  (#offset! @injection.content 0 2 0 -1)
  (#set! injection.language "sql"))

((comment) @_injection_comment
  .
  (expression_statement
    (assignment_expression
      right: (interpolated_string_expression
        [
          (string_content) @injection.content
          (interpolation
            (interpolation_brace)
            .
            (_) @injection.content)
        ]+) @_sql_string))
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-comment-injection-enabled? @_injection_comment)
  (#set! injection.language "sql")
  (#set! injection.include-children))

; Any variable beginning with sql is SQL without a marker. Use a language
; comment for SQL stored under any other name.
(variable_declarator
  name: (identifier) @_sql_variable
  [
    (string_literal
      (string_literal_content) @injection.content) @_sql_string
    (raw_string_literal
      (raw_string_content) @injection.content) @_sql_string
  ]
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-auto-injection-enabled? @_sql_variable)
  (#set! injection.language "sql"))

(variable_declarator
  name: (identifier) @_sql_variable
  (verbatim_string_literal) @injection.content @_sql_string
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-auto-injection-enabled? @_sql_variable)
  (#offset! @injection.content 0 2 0 -1)
  (#set! injection.language "sql"))

(variable_declarator
  name: (identifier) @_sql_variable
  (interpolated_string_expression
    [
      (string_content) @injection.content
      (interpolation
        (interpolation_brace)
        .
        (_) @injection.content)
    ]+) @_sql_string
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-auto-injection-enabled? @_sql_variable)
  (#set! injection.language "sql")
  (#set! injection.include-children))

(assignment_expression
  left: [
    (identifier) @_sql_variable
    (member_access_expression
      name: (identifier) @_sql_variable)
  ]
  "="
  right: [
    (string_literal
      (string_literal_content) @injection.content) @_sql_string
    (raw_string_literal
      (raw_string_content) @injection.content) @_sql_string
  ]
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-auto-injection-enabled? @_sql_variable)
  (#set! injection.language "sql"))

(assignment_expression
  left: [
    (identifier) @_sql_variable
    (member_access_expression
      name: (identifier) @_sql_variable)
  ]
  "="
  right: (verbatim_string_literal) @injection.content @_sql_string
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-auto-injection-enabled? @_sql_variable)
  (#offset! @injection.content 0 2 0 -1)
  (#set! injection.language "sql"))

(assignment_expression
  left: [
    (identifier) @_sql_variable
    (member_access_expression
      name: (identifier) @_sql_variable)
  ]
  "="
  right: (interpolated_string_expression
    [
      (string_content) @injection.content
      (interpolation
        (interpolation_brace)
        .
        (_) @injection.content)
    ]+) @_sql_string
  (#orbit-sql-string-supported? @_sql_string)
  (#orbit-sql-auto-injection-enabled? @_sql_variable)
  (#set! injection.language "sql")
  (#set! injection.include-children))
