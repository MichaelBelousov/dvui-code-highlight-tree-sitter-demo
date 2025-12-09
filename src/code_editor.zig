const std = @import("std");
const dvui = @import("dvui");
const ts = @import("tree-sitter");
const ts_wrapper = @import("tree_sitter.zig");

pub const tree_sitter = ts_wrapper;

// TODO: replace all this theme stuff with tree-sitter's own highlighting logic
/// Configuration for language-specific syntax highlighting
pub const LanguageConfig = struct {
    keywords: []const []const u8 = &.{},
    special_nodes: []const []const u8 = &.{},

    pub const Python = LanguageConfig{
        .keywords = &.{
            "def",      "class", "if",       "else",  "elif",   "for",     "while", "return",
            "import",   "from",  "as",       "try",   "except", "finally", "with",  "lambda",
            "pass",     "break", "continue", "yield", "assert", "raise",   "del",   "global",
            "nonlocal", "and",   "or",       "not",   "in",     "is",      "None",  "True",
            "False",
        },
        .special_nodes = &.{ "string", "comment", "function_definition", "class_definition" },
    };

    pub const JavaScript = LanguageConfig{
        .keywords = &.{
            "function",   "class",     "const",  "let",      "var",    "if",    "else",     "for",
            "while",      "do",        "return", "import",   "export", "from",  "as",       "try",
            "catch",      "finally",   "throw",  "new",      "this",   "super", "extends",  "static",
            "async",      "await",     "break",  "continue", "switch", "case",  "default",  "typeof",
            "instanceof", "void",      "delete", "in",       "of",     "yield", "debugger", "with",
            "null",       "undefined", "true",   "false",
        },
        .special_nodes = &.{ "string", "comment", "template_string", "regex" },
    };
};

pub const SyntaxTheme = struct {
    keyword: dvui.Color,
    function: dvui.Color,
    string: dvui.Color,
    number: dvui.Color,
    comment: dvui.Color,
    operator: dvui.Color,
    variable: dvui.Color,
    type: dvui.Color,
    default: dvui.Color,

    pub fn defaultDark() SyntaxTheme {
        return .{
            .keyword = dvui.Color{ .r = 0xC5, .g = 0x86, .b = 0xC0, .a = 0xFF }, // Purple
            .function = dvui.Color{ .r = 0xDA, .g = 0xDA, .b = 0x93, .a = 0xFF }, // Yellow
            .string = dvui.Color{ .r = 0xCE, .g = 0x91, .b = 0x78, .a = 0xFF }, // Orange
            .number = dvui.Color{ .r = 0xB5, .g = 0xCE, .b = 0xA8, .a = 0xFF }, // Light green
            .comment = dvui.Color{ .r = 0x6A, .g = 0x99, .b = 0x55, .a = 0xFF }, // Green
            .operator = dvui.Color{ .r = 0xD4, .g = 0xD4, .b = 0xD4, .a = 0xFF }, // Light gray
            .variable = dvui.Color{ .r = 0x9C, .g = 0xDC, .b = 0xFE, .a = 0xFF }, // Light blue
            .type = dvui.Color{ .r = 0x4E, .g = 0xC9, .b = 0xB0, .a = 0xFF }, // Cyan
            .default = dvui.Color{ .r = 0xD4, .g = 0xD4, .b = 0xD4, .a = 0xFF }, // Light gray
        };
    }
};

pub const HighlightRange = struct {
    start: usize,
    end: usize,
    color: dvui.Color,
};

