//! A library root for embedding fx in-process: the ACP server, its transport
//! types, and a Config the host can hand to `server.runWithTransport`.
//!
//! This mirrors how fx's own CLI composes the server (`main.zig`'s
//! `fullEntryConfig`), minus the terminal UI. A host that links this module
//! runs fx in its own process instead of spawning `fx acp`.
const std = @import("std");

pub const server = @import("acp/server.zig");
pub const jsonrpc = @import("acp/jsonrpc.zig");
pub const acp_runner = @import("core/cli/acp_runner.zig");

const builtin_context = @import("builtins/context.zig");
const builtin_gateway = @import("builtins/gateway.zig");
const builtin_mcp = @import("builtins/mcp.zig");
const builtin_modes = @import("builtins/modes.zig");
const builtin_providers = @import("builtins/providers.zig");
const builtin_skills = @import("builtins/skills.zig");
const builtin_tools = @import("builtins/tools.zig");
const native_host = @import("core/hosts/native.zig");
const agent_steps = @import("core/config/agent_steps.zig");
const agents = @import("core/agents/agents.zig");
const context_contract = @import("core/workspace/context_contract.zig");
const credentials = @import("core/auth/credentials.zig");
const shell_process_provider = @import("tools/shell/process_provider.zig");
const tool_result_limits = @import("core/tooling/tool_result_limits.zig");
const io_mod = @import("core/shared/io.zig");

const default_context_registry = context_contract.Registry{ .default_provider = builtin_context.provider };

/// The entries fx's own list tools never walk.
const ignored_list_entries = [_][]const u8{
    ".git",
    ".hg",
    ".svn",
    "node_modules",
    "zig-cache",
    ".zig-cache",
    "zig-out",
    "target",
    "dist",
    "build",
    ".next",
    ".venv",
    "__pycache__",
};

/// Builds the ACP server config the way fx's CLI does, so an embedding host
/// gets the same tools, providers and limits as `fx acp`.
pub fn embeddedConfig() acp_runner.Config {
    // A host process (the desktop app) never installs fx's own environment,
    // so fx's getenv would find nothing and project instructions, HOME and
    // profile paths would all come back missing. Read libc's environment
    // instead, which is what setLibcEnviron exists for.
    io_mod.setLibcEnviron();
    return .{
        .auth_mode = .local,
        .default_model = builtin_gateway.default_model,
        .default_agent_step_limit = agent_steps.default_max_agent_steps,
        .gateway_retry_count = builtin_gateway.retry_count,
        .gateway_chat_url = builtin_gateway.default_chat_url,
        .gateway_models_path = builtin_gateway.models_path,
        .gateway_provider = builtin_gateway.provider,
        .provider_set = builtin_providers.native,
        .process_provider = shell_process_provider.provider,
        .secret_store = native_host.secret_store,
        .prompt_policy = builtin_context.prompt_policy,
        .ignored_list_entries = &ignored_list_entries,
        .max_list_entries = 100,
        .max_read_file_bytes = 50 * 1024,
        .max_read_file_lines = 400,
        .max_read_file_line_len = 2000,
        .max_command_output_bytes = 64 * 1024,
        .max_tool_result_bytes = tool_result_limits.default_max_tool_result_bytes,
        .max_history_turns = agents.max_history_turns,
        .context_registry = default_context_registry,
        .mode_registry = builtin_modes.registry,
        // An embedding host may not have fx's Io environment installed, so
        // openFromEnv() would see no HOME. Supply it from libc instead.
        .home_override = if (std.c.getenv("HOME")) |home| std.mem.span(home) else null,
    };
}

test "embeddedConfig carries fx's own defaults" {
    const cfg = embeddedConfig();
    try std.testing.expectEqualStrings(builtin_gateway.default_model, cfg.default_model);
    try std.testing.expect(cfg.max_list_entries > 0);
    try std.testing.expect(cfg.ignored_list_entries.len > 0);
}
