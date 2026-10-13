# DOWNLOAD_MONITOR — the Download Monitor

**A Flask page at http://127.0.0.1:8833 with live progress bars for every download running on
this Mac that told it, or that it can see. A tick in the David star; from any chat, any folder.**

Marko's request, 7.9.2026: "build this Flask app, open it in the web browser. We can keep this in
my David menu, Download Monitor. So in any chat, if there are some downloads from this code, I can
see the progress. I want to see progress indicators moving, alive."

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