/// Unified code editor that supports any tree-sitter language with incremental parsing
pub const CodeEditor = struct {
    allocator: std.mem.Allocator,
    parser: *ts.Parser,
    tree: ?*ts.Tree,
    source: std.ArrayList(u8),
    theme: SyntaxTheme,
    highlights: std.ArrayList(HighlightRange),
    cursor_pos: usize,
    lang_config: LanguageConfig,

    pub fn init(allocator: std.mem.Allocator, language: *const ts.Language, lang_config: LanguageConfig) !CodeEditor {
        const parser = ts.Parser.create();
        errdefer parser.destroy();

        try parser.setLanguage(language);

        return .{
            .allocator = allocator,
            .parser = parser,
            .tree = null,
            .source = .empty,
            .theme = SyntaxTheme.defaultDark(),
            .highlights = .empty,
            .cursor_pos = 0,
            .lang_config = lang_config,
        };
    }

    pub fn deinit(self: *CodeEditor) void {
        if (self.tree) |tree| {
            tree.destroy();
        }
        self.parser.destroy();
        self.source.deinit(self.allocator);
        self.highlights.deinit(self.allocator);
    }

    pub fn setText(self: *CodeEditor, text: []const u8) !void {
        self.source.clearRetainingCapacity();
        try self.source.appendSlice(self.allocator, text);
        try self.reparse();
    }

    /// Insert text at the given byte position with incremental parsing
    pub fn insertText(self: *CodeEditor, pos: usize, text: []const u8) !void {
        if (pos > self.source.items.len) return error.InvalidPosition;

        // Create edit descriptor for tree-sitter incremental parsing
        const start_byte = pos;
        const old_end_byte = pos;
        const new_end_byte = pos + text.len;

        // Convert byte positions to points (row, column)
        const start_point = self.byteToPoint(start_byte);
        const old_end_point = start_point; // Same position for insertion
        const new_end_point = self.byteToPoint(new_end_byte); // After insertion

        // Apply edit to the tree before modifying source
        if (self.tree) |tree| {
            const edit = ts.InputEdit{
                .start_byte = @intCast(start_byte),
                .old_end_byte = @intCast(old_end_byte),
                .new_end_byte = @intCast(new_end_byte),
                .start_point = start_point,
                .old_end_point = old_end_point,
                .new_end_point = new_end_point,
            };
            tree.edit(&edit);
        }

        // Now modify the source
        try self.source.insertSlice(self.allocator, pos, text);

        // Reparse incrementally
        try self.reparseIncremental();
    }

    /// Delete a range of text with incremental parsing
    pub fn deleteRange(self: *CodeEditor, start: usize, end: usize) !void {
        if (start >= end or end > self.source.items.len) return;

        const remove_len = end - start;

        // Create edit descriptor
        const start_byte = start;
        const old_end_byte = end;
        const new_end_byte = start;

        const start_point = self.byteToPoint(start_byte);
        const old_end_point = self.byteToPoint(old_end_byte);
        const new_end_point = start_point; // Same as start for deletion

        // Apply edit to tree before modifying source
        if (self.tree) |tree| {
            const edit = ts.InputEdit{
                .start_byte = @intCast(start_byte),
                .old_end_byte = @intCast(old_end_byte),
                .new_end_byte = @intCast(new_end_byte),
                .start_point = start_point,
                .old_end_point = old_end_point,
                .new_end_point = new_end_point,
            };
            tree.edit(&edit);
        }

        // Now modify the source
        std.mem.copyForwards(u8, self.source.items[start..], self.source.items[end..]);
        self.source.shrinkRetainingCapacity(self.source.items.len - remove_len);

        // Reparse incrementally
        try self.reparseIncremental();
    }

    /// Convert byte offset to Point (row, column)
    fn byteToPoint(self: *CodeEditor, byte_offset: usize) ts.Point {
        var row: u32 = 0;
        var col: u32 = 0;
        var current_byte: usize = 0;

        while (current_byte < byte_offset and current_byte < self.source.items.len) {
            if (self.source.items[current_byte] == '\n') {
                row += 1;
                col = 0;
            } else {
                col += 1;
            }
            current_byte += 1;
        }

        return .{ .row = row, .column = col };
    }

    /// Reparse the entire document (non-incremental)
    fn reparse(self: *CodeEditor) !void {
        if (self.tree) |old_tree| {
            old_tree.destroy();
        }

        const new_tree = self.parser.parseString(self.source.items, null);
        self.tree = new_tree;
        try self.updateHighlights();
    }

    /// Reparse incrementally using the edited tree
    fn reparseIncremental(self: *CodeEditor) !void {
        const old_tree = self.tree;
        const new_tree = self.parser.parseString(self.source.items, old_tree);

        if (old_tree) |tree| {
            tree.destroy();
        }

        self.tree = new_tree;
        try self.updateHighlights();
    }

    fn updateHighlights(self: *CodeEditor) !void {
        self.highlights.clearRetainingCapacity();

        if (self.tree) |tree| {
            const root = tree.rootNode();
            try self.highlightNode(root);
        }
    }

    fn highlightNode(self: *CodeEditor, node: ts.Node) !void {
        const node_type = node.kind();
        const color = self.getColorForNodeType(node_type);

        // Only add highlights for leaf nodes
        if (node.childCount() == 0) {
            try self.highlights.append(self.allocator, .{
                .start = node.startByte(),
                .end = node.endByte(),
                .color = color,
            });
        }

        // Recursively highlight children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.highlightNode(child);
            }
        }
    }

    fn getColorForNodeType(self: *CodeEditor, node_type: []const u8) dvui.Color {
        // Check if it's a keyword
        for (self.lang_config.keywords) |keyword| {
            if (std.mem.eql(u8, node_type, keyword)) {
                return self.theme.keyword;
            }
        }

        // Strings
        if (std.mem.eql(u8, node_type, "string") or
            std.mem.indexOf(u8, node_type, "string") != null)
        {
            return self.theme.string;
        }

        // Numbers
        if (std.mem.eql(u8, node_type, "integer") or
            std.mem.eql(u8, node_type, "float") or
            std.mem.eql(u8, node_type, "number"))
        {
            return self.theme.number;
        }

        // Comments
        if (std.mem.eql(u8, node_type, "comment")) {
            return self.theme.comment;
        }

        // Function/method names
        if (std.mem.eql(u8, node_type, "identifier") or
            std.mem.indexOf(u8, node_type, "function") != null or
            std.mem.indexOf(u8, node_type, "method") != null)
        {
            return self.theme.function;
        }

        // Operators
        if (std.mem.indexOf(u8, node_type, "operator") != null or
            std.mem.eql(u8, node_type, "+") or
            std.mem.eql(u8, node_type, "-") or
            std.mem.eql(u8, node_type, "*") or
            std.mem.eql(u8, node_type, "/") or
            std.mem.eql(u8, node_type, "=") or
            std.mem.eql(u8, node_type, "==") or
            std.mem.eql(u8, node_type, "===") or
            std.mem.eql(u8, node_type, "!=") or
            std.mem.eql(u8, node_type, "!==") or
            std.mem.eql(u8, node_type, "<") or
            std.mem.eql(u8, node_type, ">") or
            std.mem.eql(u8, node_type, "=>"))
        {
            return self.theme.operator;
        }

        // Types
        if (std.mem.indexOf(u8, node_type, "type") != null) {
            return self.theme.type;
        }

        return self.theme.default;
    }

    pub fn render(self: *CodeEditor, win: *dvui.Window) !void {
        _ = win;
        var box = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .both,
            .background = true,
            .color_fill = .{ .r = 0x1E, .g = 0x1E, .b = 0x1E, .a = 0xFF },
        });
        defer box.deinit();

        // Render code with syntax highlighting
        var scroll = dvui.scrollArea(@src(), .{}, .{
            .expand = .both,
            .color_fill = .{ .r = 0x1E, .g = 0x1E, .b = 0x1E, .a = 0xFF },
        });
        defer scroll.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{
            .color_text = self.theme.default,
            .color_fill = dvui.Color.black,
        });
        defer tl.deinit();

        // Sort highlights by start position to avoid out-of-order rendering
        std.mem.sort(HighlightRange, self.highlights.items, {}, struct {
            fn lessThan(_: void, a: HighlightRange, b: HighlightRange) bool {
                return a.start < b.start;
            }
        }.lessThan);

        var last_pos: usize = 0;
        for (self.highlights.items) |h| {
            // Render text before this highlight (if any)
            if (last_pos < h.start) {
                tl.addText(self.source.items[last_pos..h.start], .{ .color_text = self.theme.default });
            }
            // Render the highlighted text
            if (h.start < h.end and h.end <= self.source.items.len) {
                tl.addText(self.source.items[h.start..h.end], .{ .color_text = h.color });
                last_pos = h.end;
            }
        }
        // Render any remaining text after the last highlight
        if (last_pos < self.source.items.len) {
            tl.addText(self.source.items[last_pos..], .{ .color_text = self.theme.default });
        }
    }
};
