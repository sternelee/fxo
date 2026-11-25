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

pub fn view(c: *ui.Context, count: usize) void {
    const box = ui.div(c).column().gap(0);
    defer box.end();
    for (lines[0..@min(count, lines.len)]) |line| {
        ui.text(c, line, .{ .size = 10, .line_height = 11, .color = t.gray_600, .mono = true, .family = t.mono_family });
    }
}
