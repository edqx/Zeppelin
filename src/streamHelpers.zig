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

pub const StreamError = error { InvalidLength };

pub fn readString(allocator: std.mem.Allocator, reader: *std.io.AnyReader) ![]const u8 {
    const strLen = try readPacked(reader);
    const buffer = try allocator.alloc(u8, strLen);
    const bytesRead = try reader.read(buffer);
    if (bytesRead != strLen) return StreamError.InvalidLength;
    return buffer;
}

pub const Message = struct {
    allocator: std.mem.Allocator,

    tag: u8,
    length: u16,
    buffer: []u8,

    stream: std.io.FixedBufferStream([]u8),

    pub fn read(allocator: std.mem.Allocator, reader2: *std.io.AnyReader) !Message {
        var message: Message = undefined;
        message.allocator = allocator;

        message.length = try reader2.readInt(u16, .little);
        message.tag = try reader2.readByte();
        message.buffer = try allocator.alloc(u8, message.length);
        message.stream = std.io.fixedBufferStream(message.buffer);
        const bytesRead = try reader2.read(message.buffer);
        if (bytesRead != message.length) return StreamError.InvalidLength;
        return message;
    }

    pub fn destroy(self: Message) void {
        self.allocator.free(self.buffer);
    }

    pub fn reader(self: *Message) std.io.AnyReader {
        return self.stream.reader().any();
    }
};