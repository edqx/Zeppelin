const std = @import("std");
const zigNetwork = @import("zig-network");
const Socket = zigNetwork.Socket;
const EndPoint = zigNetwork.EndPoint;
const ConnectionManager = @import("./ConnectionManager.zig");
const rootPackets = @import("./rootPackets.zig");
const BufferPool = @import("./BufferPool.zig");

const Zeppelin = @This();
socket: Socket,
connections: ConnectionManager,

bufferPool: BufferPool,

pub fn init(allocator: std.mem.Allocator) !Zeppelin {
    return Zeppelin{
        .socket = try Socket.create(.ipv4, .udp),
        .connections = ConnectionManager.init(allocator),
        .bufferPool = BufferPool.init(allocator, std.heap.ArenaAllocator.init(allocator))
    };
}

pub fn deinit(self: *Zeppelin) void {
    self.socket.close();
    self.connections.deinit();
}

pub fn bind(self: *Zeppelin) !void {
    try self.socket.bind(try EndPoint.parse("0.0.0.0:22023"));
}

pub fn doHealthCheck(self: *Zeppelin) !void {
    self.connections.connectionsMutex.lock();
    defer self.connections.connectionsMutex.unlock();

    var iterateConnections = self.connections.connections.valueIterator();
    while (iterateConnections.next()) |connectionPtr| {
        const connection = connectionPtr.*;
        std.log.info("[Pinger] Pinging {}..", .{ connection.endpoint });
        try self.sendPing(connection);
    }
}

pub fn startPinger(self: *Zeppelin, stopSignal: *bool) !void {
    const pingerInterval = 1000 * 1000 * 1000 * 1.5; // 1.5 seconds

    std.log.info("[Pinger] Started regular interval pinger", .{ });
    while (true) {
        if (stopSignal.*) break;
        try self.doHealthCheck();
        std.time.sleep(pingerInterval);
    }
}

pub fn sendPing(self: *Zeppelin, connection: *ConnectionManager.Connection) !void {
    const buffer = try self.bufferPool.take(3);
    var stream = std.io.fixedBufferStream(buffer.bytes);
    const writer = stream.writer().any();

    try writer.writeByte(@intFromEnum(rootPackets.Opcode.ping));
    const nonce = connection.takeNonce();
    try writer.writeInt(u16, nonce, .big);

    connection.reliableMessagesBuffer.appendMessage(.{
        .opcode = .ping,
        .nonce = nonce,
        .buffer = buffer,
        .length = stream.pos,
        .sentAt = @intCast(std.time.microTimestamp()),
        .acknowledged = false
    });

    _ = try self.socket.sendTo(connection.endpoint, buffer.bytes[0..stream.pos]);
}

pub fn sendAcknowledge(self: *Zeppelin, connection: *ConnectionManager.Connection, nonce: u16) !void {
    const buffer = try self.bufferPool.take(3);
    var stream = std.io.fixedBufferStream(buffer.bytes);
    const writer = stream.writer().any();

    try writer.writeByte(@intFromEnum(rootPackets.Opcode.acknowledge));
    try writer.writeInt(u16, nonce, .big);
    try writer.writeByte(0xff);

    _ = try self.socket.sendTo(connection.endpoint, buffer.bytes[0..stream.pos]);
}

pub fn listen(self: *Zeppelin) !void {
    var stopPingerSignal = false;
    const pingerThread = try std.Thread.spawn(.{ }, startPinger, .{ self, &stopPingerSignal });

    var messageBuffer = [_]u8{ 0 } ** (1024 * 8); // 8kb
    while (true) {
        const recv = try self.socket.receiveFrom(&messageBuffer);
        var stream = std.io.fixedBufferStream(messageBuffer[0..recv.numberOfBytes]);
        var reader = stream.reader().any();

        const maybeExistingConnection = self.connections.getExistingConnection(recv.sender);

        const opcode: rootPackets.Opcode = try reader.readEnum(rootPackets.Opcode, .little);
        switch (opcode) {
            .unreliable => {

            },
            .reliable => {
                const connection = maybeExistingConnection orelse continue;
                const nonce = try reader.readInt(u16, .big);
                try self.sendAcknowledge(connection, nonce);
            },
            .hello => {
                if (maybeExistingConnection) |existingConnection| {
                    std.log.warn("[Zeppelin] Got double handshake from {}", .{ existingConnection.endpoint });
                    return;
                }
                const connection = try self.connections.acceptConnection(recv.sender);
                const nonce = try reader.readInt(u16, .big);
                const hello = try rootPackets.HelloPacket.read(connection.arena.allocator(), &reader);
                errdefer hello.destroy();

                try self.sendAcknowledge(connection, nonce);
            },
            .disconnect => {

            },
            .acknowledge => {
                const connection = maybeExistingConnection orelse continue;
                const nonce = try reader.readInt(u16, .big);
                try connection.reliableMessagesBuffer.markAcknowledged(nonce);
            },
            .ping => {
                const connection = maybeExistingConnection orelse continue;
                const nonce = try reader.readInt(u16, .big);
                try self.sendAcknowledge(connection, nonce);
            }
        }
        std.log.info("Opcode: {}", .{ opcode });
    }

    stopPingerSignal = true;
    pingerThread.join();
}