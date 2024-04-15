const std = @import("std");
const Zeppelin = @import("./Zeppelin.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var server = try Zeppelin.init(gpa.allocator());
    try server.bind();
    try server.listen();
    _ = gpa.deinit();
}
