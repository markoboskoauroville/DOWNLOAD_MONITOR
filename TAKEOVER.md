# TAKEOVER: the Download Monitor on a fresh Mac

1. Python 3.10 at `~/.pyenv/versions/3.10.14/bin/python3` with Flask (`pip install flask`), and
   huggingface_hub for `dlmon.py hf` and repo sizes (`pip install huggingface_hub`).
2. Clone: `git clone https://github.com/markoboskoauroville/DOWNLOAD_MONITOR ~/Developer/DOWNLOAD_MONITOR`
3. The star menu (MANTRA_STAR) has the switch, `apps/download.lua`, pointing at that folder and that
   python. Tick "Download Monitor"; the page opens at http://127.0.0.1:8833.
4. Without the star: `python3 dlmon.py open`. To stop: `python3 dlmon.py down`.
5. State is under `~/.download_monitor/` (jobs, logs); nothing generated is in the repository.
