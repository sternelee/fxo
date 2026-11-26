//! The fx braille wordmark, one text node per line (nanoui's `text` does not
//! break on `\n` unless wrapping, so each line is its own box).
const ui = @import("nanoui").ui;
const t = @import("tokens.zig");

const lines = [_][]const u8{
    " ⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀",
    " ⠀⠀⠀⠀⠀⢰⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
    " ⠀⠀⠀⣠⣶⣿⣿⣷⣶⡶⣶⣶⣆⠀⠀⠀⣴⣶⣶⠆",
    " ⠀⠀⠀⠉⢹⣿⣿⠉⠉⠀⠘⢿⣿⣧⣀⣾⣿⡿⠃⠀",
    " ⠀⠀⠀⠀⣼⣿⡏⠀⠀⠀⠀⠀⠀⠻⣿⣿⣿⠟⠀⠀⠀",
    " ⠀⠀⠀⢀⣿⣿⠃⠀⠀⠀⠀⢠⣦⠘⢿⣿⣷⡀⠀⠀",
    " ⠀⠀⠀⣸⣿⡟⠀⠀⠀⠀⣰⣿⣿⠗⠀⠻⣿⣿⣄⠀",
    " ⠀⠀⠀⣿⣿⠇⠀⠀⠀⠾⠿⠿⠋⠀⠀⠀⠘⠿⠿⠦",
    "  ⠀⣸⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
    " ⣿⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
};

/// Draws the wordmark. `small` matches fx-ui's fx_mark (6pt / 7pt line,
/// gray_900) used on the About hero; otherwise the home page's larger mark.
pub fn view(c: *ui.Context, count: usize, small: bool) void {
    const box = ui.div(c).column().gap(0);
    defer box.end();
    const size: f32 = if (small) 6 else 10;
    const line_height: f32 = if (small) 7 else 11;
    const color = if (small) t.gray_900 else t.gray_600;
    for (lines[0..@min(count, lines.len)]) |line| {
        ui.text(c, line, .{ .size = size, .line_height = line_height, .color = color, .mono = true, .family = t.mono_family });
    }
}
