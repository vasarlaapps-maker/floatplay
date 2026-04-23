#!/usr/bin/env bash
# setup.sh — Generate the Xcode project and open it
set -euo pipefail

echo "=== ScreenOnScreen Setup ==="

# ── 1. Homebrew ──────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found. Installing…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Add Homebrew to PATH for this session (needed right after fresh install)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# ── 2. XcodeGen ──────────────────────────────────────────────────────────────
if ! command -v xcodegen &>/dev/null; then
  echo "Installing XcodeGen…"
  brew install xcodegen
fi

# ── 3. Generate project ───────────────────────────────────────────────────────
echo "Generating ScreenOnScreen.xcodeproj…"
xcodegen generate

# ── 4. Open in Xcode ─────────────────────────────────────────────────────────
echo "Opening project in Xcode…"
open ScreenOnScreen.xcodeproj

echo ""
echo "✔  Done!"
echo "   → Select your team in Signing & Capabilities"
echo "   → Choose an iPhone/iPad simulator or device"
echo "   → Press ▶ Run"
echo ""
echo "PiP tip: while a video plays, tap the PiP button"
echo "         in the YouTube player controls to float"
echo "         the video over any other app."
