#!/usr/bin/env bash
# Builds donjon-asr (native/asr/donjon_asr.c) for one platform into native/dist/<platform>/, next to the sherpa-onnx and
# ONNX Runtime libraries it loads and their licences. The desktop exports carry that folder inside the game
# (export_presets.cfg include_filter) and src/audio/asr.gd copies it out to user://asr/ the first time you speak.
#   native/asr/build.sh linux      # on Linux x86_64 (gcc)
#   native/asr/build.sh windows    # on Linux, cross-compiled with mingw-w64 (x86_64-w64-mingw32-gcc): the C API is
#                                  # plain C, so it links against the MSVC-built (static CRT) sherpa-onnx DLLs
#   native/asr/build.sh macos      # on macOS (clang, universal arm64 + x86_64)
#   native/asr/build.sh model      # the speech model into build/asr-model/ (tests and smoke.py), from the same pinned
#                                  # files and checksums the game downloads (src/audio/asr.gd MODEL)
# Then: python3 native/asr/smoke.py native/dist/<platform>/donjon-asr build/asr-model
# Downloads are cached in build/.cache/.
set -euo pipefail
cd "$(dirname "$0")/../.."

SHERPA_ONNX_VERSION=1.13.8
RELEASES=https://github.com/k2-fsa/sherpa-onnx/releases/download
# The model the game downloads: keep in step with src/audio/asr.gd MODEL (tests/audio/test_asr.gd checks)
MODEL_URL=https://huggingface.co/csukuangfj2/sherpa-onnx-nemotron-speech-streaming-en-0.6b-160ms-int8-2026-04-25/resolve/237e551abd7a411ef92d3595454d9f6ab5fe7d6c
MODEL_SUMS="dc0b4584ab2e4ddbf888425c076c61b736e7356a015250db7d307e6f1a8188ff  tokens.txt
0be9702c2f427a2b6bb241d298e0d3836a558de1f5b9fd3018f1cce6e2b3fa98  decoder.int8.onnx
a35eac38a22ebceb04d230ed7afe0d68f446ba6914a036b97f14fece95967e23  joiner.int8.onnx
71111f61b18e1e65e01e369434a5c0434868d2f44892742ae54240600c681209  encoder.int8.onnx"

cache=build/.cache
mkdir -p "$cache"

fetch() { # url -> cached file path
  local file="$cache/$(basename "$1")"
  if [[ ! -s $file ]]; then
    echo "   downloading $(basename "$1")" >&2
    curl -fsSL --retry 3 "$1" -o "$file.part"
    mv "$file.part" "$file"
  fi
  echo "$file"
}

sherpa() { # archive suffix -> unpacked directory
  local name="sherpa-onnx-v$SHERPA_ONNX_VERSION-$1"
  local dir="$cache/$name"
  if [[ ! -d $dir ]]; then
    tar xjf "$(fetch "$RELEASES/v$SHERPA_ONNX_VERSION/$name.tar.bz2")" -C "$cache"
  fi
  echo "$dir"
}

platform=${1:-}
src=native/asr/donjon_asr.c
out=native/dist/$platform
flags=(-O2 -Wall -Wextra -std=c99)

case "$platform" in
  linux)
    so=$(sherpa linux-x64-shared)
    rm -rf "$out" && mkdir -p "$out"
    ${CC:-gcc} "${flags[@]}" "$src" -I "$so/include" -L "$so/lib" -lsherpa-onnx-c-api -lm -lpthread -Wl,-rpath,'$ORIGIN' -o "$out/donjon-asr"
    cp "$so/lib/libsherpa-onnx-c-api.so" "$so/lib/libonnxruntime.so" "$out/"
    ;;
  windows)
    so=$(sherpa win-x64-shared-MT-Release)
    rm -rf "$out" && mkdir -p "$out"
    ${CC:-x86_64-w64-mingw32-gcc} "${flags[@]}" "$src" -I "$so/include" -L "$so/lib" -lsherpa-onnx-c-api -static-libgcc -s -o "$out/donjon-asr.exe"
    cp "$so/lib/sherpa-onnx-c-api.dll" "$so/lib/onnxruntime.dll" "$so/lib/onnxruntime_providers_shared.dll" "$out/"
    ;;
  macos)
    so=$(sherpa osx-universal2-shared)
    rm -rf "$out" && mkdir -p "$out"
    ${CC:-clang} "${flags[@]}" -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 "$src" -I "$so/include" -L "$so/lib" \
      -lsherpa-onnx-c-api -Wl,-rpath,@executable_path -o "$out/donjon-asr"
    cp "$so/lib/libsherpa-onnx-c-api.dylib" "$so/lib/libonnxruntime.dylib" "$out/"
    codesign --force --sign - "$out"/*.dylib "$out/donjon-asr" # ad-hoc: Apple silicon runs nothing unsigned
    ;;
  model)
    dir=build/asr-model
    mkdir -p "$dir/test_wavs"
    for f in tokens.txt decoder.int8.onnx joiner.int8.onnx encoder.int8.onnx test_wavs/0.wav test_wavs/8k.wav test_wavs/trans.txt; do
      [[ -s $dir/$f ]] || { echo "   downloading $f" >&2; curl -fsSL --retry 3 "$MODEL_URL/$f" -o "$dir/$f"; }
    done
    printf '%s\n' "$MODEL_SUMS" > "$dir/SHA256SUMS" # a file: BSD sha256sum (macOS) won't read the list from stdin
    sum=sha256sum
    command -v sha256sum >/dev/null || sum="shasum -a 256"
    (cd "$dir" && $sum -c SHA256SUMS) || { echo "model files don't match their checksums" >&2; exit 1; }
    echo "model: $dir ($(du -sh "$dir" | cut -f1))"
    exit 0
    ;;
  *) echo "usage: native/asr/build.sh linux|windows|macos|model" >&2; exit 1 ;;
esac

cp native/asr/licenses/*.txt "$out/"
# What the game compares to decide whether the copy in user://asr/ is current
printf 'sherpa-onnx %s\n%s\n' "$SHERPA_ONNX_VERSION" "$( (cat "$src"; ls "$out") | cksum | cut -d' ' -f1)" > "$out/VERSION"
echo "$out:"
ls -l "$out"
