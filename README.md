# DOWNLOAD_MONITOR — Download, Copy and Move (Mantra), once the Download Monitor

**Every download, copy and move on this Mac, each with its own line, in `/Applications/Download, Copy and Move
(Mantra).app`; since v6 also a file viewer: any number of panes as columns, ICONS with real thumbnails or LIST with all
details, Finder's Quick Look full screen, driven from Python (`dlmon.py view`); the size beside every folder; ONE queue
for copies and moves, one at a time. The server is still http://127.0.0.1:8833 and every dlmon.py command still works.**

## The file viewer: any number of panes, ICONS | LIST, Quick Look, driven from Python (v6, 6.11.2026)

Marko, 6.11.2026: *"update my application, download that and copier, and it can open any number of folders at the same
time, creating many vertical windows ... I can double-click any file, and it will open up in its viewer ... through the
Python API control it ... icon view and list view. If I'm in icon view, I have a slider at the top to enlarge icons, or
a list view with all details ... use the previewer mechanism from the Mac's itself ... when I click on one file, the
preview will open in full screen ... I just press the down arrow or up arrow to go through the three files, and it
should play those files. Then I press Escape"*

- **Panes as columns**, as many as wanted (two by default; ADD PANE | REMOVE PANE over them), each remembered with its
  folder, view, icon size, sort and PREVIEW. Each pane: PANE n (green = the active one) and the free space, BACK | UP |
  HOME | VOLUMES | HIDDEN, the path with every folder a button (grey > between), ICONS | LIST | PREVIEW.
- **ICONS**: real thumbnails (QuickLookThumbnailing; a video shows a frame), name, size and duration under each, the
  SIZE slider (48–512) on top. Click selects, ⌘-click adds, ⇧-click a range; ← → ↑ ↓ move.
- **LIST**: NAME · SIZE (a folder's whole size, measured in the background) · KIND · MODIFIED · TIME (the duration of a
  video or a sound). Each title is a button: click sorts, again the other way (size, date and time biggest first). The
  name wraps, nothing is cut; a narrow pane leaves out KIND under 560 pt, then MODIFIED under 460 pt.
- **Double click**: a folder is entered, a file opens in its own app (NSWorkspace). ⌘↓ opens too, ⌘↑ goes up.
- **Space** = Finder's Quick Look (QLPreviewPanel) on the selected file; Space or Escape closes it. **PREVIEW** on a
  pane: one click on a file opens it full screen (after the double-click time, so a double click still opens the app);
  in the preview ↓ / → go to the next file of that pane and ↑ / ← to the one before, the pane's selection moves with it
  and the video plays; Escape closes.
- **Copy and move between panes**: COPY → / MOVE → put the active pane's selection into the folder of the pane to its
  right, ← COPY / ← MOVE into the one to its left (with two panes: the same as v5). The active pane is the one last
  clicked; its number is shown as FROM PANE n.
- Every word is an Accessibility button with an identifier: `add-pane`, `remove-pane`, `copy-right`, `move-right`,
  `copy-left`, `move-left`, and per pane n: `pane-n`, `back-n`, `up-n`, `home-n`, `volumes-n`, `hidden-n`, `icons-n`,
  `list-n`, `preview-n`, `size-n` (slider), `sort-n-name|size|kind|date|duration`, `path-n-k`, `item-n-<name>`.
- ✕ hides the window (the app and the server stay); the Dock, the star or `dlmon.py view` bring the same window back.

```
dlmon.py view open <folder> [<folder> ...] [--mode icons|list]   the panes become these folders, window in front
dlmon.py view add <folder> | remove | go <folder> [--pane N]
dlmon.py view mode icons|list [--pane N]        dlmon.py view size <48..512> [--pane N]
dlmon.py view previewmode on|off [--pane N]
dlmon.py view select <file>                     dlmon.py view preview <file> [--window]   (full screen by default)
dlmon.py view next | prev                       dlmon.py view close
dlmon.py view list                              what every pane shows, the selection, the preview
```

How it is wired: `dlmon.py view` posts the command to the server (`POST /view`, kept in order with a number); the window
polls `GET /view/commands?after=N` twice a second with /progress, applies it (`app/Viewer.swift`, ViewCommands), answers
`POST /view/done` (dlmon.py prints that answer) and posts what the panes show to `POST /view/state` (`GET /view/state`,
`dlmon.py view list`). A window that starts takes only the commands of the last 20 seconds. dlmon.py opens the app first
if it is not running.

## Copy and move: one queue, one at a time (v5, 5.11.2026)

