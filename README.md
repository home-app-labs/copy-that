# Copy That

Clipboard history that never leaves your Mac.

Press ⇧⌘V in any app and a strip of cards slides up with everything you copied: text, links, screenshots, files. Pick one and it is pasted where you were typing. Keep the things you reuse as snippets in your own groups.

**[Download the installer](https://github.com/home-app-labs/copy-that/releases/latest/download/Copy-That.pkg)** · [Website](https://homeapplabs.com/copy-that/) · macOS 14 or later · free

## What it does

- **History behind one shortcut.** ⇧⌘V opens the history on top of any app. The app you were typing in stays active, so the paste lands there.
- **Previews that fit the content.** Text shows its first lines, a screenshot shows a thumbnail, a file shows its icon and folder.
- **Links without the network.** A link is drawn as a card with its domain and address, taken from the text itself. Copy That never fetches a preview and never contacts the network at all.
- **Search and tabs.** Just start typing. Tab moves between All, Text, Links, Images, Files and your groups.
- **Snippets in groups.** Save a history entry into a group with ⌘P, or write a snippet by hand with ⌘N. Snippets are separate copies: they are not pushed out by the history limits and keep their place in the group.
- **Paste the way you want.** Return pastes, Shift-Return pastes as plain text, ⌘1–9 pastes by number, ⌘C only copies.
- **You decide how long history lives.** Limit it by number of items and by age, from one day to forever.
- **Passwords stay out.** Entries that password managers mark as concealed or temporary are not recorded, and recording can be paused from the menu bar.
- **Your data stays yours.** Plain files on your Mac. No account, no sync, no tracking.

## Keys

| Key | Action |
| --- | --- |
| ⇧⌘V | Open or close the history |
| ← → | Select a card. With ⌘: jump to the first or last |
| Return | Paste the selected card |
| Shift-Return | Paste it as plain text |
| ⌘1–9 | Paste the card with that number |
| ⌘C | Copy without pasting |
| ⌘P | Save the selected history entry into the group used last |
| ⌘N | Write a new snippet |
| ⌘E | Edit the selected snippet |
| ⌘⌫ | Delete the selected card |
| Tab | Next tab |
| Esc | Clear the search, or close |

Double-click a card to paste it. Right-click a card or a group for more: save or move to a group, rename or delete a group.

## Install

1. Download [Copy-That.pkg](https://github.com/home-app-labs/copy-that/releases/latest/download/Copy-That.pkg) and open it.
2. The app is not signed with a paid Apple developer certificate, so macOS blocks the installer the first time. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
3. Follow the installer. It copies Copy That to your Applications folder and opens it.

There is a step by step guide with pictures on the [website](https://homeapplabs.com/install/).
Prefer to move the app yourself? Take `Copy-That.zip` from the [latest release](https://github.com/home-app-labs/copy-that/releases/latest).

## Permissions

- **Accessibility** lets the app press ⌘V for you after you pick a card. macOS asks the first time. Without it the card is only copied to the clipboard and you press ⌘V yourself.
- **Paste from Other Apps.** If macOS asks whether Copy That may read the clipboard, choose "Always Allow" in System Settings → Privacy & Security.
- **⇧⌘V** may already be taken by another clipboard app. Switch the shortcut off there.

## Build from source

You need Xcode 15 or later.

    git clone https://github.com/home-app-labs/copy-that.git
    cd copy-that
    ./build.sh --install --run

`./build.sh` assembles `build/Copy That.app`, `--install` copies it to `/Applications`, `--run` opens it. Run the tests with `swift test`.

The app is signed ad hoc, so macOS forgets the Accessibility permission after every rebuild: remove Copy That from the list and add it again. If you have a signing certificate, `PASTEPLUS_SIGN_IDENTITY="..." ./build.sh` keeps the permission.

## Layout

| Path | What is there |
| --- | --- |
| `Sources/PastePlus/ClipItem.swift` | A history entry, link detection, the content fingerprint |
| `Sources/PastePlus/HistoryStore.swift` | History, groups and snippets: adding, duplicates, limits, saving |
| `Sources/PastePlus/Pasteboard.swift` | Watching the clipboard, writing back, sending ⌘V |
| `Sources/PastePlus/HotKey.swift` | The system-wide ⇧⌘V shortcut |
| `Sources/PastePlus/HistoryPanel.swift` | The panel, its keys, search and selection state |
| `Sources/PastePlus/HistoryView.swift` | Cards, group tabs, the snippet editor |
| `Sources/PastePlus/PastePlusApp.swift` | Launch, the menu bar menu, development aids |
| `Tests` | Unit tests for the history, groups and link detection |
| `Resources` | Info.plist and the icon |
| `scripts` | Icon drawing and the release script |

The app was first called Paste Plus. The code, the bundle identifier `local.pasteplus` and the data folder keep that name so that existing history and settings carry over.

## Where your data lives

| What | Where |
| --- | --- |
| History and snippets | `~/Library/Application Support/PastePlus/history.json` |
| Groups | `groups.json` in the same folder |
| Images and rich text | the `blobs` folder next to them |
| Settings | the `local.pasteplus` defaults domain |

The folder is readable by your user only. Deleting the app does not delete it. Remove the folder to start from scratch.

## Development aids

Environment variables that make the app easier to test. Run the built binary directly, for example `PASTEPLUS_DEMO=1 .build/debug/PastePlus`.

| Variable | Effect |
| --- | --- |
| `PASTEPLUS_DATA_DIR=/path` | Keep the history in another folder, so tests do not touch real data |
| `PASTEPLUS_DEMO=1` | Fill an empty history with sample items and groups |
| `PASTEPLUS_DEMO_QUERY=text` | Type that into the search field |
| `PASTEPLUS_DEMO_SHOW=group`, `editor` or `newgroup` | Open the first group, the snippet editor or the group name field |
| `PASTEPLUS_SNAPSHOT_DIR=/path` | Open the panel, save `panel.png` there after two seconds and quit |

## Releasing

1. Put the new version number into `VERSION` and describe the changes in `release-notes/<version>.md`.
2. Commit.
3. Run `./scripts/release.sh --publish`. It builds a universal app, the installer and the zip, tags the commit and creates the GitHub release with the files attached.

The download links above always point at the latest release.

## Made with AI

Copy That is built by [Home App Labs](https://homeapplabs.com): one person with an idea, and an AI coding assistant doing the typing. Every line is here to read. Fork it and make it yours.

## License

[MIT](LICENSE)
