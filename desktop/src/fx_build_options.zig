//! The build_options fx expects when it is linked as a library. fx's own
//! build.zig generates these; a host that embeds fx supplies the same shape.
pub const git_commit = "0000000000000000000000000000000000000000";
pub const app_version = "0.0.17";
pub const update_channel = "stable";
pub const wasm_surface = .none;
pub const libfx = true;
pub const builtin_tools = true;
