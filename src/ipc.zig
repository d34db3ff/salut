const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const stream = std.net.Stream;

const host_endian = builtin.cpu.arch.endian();

/// requests
pub const Request = union(enum) {
    // ======= ipc message defs =========
    CreateSession: struct { type: []const u8, username: []const u8 },
    PostAuthMessageResponse: struct { type: []const u8, response: []const u8 },
    StartSession: struct { type: []const u8, cmd: []const []const u8, env: []const []const u8 },
    CancelSession: struct { type: []const u8 },

    // ======= ipc procedures ========
    pub fn send(self: Request, allocator: mem.Allocator, socket: stream) !void {
        const writer = socket.writer();
        const msg = try std.json.stringifyAlloc(allocator, self, .{});
        try writer.writeInt(u32, @intCast(msg.len), host_endian);
        writer.writeAll(msg) catch {
            std.debug.print("writing to the socket failed", .{});
        };
    }
};

/// responses
pub const Response = union(enum) {
    // ======= ipc message defs =========
    Success: struct {},
    Error: struct { error_type: enum { auth_error, @"error" }, description: []const u8 },
    AuthMessage: struct { auth_message_type: enum { visible, secret, info, @"error" }, auth_message: []const u8 },

    // ======= ipc procedures ========
    pub fn recv(allocator: mem.Allocator, socket: stream) !Response {
        const reader = socket.reader();
        const length = reader.readInt(u32, host_endian);

        const msg = try allocator.alloc(u8, length);
        defer allocator.free(msg);

        std.debug.assert(reader.readAll(msg).? == length); // crash if length != bytes read

        const val = try std.json.parseFromSlice(std.json.Value, allocator, msg, .{});
        defer val.deinit();

        const msg_type = val.value.object.get("type");

        for (std.meta.fields(Response)) |field| {
            if (mem.eql(u8, msg_type, field.name)) {
                return std.json.parseFromSlice(field.type, msg, .{});
            }
        }

        unreachable; // unknown message type

    }
};
