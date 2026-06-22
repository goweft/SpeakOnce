#!/usr/bin/env bash
# SpeakOnce installer - system deps, whisper.cpp (Vulkan), model, scripts, hotkeys.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
WHISPER_DIR="${SPEAKONCE_WHISPER_DIR:-$HOME/whisper.cpp}"
MODEL_NAME="${SPEAKONCE_MODEL_NAME:-small.en}"
BIN="$HOME/.local/bin"
PACKS="$HOME/.config/speakonce/packs"

say(){ printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

say "Installing system packages (needs sudo)"
sudo apt-get update -qq || true
sudo apt-get install -y build-essential cmake git curl python3 jq \
  xdotool pulseaudio-utils libvulkan-dev glslc spirv-headers spirv-tools vulkan-tools libnotify-bin

say "Building whisper.cpp with the Vulkan backend"
[ -d "$WHISPER_DIR" ] || git clone --depth 1 https://github.com/ggml-org/whisper.cpp "$WHISPER_DIR"
cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$WHISPER_DIR/build" -j"$(nproc)" --target whisper-cli

say "Downloading the $MODEL_NAME model"
[ -f "$WHISPER_DIR/models/ggml-$MODEL_NAME.bin" ] || \
  ( cd "$WHISPER_DIR" && bash ./models/download-ggml-model.sh "$MODEL_NAME" )

say "Installing scripts and packs"
mkdir -p "$BIN" "$PACKS"
install -m 0755 "$REPO/bin/speakonce"       "$BIN/speakonce"
install -m 0755 "$REPO/bin/speakonce-clean" "$BIN/speakonce-clean"
cp -n "$REPO"/packs/*.txt "$PACKS"/ 2>/dev/null || true
case ":$PATH:" in *":$BIN:"*) ;; *) echo "   NOTE: add $BIN to your PATH";; esac

say "Verifying GPU transcription"
"$WHISPER_DIR/build/bin/whisper-cli" -m "$WHISPER_DIR/models/ggml-$MODEL_NAME.bin" \
  -f "$WHISPER_DIR/samples/jfk.wav" -np -nt 2>/dev/null | head -1 || true

if command -v xfconf-query >/dev/null && xfconf-query -c xfce4-keyboard-shortcuts -l >/dev/null 2>&1; then
  say "Binding XFCE hotkeys (F9 = raw, F10 = clean)"
  xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/F9"  -n -t string -s "$BIN/speakonce" 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/F9"  -s "$BIN/speakonce"
  xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/F10" -n -t string -s "$BIN/speakonce clean" 2>/dev/null || \
    xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/F10" -s "$BIN/speakonce clean"
  echo "   F9 -> dictate (raw),  F10 -> dictate + cleanup"
else
  echo "   NOT on XFCE (or no session bus). Bind two hotkeys yourself:"
  echo "     raw:   $BIN/speakonce"
  echo "     clean: $BIN/speakonce clean"
fi

say "Done. Focus a text field and press F9 to dictate."
echo "   Cleanup mode (F10) needs Ollama + a small instruct model:"
echo "     ollama pull qwen2.5-coder:7b   # or a lighter one: llama3.2:3b"
