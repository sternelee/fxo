//! Text-output parsers for `fx permissions` and `fx doctor`, split out of
//! fxcli.zig to keep both files under the size budget. Pure.
const std = @import("std");
const fxcli = @import("fxcli.zig");
const Info = fxcli.Info;
const Level = fxcli.Level;

pub fn parsePermissions(info: *Info, text: []const u8) void {
    info.rule_count = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, line, "[permissions]")) line = std.mem.trimStart(u8, line["[permissions]".len..], " \t");
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "mode=") != null) continue;
        if (std.mem.indexOf(u8, line, "(none)") != null) continue;
        if (std.mem.startsWith(u8, line, "configured rules") or std.mem.startsWith(u8, line, "session grants")) continue;
        if (info.rule_count >= info.rules.len) break;
        var rule = line;
        if (std.mem.indexOf(u8, line, ": ")) |at| rule = line[at + 2 ..];
        info.rules[info.rule_count].set(rule);
        info.rule_count += 1;
    }
}

/// Parses `fx doctor` text output. Pure.
pub fn parseDoctor(info: *Info, text: []const u8) void {
    info.doctor_ok = 0;
    info.doctor_warn = 0;
    info.doctor_fail = 0;
    info.check_count = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, line, "[doctor] version=")) {
            info.doctor_version.set(line["[doctor] version=".len..]);
            continue;
        }
        const level: Level = if (std.mem.startsWith(u8, line, "[ok]"))
            .ok
        else if (std.mem.startsWith(u8, line, "[warn]"))
            .warn
        else if (std.mem.startsWith(u8, line, "[fail]"))
            .fail
        else
            continue;
        // The prefix length differs per level: [ok] is 4, [warn]/[fail] are 6.
        const prefix: usize = switch (level) {
            .ok => "[ok]".len,
            .warn => "[warn]".len,
            .fail => "[fail]".len,
        };
        switch (level) {
            .ok => info.doctor_ok += 1,
            .warn => info.doctor_warn += 1,
            .fail => info.doctor_fail += 1,
        }
        // Keep the first few checks for the About page's list.
        if (info.check_count < info.checks.len) {
            const body = std.mem.trim(u8, line[prefix..], " \t\r");
            var name: []const u8 = body;
            var detail: []const u8 = "";
            if (std.mem.indexOf(u8, body, ": ")) |at| {
                name = body[0..at];
                detail = body[at + 2 ..];
            }
            var check = &info.checks[info.check_count];
            check.level = level;
            check.name.set(name);
            check.detail.set(detail);
            info.check_count += 1;
        }
    }
}
