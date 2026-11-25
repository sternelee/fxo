//! Design tokens transcribed from fx-ui-main/src/design/tokens.rs.
//! Dark Geist palette: near-black surfaces, white foreground, subtle alpha borders.
const std = @import("std");
const ui = @import("nanoui").ui;
const Color = ui.Color;

pub const white = Color.white;
pub const background_100 = Color.hex(0x0a0a0a);
pub const background_200 = Color.hex(0x000000);
pub const gray_100 = Color.hex(0x1a1a1a);
pub const gray_200 = Color.hex(0x1f1f1f);
pub const gray_300 = Color.hex(0x292929);
pub const gray_400 = Color.hex(0x2e2e2e);
pub const gray_500 = Color.hex(0x454545);
pub const gray_600 = Color.hex(0x878787);
pub const gray_700 = Color.hex(0x8f8f8f);
pub const gray_900 = Color.hex(0xa1a1a1);
pub const gray_1000 = Color.hex(0xededed);

pub const alpha_100 = Color{ .r = 1, .g = 1, .b = 1, .a = @as(f32, 0x0f) / 255.0 };
pub const alpha_200 = Color{ .r = 1, .g = 1, .b = 1, .a = @as(f32, 0x17) / 255.0 };
pub const alpha_300 = Color{ .r = 1, .g = 1, .b = 1, .a = @as(f32, 0x21) / 255.0 };
pub const alpha_400 = Color{ .r = 1, .g = 1, .b = 1, .a = @as(f32, 0x24) / 255.0 };

pub const amber_700 = from_hsl(39, 100, 57);
pub const red_700 = from_hsl(358, 75, 59);
pub const red_900 = from_hsl(358, 100, 69);
pub const green_900 = from_hsl(131, 43, 57);
pub const blue_700 = from_hsl(212, 100, 48);

pub const column_width: f32 = 720;
pub const sidebar_width: f32 = 248;

pub const mono_family = "Geist Mono";
pub const sans_family = ".SystemUIFont";

fn from_hsl(h_deg: f32, s_pct: f32, l_pct: f32) Color {
    const h = h_deg / 360.0;
    const s = s_pct / 100.0;
    const l = l_pct / 100.0;
    const c = (1.0 - @abs(2.0 * l - 1.0)) * s;
    const x = c * (1.0 - @abs(@mod(h * 6.0, 2.0) - 1.0));
    const m = l - c / 2.0;
    const sector: u8 = @intFromFloat(@floor(h * 6.0));
    const rgb = switch (sector) {
        0 => [3]f32{ c, x, 0 },
        1 => [3]f32{ x, c, 0 },
        2 => [3]f32{ 0, c, x },
        3 => [3]f32{ 0, x, c },
        4 => [3]f32{ x, 0, c },
        else => [3]f32{ c, 0, x },
    };
    return .{ .r = rgb[0] + m, .g = rgb[1] + m, .b = rgb[2] + m };
}

test "tokens match fx-ui values" {
    try std.testing.expectEqual(@as(u8, 0x0a), @as(u8, @intFromFloat(background_100.r * 255.0)));
    try std.testing.expectEqual(@as(u8, 0xed), @as(u8, @intFromFloat(gray_1000.r * 255.0)));
    try std.testing.expectApproxEqAbs(@as(f32, 36), alpha_400.a * 255.0, 0.01);
}
