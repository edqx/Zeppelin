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
    maybeAllocator: ?std.mem.Allocator = null,

    platform: Platform,
    platformName: []const u8,
    platformId: ?u64,

    pub fn initFromReader(allocator: std.mem.Allocator, reader: *std.io.AnyReader) !PlatformData {
        var platformData: PlatformData = undefined;
        platformData.maybeAllocator = allocator;

        var message = try streamHelpers.Message.initFromReader(allocator, reader);
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
        const allocator = self.maybeAllocator orelse return;

        allocator.free(self.platformName);
    }
};

pub const DisconnectReason = enum(u8) {
    exitGame,
	gameFull,
	gameStarted,
	gameNotFound,
	incorrectVersion = 5,
	banned,
	kicked,
	custom,
	invalidName,
	hacking,
	notAuthorized,
	destroy = 16,
	unknownError,
	incorrectGame,
	serverRequest,
	serverFull,
	internalPlayerMissing = 100,
	internalNonceFailure,
	internalConnectionToken,
	platformLock,
	lobbyInactivity,
	matchmakerInactivity,
	invalidGameOptions,
	noServersAvailable,
	quickmatchDisabled,
	tooManyGames,
	quickchatLock,
	matchmakerFull,
	sanctions,
	serverError,
	selfPlatformLock,
	intentionalLeaving = 208,
	focusLostBackground = 207,
	focusLost = 209,
	newConnection,
	platformParentalControlsBlock,
	platformUserBlock
};

pub const ReliablePacket = struct {
    maybeAllocator: ?std.mem.Allocator = null,

    messages: []streamHelpers.Message,

    pub fn initFromReader(allocator: std.mem.Allocator, reader: *std.io.AnyReader) !ReliablePacket {
        var packet: ReliablePacket = undefined;
        packet.maybeAllocator = allocator;

        var list = std.ArrayList(streamHelpers.Message).init(allocator);
        defer list.deinit();

        while (true) {
            const message = streamHelpers.Message.initFromReader(allocator, reader) catch |e| {
                if (e == error.EndOfStream) break;
                return e;
            };
            try list.append(message);
        }

        packet.messages = try list.toOwnedSlice();
        return packet;
    }

    pub fn deinit(self: ReliablePacket) void {
        const allocator = self.maybeAllocator orelse return;

        for (self.messages) |message| {
            message.destroy();
        }
        allocator.free(self.messages);
    }
};

pub const HelloPacket = struct {
    maybeAllocator: ?std.mem.Allocator = null,

    broadcastVersion: i32,
    customizationName: []const u8,
    authNonce: u32,
    currentLanguage: SupportedLangs,
    chatMode: ChatMode,
    platformData: PlatformData,
    friendCode: []const u8,

    pub fn initFromReader(allocator: std.mem.Allocator, reader: *std.io.AnyReader) !HelloPacket {
        var packet: HelloPacket = undefined;
        packet.maybeAllocator = allocator;

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
        const allocator = self.maybeAllocator orelse return;

        allocator.free(self.customizationName);
        allocator.free(self.friendCode);
        self.platformData.destroy();
    }
};

pub const DisconnectPacket = struct {
    maybeAllocator: ?std.mem.Allocator = null,

    showReason: bool,
    reason: DisconnectReason,
    maybeCustomMessage: ?[]const u8,

    pub fn initFromReader(allocator: std.mem.Allocator, reader: *std.io.AnyReader) !DisconnectPacket {
        var packet: DisconnectPacket = undefined;
        packet.maybeAllocator = allocator;

        packet.showReason = (reader.readByte() catch |e| blk: {
            if (e == error.EndOfStream) break :blk 0;
            return e;
        }) == 1;

        const message = try streamHelpers.Message.initFromReader(allocator, reader);
        var reader2 = message.reader();
        packet.reason = @enumFromInt(message.tag);

        packet.maybeCustomMessage = switch (packet.reason) {
            .custom => try streamHelpers.readString(allocator, &reader2),
            else => null
        };

        return packet;
    }

    pub fn destroy(self: DisconnectPacket) void {
        const allocator = self.maybeAllocator orelse return;
        if (self.maybeCustomMessage) |customMessage| allocator.free(customMessage);
    }
};