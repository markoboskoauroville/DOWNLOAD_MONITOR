# LESSONS — Download Monitor

1. **huggingface_hub 0.20 downloads into a temporary folder at the cache root**, not into `blobs/`,
   and moves the file over when it is complete. So the blobs say how much is *finished*, and only
   the tqdm line in the downloader's log says how far the file *in flight* is. A monitor needs both:
   blobs plus the log's current file. (A newer hub writes `<blob>.incomplete` in blobs instead.)

2. **Do not trust one file's presence as "downloaded".** A repo with several safetensors has some of
   them long before the last; the Hub's file list against the snapshot folder is the test.

3. **Measure speed yourself.** tqdm's speed is per file and per process; four downloads share one
   line. A minute of (time, megabytes) samples per job gives a speed and an ETA that are true for
   any source, a report from a shell script included.

4. **A shared line finishes together.** Four downloads at 0.5 MB/s in total do not finish at their
   own ETAs: when the small ones land, the big ones speed up. The total bytes over the total speed
   is the honest estimate for "when is everything here".

5. **A temp file can become a resumable partial.** huggingface_hub without `resume_download` writes
   the file in flight to `hub/tmpXXXX`; with it, to `blobs/<etag>.incomplete`, and continues from that
   size with a Range header. The bytes are the same bytes. So a download started the first way is
   taken over by stopping it, moving its temp file (found with `lsof -p`) to
   `blobs/<etag>.incomplete` (the etag from `get_hf_file_metadata`), and starting again with resume.
   When two files were in flight at once, the log's tqdm lines (one per file, keyed by total) say
   which temp file is which.

6. **Only offer pause where continue is possible.** Marko's rule: a pause that throws bytes away is
   not a pause. A download the monitor does not own shows no button until it is taken over.

- (13.10.2026) To test the window without stopping the server, close it with `pkill -9 -x DownloadMonitor`: a normal quit
  sends POST /quit.

- (5.11.2026) **Path Finder cannot be scripted** (`sdef` empty), so file moves got their own engine here. **/usr/bin/rsync
  is openrsync** on this Mac (no `--info=progress2`), so the copier is Python: 8 MB chunks, fsync, `.dlmon-part`, rename.
- (5.11.2026) **The copier must not die with the window.** Quitting the app POSTs /quit to the server; the copier is a
  separate detached process (start_new_session) and the server restarts it from the job files. The runner never writes
  the job file (the server and dlmon.py own it) and keys its status by a `run` id, so a retry forgets an old FAILED.
- (5.11.2026) **APFS clones make a folder bigger on an external drive.** ~/Music/SantoshiKoncert was 242 GB by `du` but
  360 GB of files (Ableton "Copy Project" makes clones that share blocks); the Seagate stores every byte. Check the
  logical size (the queue's total) against the free space, not du. The copier checks the room before it starts.
- (5.11.2026) **Resume by size and date** trusts the destination: a file with the same size and modification time is
  skipped. The move's MD5 covers only the five largest files, so the check is count + bytes + sample, not every byte.
- (5.11.2026) **A server-side helper that decides whether to start the copier must skip jobs already finished but not
  yet written down**; first version waited on a finished head and never started the next job.
- (5.11.2026) To test the window without stopping the server: `pkill -9 -x DownloadCopyMove` (a normal quit sends /quit).
- (6.11.2026) **A SwiftUI Table on macOS cuts long names** (one line per row, "…"), against never-cut-text: LIST is a
  List with its own column titles as buttons, and the name `fixedSize(horizontal: false, vertical: true)` wraps.
- (6.11.2026) **The type checker gives up on a long modifier chain** inside ForEach in a LazyVGrid ("unable to type-check
  this expression in reasonable time"): build the cell in a function in small `let` steps.
- (6.11.2026) **QLPreviewPanel full screen**: `enterFullScreenMode(screen, withOptions: nil)` after the panel is shown;
  to close, `exitFullScreenMode` then `orderOut` again after the exit animation (0.4 s, 0.9 s): an orderOut at once left
  the small panel playing. With one item in the data source the arrows reach `previewPanel(_:handle:)`, so ↑ ↓ move
  the pane's selection and `reloadData()` follows. The data source is set directly on the shared panel (no responder
  chain controller); it works.
- (6.11.2026) **A pane method called `open` hides Darwin's `open(path, O_EVTONLY)`** inside the class: named openItems.
- (6.11.2026) **Python to a SwiftUI app without Apple Events**: the server keeps numbered commands, the window polls
  them, answers each by number, and posts its state; a fresh window takes only the last 20 seconds of commands.
- (6.11.2026) **A part that hides must give back its room**: the panes and the queue sit in a VSplitView only while both
  are shown, else the one left takes the whole height (`maxHeight: .infinity`); DOWNLOADS alone counts only while there
  is a download, or it held an empty half of the window.
- (6.11.2026) **A bare-bone layout keeps the way back**: entering it stores the parts and the pane folders
  (`dash.before`, `dash.before.paths`); leaving puts them back, with the folder the one pane showed as pane 1.


## 6.11.2026: media details

- Marko wants every file on ONE line with a horizontal scroller, not a wrapped details line and not a report under it
  (v8/v9 wrapped; v10 is the answer). Field order for him: time, resolution, fps, bit rate, codec.
- A SwiftUI List scrolls sideways inside ScrollView(.horizontal) when it is given a fixed width and the height of the
  GeometryReader; column widths are measured with NSString.size(withAttributes:) so nothing is cut.
- MediaArea's Mac CLI dmg holds a self-contained universal `mediainfo`: no dylib bundling needed.
