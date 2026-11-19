# Bug Fix: IPC trust drops when the support folder is moved

- **Slug**: ipc-socket-trust
- **Fixed**: 2026-11-19
- **Status**: applied

## Summary

Release builds ignore `ZEUS_SUPPORT_DIR` and keep the program-name policy. The socket directory is 0700, owned by this user, and the umask is 077 across bind. `zeus-hook` asks for a signed server. A requirement that pins an identifier is checked with strict validation. F4 and F5 were left as design notes.

## Tests

- `PeerCredentialsTests.aRelocatedSupportFolderIsTheOnlyWayToDropTheProgramNameRule`
- `PeerCredentialsTests.theHookTrustsOnlyTheSameUserAndASignedServer`
