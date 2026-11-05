# TAKEOVER: the Download Monitor on a fresh Mac

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
