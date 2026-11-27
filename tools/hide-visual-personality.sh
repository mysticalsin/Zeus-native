#!/bin/sh
# FluidAudio's libtext_processing_rs.a and this archive both define
# rust_eh_personality. The Mac link fails on that duplicate. Rename the copy
# inside libzeus_visual.a so each archive keeps its own.
set -eu
archive=${1:?usage: hide-visual-personality.sh libzeus_visual.a}

if [ ! -f "$archive" ]; then
  echo "missing archive: $archive" >&2
  exit 1
fi

redefine() {
  from=$1
  to=$2
  if command -v llvm-objcopy >/dev/null 2>&1; then
    llvm-objcopy --redefine-sym "$from=$to" "$archive"
  elif command -v xcrun >/dev/null 2>&1 && xcrun --find llvm-objcopy >/dev/null 2>&1; then
    xcrun llvm-objcopy --redefine-sym "$from=$to" "$archive"
  elif command -v rustc >/dev/null 2>&1; then
    host=$(rustc -vV | sed -n 's/^host: //p')
    tool="$(rustc --print sysroot)/lib/rustlib/${host}/bin/llvm-objcopy"
    if [ -x "$tool" ]; then
      "$tool" --redefine-sym "$from=$to" "$archive"
    else
      echo "llvm-objcopy is required to rename rust_eh_personality" >&2
      exit 1
    fi
  else
    echo "llvm-objcopy is required to rename rust_eh_personality" >&2
    exit 1
  fi
}

symbols=$(nm -g "$archive")
if printf '%s\n' "$symbols" | grep -Eq '(^|[[:space:]])_rust_eh_personality$'; then
  redefine _rust_eh_personality _zeus_visual_eh_personality
elif printf '%s\n' "$symbols" | grep -Eq '(^|[[:space:]])rust_eh_personality$'; then
  redefine rust_eh_personality zeus_visual_eh_personality
else
  echo "visual archive has no rust_eh_personality"
  exit 0
fi

if nm -g "$archive" | grep -Eq ' [TDS] _?rust_eh_personality$'; then
  echo "rust_eh_personality is still public in $archive" >&2
  exit 1
fi
echo "renamed rust_eh_personality in $archive"
