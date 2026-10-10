; Macro definitions. Uses of a macro are only known to a language server (semantic token `macro`).
(preproc_def
  name: (identifier) @macro)
(preproc_function_def
  name: (identifier) @macro)
; Capture names are ranked by first appearance in the query, so `@macro` has to precede `@constant`.

"break" @keyword
"case" @keyword
"const" @keyword
"continue" @keyword
"default" @keyword
"do" @keyword
"else" @keyword
"enum" @keyword
"extern" @keyword
"for" @keyword
"if" @keyword
"inline" @keyword
"return" @keyword
"sizeof" @keyword
"static" @keyword
"struct" @keyword
"switch" @keyword
"typedef" @keyword
"union" @keyword
"volatile" @keyword
"while" @keyword

"#define" @preprocessor
"#elif" @preprocessor
"#else" @preprocessor
"#endif" @preprocessor
"#if" @preprocessor
"#ifdef" @preprocessor
"#ifndef" @preprocessor
"#include" @preprocessor
(preproc_directive) @preprocessor

"--" @operator
"-" @operator
"-=" @operator
"->" @operator
"=" @operator
"!=" @operator
"*" @operator
"&" @operator
"&&" @operator
"+" @operator
"++" @operator
"+=" @operator
"<" @operator
"==" @operator
">" @operator
"||" @operator

"." @delimiter
";" @delimiter

(string_literal) @string
(system_lib_string) @string

(null) @constant
(number_literal) @number
(char_literal) @number

(call_expression
  function: (identifier) @function)
(call_expression
  function: (field_expression
    field: (field_identifier) @function))
(function_declarator
  declarator: (identifier) @function)
; Parameters: the declared name only, because uses inside the body look like any other identifier.
(parameter_declaration
  declarator: (identifier) @parameter)
(parameter_declaration
  declarator: (pointer_declarator
    declarator: (identifier) @parameter))
(parameter_declaration
  declarator: (pointer_declarator
    declarator: (pointer_declarator
      declarator: (identifier) @parameter)))
(parameter_declaration
  declarator: (array_declarator
    declarator: (identifier) @parameter))

; Assignment targets: the variable being written to, as opposed to the ones being read.
(assignment_expression
  left: (identifier) @variable.assigned)
; Fields written through `.` or `->` stay `@property` (below) so they keep the member color.
(assignment_expression
  left: (pointer_expression
    argument: (identifier) @variable.assigned))
(init_declarator
  declarator: (identifier) @variable.assigned)
(init_declarator
  declarator: (pointer_declarator
    declarator: (identifier) @variable.assigned))
(update_expression
  argument: (identifier) @variable.assigned)

(field_identifier) @property
(statement_identifier) @label
(type_identifier) @type
(primitive_type) @type.builtin
(sized_type_specifier) @type.builtin

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z\\d_]*$"))

(identifier) @variable

(comment) @comment
