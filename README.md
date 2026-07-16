# Nauvis

A minimal native macOS interface for [Pi](https://pi.dev): one persistent Pi session per Bonsplit tab.

## Run

1. Install and authenticate Pi.
2. Open `Nauvis.xcodeproj` and run the app.
3. Press `⌘T` for a new session and `⌘W` to close one.

Nauvis uses Pi's RPC mode, the documented integration boundary for non-Node apps. It finds `pi` on the usual Homebrew and local install paths. Set `PI_EXECUTABLE` to use another executable and `NAUVIS_CWD` to choose the sessions' working directory.
