const std = @import("std");

pub fn readPacked(reader: *std.io.AnyReader) !u32 {
    var out: u32 = 0;
    var shift: u3 = 0;
    while (true) : (shift += 7) {  
        const next = try reader.readByte();
        out |= (next & 0b01111111) << shift;
        if ((next & 0b10000000) != 0) out <<= shift else break;
    }
    return out;
}

pub fn readString(allocator: std.mem.Allocator, reader: *std.io.AnyReader) ![]const u8 {
    const strLen = try readPacked(reader);
    const buffer = try allocator.alloc(u8, strLen);
    try reader.readNoEof(buffer);
    return buffer;
}

pub const Message = struct {
    maybeAllocator: ?std.mem.Allocator = null,

    tag: u8,
    stream: std.io.FixedBufferStream([]u8),

    pub fn initFromReader(allocator: std.mem.Allocator, reader2: *std.io.AnyReader) !Message {
        var message: Message = undefined;
        message.maybeAllocator = allocator;

        const length = try reader2.readInt(u16, .little);
        message.tag = try reader2.readByte();
        const buffer = try allocator.alloc(u8, length);
        message.stream = std.io.fixedBufferStream(buffer);
        try reader2.readNoEof(message.stream.buffer);
        return message;
    }

    pub fn write(self: Message, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u16, @intCast(self.stream.buffer.len), .little);
        try writer.writeInt(u8, self.tag, .little);
        _ = try writer.write(self.stream.buffer);
    }

    pub fn destroy(self: Message) void {
        const allocator = self.maybeAllocator orelse return;
        allocator.free(self.stream.buffer);
    }

    pub fn reader(self: *Message) std.io.AnyReader {
        return self.stream.reader().any();
    }
};