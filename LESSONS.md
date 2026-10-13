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
