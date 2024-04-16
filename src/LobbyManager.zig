const std = @import("std");
const Lobby = @import("./Lobby.zig");

const LobbyManager = @This();

allocator: std.mem.Allocator,
pool: std.heap.MemoryPool(Lobby),

prng: std.Random.DefaultPrng,
lobbies: std.AutoHashMap(Lobby.GameCode, *Lobby),

pub fn init(allocator: std.mem.Allocator) LobbyManager {
    return LobbyManager{
        .allocator = allocator,
        .pool = std.heap.MemoryPool(Lobby).init(allocator),
        .prng = std.Random.DefaultPrng.init(0),
        .lobbies = std.AutoHashMap(Lobby.GameCode, *Lobby).init(allocator)
    };
}

pub fn deinit(self: *LobbyManager) void {
    var lobbiesIterator = self.lobbies.valueIterator();
    while (lobbiesIterator.next()) |lobby| {
        lobby.*.destroy();
    }
    self.pool.deinit();
}

pub fn generateUniqueCode(self: *LobbyManager) !Lobby.GameCode {
    var code = try Lobby.GameCode.generateRandom(self.prng.random(), .v2);
    while (self.lobbies.get(code) != null) {
        code = try Lobby.GameCode.generateRandom(self.prng.random(), .v2);
    }
    return code;
}

pub fn openLobby(self: *LobbyManager) !*Lobby {
    const lobby = try self.pool.create();
    lobby.* = Lobby.init(self.allocator);
    lobby.setGameCode(try self.generateUniqueCode());
    std.log.info("[LobbyManager] opened lobby {}", .{ lobby.* });
    try lobby.start();
    return lobby;
}