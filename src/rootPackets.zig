const std = @import("std");
const streamHelpers = @import("./streamHelpers.zig");

pub const Opcode = enum(u8) {
    unreliable,
    reliable,
    hello = 0x08,
    disconnect,
    acknowledge,
    ping = 0x0c
};

pub const SupportedLangs = enum(u32) {
    english,
    latinAmerican,
    brazillian,
    portuguese,
    korean,
    russian,
    dutch,
    filipino,
    french,
    german,
    italian,
    japanese,
    spanish,
    simplifiedChinese,
    traditionalChinese,
    irish
};

pub const ChatMode = enum(u8) {
    freeChatOrQuickChat = 1,
    quickChatOnly
};

pub const Platform = enum(u8) {
    unknown,
    standaloneEpicPC,
    standaloneSteamPC,
    standaloneMac,
    standaloneWin10,
    standaloneItch,
    iPhone,
    android,
    nintendoSwitch,
    xbox,
    playstation
};

pub const PlatformData = struct {
    allocator: std.mem.Allocator,

    platform: Platform,
    platformName: []const u8,
    platformId: ?u64,

    pub fn initFromReader(allocator: std.mem.Allocator, reader: *std.io.AnyReader) !PlatformData {
        var platformData: PlatformData = undefined;
        platformData.allocator = allocator;

        var message = try streamHelpers.Message.read(allocator, reader);
        defer message.destroy();
        var subReader = message.reader();

        platformData.platform = @enumFromInt(message.tag);
        platformData.platformName = try streamHelpers.readString(allocator, &subReader);
        platformData.platformId = switch (platformData.platform) {
            .playstation, .xbox => try subReader.readInt(u64, .little),
            else => null
        };

        return platformData;
    }

    pub fn destroy(self: PlatformData) void {
        self.allocator.free(self.platformName);
    }
};

pub const ReliablePacket = struct {
    allocator: std.mem.Allocator,
    messages: []streamHelpers.Message,

    pub fn initFromReader(allocator: std.mem.Allocator, reader: *std.io.AnyReader) !ReliablePacket {
        var packet: ReliablePacket = undefined;
        packet.allocator = allocator;

        var list = std.ArrayList(streamHelpers.Message).init(allocator);
        defer list.deinit();

        while (true) {
            const message = streamHelpers.Message.read(allocator, reader) catch |e| {
                if (e == error.EndOfStream) break;
                return e;
            };
            try list.append(message);
        }

        packet.messages = try list.toOwnedSlice();
        return packet;
    }

    pub fn deinit(self: ReliablePacket) void {
        for (self.messages) |message| {
            message.destroy();
        }
        self.allocator.free(self.messages);
    }
};

pub const HelloPacket = struct {
    allocator: std.mem.Allocator,
    broadcastVersion: i32,
    customizationName: []const u8,
    authNonce: u32,
    currentLanguage: SupportedLangs,
    chatMode: ChatMode,
    platformData: PlatformData,
    friendCode: []const u8,

    pub fn initFromReader(allocator: std.mem.Allocator, reader: *std.io.AnyReader) !HelloPacket {
        var packet: HelloPacket = undefined;
        packet.allocator = allocator;

        _ = try reader.readByte(); // hazel version (hard-coded to 1)

        packet.broadcastVersion = try reader.readInt(i32, .little);

        packet.customizationName = try streamHelpers.readString(allocator, reader);
        errdefer allocator.free(packet.customizationName);

        packet.authNonce = try reader.readInt(u32, .little);
        packet.currentLanguage = try reader.readEnum(SupportedLangs, .little);
        packet.chatMode = try reader.readEnum(ChatMode, .little);

        packet.platformData = try PlatformData.initFromReader(allocator, reader);
        errdefer packet.platformData.destroy();

        packet.friendCode = try streamHelpers.readString(allocator, reader);
        errdefer allocator.free(packet.friendCode);

        return packet;
    }

    pub fn destroy(self: HelloPacket) void {
        self.allocator.free(self.customizationName);
        self.allocator.free(self.friendCode);
        self.platformData.destroy();
    }
};