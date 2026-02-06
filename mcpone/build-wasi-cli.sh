#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MCPONE_DIR="$ROOT_DIR/mcpone"

usage() {
  cat <<'EOF'
Build the sqlite3 CLI as a WASI (preview1) WebAssembly module.

Usage:
  ./mcpone/build-wasi-cli.sh [--clean] [--reconfigure] [--wasi-sdk PATH] [--build-dir DIR] [--out FILE] [--flavor full|minimal]

Environment:
  WASI_SDK_PATH   Path to a wasi-sdk install (must contain bin/clang).
                 If unset, the script will try to auto-detect ~/.wasi-sdk/wasi-sdk-*/.
EOF
}

want_clean=0
want_reconfigure=0
wasi_sdk_path="${WASI_SDK_PATH:-}"
build_dir="$MCPONE_DIR/.build/sqlite-wasi-cli"
out_file="$MCPONE_DIR/out/sqlite3.wasm"
flavor="full"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      want_clean=1
      shift
      ;;
    --reconfigure)
      want_reconfigure=1
      shift
      ;;
    --wasi-sdk)
      wasi_sdk_path="${2:-}"
      shift 2
      ;;
    --build-dir)
      build_dir="${2:-}"
      shift 2
      ;;
    --out)
      out_file="${2:-}"
      shift 2
      ;;
    --flavor)
      flavor="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" 1>&2
      usage 1>&2
      exit 2
      ;;
  esac
done

if [[ "$want_clean" == "1" ]]; then
  rm -rf -- "$build_dir"
  rm -f -- "$out_file"
  exit 0
fi

if [[ -z "$wasi_sdk_path" ]]; then
  if [[ -d "$HOME/.wasi-sdk" ]]; then
    # Prefer newest installed SDK *directory*.
    candidates=()
    for cand in "$HOME/.wasi-sdk"/wasi-sdk-*; do
      [[ -d "$cand" ]] || continue
      candidates+=("$cand")
    done
    if ((${#candidates[@]})); then
      wasi_sdk_path="$(ls -dt "${candidates[@]}" 2>/dev/null | head -n 1 || true)"
    fi
  fi
fi

if [[ -z "$wasi_sdk_path" ]]; then
  echo "WASI SDK not found. Set WASI_SDK_PATH or pass --wasi-sdk PATH." 1>&2
  exit 1
fi

cc="$wasi_sdk_path/bin/clang"
if [[ ! -x "$cc" ]]; then
  echo "Missing WASI clang at: $cc" 1>&2
  exit 1
fi

mkdir -p -- "$build_dir"
mkdir -p -- "$(dirname -- "$out_file")"

if [[ "$want_reconfigure" == "1" || ! -f "$build_dir/Makefile" ]]; then
  # Avoid creating macOS .dSYM bundles for build tools.
  (cd -- "$build_dir" && \
    BUILD_CFLAGS="${BUILD_CFLAGS:--O2}" \
      "$ROOT_DIR/configure" --with-wasi-sdk="$wasi_sdk_path")
fi

# Generate the amalgamation + shell sources inside the build dir.
(cd -- "$build_dir" && make sqlite3.c shell.c)

common_cflags=(
  -O3 -DNDEBUG
  -D_WASI_EMULATED_SIGNAL
  -D_WASI_EMULATED_PROCESS_CLOCKS
  -D_WASI_EMULATED_GETPID
  -D_WASI_EMULATED_MMAN
  -DSQLITE_NOHAVE_SYSTEM
  -DSQLITE_USE_URI=1
  -DSQLITE_TEMP_STORE=2
  -DSQLITE_THREADSAFE=0
  -DSQLITE_OMIT_LOAD_EXTENSION=1
  '-DSQLITE_DEFAULT_UNIX_VFS="unix-none"'
)

feature_cflags=()
case "$flavor" in
  minimal)
    # Keep this small. Add flags here as needed for your use case.
    feature_cflags+=(
      -DSQLITE_DQS=0
    )
    ;;
  full)
    feature_cflags+=(
      -DSQLITE_DQS=0
      -DSQLITE_ENABLE_BYTECODE_VTAB
      -DSQLITE_ENABLE_DBPAGE_VTAB
      -DSQLITE_ENABLE_DBSTAT_VTAB
      -DSQLITE_ENABLE_EXPLAIN_COMMENTS
      -DSQLITE_ENABLE_FTS4
      -DSQLITE_ENABLE_FTS5
      -DSQLITE_ENABLE_MATH_FUNCTIONS
      -DSQLITE_ENABLE_OFFSET_SQL_FUNC
      -DSQLITE_ENABLE_PERCENTILE=1
      -DSQLITE_ENABLE_PREUPDATE_HOOK
      -DSQLITE_ENABLE_RTREE
      -DSQLITE_ENABLE_SESSION
      -DSQLITE_ENABLE_STMTVTAB
      -DSQLITE_ENABLE_UNKNOWN_SQL_FUNCTION
      -DSQLITE_ENABLE_COLUMN_METADATA
      -DSQLITE_STRICT_SUBTYPE=1
    )
    ;;
  *)
    echo "Unknown --flavor: $flavor (expected: full|minimal)" 1>&2
    exit 2
    ;;
esac

link_libs=(
  -lwasi-emulated-signal
  -lwasi-emulated-process-clocks
  -lwasi-emulated-getpid
  -lwasi-emulated-mman
)

(cd -- "$build_dir" && \
  "$cc" \
    "${common_cflags[@]}" \
    "${feature_cflags[@]}" \
    -o "$out_file" \
    shell.c sqlite3.c \
    "${link_libs[@]}")

echo "Wrote: $out_file"
