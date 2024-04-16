const std = @import("std");

const BufferPool = @This();

pub const BufferPoolError = error { InvalidSize };

pub const Buffer = struct {
    pool: *BufferPool,
    bytes: []u8,
    inUse: bool,

    pub fn relinquish(self: *Buffer) void {
        self.pool.relinquish(self);
    }
};

arena: std.heap.ArenaAllocator,
freeBuffers: std.ArrayList(*Buffer),
buffersPool: std.heap.MemoryPool(Buffer),
buffersMutex: std.Thread.Mutex,

pub fn init(allocator: std.mem.Allocator, arena: std.heap.ArenaAllocator) BufferPool {
    return BufferPool{
        .arena = arena,
        .freeBuffers = std.ArrayList(*Buffer).init(allocator),
        .buffersPool = std.heap.MemoryPool(Buffer).init(allocator),
        .buffersMutex = .{}
    };
}

pub fn deinit(self: BufferPool) void {
    self.arena.deinit();
    self.buffersPool.deinit();
    self.freeBuffers.deinit();
}

pub fn getBufferSize(size: usize) !usize {
    return try std.math.ceilPowerOfTwo(usize, size);
}

pub fn create(self: *BufferPool, size: usize) !*Buffer {
    if (size == 0) return BufferPoolError.InvalidSize;

    const buffer = try self.buffersPool.create();
    buffer.* = Buffer{
        .pool = self,
        .bytes = try self.arena.allocator().alloc(u8, try getBufferSize(size)),
        .inUse = false
    };
    return buffer;
}

pub fn take(self: *BufferPool, size: usize) !*Buffer {
    if (size == 0) return BufferPoolError.InvalidSize;

    self.buffersMutex.lock();
    defer self.buffersMutex.unlock();

    const buffer = for (self.freeBuffers.items) |buffer| {
        if (buffer.bytes.len == try getBufferSize(size)) break buffer;
    } else {
        const buffer = try self.create(size);
        buffer.inUse = true;
        return buffer;
    };
    return buffer;
}

pub fn relinquish(self: *BufferPool, buffer: *Buffer) void {
    self.buffersMutex.lock();
    defer self.buffersMutex.unlock();
    buffer.inUse = false;
    self.freeBuffers.append(buffer) catch |e| std.debug.panic("{}", .{ e });
}