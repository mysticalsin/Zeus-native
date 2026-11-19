# Bug Assessment: IPC trust drops when the support folder is moved

- **Slug**: ipc-socket-trust
- **Created**: 2026-11-19
- **Source**: pasted text (Sentinel IPC pass, accept with residuals)
- **Verdict**: valid
- **Severity**: low

## Symptom

A release process that has `ZEUS_SUPPORT_DIR` set drops the program-name check. The socket directory is not created at 0700 and checked before bind. `zeus-hook` trusts a reply without checking the server's uid or signature. A pinned identifier is not checked with strict validation.

## Proposed Remediation

Release builds ignore `ZEUS_SUPPORT_DIR` and keep the executable policy. The socket directory is created at 0700, checked with lstat, and the umask is 077 before bind. The hook checks uid and signature before it trusts a reply. Strict validation is used when the requirement pins an identifier.
