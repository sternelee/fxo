const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const nanoui = b.dependency("nanoui", .{ .target = target, .optimize = optimize }).module("nanoui");

    // fx is linked in-process, the way the CLI runs it: the ACP server is
    // driven over an in-memory transport instead of spawning `fx acp`.
    const fx = b.createModule(.{
        .root_source_file = b.path("../src/fxlib_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The packaging scripts pass -Dversion so the bundle and fx's own build
    // options agree on one version. Development builds keep the source default.
    const version = b.option([]const u8, "version", "fx desktop's version (release builds)") orelse "";
    const fx_options = b.addOptions();
    fx_options.addOption([]const u8, "app_version", if (version.len > 0) version else "0.0.17");
    fx_options.addOption([]const u8, "git_commit", "0000000000000000000000000000000000000000");
    fx_options.addOption([]const u8, "update_channel", "stable");
    fx_options.addOption([]const u8, "wasm_surface", "none");
    fx_options.addOption(bool, "libfx", true);
    fx_options.addOption(bool, "builtin_tools", true);
    fx.addOptions("build_options", fx_options);
    // fx's session store is its own module with its own build options.
    const sm_options = b.addOptions();
    sm_options.addOption(bool, "hooks", false);
    sm_options.addOptionPathUntracked("trace_dir", b.path("zig-out/session-manager-traces"));
    sm_options.addOptionPathUntracked("src_dir", b.path("../src/core/session_manager"));
    const session_manager = b.createModule(.{
        .root_source_file = b.path("../src/core/session_manager/api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    session_manager.addImport("build_options", sm_options.createModule());
    fx.addImport("session_manager", session_manager);

    // fx's self_exe helper needs these in a test build.
    const test_paths = b.addOptions();
    test_paths.addOptionPathUntracked("product_exe", b.path("zig-out/bin/fx-desktop"));
    test_paths.addOptionPathUntracked("source_root", b.path("../src"));
    fx.addImport("test_paths", test_paths.createModule());

    const exe = b.addExecutable(.{
        .name = "fx-desktop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nanoui", .module = nanoui },
                .{ .name = "fx", .module = fx },
            },
        }),
    });
    if (target.result.os.tag == .windows) exe.subsystem = .windows;
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Run fx desktop").dependOn(&run.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nanoui", .module = nanoui },
                .{ .name = "fx", .module = fx },
            },
        }),
    });
    b.step("test", "Run headless view tests").dependOn(&b.addRunArtifact(tests).step);
}
