; Macro definitions. Uses of a macro are only known to a language server (semantic token `macro`).
(preproc_def
  name: (identifier) @macro)
(preproc_function_def
  name: (identifier) @macro)
; Capture names are ranked by first appearance in the combined C++ and C query, so `@macro` comes first.

; Functions

(call_expression
  function: (qualified_identifier
    name: (identifier) @function))

(template_function
  name: (identifier) @function)

(template_method
  name: (field_identifier) @function)

(template_function
  name: (identifier) @function)

(function_declarator
  declarator: (qualified_identifier
    name: (identifier) @function))

(function_declarator
  declarator: (qualified_identifier
    name: (identifier) @function))

(function_declarator
  declarator: (field_identifier) @function)

; Types

(namespace_identifier) @namespace

(auto) @type.builtin

; Parameters passed by reference or with a default value (plain ones are matched by the C query)
(parameter_declaration
  declarator: (reference_declarator
    (identifier) @parameter))
(parameter_declaration
  declarator: (pointer_declarator
    declarator: (reference_declarator
      (identifier) @parameter)))
(optional_parameter_declaration
  declarator: (identifier) @parameter)
(optional_parameter_declaration
  declarator: (reference_declarator
    (identifier) @parameter))
(optional_parameter_declaration
  declarator: (pointer_declarator
    declarator: (identifier) @parameter))

; Constants

(this) @variable.builtin
(null "nullptr" @constant)

; Keywords

[
 "catch"
 "class"
 "co_await"
 "co_return"
 "co_yield"
 "constexpr"
 "constinit"
 "consteval"
 "delete"
 "explicit"
 "final"
 "friend"
 "mutable"
 "namespace"
 "noexcept"
 "new"
 "override"
 "private"
 "protected"
 "public"
 "template"
 "throw"
 "try"
 "typename"
 "using"
 "virtual"
 "concept"
 "requires"
] @keyword

; Strings

(raw_string_literal) @string
