const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const posix = std.posix;
const stream = std.net.Stream;

const greeting = "Hello there";
const prompt = "Username:";

pub fn main() !void {
    var tty = try fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
    defer tty.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(.ok == gpa.deinit()); // mem leak detection
    const allocator = gpa.allocator();

    var username = std.ArrayList(u8).init(allocator);
    defer username.deinit();

    var win_size: posix.winsize = undefined;
    const original = try posix.tcgetattr(tty.handle);
    var raw = original;
    try config_tty(tty, &raw, &win_size);
    defer restore_tty(tty, original) catch {};

    // const ipc_socket = try std.net.connectUnixSocket(std.posix.getenv("GREETD_SOCK").?);

    var buffer: [1]u8 = undefined;
    while (true) {
        try render(tty, username, win_size);
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
            try posix.tcsetattr(tty.handle, .NOW, original);
        } else {
            // fun fact: backspace actually maps to 0x7F in some terminals
            if (buffer[0] == '\x08' or buffer[0] == '\x7f') {
                _ = username.popOrNull();
            } else if (buffer[0] == '\r') {
                // try create_session(ipc_socket, username.items);
            } else {
                try username.appendSlice(&buffer);
            }
        }
    }
}

fn config_tty(tty: fs.File, raw: *posix.termios, win_size: *posix.winsize) !void {
    // config terminal
    raw.lflag = @as(posix.tc_lflag_t, .{ .ECHO = false, .ICANON = false, .ISIG = false });
    raw.iflag = @as(posix.tc_iflag_t, .{ .IXON = false, .ICRNL = false });
    raw.oflag = @as(posix.tc_oflag_t, .{ .OPOST = false });
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;
    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    try posix.tcsetattr(tty.handle, .FLUSH, raw.*);
    try tty.writeAll("\x1B[?25l\x1B[s\x1B[?47h\x1B[?1049h");

    win_size.* = try get_size(tty);
    // handle window size change
    try posix.sigaction(posix.SIG.WINCH, &posix.Sigaction{
        .handler = .{ .handler = sigwinch_handler },
        .mask = posix.empty_sigset,
        .flags = 0,
    }, null);
}

fn restore_tty(tty: fs.File, attr: posix.termios) !void {
    // restore terminal
    try posix.tcsetattr(tty.handle, .FLUSH, attr);
    try tty.writeAll("\x1B[?1049l\x1B[?47l\x1B[u\x1B[?25h");
}

fn get_size(tty: fs.File) !posix.winsize {
    var size = mem.zeroes(posix.winsize);
    const err = posix.system.ioctl(tty.handle, posix.T.IOCGWINSZ, @intFromPtr(&size));
    if (posix.errno(err) != .SUCCESS) {
        return posix.unexpectedErrno(@enumFromInt(err));
    }
    debug.print("get_size: width{} height{}", .{ size.ws_col, size.ws_row });
    return size;
}

fn move_cursor(tty: fs.File, row: usize, col: usize) !void {
    // line index starts from 1
    _ = try tty.writer().print("\x1B[{};{}H", .{ row + 1, col + 1 });
}

fn write_line(tty: fs.File, text: []const u8, line_num: usize, col_num: usize, selected: bool) !void {
    if (selected) {
        try tty.writeAll("\x1B[46m"); //set color
    } else {
        try tty.writeAll("\x1B[m\x1B[48;5;236m"); //reset color
    }
    try move_cursor(tty, line_num, col_num);
    try tty.writeAll(text);
}

fn render(tty: fs.File, username: std.ArrayList(u8), window_size: posix.winsize) !void {
    try tty.writeAll("\x1B[48;5;236m\x1B[2J\x1B[m"); // set background color
    try write_line(tty, greeting, 1, window_size.ws_col / 2 - greeting.len / 2, false);
    try write_line(tty, prompt, window_size.ws_row / 2, window_size.ws_col / 2 - prompt.len * 2, false);
    try write_line(tty, "\x1B[100mF1\x1B[48;5;236m - Select Session", window_size.ws_row, 0, false);
    try write_line(tty, "\x1B[100mF2\x1B[48;5;236m - Enter Command", window_size.ws_row, 20, false);
    try tty.writeAll("\x1B[?25h\x1B[1 q"); // restore cursor
    try write_line(tty, username.items, window_size.ws_row / 2, window_size.ws_col / 2, false);
}

// signal handler for WINCH
fn sigwinch_handler(_: c_int) callconv(.C) void {
    // tty.writeAll("\x1B[m\x1B[2J") catch unreachable; // clear screen
    // window_size = get_size(tty) catch unreachable;
    // render(tty, get_size(tty)) catch unreachable;
    // to handle window size change in a signal handler we will have to reintroduce global variables
    // well.. this doesn't make sense for a greeter anyway, just crash instead
    unreachable;
}