Marko, 5.11.2026: *"if there is no scripting support, we need to have that. We need to use our Download app to be
Download and Copy Move app. Rename it and copy the system of Pathfinder to show what's moving and the speed and put
everything in the queue. We are not moving files multiple at the same time."* And: *"This app will also have 2 windows,
left and right, for copying between 2 locations manually ... Folder size— what is the folder size?"*

```
dlmon.py copy SRC DST            a file or a folder; DST is the new full path (DST/ = into that folder)
dlmon.py move SRC DST            the same, and the original goes only after the check, a symlink left in its place
dlmon.py queue                   the queue in order: phase, %, GB, files, MB/s, time left, ready at, the file in hand
dlmon.py pause|start|cancel <id> PAUSE holds the queue at that job; START continues (or retries a FAILED one); CANCEL takes it out
POST /copy {src, dst, mode}      or {items: [...], dst_dir, mode}: what the panes send
```

- **The engine is `copier.py`**, one detached process (pid in `~/.download_monitor/copier.pid`); the server starts it
  whenever the queue has work, so a restart of the server or the window does not stop a copy, and the queue survives
  a restart. It never writes the job file; its progress is `~/.download_monitor/copy/<id>.json`.
- **Resumable.** Each file goes to `<name>.dlmon-part` and is renamed when whole, times and mode set from the original;
  a file already there with the same size and date is skipped (an earlier rsync -a or a stopped run goes on); a
  `.dlmon-part` continues from its last byte.
- **A move is verified before anything is deleted**: every source file at the destination with its size, the same
  count and total bytes, the MD5 of the five largest files on both sides. Then the original is renamed aside, a symlink
  to the new place made at the old path, and the original deleted. A failed check keeps the original: FAILED, with the
  reason. On the same disk a move is a rename (plus the symlink).
- **A drive not connected** (source or destination under /Volumes/<name>) is not a failure: QUEUED · DRIVE NOT
  CONNECTED, and it starts by itself when the drive is back, also when it is pulled out in the middle.
- **The window**: the first row DOWNLOAD, COPY AND MOVE · ON | OFF … v5 · TOP · ✕; the two panes (BACK | UP | HOME |
  VOLUMES | HIDDEN, free space, every folder's size measured in the background by `Sizer`, "…" until known, measured
  again when it changes or after two minutes; double click opens); COPY → / MOVE → / ← COPY / ← MOVE between them (a
  MOVE asks first); under them the queue: MOVE/COPY, name, from → to, a hairline, DONE · PERCENT · SPEED · TIME LEFT ·
  READY AT · FILES, the file in hand, PAUSE | CANCEL | FOLDER; then the downloads as before. Every word is a real
  Accessibility button, orange under the mouse, red while pressed. Resizable (980×640 at least), remembers its place.
- **Built only by GitHub Actions** (`.github/workflows/build.yml` on a push to main, release marked Latest); the icon
  DOWNLOAD / COPY MOVE is drawn there by `icon/six_icon.swift` (a copy of STAR_SWIFT icons6) from `icon/six.json`.

Marko's request, 7.9.2026: "build this Flask app, open it in the web browser. We can keep this in
my David menu, Download Monitor. So in any chat, if there are some downloads from this code, I can
see the progress. I want to see progress indicators moving, alive."

## The Swift window: ON / OFF and the ✕ (v2, 19.10.2026)

