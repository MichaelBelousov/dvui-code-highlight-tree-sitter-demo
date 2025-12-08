// Re-export tree-sitter types and functions from the official bindings
// This file provides a simplified interface for our code editor

const ts = @import("tree-sitter");
const build_options = @import("build_options");

// Re-export commonly used types
pub const Parser = ts.Parser;
pub const Tree = ts.Tree;
pub const Node = ts.Node;
pub const Point = ts.Point;
pub const Range = ts.Range;
pub const InputEdit = ts.InputEdit;
pub const Language = ts.Language;
pub const Query = ts.Query;
pub const QueryCursor = ts.QueryCursor;

// Python language support (conditionally available based on build options)
extern fn tree_sitter_python() *const Language;

pub fn pythonLanguage() *const Language {
    return tree_sitter_python();
}

/// Load the Python language grammar.
/// Compile-time error if Python support was disabled at build time.
/// Use -Dpython=true when building to enable Python support (enabled by default).
pub fn loadPythonLanguage() !*const Language {
    if (!build_options.enable_python) {
        @compileError("Python language support was disabled at build time. Rebuild with -Dpython=true (or without -Dpython=false)");
    }
    return pythonLanguage();
}

// JavaScript language support (conditionally available based on build options)
extern fn tree_sitter_javascript() *const Language;

pub fn javascriptLanguage() *const Language {
    return tree_sitter_javascript();
}

/// Load the JavaScript language grammar.
/// Compile-time error if JavaScript support was disabled at build time.
/// Use -Djavascript=true when building to enable JavaScript support (enabled by default).
pub fn loadJavaScriptLanguage() !*const Language {
    if (!build_options.enable_javascript) {
        @compileError("JavaScript language support was disabled at build time. Rebuild with -Djavascript=true (or without -Djavascript=false)");
    }
    return javascriptLanguage();
}
