const std = @import("std");
const zigNetwork = @import("zig-network");
const EndPoint = zigNetwork.EndPoint;

pub const Connection = struct {
    arena: std.heap.ArenaAllocator,
    endpoint: EndPoint,
    outgoingNonce: u16,

    pub fn init(arena: std.heap.ArenaAllocator, endpoint: EndPoint) Connection {
        return Connection{
            .arena = arena,
            .endpoint = endpoint,
            .outgoingNonce = 1
        };
    }

    pub fn deinit(self: Connection) void {
        self.arena.deinit();
    }

    pub fn takeNonce(self: *Connection) u16 {
        const tmp = self.outgoingNonce;
        self.outgoingNonce += 1;
        return tmp;
    }
};

const ConnectionManager = @This();

allocator: std.mem.Allocator,
pool: std.heap.MemoryPool(Connection),

connections: std.AutoHashMap(EndPoint, *Connection),

pub fn init(allocator: std.mem.Allocator) ConnectionManager {
    return ConnectionManager{
        .allocator = allocator,
        .pool = std.heap.MemoryPool(Connection).init(allocator),
        .connections = std.AutoHashMap(EndPoint, *Connection).init(allocator)
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

pub fn acceptConnection(self: *ConnectionManager, endpoint: EndPoint) !*Connection {
    if (self.connections.get(endpoint)) |existingConnection| return existingConnection;

    const arena = std.heap.ArenaAllocator.init(self.allocator);

    const connection = try self.pool.create();
    connection.* = Connection.init(arena, endpoint);
    try self.connections.put(endpoint, connection);
    
    std.log.info("[ConnectionManager] accepted connection from {}", .{ endpoint });
    return connection;
}

pub fn removeConnection(self: *ConnectionManager, connection: *Connection) !void {
    self.connections.remove(connection.endpoint);
    connection.deinit();
    self.pool.destroy(connection);
}