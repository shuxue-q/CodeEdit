//
//  CMakeCompletionTables.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

/// The keyword and snippet tables for CMake, used by ``TreeSitterSnippetProvider`` under the
/// language id `cmake`.
///
/// Each entry lists the intents it is offered for (see ``CMakeTokenRules``):
///
/// - Command names and snippets: at command position (``CompletionIntent/statement``,
///   ``CompletionIntent/topLevel``, and ``CompletionIntent/unknown`` for a document without a tree).
///   Command names are listed with kind `.function`, as the language server lists them, so a name
///   both sources offer is shown once.
/// - Keyword arguments (`PUBLIC`, `REQUIRED`): in ``CompletionIntent/argument``.
/// - Variables (`CMAKE_SOURCE_DIR`): inside `${…}` (``CompletionIntent/variableReference``) and in
///   argument position, where `set(CMAKE_…` and `if(APPLE)` name them without the braces. They are
///   offered with kind `.variable`.
///
/// Snippet bodies use the LSP syntax and two-space indentation, CMake's convention.
enum CMakeCompletionTables {
    typealias Keyword = TreeSitterSnippetProvider.Keyword
    typealias Snippet = TreeSitterSnippetProvider.Snippet

    /// Where a command can start.
    private static let commandPositions: Set<CompletionIntent> = [.statement, .topLevel, .unknown]
    /// Where a keyword argument can go.
    private static let arguments: Set<CompletionIntent> = [.argument]
    /// Where a variable name can go.
    private static let variablePositions: Set<CompletionIntent> = [.argument, .variableReference]

    private static func entries(
        _ texts: [String],
        _ intents: Set<CompletionIntent>,
        kind: LSPCompletionCategory = .keyword
    ) -> [Keyword] {
        texts.map { Keyword(text: $0, intents: intents, kind: kind) }
    }

    // MARK: - Keywords

    /// The flow-control and definition commands.
    static let flowControlCommands = [
        "if", "elseif", "else", "endif", "foreach", "endforeach", "while", "endwhile",
        "function", "endfunction", "macro", "endmacro", "block", "endblock",
        "return", "break", "continue"
    ]

    /// The commands most CMake files use.
    static let commonCommands = [
        "cmake_minimum_required", "project", "add_executable", "add_library", "target_link_libraries",
        "target_include_directories", "target_compile_features", "target_compile_definitions",
        "target_compile_options", "target_sources", "set", "unset", "option", "message", "find_package",
        "find_library", "find_path", "find_program", "include", "include_directories", "add_subdirectory",
        "install", "add_custom_command", "add_custom_target", "add_test", "enable_testing", "list",
        "string", "file", "get_target_property", "set_target_properties", "set_property", "get_property",
        "configure_file", "execute_process", "math", "cmake_policy", "cmake_parse_arguments",
        "add_definitions", "add_compile_options", "link_directories", "mark_as_advanced",
        "FetchContent_Declare", "FetchContent_MakeAvailable"
    ]

    /// The keyword arguments of the common commands.
    static let keywordArguments = [
        "PUBLIC", "PRIVATE", "INTERFACE", "STATIC", "SHARED", "MODULE", "OBJECT", "REQUIRED", "QUIET",
        "COMPONENTS", "CONFIG", "VERSION", "LANGUAGES", "DESCRIPTION", "CACHE", "PARENT_SCOPE", "FORCE",
        "BOOL", "STRING", "PATH", "FILEPATH", "INTERNAL", "STATUS", "WARNING", "FATAL_ERROR", "SEND_ERROR",
        "AUTHOR_WARNING", "DEPRECATION", "NOTICE", "VERBOSE", "DEBUG", "TRACE", "TARGETS", "FILES",
        "DIRECTORY", "DESTINATION", "RUNTIME", "LIBRARY", "ARCHIVE", "PROPERTIES", "APPEND", "GLOB",
        "GLOB_RECURSE", "COMMAND", "DEPENDS", "OUTPUT", "WORKING_DIRECTORY", "COMMENT", "ON", "OFF", "TRUE",
        "FALSE", "AND", "OR", "NOT", "EXISTS", "DEFINED", "STREQUAL", "MATCHES", "VERSION_GREATER_EQUAL",
        "IN_LIST", "LISTS", "RANGE"
    ]

