# TAKEOVER: the Download Monitor on a fresh Mac

**v23 (6.11.2026, ~06:20):** the amber live text is drawn BEFORE the name in ListRow (and shownName), at the left of the line. Run 42165444591 green.

**v22 (6.11.2026, ~06:05): WRITING.** `Pane.scanOpen()` runs `lsof -F fan +d <folder>` every 3 s on a background queue; a file another program has open for writing (access w/u) is a live row (`Live.held`) even when its size does not change (DaVinci multi-pass analysis leaves a 819 KB stub for minutes); the TIME column says `writing` until MediaInfo can read it. Run 42165147418 green.

**v21 (6.11.2026, ~05:50): live size and write speed.** `app/Panes.swift`: `Live` (size, speed, text), `Pane.live` + a 1 s tick (common run loop mode) that stats every file of the folder, a growing file is live, three unchanged ticks end it and reload; Row.live/shownName, ListRow and IconCell draw it in AMBER; `state()` carries `live`. GitHub run 42164592345 green, v21 Latest, installed, signed, proven with a 25 MB/s test file (window capture: `150.0 MB · 150,000,000 bytes (24.7 MB/s)`, plain name after it stopped). Marko to try it on a real download or copy.

**v11 (6.11.2026, ~04:15): DASHBOARD solo.** First press hides a part, second solos it, third brings everything back; run 42152482750 green, installed and signed "Mantra Apps", checked by `dlmon.py view press` and a window capture. Marko to try it by hand.

**State 6.11.2026 (later): v7, the DASHBOARD.** `app/Dashboard.swift`: Part, Dash (on/off per part, bare with
enterBare/leaveBare/full, UserDefaults `dash.*`), DashRow (the words in the first row). PaneView is split into header,
nav, views, slider, footer, each behind `dash.shown(...)`; MonitorView.parts picks the panes over the queue (VSplitView)
or either alone. ViewCommands: `show`, `hide`, `layout`; the state carries `parts`. `dlmon.py view show|hide|layout|parts`.
Built by GitHub (run 42148103596 green), release v7 Latest, installed and signed "Mantra Apps"; left in FULL showing
HIR_96 | HIR_98 ALL_VERSIONS_2026-11-05 in LIST.

**State 6.11.2026: v6, the file viewer.** `app/Panes.swift`: Pane (folder, items, selection, mode icons|list, iconSize,
preview, sortKey/ascending, all in UserDefaults `pane.<i>.*`), Panes (the list, `panes.paths`, active), Sizer, Durations
(AVURLAsset), PaneView, ListView/ListRow (own sortable titles, wrapping names), IconsView/IconCell, Flow (wrapping rows).
`app/Viewer.swift`: Thumbs (QLThumbnailGenerator), QL (QLPreviewPanel data source and delegate, set directly on the
shared panel; one item, the arrows move the pane), Keys (local key monitor: Space, arrows in ICONS, ⌘↓ ⌘↑),
ViewCommands (apply / state). `app/App.swift`: Monitor.pollView / reportView, the panes row, transfer(dir:). Server:
`/view`, `/view/commands`, `/view/done`, `/view/state` in monitor.py; `dlmon.py view …`. Built by GitHub (run
42142202400 green), release v6 Latest, installed and signed "Mantra Apps"; left showing HIR_96 | HIR_98
ALL_VERSIONS_2026-11-05 in LIST. Install: `gh release download v6 -p app.zip`, ditto into /Applications, `codesign
--force -s "Mantra Apps"`; quit the running copy first with `osascript -e 'tell application id
"community.auroville.downloadmonitor" to quit'` when `dlmon.py queue` shows nothing running.

