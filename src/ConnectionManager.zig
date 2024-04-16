const std = @import("std");
const zigNetwork = @import("zig-network");
const EndPoint = zigNetwork.EndPoint;
const rootPackets = @import("./rootPackets.zig");
const BufferPool = @import("./BufferPool.zig");

pub const SentMessage = struct {
    opcode: rootPackets.Opcode,
    nonce: u16,
    buffer: *BufferPool.Buffer,
    length: usize,
    sentAt: u64,
    acknowledged: bool
};

pub const ReliableMessagesBuffer = struct {
    pub const Size = 8;
    pub const BufferIndex = std.meta.Int(.unsigned, std.math.log2_int_ceil(usize, Size) + 2);

    reliableMessages: [Size]SentMessage,
    cursor: BufferIndex,
    max: BufferIndex,

    pub fn init() ReliableMessagesBuffer {
        return ReliableMessagesBuffer{
            .reliableMessages = undefined,
            .cursor = 0,
            .max = 0
        };
    }

    pub fn isDead(self: ReliableMessagesBuffer, maximumSentAt: u64) bool {
        return inline for (0.., self.reliableMessages) |i, message| {
            if (i >= self.max) return;
            if (message.sentAt <= maximumSentAt and message.acknowledged) break false;
        } else true;
    }

    pub fn markAcknowledged(self: *ReliableMessagesBuffer, nonce: u16) !void {
        inline for (0.., &self.reliableMessages) |i, *message| {
            if (i >= self.max) return;
            if (message.nonce == nonce) {
                message.acknowledged = true;
                try message.buffer.relinquish();
                break;
            }
        }
    }

    pub fn appendMessage(self: *ReliableMessagesBuffer, message: SentMessage) void {
        self.reliableMessages[self.cursor] = message;
        self.cursor = (self.cursor + 1) % Size;
        self.max = @min(Size, self.max + 1);
    }
};

pub const ConnectionInfo = struct {
    id: u32,
    name: []const u8,
    platform: rootPackets.Platform,
    language: rootPackets.SupportedLangs,
    chatMode: rootPackets.ChatMode
};

pub const Connection = struct {
    arena: std.heap.ArenaAllocator,

    endpoint: EndPoint,
    info: ConnectionInfo,

    outgoingNonce: u16,
    reliableMessagesBuffer: ReliableMessagesBuffer,

    pub fn init(arena: std.heap.ArenaAllocator, endpoint: EndPoint, info: ConnectionInfo) Connection {
        return Connection{
            .arena = arena,
            .endpoint = endpoint,
            .info = info,
            .outgoingNonce = 1,
            .reliableMessagesBuffer = ReliableMessagesBuffer.init()
        };
    }

    pub fn deinit(self: Connection) void {
        self.arena.deinit();
    }
    
    pub fn format(value: Connection, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
        _ = fmt; _ = options;
        try writer.print("{s} (id: {}, lang: {}, addr: {})", .{ value.info.name, value.info.id, value.info.language, value.endpoint });
    }

    pub fn takeNonce(self: *Connection) u16 {
        const tmp = self.outgoingNonce;
        self.outgoingNonce = @addWithOverflow(self.outgoingNonce, 1)[0];
        return tmp;
    }
};

const ConnectionManager = @This();

allocator: std.mem.Allocator,
pool: std.heap.MemoryPool(Connection),

connectionId: u32,

connections: std.AutoHashMap(EndPoint, *Connection),
connectionsMutex: std.Thread.Mutex,

pub fn init(allocator: std.mem.Allocator) ConnectionManager {
    return ConnectionManager{
        .allocator = allocator,
        .pool = std.heap.MemoryPool(Connection).init(allocator),
        .connectionId = 1,
        .connections = std.AutoHashMap(EndPoint, *Connection).init(allocator),
        .connectionsMutex = .{}
    };
}

pub fn deinit(self: *ConnectionManager) void {
    var connectionsIterator = self.connections.valueIterator();
    while (connectionsIterator.next()) |connection| {
        connection.*.deinit();
    }
    self.connections.deinit();
    self.pool.deinit();
}

pub fn takeConnectionId(self: *ConnectionManager) u32 {
    const tmp = self.connectionId;
    self.connectionId = @addWithOverflow(self.connectionId, 1)[0];
    return tmp;
}

pub fn acceptConnection(self: *ConnectionManager, arena: std.heap.ArenaAllocator, endpoint: EndPoint, info: ConnectionInfo) !*Connection {
    const connection = try self.pool.create();
    connection.* = Connection.init(arena, endpoint, info);

    self.connectionsMutex.lock();
    defer self.connectionsMutex.unlock();

    try self.connections.put(endpoint, connection);
    
    std.log.info("[ConnectionManager] accepted connection from {}", .{ connection.* });
    return connection;
}

pub fn getExistingConnection(self: *ConnectionManager, endpoint: EndPoint) ?*Connection {
    return self.connections.get(endpoint);
}

pub fn removeConnection(self: *ConnectionManager, connection: *Connection) !void {
    self.connections.remove(connection.endpoint);
    connection.deinit();
    self.pool.destroy(connection);
}