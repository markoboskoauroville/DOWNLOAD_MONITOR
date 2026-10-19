# TAKEOVER: the Download Monitor on a fresh Mac

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
