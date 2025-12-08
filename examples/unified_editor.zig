const std = @import("std");
const dvui = @import("dvui");
const CodeEditor = @import("dvui-code");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const EditorMode = enum {
    python,
    javascript,
};

pub fn main() !void {
    defer _ = gpa_instance.deinit();

    // Initialize dvui with raylib backend
    var backend = try dvui.backend.initWindow(.{
        .gpa = gpa,
        .size = .{ .w = 1280.0, .h = 720.0 },
        .min_size = .{ .w = 640.0, .h = 480.0 },
        .vsync = true,
        .title = "Unified Code Editor - Python & JavaScript",
    });
    defer backend.deinit();

    // Initialize dvui Window
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    // Start with Python mode
    var mode: EditorMode = .python;

    // Initialize the unified code editor with Python
    var editor = try CodeEditor.CodeEditor.init(
        gpa,
        CodeEditor.tree_sitter.pythonLanguage(),
        CodeEditor.LanguageConfig.Python,
    );
    defer editor.deinit();

    // Sample Python code
    const python_code =
        \\# Python Syntax Highlighting Demo
        \\def fibonacci(n):
        \\    """Calculate fibonacci number recursively."""
        \\    if n <= 1:
        \\        return n
        \\    return fibonacci(n - 1) + fibonacci(n - 2)
        \\
        \\class Calculator:
        \\    def __init__(self, value=0):
        \\        self.value = value
        \\
        \\    def add(self, x):
        \\        self.value += x
        \\        return self.value
        \\
        \\# Test with incremental parsing
        \\result = fibonacci(10)
        \\print(f"Result: {result}")
    ;

    // Sample JavaScript code
    const javascript_code =
        \\// JavaScript Syntax Highlighting Demo
        \\function fibonacci(n) {
        \\    if (n <= 1) {
        \\        return n;
        \\    }
        \\    return fibonacci(n - 1) + fibonacci(n - 2);
        \\}
        \\
        \\class Calculator {
        \\    constructor(value = 0) {
        \\        this.value = value;
        \\    }
        \\
        \\    add(x) {
        \\        this.value += x;
        \\        return this.value;
        \\    }
        \\}
        \\
        \\// Test with incremental parsing
        \\const result = fibonacci(10);
        \\console.log(`Result: ${result}`);
    ;

    try editor.setText(python_code);

    main_loop: while (true) {
        // Render
        dvui.backend.c.BeginDrawing();
        defer dvui.backend.c.EndDrawing();

        try win.begin(std.time.nanoTimestamp());

        // Process events
        try backend.addAllEvents(&win);

        // Clear background
        backend.clear();

        // All UI must be in a block so widgets deinit before win.end()
        {
            // Create main layout
            var main_box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
            defer main_box.deinit();

            // Title bar
            {
            var title_box = dvui.box(@src(), .{ .dir = .horizontal }, .{
                .padding = .{ .x = 10, .y = 10 },
                .background = true,
                .color_fill = .{ .r = 0x2D, .g = 0x2D, .b = 0x30, .a = 0xFF },
            });
            defer title_box.deinit();

            dvui.label(@src(), "Unified Code Editor (with Incremental Parsing)", .{}, .{
                .font_style = .title,
                .color_text = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF },
            });

            _ = dvui.spacer(@src(), .{ .expand = .horizontal });

            // Language switcher
            const python_active = mode == .python;
            const js_active = mode == .javascript;

            if (dvui.button(@src(), "Python", .{}, .{
                .color_fill = if (python_active) .{ .r = 0x00, .g = 0x7A, .b = 0xCC, .a = 0xFF } else .{ .r = 0x50, .g = 0x50, .b = 0x50, .a = 0xFF },
            })) {
                if (mode != .python) {
                    mode = .python;
                    editor.deinit();
                    editor = try CodeEditor.CodeEditor.init(
                        gpa,
                        CodeEditor.tree_sitter.pythonLanguage(),
                        CodeEditor.LanguageConfig.Python,
                    );
                    try editor.setText(python_code);
                }
            }

            if (dvui.button(@src(), "JavaScript", .{}, .{
                .color_fill = if (js_active) .{ .r = 0x00, .g = 0x7A, .b = 0xCC, .a = 0xFF } else .{ .r = 0x50, .g = 0x50, .b = 0x50, .a = 0xFF },
            })) {
                if (mode != .javascript) {
                    mode = .javascript;
                    editor.deinit();
                    editor = try CodeEditor.CodeEditor.init(
                        gpa,
                        CodeEditor.tree_sitter.javascriptLanguage(),
                        CodeEditor.LanguageConfig.JavaScript,
                    );
                    try editor.setText(javascript_code);
                }
            }

            if (dvui.button(@src(), "Quit", .{}, .{})) {
                break :main_loop;
            }
        }

        // Info bar
        {
            var info_box = dvui.box(@src(), .{ .dir = .horizontal }, .{
                .padding = .{ .x = 10, .y = 5 },
                .background = true,
                .color_fill = .{ .r = 0x25, .g = 0x25, .b = 0x28, .a = 0xFF },
            });
            defer info_box.deinit();

            var buf: [256]u8 = undefined;
            const mode_name = if (mode == .python) "Python" else "JavaScript";
            const info_text = try std.fmt.bufPrint(&buf, "Mode: {s} | Lines: {} | Chars: {} | Highlights: {}", .{
                mode_name,
                std.mem.count(u8, editor.source.items, "\n") + 1,
                editor.source.items.len,
                editor.highlights.items.len,
            });

            dvui.label(@src(), "{s}", .{info_text}, .{
                .color_text = .{ .r = 0xAA, .g = 0xAA, .b = 0xAA, .a = 0xFF },
            });
        }

        // Editor area
        {
            var editor_box = dvui.box(@src(), .{ .dir = .vertical }, .{
                .expand = .both,
                .background = true,
                .color_fill = .{ .r = 0x1E, .g = 0x1E, .b = 0x1E, .a = 0xFF },
                .padding = .{ .x = 10, .y = 10 },
            });
            defer editor_box.deinit();

            try editor.render(&win);
        }

        // Status bar
        {
            var status_box = dvui.box(@src(), .{ .dir = .horizontal }, .{
                .padding = .{ .x = 10, .y = 5 },
                .background = true,
                .color_fill = .{ .r = 0x00, .g = 0x7A, .b = 0xCC, .a = 0xFF },
            });
            defer status_box.deinit();

            dvui.label(@src(), "Unified Editor with Incremental Parsing | Tree-sitter | Switch languages to test", .{}, .{
                .color_text = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF },
            });
        }
        } // End UI block - all widgets deinit here

        // Check for quit events
        for (dvui.events()) |*e| {
            if (e.evt == .window and e.evt.window.action == .close) break :main_loop;
            if (e.evt == .app and e.evt.app.action == .quit) break :main_loop;
        }

        // marks end of dvui frame
        const end_micros = try win.end(.{});
        _ = end_micros;

        // Set cursor
        backend.setCursor(win.cursorRequested());
    }
}
