# fx desktop

Native desktop UI for the [fx](https://fx.sh) coding agent, written in Zig with
[nanoui](https://github.com/justrach/nanoui). The visual design follows
`fx-ui-main` (Geist dark palette, 248pt sidebar, 720pt transcript column).

This is a separate subproject from fx's Zig CLI: it does not change the main
`zig build` or `src/`, and it drives the agent through `fx acp` over stdio.

## Build and run

nanoui is a path dependency. The checkout must sit next to `nanoui`:

```
<parent>/
  fxo/       this repository
  nanoui/    https://github.com/justrach/nanoui
```

```bash
cd desktop
zig build          # builds zig-out/bin/fx-desktop
zig build run      # opens the window
zig build test     # headless ui.Tester specs, no window
```

Requires Zig 0.17.1 and, on macOS, the Xcode command-line tools.

To check the look without opening a window:

```bash
./zig-out/bin/fx-desktop --nanoui-snapshot=/tmp/fx.png --nanoui-dark \
  --nanoui-script="click:New session;wait:0.2"
```

## Layout

```
desktop/
  build.zig, build.zig.zon   nanoui dependency, exe, tests
  src/
    main.zig         app entry, window, headless guard
    view.zig         root shell, shortcuts, engine snapshot merge
    state.zig        UI state (main thread only)
    engine.zig       fx acp process, JSON-RPC, worker snapshot
    tokens.zig       design colours and sizes from fx-ui-main
    widgets.zig      shared controls (nav, pill, button, dot)
    art.zig          braille wordmark, one text node per line
    sidebar.zig      workspaces and sessions
    home.zig         hero, composer, recent sessions
    thread.zig       transcript and answer
    composer.zig     text field and toolbar
    permission.zig   approval card (question, preview, Allow/Deny)
    palette.zig      ⌘K command palette (search + sessions overlay)
    git.zig          git status/diff parsing + refresh
    changes.zig      ⌘\ changes panel (file list + diff)
    settings.zig     ⌘, settings shell (section nav + cards)
    settings_pages.zig  the six settings pages
    icons.zig        fx SVG icon set, transcribed from design/assets.rs
    fxcli.zig        fx CLI bridge (status/usage/mcp/permissions/doctor)
    acp_parse.zig    pure ACP parsing (permissions, tool steps, questions)
    picker.zig       @ / / composer picker (trigger, discovery, ranking)
    composer_menu.zig  permission/model/thinking/usage pill menus
    dialog.zig       confirm / rename / full-access / discard dialogs
    proc.zig         Threaded Io for child processes (git, fx)
    tests.zig        headless layout and interaction specs
```

## Scope

The MVP covers the main path: sidebar, home, thread and composer, with a
streaming ACP client that creates a session, sends prompts and renders agent
text. Permission requests now surface as an approval card in the thread: Allow
/ Always allow / Deny, plus Enter to allow and Esc to deny. The answer is sent
back to `fx acp` as a JSON-RPC result.

To preview the card without a live agent:

```bash
./zig-out/bin/fx-desktop --nanoui-snapshot=/tmp/perm.png --nanoui-dark \
  --fx-preview-permission
```

`⌘K` opens the command palette: search commands and sessions, arrows to move,
Enter to run, Esc to close. Each command carries its own icon (sessions show a
dot), shortcuts sit at the right edge, and the footer lists the key hints.
Preview it with `--fx-preview-palette`.

`⌘\` toggles the changes panel: a 400pt split with Staged / Not staged group
cards, each row a status dot, file name, +/- counts and its directory (or
"new file"). Group headings carry Stage all / Unstage all; hovering a row swaps
the counts for Discard and Stage/Unstage. Click a file to open its diff card
(capped at 120 lines with a "Show N more lines" expander) and the remaining
files as folded cards. Untracked files get real line counts, binary files 0.
It reads `git status`/`git diff` on a real Threaded Io (`proc.zig`), and the
workspace's status loads as soon as a folder is added. Preview it with
`--fx-preview-changes`.

`⌘,` opens Settings with all six sections (Models & accounts, Behaviour, MCP
servers, Skills, Usage, About). Data-backed sections read real `fx` output via
`fxcli.zig`: a background loader gathers `fx status/usage/mcp/permissions/
doctor` into a bounded snapshot; headless snapshots gather synchronously.
Accounts show the actual connected providers, Usage shows real totals and
per-model rows, MCP shows live status and tool counts, Skills are discovered
from `.fx/skills` / `~/.fx/skills` / `.agents` / `.claude`, About shows the fx
version and doctor counts. Preview with `--fx-preview-settings` or
`--fx-settings-section=N` (0-5).

All icons are the design's SVG paths (`icons.zig`), not Unicode substitutes.
The header carries the workspace › session breadcrumb, branch pill, diff
counts and overflow menu; the sidebar shows the real user name, provider and
a theme toggle; the composer has shield/plus/arrow SVGs, a Fast switch and a
usage menu. Permission mode / Model / usage popups are fixed overlays anchored
to the pill that opened them (its rect captured on click), so they follow the
button without ever moving the input field. macOS traffic lights are placed in
the 48pt sidebar header via
nanoui's `traffic_lights` window option (AppKit draws them, so they do not
appear in headless snapshots). The collapsed-sidebar tab bar reserves 92pt on
macOS (`tabbar.zig`, matching the design's `render_tabs`) so the expand button
clears the window buttons; other platforms keep a 12pt inset.

The transcript shows the working timeline (thoughts, tool steps with status
and output, changed-files card) and numbered question cards from
`ask_user_question`. A running turn shows a spinner and "Working · Ns · N
actions"; a settled turn folds its steps into "Worked for Ns" with a chevron
that expands them on click. Each answer ends with a copy button and a
"model · duration" footer. Prompt images render as 96×72 thumbnails above the
bubble. The composer has `@` file and `/` skill pickers plus
working permission/model/thinking pill menus. Confirm/rename/full-access
dialogs are implemented.

Home has Recent / Running / Archived tabs with counts and an All sessions
shortcut. Recent groups sessions under Today / Yesterday / Earlier headings;
each row is a status mark (spinner while running), the title, a note (what the
running turn is doing) and a right-aligned age. Archived sessions live only in
their own tab. Collapsing the sidebar reveals a tab bar with open sessions,
new, search and settings.

Image attachments (native file panel, bounded to 8 files / 3.75 MiB each,
rendered as composer thumbnails) and the native Open folder picker are
implemented via `nanoui.dialog.open`.

The transcript renders Markdown answers (bold, italic, inline code, headings,
bullets, fenced code) via nanoui's `ui.markdown`, folds consecutive same-kind
tool steps into "+N more" rows, and shows numbered cards for
`ask_user_question`.

Permission approvals show a colored line diff (LCS of old/new strings) with
file path, +/- counts and "Always allow edits in <dir>/", matching the design
screenshot. Permission mode / thinking / Fast mode write back through ACP
`session/set_config_option` and `fx config set`; the write-back format was
verified against a live `fx acp` session (mode write returned OK).