**State 5.11.2026 evening: v5, Download, Copy and Move (Mantra)** (`/Applications/Download, Copy and Move (Mantra).app`,
executable DownloadCopyMove, bundle id unchanged community.auroville.downloadmonitor). Copy/move queue: `copier.py`
(engine, detached, one at a time), `monitor.py` (POST /copy, control pause/start/cancel for copy jobs, ensure_copier on
every /progress and at start), `dlmon.py copy|move|queue|cancel`. Window: `app/App.swift` (top row, queue rows CopyRow,
downloads JobRow), `app/Panes.swift` (Pane, PaneView, Sizer folder sizes). Running on 5.11.2026: the Santoshi move and
five folder moves to /Volumes/Video_Marko (MANTRA_MANIFEST modules/file-moves.md log). Install: `gh release download v5
-p app.zip`, ditto into /Applications, `codesign --force -s "Mantra Apps"`.

Earlier: **v4.** Icon like VM REMOTE: DOWNLOAD / MONITOR on the black terminal tile, orange square cursor
(STAR_SWIFT icons6 `terminal:#FF9F0A`). The branch is `main` (renamed from master 5.11.2026); built by GitHub Actions.


1. Python 3.10 at `~/.pyenv/versions/3.10.14/bin/python3` with Flask (`pip install flask`), and
   huggingface_hub for `dlmon.py hf` and repo sizes (`pip install huggingface_hub`).
2. Clone: `git clone https://github.com/markoboskoauroville/DOWNLOAD_MONITOR ~/Developer/DOWNLOAD_MONITOR`
3. The star menu (MANTRA_STAR) has the switch, `apps/download.lua`, pointing at that folder and that
   python. Tick "Download Monitor"; the page opens at http://127.0.0.1:8833.
4. Without the star: `python3 dlmon.py open`. To stop: `python3 dlmon.py down`.
5. State is under `~/.download_monitor/` (jobs, logs); nothing generated is in the repository.

## The Swift window (13.10.2026)

`app/App.swift`: Monitor (poll /progress every 0.5 s, the server started detached with nohup if /health fails, POST
/quit in applicationWillTerminate), JobRow, MonitorView. FOLDER reads the job's own json in ~/.download_monitor/jobs
for `file`, else the Hugging Face cache folder of its repo. Icon `icon/make_icon.swift`.

19.10.2026, v2: the ON / OFF row and the ✕ at the top of MonitorView; CloseX.put(on:) adds the ✕ to the delete NSAlert
(stopModal = Cancel); applicationShouldHandleReopen brings the window back. Marko to try OFF, ✕ and the delete ✕.

**31.10.2026, v3: TOP on the first row.** Marko: *"Each needs to have the same user interface elements. On, off and top"*.
TOP left of ✕ (green = window `.floating`, UserDefaults `onTop`, applied at launch); OFF, TOP, ✕ are Accessibility
buttons (`off`, `top`, `close`). A build is relaunched only when no row is running (`dlmon.py list`): OFF stops the server.

## 6.11.2026, v10: MediaInfo columns, pane jump in the preview

Built by GitHub (run 42152019244 green), release v10 Latest, installed and signed "Mantra Apps" (sign
Contents/Resources/mediainfo first, then the app). The workflow downloads MediaInfo_CLI_26.05_Mac.dmg from mediaarea.net
on the runner (universal, links only libz/libc++/libSystem). app/MediaInfo.swift parses `mediainfo --Output=JSON`;
LCOLS in app/Panes.swift is the column list (order = Marko's: time, resolution, fps, bit rate, codec). Waiting: Marko
tries ← → in the full-screen preview.

## 6.11.2026 night, v11 to v20 (this session: v8 to v10 MediaInfo, v12 filter, v13 divider, v14 pane count + paths, v15 columns, v16 to v20 bare title bar, preview fit, Command-I)

Built by GitHub, v20 Latest, installed signed "Mantra Apps". Files: app/MediaInfo.swift, Columns.swift, Info.swift,
StatusBar.swift, Panes.swift (LCOLS, PaneDivider, FilterBox), Viewer.swift (QL.fit = preview shaped like the media).
Waiting: Marko tries ← → and Command-I by hand; the dashboard still shows "SOLO PANES" from the other session's solo test.
