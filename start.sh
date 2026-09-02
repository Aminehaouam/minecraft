#!/usr/bin/env bash
# One-click launcher for macOS and Linux. Double-click start.command on macOS,
# or run ./start.sh from a terminal.
set -u
cd "$(dirname "$0")"

keep_open () {
  echo
  read -r -p "Press Enter to close this window... " _ || true
}

if ! command -v node >/dev/null 2>&1; then
  echo
  echo "  Node.js is not installed - the bot needs it to run."
  echo
  if command -v brew >/dev/null 2>&1; then
    read -r -p "  Install it now with Homebrew? [Y/n] " answer
    case "${answer:-Y}" in
      [Nn]*) ;;
      *) brew install node ;;
    esac
  elif command -v apt-get >/dev/null 2>&1; then
    echo "  Install it with:  sudo apt-get install -y nodejs npm"
  elif command -v dnf >/dev/null 2>&1; then
    echo "  Install it with:  sudo dnf install -y nodejs"
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo "  Or download the LTS installer from https://nodejs.org"
    if command -v open >/dev/null 2>&1; then open "https://nodejs.org/en/download"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "https://nodejs.org/en/download" >/dev/null 2>&1
    fi
    keep_open
    exit 1
  fi
fi

node "scripts/launch.js"
status=$?
if [ $status -ne 0 ]; then keep_open; fi
exit $status
