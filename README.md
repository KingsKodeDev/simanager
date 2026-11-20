# Simanager

A macOS app that shows every booted iOS simulator on this Mac, how much memory
each one holds, and what it is tied to (Claude session, zellij session and tab,
terminal). It shuts simulators down or deletes them, one at a time or all at
once, and reaps the abandoned ones on its own. It lives in a window and in the
menu bar.

## Build and run

```bash
xcodebuild -project Simanager.xcodeproj -scheme Simanager -derivedDataPath build build
open build/Build/Products/Debug/Simanager.app
```

Or open `Simanager.xcodeproj` in Xcode and run the `Simanager` scheme.

The logic is a local Swift package with its own tests, which never launch the app:

```bash
swift test --package-path Packages/SimanagerCore
```

Signing is set to Kings Kode Ltd.'s development team (`DEVELOPMENT_TEAM` in the
project); change it to your own team to build. Keep a real signing identity
rather than "Sign to Run Locally": a stable signature is what lets macOS
remember a folder-access grant across rebuilds, and an ad-hoc one is asked
again after every build. The app asks for folder access when a lane repository
(below) sits in Documents, Desktop or Downloads, because it runs
`git worktree list` there.

The app is not sandboxed: it runs `xcrun simctl`, `ps`, `lsof`, `git` and
`zellij`, and reads Claude Code's session files under `~/.claude*`.

## Lanes: which checkout a simulator belongs to

`~/.config/simanager/lanes.json` is written on first launch with no lanes and is
edited by hand. It is never overwritten; if it does not parse, the window says
so and nothing is reaped until it is fixed.

```json
{ "lanes": [ { "namePrefix": "ACME",
               "repo": "/Users/you/projects/acme-app",
               "mainTag": "main" } ] }
```

A simulator named `<namePrefix> <tag> … - <device>` belongs to the repo itself
when `<tag>` is `mainTag`, and otherwise to the git worktree whose folder is
named `<tag>`.

## Auto-reaping

A simulator is shut down automatically when all of these hold:

1. It is not pinned (the pin button on its row).
2. No live session has been tied to it on any refresh for the idle period (30 minutes by default).
3. A scan of recent Claude transcripts finds no command against it, from a session that is still running, within that period.
4. Every probe succeeded: a failed `ps`, `lsof`, `simctl` or `git` read restarts the clocks instead of counting as "nobody is using it".

The clock starts when the app starts, so nothing is reaped in the first idle
period after launch. Everything the app does on its own is in the Activity list
at the bottom of the window, with the reason.

To turn it off: the switch in the menu-bar popover or in Settings (⌘,). To run
once without it: `open build/Build/Products/Debug/Simanager.app --args -reapEnabled NO`.
Settings also holds the idle period (15 min to 2 h), the action (Shut down or
Delete) and Launch at login.
