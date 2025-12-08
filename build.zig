const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options
    const enable_python = b.option(bool, "python", "Enable Python language support (default: true)") orelse true;
    const enable_javascript = b.option(bool, "javascript", "Enable JavaScript language support (default: true)") orelse true;

    // DVUI dependency with raylib backend for the demo
    const dvui_raylib_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .raylib,
    });
    const dvui_raylib_module = dvui_raylib_dep.module("dvui_raylib");

    // Tree-sitter dependency
    const zig_tree_sitter_dep = b.dependency("zig-tree-sitter", .{
        .target = target,
        .optimize = optimize,
    });

    // Get tree-sitter module
    const tree_sitter_module = zig_tree_sitter_dep.module("tree_sitter");

    // Build options module for conditional compilation
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_python", enable_python);
    build_options.addOption(bool, "enable_javascript", enable_javascript);

    // Tree-sitter Python language support
    var ts_python_lib: ?*std.Build.Step.Compile = null;
    if (enable_python) {
        const ts_python_dep = b.dependency("tree-sitter-python", .{
            .target = target,
            .optimize = optimize,
        });

        // Create module for Python library
        const python_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        // Add Python grammar sources
        python_mod.addCSourceFile(.{
            .file = ts_python_dep.path("src/parser.c"),
            .flags = &.{"-std=c11"},
        });
        python_mod.addCSourceFile(.{
            .file = ts_python_dep.path("src/scanner.c"),
            .flags = &.{"-std=c11"},
        });

        // Add include paths
        python_mod.addIncludePath(ts_python_dep.path("src"));
        python_mod.addIncludePath(zig_tree_sitter_dep.path("include"));

        // Build tree-sitter-python as a static library
        const python_lib = b.addLibrary(.{
            .name = "tree-sitter-python",
            .linkage = .static,
            .root_module = python_mod,
        });

        ts_python_lib = python_lib;
    }

    // Tree-sitter JavaScript language support
    var ts_javascript_lib: ?*std.Build.Step.Compile = null;
    if (enable_javascript) {
        const ts_javascript_dep = b.dependency("tree-sitter-javascript", .{
            .target = target,
            .optimize = optimize,
        });

        // Create module for JavaScript library
        const javascript_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        // Add JavaScript grammar sources
        javascript_mod.addCSourceFile(.{
            .file = ts_javascript_dep.path("src/parser.c"),
            .flags = &.{"-std=c11"},
        });
        javascript_mod.addCSourceFile(.{
            .file = ts_javascript_dep.path("src/scanner.c"),
            .flags = &.{"-std=c11"},
        });

        // Add include paths
        javascript_mod.addIncludePath(ts_javascript_dep.path("src"));
        javascript_mod.addIncludePath(zig_tree_sitter_dep.path("include"));

        // Build tree-sitter-javascript as a static library
        const javascript_lib = b.addLibrary(.{
            .name = "tree-sitter-javascript",
            .linkage = .static,
            .root_module = javascript_mod,
        });

        ts_javascript_lib = javascript_lib;
    }

    // Create a module for the code editor
    const dvui_code_module = b.addModule("dvui-code", .{
        .root_source_file = b.path("src/code_editor.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add imports to the module
    dvui_code_module.addImport("dvui", dvui_raylib_module);
    dvui_code_module.addImport("tree-sitter", tree_sitter_module);
    dvui_code_module.addImport("build_options", build_options.createModule());

    // Unified editor demo executable
    const demo = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/unified_editor.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link Python library if enabled
    if (ts_python_lib) |python_lib| {
        demo.linkLibrary(python_lib);
    }

    // Link JavaScript library if enabled
    if (ts_javascript_lib) |javascript_lib| {
        demo.linkLibrary(javascript_lib);
    }

    // Add imports to unified demo
    demo.root_module.addImport("dvui", dvui_raylib_module);
    demo.root_module.addImport("dvui-code", dvui_code_module);
    demo.root_module.addImport("tree-sitter", tree_sitter_module);
    demo.root_module.addImport("build_options", build_options.createModule());

    // Install step for unified demo
    const install_unified_demo = b.addInstallArtifact(demo, .{});

    // Run step for unified demo
    const run_unified_demo = b.addRunArtifact(demo);
    run_unified_demo.step.dependOn(&install_unified_demo.step);

    if (b.args) |args| {
        run_unified_demo.addArgs(args);
    }

    const unified_demo_step = b.step("unified-demo", "Run the unified code editor demo");
    unified_demo_step.dependOn(&run_unified_demo.step);

    // Default demo step
    const demo_step = b.step("demo", "Run the unified code editor demo");
    demo_step.dependOn(&run_unified_demo.step);

    // Default install step
    b.getInstallStep().dependOn(&install_unified_demo.step);
}
