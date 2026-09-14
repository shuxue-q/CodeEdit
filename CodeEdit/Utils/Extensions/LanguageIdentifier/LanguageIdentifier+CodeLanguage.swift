//
//  LanguageIdentifier+CodeLanguage.swift
//  CodeEdit
//
//  Created by Khan Winter on 9/9/24.
//

import LanguageServerProtocol
import CodeEditLanguages

extension CodeLanguage {
    /// The LSP language identifier for this code language, or `nil` if no language server supports it.
    var lspLanguageId: String? {
        switch self.id {
        case .agda,
                .bash,
                .cmake,
                .haskell,
                .julia,
                .kotlin,
                .ocaml,
                .ocamlInterface,
                .regex,
                .toml,
                .verilog,
                .zig,
                .plainText:
            return nil
        case .c:
            return LanguageIdentifier.c.rawValue
        case .cpp:
            return LanguageIdentifier.cpp.rawValue
        case .cSharp:
            return LanguageIdentifier.csharp.rawValue
        case .css:
            return LanguageIdentifier.css.rawValue
        case .dart:
            return LanguageIdentifier.dart.rawValue
        case .dockerfile:
            return LanguageIdentifier.dockerfile.rawValue
        case .elixir:
            return LanguageIdentifier.elixir.rawValue
        case .go, .goMod:
            return LanguageIdentifier.go.rawValue
        case .html:
            return LanguageIdentifier.html.rawValue
        case .java:
            return LanguageIdentifier.java.rawValue
        case .javascript, .jsdoc:
            return LanguageIdentifier.javascript.rawValue
        case .json:
            return LanguageIdentifier.json.rawValue
        case .jsx:
            return LanguageIdentifier.javascriptreact.rawValue
        case .lua:
            return LanguageIdentifier.lua.rawValue
        case .markdown, .markdownInline:
            return LanguageIdentifier.markdown.rawValue
        case .objc:
            return LanguageIdentifier.objc.rawValue
        case .perl:
            return LanguageIdentifier.perl.rawValue
        case .php:
            return LanguageIdentifier.php.rawValue
        case .python:
            return LanguageIdentifier.python.rawValue
        case .ruby:
            return LanguageIdentifier.ruby.rawValue
        case .rust:
            return LanguageIdentifier.rust.rawValue
        case .scala:
            return LanguageIdentifier.scala.rawValue
        case .sql:
            return LanguageIdentifier.sql.rawValue
        case .swift:
            return LanguageIdentifier.swift.rawValue
        case .tsx:
            return LanguageIdentifier.typescriptreact.rawValue
        case .typescript:
            return LanguageIdentifier.typescript.rawValue
        case .yaml:
            return LanguageIdentifier.yaml.rawValue
        }
    }
}
