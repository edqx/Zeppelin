const std = @import("std");
const ConnectionManager = @import("./ConnectionManager.zig");
const MessageRecord = ConnectionManager.MessageRecord;
const Connection = ConnectionManager.Connection;
const streamHelpers = @import("./streamHelpers.zig");

pub const SocketInterface = struct {
    context: *anyopaque,
    vtable: struct {
        sendMessage: *const fn (context: *anyopaque, connection: *Connection, message: MessageRecord) void
    },

    pub fn sendMessage(self: SocketInterface, connection: *Connection, message: MessageRecord) void {
        self.vtable.sendMessage(self.context, connection, message);
    }
};

pub const GameCode = struct {
    pub const GameModeError = error { InvalidLength };
    pub const v2CharMap = "QWXRTYLPESDFGHUJKZOCVBINMA";
    pub const v2IntMap = [_]u8{ 25, 21, 19, 10, 8, 11, 12, 13, 22, 15, 16, 6, 24, 23, 18, 7, 0, 3, 9, 4, 14, 20, 1, 2, 5, 17 };

    pub const Kind = enum { v1, v2 };

    id: i32,

    pub inline fn nil(comptime kind: Kind) GameCode {
        return switch (kind) {
            inline .v1 => fromString("AAAA") catch unreachable,
            inline .v2 => fromString("AAAAAA") catch unreachable
        };
    }

    pub inline fn kindFromLen(len: usize) !Kind {
        return switch (len) {
            4 => Kind.v1,
            6 => Kind.v2,
            else => GameModeError.InvalidLength
        };
    }

    pub inline fn lenFromKind(kind: Kind) usize {
        return switch (kind) {
            .v1 => 4,
            .v2 => 6
        };
    }
    
    pub fn fromString(str: []const u8) !GameCode {
        return switch (try kindFromLen(str.len)) {
            .v1 => GameCode{ .id = @as(*const i32, @alignCast(@ptrCast(str.ptr))).* },
            .v2 => blk: {
                const a: u32 = v2IntMap[@intCast(str[0] - 65)];
                const b: u32 = v2IntMap[@intCast(str[1] - 65)];
                const c: u32 = v2IntMap[@intCast(str[2] - 65)];
                const d: u32 = v2IntMap[@intCast(str[3] - 65)];
                const e: u32 = v2IntMap[@intCast(str[4] - 65)];
                const f: u32 = v2IntMap[@intCast(str[5] - 65)];
                const one = (a + 26 * b) & 0x3ff;
                const two = c + 26 * (d + 26 * (e + 26 * f));

                const id = one | ((two << 10) & 0x3ffffc00) | 0x80000000;

                break :blk GameCode{
                    .id = @bitCast(id)
                };
            }
        };
    }

    pub fn getKind(self: GameCode) Kind {
        return if (self.id < 0) return Kind.v2 else Kind.v1;
    }

    pub fn format(value: GameCode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
        _ = fmt; _ = options;
        switch (value.getKind()) {
            .v1 => {
                const asBytes = [_]u8{
                    @intCast(value.id & 0xff),
                    @intCast((value.id >> 8) & 0xff),
                    @intCast((value.id >> 16) & 0xff),
                    @intCast((value.id >> 24) & 0xff)
                };
                try writer.print("{s}", .{ &asBytes });
            },
            .v2 => {
                const a = value.id & 0x3ff;
                const b = (value.id >> 10) & 0xfffff;

                const asBytes = [_]u8{
                    v2CharMap[@intCast(@mod(a, 26))],
                    v2CharMap[@intCast(@divFloor(a, 26))],
                    v2CharMap[@intCast(@mod(b, 26))],
                    v2CharMap[@intCast(@mod(@divFloor(b, 26), 26))],
                    v2CharMap[@intCast(@mod(@divFloor(b, 26 * 26), 26))],
                    v2CharMap[@intCast(@mod(@divFloor(b, 26 * 26 * 26), 26))]
                };

                try writer.print("{s}", .{ &asBytes });
            }
        }
    }

    pub fn generateRandom(random: std.Random, comptime kind: Kind) !GameCode {
        var str: [lenFromKind(kind)]u8 = undefined;
        inline for (0..str.len) |i| str[i] = random.intRangeLessThan(u8, 65, 91);
        return fromString(&str);
    }
};

pub const Player = struct {
    connection: *Connection,
};

const Lobby = @This();

const MAX_PLAYERS = 256;

pub const LobbyState = enum {
    Destroyed,
    NotStarted,
    Started,
    Ended
};

allocator: std.mem.Allocator,
gameCode: GameCode,
maybeWorkerThread: ?std.Thread,

state: LobbyState,

gameDataMutex: std.Thread.Mutex,
gameDataMessageQueue: std.ArrayList(streamHelpers.Message),

players: [MAX_PLAYERS]?*Connection,

pub fn init(allocator: std.mem.Allocator) Lobby {
    return Lobby{
        .allocator = allocator,
        .gameCode = GameCode.nil(.v2),
        .maybeWorkerThread = null,
        .state = LobbyState.Destroyed,
        .gameDataMutex = std.Thread.Mutex{},
        .gameDataMessageQueue = std.ArrayList(streamHelpers.Message).init(allocator),
        .players = [_]?*Connection{ null } ** MAX_PLAYERS
    };
}

pub fn destroy(self: *Lobby) void {
    self.state = .Destroyed;
    if (self.maybeWorkerThread) |workerThread| {
        workerThread.join();
    }
    self.gameDataMessageQueue.deinit();
}

pub fn format(value: Lobby, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
    _ = fmt; _ = options;
    try writer.print("{}", .{ value.gameCode });
}

pub fn setGameCode(self: *Lobby, gameCode: GameCode) void {
    self.gameCode = gameCode;
}

pub fn start(self: *Lobby) !void {
    self.maybeWorkerThread = try std.Thread.spawn(.{ }, fixedUpdate, .{ self });
}

pub fn fixedUpdate(self: *Lobby) void {
    const fixedUpdateInterval = 1000 * 1000 * 20; // 20ms

    while (true) {
        if (self.state == .Destroyed) break;

        self.gameDataMutex.lock();
        for (self.gameDataMessageQueue.items) |gameDataMessage| {
            _ = gameDataMessage;
        }
        self.gameDataMutex.unlock();

        std.time.sleep(fixedUpdateInterval);
    }
}