    /// The variables most CMake files read or set.
    static let variables = [
        "CMAKE_SOURCE_DIR", "CMAKE_CURRENT_SOURCE_DIR", "CMAKE_BINARY_DIR", "CMAKE_CURRENT_BINARY_DIR",
        "CMAKE_CURRENT_LIST_DIR", "CMAKE_MODULE_PATH", "CMAKE_BUILD_TYPE", "CMAKE_CXX_STANDARD",
        "CMAKE_C_STANDARD", "CMAKE_CXX_FLAGS", "CMAKE_C_FLAGS", "CMAKE_EXPORT_COMPILE_COMMANDS",
        "CMAKE_INSTALL_PREFIX", "CMAKE_SYSTEM_NAME", "CMAKE_PREFIX_PATH", "CMAKE_TOOLCHAIN_FILE",
        "PROJECT_NAME", "PROJECT_SOURCE_DIR", "PROJECT_BINARY_DIR", "PROJECT_VERSION", "BUILD_SHARED_LIBS",
        "APPLE", "WIN32", "UNIX", "MSVC", "CMAKE_CXX_COMPILER_ID"
    ]

    /// All keyword entries: command names, keyword arguments, and variables.
    static let keywords: [Keyword] =
        entries(flowControlCommands + commonCommands, commandPositions, kind: .function)
        + entries(keywordArguments, arguments)
        + entries(variables, variablePositions, kind: .variable)

    // MARK: - Snippets

    /// All snippet entries, offered at command position.
    static let snippets: [Snippet] = [
        Snippet(
            label: "cmake_minimum_required",
            body: "cmake_minimum_required(VERSION ${1:3.20})",
            detail: "cmake_minimum_required(VERSION 3.20)",
            intents: commandPositions
        ),
        Snippet(
            label: "project",
            body: "project(${1:name} VERSION ${2:1.0.0} LANGUAGES ${3:CXX})",
            detail: "project(name VERSION 1.0.0 LANGUAGES CXX)",
            intents: commandPositions
        ),
        Snippet(
            label: "add_executable",
            body: "add_executable(${1:target} ${2:main.cpp})",
            detail: "add_executable(target sources…)",
            intents: commandPositions
        ),
        Snippet(
            label: "add_library",
            body: "add_library(${1:target} ${2|STATIC,SHARED,OBJECT,INTERFACE,MODULE|} ${3:source.cpp})",
            detail: "add_library(target STATIC sources…)",
            intents: commandPositions
        ),
        Snippet(
            label: "target_link_libraries",
            body: "target_link_libraries(${1:target} ${2|PRIVATE,PUBLIC,INTERFACE|} ${3:library})",
            detail: "target_link_libraries(target PRIVATE library)",
            intents: commandPositions
        ),
        Snippet(
            label: "if",
            body: "if(${1:condition})\n  $0\nendif()",
            detail: "if(condition) … endif()",
            intents: commandPositions
        ),
        Snippet(
            label: "if else",
            body: "if(${1:condition})\n  $2\nelse()\n  $0\nendif()",
            detail: "if(condition) … else() … endif()",
            intents: commandPositions
        ),
        Snippet(
            label: "foreach",
            body: "foreach(${1:item} ${2:IN LISTS} ${3:list})\n  $0\nendforeach()",
            detail: "foreach(item IN LISTS list) … endforeach()",
            intents: commandPositions
        ),
        Snippet(
            label: "while",
            body: "while(${1:condition})\n  $0\nendwhile()",
            detail: "while(condition) … endwhile()",
            intents: commandPositions
        ),
        Snippet(
            label: "function",
            body: "function(${1:name} ${2:args})\n  $0\nendfunction()",
            detail: "function(name args) … endfunction()",
            intents: commandPositions
        ),
        Snippet(
            label: "macro",
            body: "macro(${1:name} ${2:args})\n  $0\nendmacro()",
            detail: "macro(name args) … endmacro()",
            intents: commandPositions
        ),
        Snippet(
            label: "option",
            body: "option(${1:NAME} \"${2:description}\" ${3|OFF,ON|})",
            detail: "option(NAME \"description\" OFF)",
            intents: commandPositions
        ),
        Snippet(
            label: "find_package",
            body: "find_package(${1:Package} ${2:REQUIRED})",
            detail: "find_package(Package REQUIRED)",
            intents: commandPositions
        ),
        Snippet(
            label: "install",
            body: "install(TARGETS ${1:target}\n  RUNTIME DESTINATION ${2:bin}\n  LIBRARY DESTINATION ${3:lib}\n"
                + "  ARCHIVE DESTINATION ${4:lib}\n)",
            detail: "install(TARGETS target …)",
            intents: commandPositions
        ),
        Snippet(
            label: "add_custom_command",
            body: "add_custom_command(\n  OUTPUT ${1:output}\n  COMMAND ${2:command}\n  DEPENDS ${3:dependency}\n"
                + "  COMMENT \"${4:comment}\"\n)",
            detail: "add_custom_command(OUTPUT … COMMAND … DEPENDS …)",
            intents: commandPositions
        )
    ]
}
