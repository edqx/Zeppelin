const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const zigNetwork = b.addModule("zig-network", .{
        .root_source_file = .{ .path = "zig-network/network.zig" }
    });

    const exe = b.addExecutable(.{
        .name = "Zeppelin",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zig-network", zigNetwork);
    b.installArtifact(exe);
}
