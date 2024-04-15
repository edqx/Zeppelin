const std = @import("std");
const zigNetwork = @import("zig-network");
const Socket = zigNetwork.Socket;
const EndPoint = zigNetwork.EndPoint;
const ConnectionManager = @import("./ConnectionManager.zig");
const rootPackets = @import("./rootPackets.zig");

const Zeppelin = @This();

socket: Socket,

connections: ConnectionManager,

pub fn init(allocator: std.mem.Allocator) !Zeppelin {
    return Zeppelin{
        .socket = try Socket.create(.ipv4, .udp),
        .connections = ConnectionManager.init(allocator)
    };
}

pub fn deinit(self: *Zeppelin) void {
    self.socket.close();
    self.connections.deinit();
}

pub fn bind(self: *Zeppelin) !void {
    try self.socket.bind(try EndPoint.parse("0.0.0.0:22023"));
}

pub fn listen(self: *Zeppelin) !void {
    var messageBuffer = [_]u8{ 0 } ** (1024 * 8); // 8kb
    while (true) {
        const recv = try self.socket.receiveFrom(&messageBuffer);
        var stream = std.io.fixedBufferStream(messageBuffer[0..recv.numberOfBytes]);
        var reader = stream.reader().any();
        
        const connection = try self.connections.acceptConnection(recv.sender);

        const opcode: rootPackets.Opcode = try reader.readEnum(rootPackets.Opcode, .little);
        switch (opcode) {
            .unreliable => {

            },
            .reliable => {

            },
            .hello => {
                const nonce = try reader.readInt(u16, .big);
                const hello = try rootPackets.HelloPacket.read(connection.arena.allocator(), &reader);
                errdefer hello.destroy(connection.arena.allocator());

                std.log.info("hello packet: {}", .{ hello });
                _ = nonce;
            },
            .disconnect => {

            },
            .acknowledge => {

            },
            .ping => {

            }
        }
        std.log.info("opcode: {}", .{ opcode });
    }
}