const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const stream = std.net.Stream;

const host_endian = builtin.cpu.arch.endian();

/// requests
const Request = union(enum) {
    // ======= ipc message defs =========
    create_session: struct { type: []const u8, username: []const u8 },
    post_auth_message_response: struct { type: []const u8, response: []const u8 },
    start_session: struct { type: []const u8, cmd: []const []const u8, env: []const []const u8 },
    cancel_session: struct { type: []const u8 },

    // ======= ipc procedures ========
    fn send(self: Request, allocator: mem.Allocator, socket: stream) !void {
        var msg: []const u8 = &.{};

        switch (self) {
            .create_session => {
                msg = try std.json.stringifyAlloc(allocator, self.create_session, .{});
            },
            .post_auth_message_response => {
                msg = try std.json.stringifyAlloc(allocator, self.post_auth_message_response, .{});
            },
            .start_session => {
                msg = try std.json.stringifyAlloc(allocator, self.start_session, .{});
            },
            .cancel_session => {
                msg = try std.json.stringifyAlloc(allocator, self.cancel_session, .{});
            },
        }
        const writer = socket.writer();
        std.debug.print("salut: message to send {s}", .{msg});
        try writer.writeInt(u32, @intCast(msg.len), host_endian);
        writer.writeAll(msg) catch {
            std.debug.print("writing to the socket failed", .{});
        };
    }
};

/// responses
const Response = union(enum) {
    // ======= ipc message defs =========
    success: struct {},
    @"error": struct { error_type: enum { auth_error, @"error" }, description: []const u8 },
    auth_message: struct { auth_message_type: enum { visible, secret, info, @"error" }, auth_message: []const u8 },

    // ======= ipc procedures ========
    fn recv(allocator: mem.Allocator, socket: stream) !Response {
        const reader = socket.reader();
        const length = try reader.readInt(u32, host_endian);
        const msg = try allocator.alloc(u8, length);
        defer allocator.free(msg);

        std.debug.assert(try reader.readAll(msg) == length); // crash if length != bytes read

        const val = try std.json.parseFromSlice(std.json.Value, allocator, msg, .{});
        defer val.deinit();

        const msg_type = val.value.object.get("type").?;

        std.debug.print("salut: received message type {s}", .{msg_type.string});

        inline for (std.meta.fields(Response)) |field| {
            if (mem.eql(u8, msg_type.string, field.name)) {
                const resp = try std.json.parseFromSliceLeaky(field.type, allocator, msg, .{ .ignore_unknown_fields = true });
                return @unionInit(Response, field.name, resp);
            }
        }

        unreachable; // unknown message type

    }
};

pub fn create_session(allocator: std.mem.Allocator, ipc_socket: std.net.Stream, username: []const u8) !Response {
    const req: Request = .{ .create_session = .{ .type = "create_session", .username = username } };
    try req.send(allocator, ipc_socket);
    return try Response.recv(allocator, ipc_socket);
}

pub fn post_auth_message_response(allocator: std.mem.Allocator, ipc_socket: std.net.Stream) !Response {
    const req: Request = .{ .post_auth_message_response = .{ .type = "post_auth_message_response", .response = "\n" } };
    try req.send(allocator, ipc_socket);
    return try Response.recv(allocator, ipc_socket);
}

pub fn start_session(allocator: std.mem.Allocator, ipc_socket: std.net.Stream, command: []const []const u8, env: []const []const u8) !Response {
    // send start_session req
    const req: Request = .{ .start_session = .{ .type = "start_session", .cmd = command, .env = env } };
    try req.send(allocator, ipc_socket);
    return try Response.recv(allocator, ipc_socket);
}
