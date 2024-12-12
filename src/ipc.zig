const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const posix = std.posix;
const stream = std.net.Stream;

// ======= ipc message defs =========
// requests
const Request = enum { CreateSession, PostAuthMessageResponse, StartSession, CancelSession };

const CreateSession = struct { type: []const u8, username: []const u8 };
const PostAuthMessageResponse = struct { type: []const u8, response: []const u8 };
const StartSession = struct { type: []const u8, cmd: [][]const u8, env: [][]const u8 };
const CancelSession = struct { type: []const u8 };

// response
const Response = enum { Success, Error, AuthMessage };

// we don't bother to implement error/auth_message enums for now
const Success = struct { type: []const u8 };
const Error = struct { type: []const u8, error_type: []const u8, description: []const u8 };
const AuthMessage = struct { type: []const u8, auth_message_type: []const u8, auth_message: []const u8 };


// ======= ipc procedures ========
fn create_session(socket: stream, user: []const u8, allocator: ) !void {
    const csession = CreateSession{
        .type = "create_session",
        .username = user,
    };
    const msg = std.ArrayList(u8).init(allocator);
    // try std.json.stringify(csession, .{}, msg.writer());
    // todo: add u32 length
    _ = .{ csession, msg, socket };
    // socket.writeAll(msg);
}
