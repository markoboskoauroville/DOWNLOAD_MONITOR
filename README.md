# DOWNLOAD_MONITOR — the Download Monitor

**A Flask page at http://127.0.0.1:8833 with live progress bars for every download running on
this Mac that told it, or that it can see. A tick in the David star; from any chat, any folder.**

Marko's request, 7.9.2026: "build this Flask app, open it in the web browser. We can keep this in
my David menu, Download Monitor. So in any chat, if there are some downloads from this code, I can
see the progress. I want to see progress indicators moving, alive."

## The shape

    monitor.py         the Flask server: the page, /progress as json, /report, /forget, /quit, /health
    dlmon.py           the hands: up, open, hf <repo> (a Hugging Face download that shows here),
                       add (watch a download someone else started), report, done, forget, clear, list
    ~/.download_monitor/jobs/<id>.json     one file per download: what it is and where to look
    ~/.download_monitor/logs/              the tqdm logs of downloads dlmon.py hf started
    ~/.download_monitor/monitor.log        the server's own log

The star menu's switch is `apps/download.lua` in MANTRA_STAR: a tick starts the server detached and
opens the page in Chrome; a second tick ends it. Its submenu, while it runs: open the page, clear
the finished rows. Nothing runs until the box is ticked.

## How a download gets on the page

A job file names where to look, and the monitor measures from there, every two seconds:

- **a Hugging Face repo** (`"repo"`): the finished files in `~/.cache/huggingface/hub/<repo>/blobs`;
- **a log with tqdm lines** (`"log"`): the file still in flight (huggingface_hub writes it to a
  temporary folder, so only the log knows how far it is), and `DONE` on a line of its own;
- **a report** (`POST /report {id, name, have_mb, want_mb, done}`): any script, in any language,
  saying where it is. `dlmon.py report <id> <have_mb> <want_mb>` does that from a shell.

Speed and ETA are not copied from anywhere: the monitor keeps the last minute of samples per
download and works them out itself, so they are true for every source. When the bytes reach the
size, or the log says DONE, the row turns blue and stays until cleared.

    python3 dlmon.py hf mlx-community/whisper-medium-mlx        # download it, and show it
    python3 dlmon.py add my-model --name "My model" --want-mb 2048 \
        --repo org/name --log ~/somewhere/download.log         # watch one already running
    python3 dlmon.py list                                       # the same numbers in the terminal

The repo's total size comes from the Hub when the network is there; without it a download still
shows, counting up, and turns done on DONE.

## The page

Dark, one bar per download, a soft shine moving across a bar that is alive, blue and still when it
is done, red on an error. Under the bars, ALL: the total, and when the last one lands. The bars
glide to each new width, so at two seconds a tick they are always moving.

## Ports on this Mac

8825 the sister (MANTRA CHAT), 8829 the macro recorder, 8831 the mouse, **8833 this**. Never a
second server on another app's port; `/health` first.
