# mcpone WASI/wasm builds

This directory contains build scripts which are intentionally kept separate from upstream SQLite build plumbing, so upstream merges stay easy.

## Build sqlite3 CLI for WASI (preview1)

Produces a WASI (preview1) WebAssembly *CLI* module (not the JS/emscripten `ext/wasm` build).

```sh
./mcpone/build-wasi-cli.sh
```

Or:

```sh
make -f mcpone/Makefile wasm-cli
```

Output:

- `mcpone/out/sqlite3-cli.wasm`

All intermediate build artifacts go under `mcpone/.build/` and are ignored via `mcpone/.gitignore`.

### Toolchain

Provide a wasi-sdk via:

- `WASI_SDK_PATH=/path/to/wasi-sdk-XX.Y-... ./mcpone/build-wasi-cli.sh`

If `WASI_SDK_PATH` is unset, the script auto-detects the newest directory under `~/.wasi-sdk/wasi-sdk-*`.

### Notes

The build defines `SQLITE_NOHAVE_SYSTEM` because WASI environments do not support `system()`. That removes shell features like `.system`/`.shell` and the `edit()` SQL function.