`/Applications/Download Monitor (Mantra).app` (now Download, Copy and Move (Mantra)) starts with **DOWNLOAD MONITOR  ON  OFF** (MANTRA_MANIFEST swift-apps.md):
ON is lit while it runs; OFF quits it, and the quit stops the server at 8833 as before (downloads started by dlmon.py
keep going). The ✕ at the far right of that row (Marko: *"unify the position of the close button on every application.
It's far upper right corner. There is X to close the dialog in every dialog, same"*) closes the window only; the app and
the server stay on, and a click on its row in the star brings the window back. The delete question has the same ✕
(= Cancel).

## The shape

```
monitor.py         the Flask server: the page, /progress as json, /report, /forget, /quit, /health
dlmon.py           the hands: up, open, hf <repo> (a Hugging Face download that shows here),
                   add (watch a download someone else started), report, done, forget, clear, list
~/.download_monitor/jobs/<id>.json     one file per download: what it is and where to look
~/.download_monitor/logs/              the tqdm logs of downloads dlmon.py hf started
~/.download_monitor/monitor.log        the server's own log
```

The star menu's switch is `apps/download.lua` in MANTRA_STAR: a tick starts the server detached and
opens the page in Chrome; a second tick ends it. Its submenu, while it runs: open the page, clear
the finished rows, delete every row. Nothing runs until the box is ticked.

## Managing the list

Marko, 9.9.2026: "sometimes I don't want to keep the whole history of downloads ... I can check all
and delete all, or check individual and delete entries." Every row has a check box; a bar above the
list has *select all* and *delete selected*, with the count. A selected row that is still downloading
is stopped first, after a question. The same from outside: `POST /forget_many {"ids": [...]}` or
`{"all": true}`, `dlmon.py clear --all` (`clear` alone still takes only the finished rows), and the
star's *Delete every download row…*. The picks live in the page only; a reload forgets them.

## How a download gets on the page

A job file names where to look, and the monitor measures from there, every two seconds:

- **a Hugging Face repo** (`"repo"`): the finished files in `~/.cache/huggingface/hub/<repo>/blobs`, or in the job's own cache folder (`"hub"`, given as `dlmon.py hf <repo> --into <folder>`; the voice engines land in `~/Developer/VOICE_ENGINES/hub` this way since 14.9.2026);
- **a log with tqdm lines** (`"log"`): the file still in flight (huggingface_hub writes it to a
  temporary folder, so only the log knows how far it is), and `DONE` on a line of its own;
- **a report** (`POST /report {id, name, have_mb, want_mb, done}`): any script, in any language,
  saying where it is. `dlmon.py report <id> <have_mb> <want_mb>` does that from a shell.

Speed and ETA are not copied from anywhere: the monitor keeps the last minute of samples per
download and works them out itself, so they are true for every source. When the bytes reach the
size, or the log says DONE, the row turns blue and stays until cleared.

```
python3 dlmon.py hf mlx-community/whisper-medium-mlx        # download it, and show it
python3 dlmon.py add my-model --name "My model" --want-mb 2048 \
    --repo org/name --log ~/somewhere/download.log         # watch one already running
python3 dlmon.py list                                       # the same numbers in the terminal
```

The repo's total size comes from the Hub when the network is there; without it a download still
shows, counting up, and turns done on DONE.

## The control: pause, continue, restart

Marko, 7.9.2026: "make this monitor also the controller of the download process, two ways back and
forth: I can pause any download here and start it, and restart it. Give me the control." And: "I can
pause only the ones which can continue; if they cannot be stitched at the end, then don't."

A download the monitor runs itself is a **worker** the server owns (`dlmon.py _worker`, a
`snapshot_download` with `resume_download=True`, retried when the line breaks). Its partial file
lives in the cache as `blobs/<etag>.incomplete`, so:

- **pause** sends the worker SIGTERM; the bytes stay; the bar turns amber and says PAUSED;
- **continue** starts a worker again and it goes on from the byte it stopped at;
- **restart** deletes the repo's cache folder and starts from zero; the page asks first.

`dlmon.py hf <repo>` starts a download this way. A download some other process started shows on the
page but gets **no pause button**, because stopping it would lose what is down (without resume,
huggingface_hub writes to a temp file at the cache root). `dlmon.py takeover <id>` fixes that: it
stops the process, finds the temp file it had open (lsof), moves it into the cache under the file's
etag as the resumable partial, and starts the monitor's own worker, which continues from that byte.
Measured 7.9.2026: a 314 MB temp file became `…incomplete` and the bar went on at 64%.

The same three actions from a shell: `dlmon.py pause|start|restart <id>`.

## The page

Dark, one bar per download, a soft shine moving across a bar that is alive, amber when paused,
blue and still when it is done, red on an error. Beside each name, its buttons. Under the bars, ALL: the total, and when the last one lands. The bars
glide to each new width, so at two seconds a tick they are always moving.

## Ports on this Mac

8825 the sister (MANTRA CHAT), 8829 the macro recorder, 8831 the mouse, **8833 this**. Never a
second server on another app's port; `/health` first.

## The Swift window (13.10.2026)

`/Applications/Download Monitor (Mantra).app` (v1, `app/App.swift`, `./build.sh`, signed "Mantra Apps") replaces the
star's `apps/download.lua` and the Chrome page: every row with its bar, size, speed and "done at", PAUSE / START /
RESTART for a job dlmon.py runs, FOLDER, select all / delete selected / clear finished. It reads `GET /progress` twice
a second and acts through `POST /control/<id>/<action>` and `/forget_many`; **the server and dlmon.py are unchanged**,
so every session keeps calling them as before. Opening the app starts `monitor.py` if :8833 is down; quitting the app
stops it (`POST /quit`), as the star's second tick did. A download dlmon.py started keeps going (its worker has a
session of its own); a session that needs the monitor starts it again with `dlmon.py up`.
