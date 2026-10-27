# Steam Lobbies + Server Browser — spec (WIP)

> Specced 2026-10-26. Delete this file once it ships and its "how it works" is folded into
> [LobbyGameFlowMP](./LobbyGameFlowMP.md) and [Architecture](./Architecture.md).

- [Spec (decided)](#spec-decided)
- [What exists today](#what-exists-today)
- [Plan](#plan)
- [Open questions](#open-questions)

## Spec (decided)

- **Steam builds only.** The Server Browser button and every new lobby control are hidden unless
  `steam_manager.is_logged_in()`. Web and no-Steam builds are unchanged.
- **Max 8 players, fixed.** No max-player setting. `SteamManager.LOBBY_MAX_MEMBERS` stays at 8,
  with a comment that raising it means adding a spawn point for every player.
- **Visibility:** public (listed in the browser) or friends-only (today's behaviour).
- **Kick:** the host can kick from the player list. No bans, so a kicked player can rejoin.
- **Joinable only in the lobby menu and free roam.** Locked during races and events, meaning any mode
  whose `is_late_joinable()` is false.
- **Server Browser** is a new menu state, reached from a new "Server Browser" button in the play menu.
- **Hosting** stays in the existing lobby menu, which gets the new controls.

## What exists today

- `SteamManager`: create/join/leave lobbies, invites, cold launch via `+connect_lobby`, and the game code
  stored as lobby data (`LOBBY_GAME_ID_KEY`). Lobbies are always `LOBBY_TYPE_FRIENDS_ONLY` with 8 members.
- `MultiplayerSteam`: the `SteamMultiplayerPeer` transport. The lobby ID is the game code, and
  joiners join the Steam lobby before connecting to its owner.
- `ConnectionManager.start_server()`: non-Steam hosts (WebRTC/IP) still create a friends-only Steam
  lobby when logged in, only to carry invites.
- Late join: `GamemodeManager._on_client_connection_succeeded` puts a mid-race joiner into free roam.
  Only `FreeRoamGameMode.is_late_joinable()` returns true.
- `LobbyPanel` (the player list and invite button) is shared by the lobby menu and the pause menu.
- Kick isn't implemented yet.
- **The Steam transport (A2) has never been tested with two accounts.** Test it before building on it.

## Plan

1. **`SteamManager`**
   - `host_lobby()` takes a visibility (public `2` / friends-only `1`).
   - Live setters: visibility (`setLobbyType`) and joinable (`setLobbyJoinable`). A non-joinable
     lobby drops out of search results and refuses joins and invites.
   - New lobby data keys: host name, level, mode, and game version (`config/version`).
   - `find_lobbies()`: version filter + worldwide distance filter, then `requestLobbyList()`, then
     await `lobby_match_list`. Returns rows of id, name, members/limit, level and mode.
   - `join_lobby()`: turn the enter-response codes (full, locked) into readable failure reasons.
2. **Joinability:** the host sets joinable = `is_late_joinable()` on every gamemode transition, and
   joinable again on `end_game()` / back to the lobby. Wire it where transitions are already observed.
3. **Kick:** add a host-only kick button on each player list row (not on the host's own row).
   The server sends an RPC to the kicked peer (toast: "Kicked by host"), then calls
   `multiplayer_peer.disconnect_peer(id)`. The client's existing `server_disconnected` →
   `disconnect_client()` → `leave_lobby()` path handles teardown. Works on every transport.
4. **Lobby menu (host):** a visibility picker (Public / Friends only), shown only to the host on the
   Steam transport. It can be changed while the lobby is live.
5. **Server Browser menu state:** Back, Refresh, and a list (lobby name, players x/8, level, mode).
   Join goes through the play menu's existing `_join_game` path with the lobby ID. Needs loading and
   empty states. The play menu's "Server Browser" button is hidden when not logged in.
6. **Localization:** keys for all new labels.
7. **Docs:** fold into LobbyGameFlowMP.md and Architecture.md, then delete this file.

## Open questions

1. **Public lobbies on non-Steam transports?** Recommend: the visibility picker only appears on the
   Steam transport. WebRTC/IP hosts keep their friends-only invite lobby, so the browser only ever
   lists Steam-transport games.
2. **Default visibility** when hosting: friends-only (today) or public?
3. **Lobby name:** automatic ("<host>'s lobby") or a host-editable text field? An editable name is a
   profanity risk once strangers can see it.
4. **Friends' lobbies in the browser?** `requestLobbyList` only returns public lobbies. Add a
   "Friends" section (friends' current lobbies via the Steam friends API), or leave friends to
   invites and the overlay's "Join Game"?
5. **Mid-race lock for non-Steam joins:** the Steam lock only covers Steam lobby joins. WebRTC/IP
   joiners mid-race still land in free roam (today's behaviour). Keep that, or have the server
   reject them?
6. **Kick in the pause menu too?** `LobbyPanel` is shared, so kick shows up there automatically
   unless it's gated. Recommend yes, since the host is usually in-game.
7. **Back from a lobby joined via the browser:** return to the browser or to the play menu?
8. **Version match:** require an exact `config/version` match (v0.0.158 only sees v0.0.158)?
   Recommend yes, since synced state changes between releases.
9. **Strangers:** public lobbies end the "friends-only, skip auth/anti-cheat" assumption. Audit
   `any_peer` RPCs for sender validation before shipping public, or accept the risk for now?
10. **Avatars:** `request_avatar()` notes that non-friends never load, and public lobbies are mostly
    non-friends. Fix it (request user info first) as part of this work, or leave the default icons?
