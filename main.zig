const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const posix = std.posix;

var tty: fs.File = undefined;
var raw: posix.termios = undefined;
var window_size: posix.winsize = undefined;
var selector: u8 = 0;
var username: std.ArrayList(u8) = undefined;
const greeting = "Hello there";
const prompt = "Username:";

pub fn main() !void {
    tty = try fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
    defer tty.close();

    const original = try posix.tcgetattr(tty.handle);
    raw = original;
    try config_tty();
    defer restore_tty(original) catch {};

    var alloc_type = std.heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(.ok == alloc_type.deinit()); // mem leak detection
    const allocator = alloc_type.allocator();
    username = std.ArrayList(u8).init(allocator);
    defer username.deinit();

    window_size = try get_size();
    // handle window size change
    try posix.sigaction(posix.SIG.WINCH, &posix.Sigaction{
        .handler = .{ .handler = sigwinch_handler },
        .mask = posix.empty_sigset,
        .flags = 0,
    }, null);

    var buffer: [1]u8 = undefined;
    while (true) {
        try render(selector);
        _ = try tty.read(&buffer);

        if (buffer[0] == '\x1B') {
            raw.cc[@intFromEnum(posix.V.TIME)] = 1;
            raw.cc[@intFromEnum(posix.V.MIN)] = 0;
            try posix.tcsetattr(tty.handle, .NOW, raw);

            var escape_buf: [8]u8 = undefined;
            const escape_len = try tty.read(&escape_buf);

            if (escape_len == 0) return;

            raw.cc[@intFromEnum(posix.V.TIME)] = 0;
            raw.cc[@intFromEnum(posix.V.MIN)] = 1;
            try posix.tcsetattr(tty.handle, .NOW, raw);

            if (mem.eql(u8, escape_buf[0..escape_len], "[A") or mem.eql(u8, escape_buf[0..escape_len], "[D")) {
                selector -|= 1;
            } else if (mem.eql(u8, escape_buf[0..escape_len], "[B") or mem.eql(u8, escape_buf[0..escape_len], "[C")) {
                selector = @min(selector + 1, 0);
            }
        } else {
            // fun fact: backspace actually maps to 0x7F in some terminals
            if (buffer[0] == '\x08' or buffer[0] == '\x7f') {
                _ = username.popOrNull();
            } else {
                try username.appendSlice(&buffer);
            }
        }
    }
}

fn config_tty() !void {
    // config terminal
    raw.lflag = @as(posix.tc_lflag_t, .{ .ECHO = false, .ICANON = false, .ISIG = false });
    raw.iflag = @as(posix.tc_iflag_t, .{ .IXON = false, .ICRNL = false });
    raw.oflag = @as(posix.tc_oflag_t, .{ .OPOST = false });
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;
    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    try posix.tcsetattr(tty.handle, .FLUSH, raw);
    try tty.writeAll("\x1B[?25l\x1B[s\x1B[?47h\x1B[?1049h");
}

fn restore_tty(attr: posix.termios) !void {
    // restore terminal
    try posix.tcsetattr(tty.handle, .FLUSH, attr);
    try tty.writeAll("\x1B[?1049l\x1B[?47l\x1B[u\x1B[?25h");
}

fn get_size() !posix.winsize {
    var size = mem.zeroes(posix.winsize);
    const err = posix.system.ioctl(tty.handle, posix.T.IOCGWINSZ, @intFromPtr(&size));
    if (posix.errno(err) != .SUCCESS) {
        return posix.unexpectedErrno(@enumFromInt(err));
    }
    debug.print("get_size: width{} height{}", .{ size.ws_col, size.ws_row });
    return size;
}

fn move_cursor(row: usize, col: usize) !void {
    // indices start from 1
    _ = try tty.writer().print("\x1B[{};{}H", .{ row + 1, col + 1 });
}

fn write_line(text: []const u8, line_num: usize, col_num: usize, selected: bool) !void {
    if (selected) {
        //set color
        try tty.writeAll("\x1B[46m");
    } else {
        //reset color
        try tty.writeAll("\x1B[m\x1B[48;5;236m");
    }
    try move_cursor(line_num, col_num);
    try tty.writeAll(text);
}

fn render(_: u8) !void {
    // background color
    try tty.writeAll("\x1B[48;5;236m\x1B[2J\x1B[m");
    try write_line(greeting, 1, window_size.ws_col / 2 - greeting.len / 2, false);
    try write_line(prompt, window_size.ws_row / 2, window_size.ws_col / 2 - prompt.len * 2, false);
    try write_line("\x1B[100mF1\x1B[48;5;236m - Select Session", window_size.ws_row, 0, false);
    try write_line("\x1B[100mF2\x1B[48;5;236m - Enter Command", window_size.ws_row, 20, false);
    // restore cursor
    try tty.writeAll("\x1B[?25h\x1B[1 q");
    try write_line(username.items, window_size.ws_row / 2, window_size.ws_col / 2, false);
}

// signal handler
fn sigwinch_handler(_: c_int) callconv(.C) void {
    tty.writeAll("\x1B[m\x1B[2J") catch {}; // clear screen
    window_size = get_size() catch unreachable;
    render(selector) catch {};
}
