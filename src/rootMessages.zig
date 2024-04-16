pub const RootMessageTag = enum(u8) {
    hostGame,
    joinGame,
    startGame,
    removeGame,
    removePlayer,
    gameData,
    gameDataTo,
    joinedGame,
    endGame,
    getGameList,
    alterGame,
    kickPlayer,
    waitForHost,
    redirect,
    masterServerList,
    getGameListV2 = 16,
    reportPlayer,
    setGameSession = 20, // unimplemented in-game
    setActivePodType,
    queryPlatformIds,
    queryLobbyInfo, // unimplemented in-game
};

pub const HostGameMessage = struct {
    
};