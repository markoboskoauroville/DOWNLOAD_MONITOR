# Download Monitor: momentary updates

## 13.10.2026: from Lua to Swift
> "go through my start menu. If any app is not a Swift app, you need to convert it to a Swift app. We are quitting the Lua, no more Lua, only Swift. And everything will be in the application folder, name of the app in parentheses. Mantra"

MANTRA_STAR apps/download.lua (the star's switch) and the Chrome page become "Download Monitor (Mantra).app", a native
window. The server (monitor.py, :8833) and dlmon.py stay exactly as they are: every session calls them.
**Status:** built v1 13.10.2026; checked against the running server (153 rows). Marko to try.

## 19.10.2026: ON / OFF at the top of the window

> When I select any of the apps, the user interface opens up. In the top of every user interface, there will now be an on/off switch ... If I say on, I close it's on ... When I just switch the check mark, and that's how I activate it. This is gone. Let's work like this. This is the workflow now.

(MANTRA_MANIFEST modules/swift-apps.md, "ON / OFF at the top of every window"; the star, STAR_SWIFT v5, now only opens apps.)

1. The first row of the main window is ON / OFF in the window's own style, named after what it switches. ON is lit while
   the app runs; OFF stops the engine cleanly and quits the app. — **Status:** built 19.10.2026, v2: DOWNLOAD MONITOR
   ON  OFF; OFF = NSApp.terminate, whose applicationWillTerminate POSTs /quit to the server (as the quit always did).
   Checked by screenshot (the app was not running: opened once, then closed with pkill -9 so the server, which was
   running, stayed up). Marko to try OFF.
2. Closing the window leaves the app ON; the reopen (a click in the star or the Dock) shows the window again; `--login`
   still starts without a window. — **Status:** built 19.10.2026, v2 (it already stayed on without its window; the
   reopen now brings it back; it has no --login).

> please unify the position of the close button on every application. It's far upper right corner. There is X to close the dialog in every dialog, same.

3. An ✕ at the window's far upper-right corner, on the ON / OFF row (ON / OFF at the left, ✕ at the right), grey; it
   closes the window only, the app stays ON. Every other dialog the app opens gets the same ✕. The title bar and its
   traffic lights stay as they are. — **Status:** built 19.10.2026, v2: ✕ (xmark, grey, 30×30) at the far right of
   the ON / OFF row, performClose; the delete question (NSAlert) has a 28×28 ✕ in its top-right corner = Cancel (not
   seen on screen: it needs a click). Marko to try ✕ and the delete ✕.

## 31.10.2026: ON, OFF and TOP in every application

> Please go to all the interface of my applications. Each needs to have the same user interface elements. On, off and top. Please build it in every application.

The first row as MANTRA_MANIFEST swift-apps.md "The first row of every app: ON OFF … TOP ✕": ON, OFF at the left, TOP
(green: the window above every other, UserDefaults `onTop`, applied at launch) beside ✕ at the right; each an
Accessibility button (`off`, `top`, `close`).
**Status:** done 31.10.2026 in v3: TOP left of ✕ (green = `.floating`, `onTop`, applied at launch); OFF, TOP, ✕ carry
Accessibility identifiers. No download running (speed 0, no row running), so the v2 copy was quit through its menu's
Quit and v3 reopened with `--login`; the server came back on :8833 with its 458 rows. Checked by a capture of the window
(640 pt, its only width) and `top` found through Accessibility.

## 5.11.2026

"please style the download monitor mantra icon to look exactly the same as VM remote. Make the text different. Download monitor full, two-line text without abbreviations, and just add an orange dot at the end or better say, square. It's the entry point in the terminal"
**Status:** saved first.
**Status (5.11.2026, ~12:40):** v4 built by GitHub (first workflow run), installed, running (page 200). Icon: the VM REMOTE terminal tile, DOWNLOAD / MONITOR, orange square cursor (STAR_SWIFT icons6 symbol terminal:#FF9F0A). The repo's branch renamed master → main (one branch rule).

## 5.11.2026 (evening): Download, Copy and Move

"Please write in the manifest any file movement I'm asking you to do. We need to use Pathfinder so I can monitor progress."

"if there is no scripting support, we need to have that. We need to use our Download app to be Download and Copy Move app. Rename it and copy the system of Pathfinder to to show what's moving and the speed and put everything in the queue. We are not moving files multiple at the same time. Everything is in the queue, and in my download copy move application, I can see what's going on. And for engine behind, you choose anything what you like."

**Status:** saved first.

"This app will also have 2 windows, left and right, for copying between 2 locations manually. And it needs to always next to every folder, right, which is now, as you can see, our application Pathfinder doesn't do. Folder size— what is the folder size?"

**Status:** saved first (5.11.2026, evening).
**Status (5.11.2026, ~19:25):** v5 built by GitHub (run 42082689116, green), installed as `/Applications/Download, Copy and
Move (Mantra).app` (the old-named app removed), running. Two panes LEFT / RIGHT with BACK | UP | HOME | VOLUMES | HIDDEN,
free space, every folder's size (background, "…" until known); COPY → / MOVE → / ← COPY / ← MOVE into the one queue.
Engine copier.py: one at a time, resumable, a move verified (count, bytes, MD5 of the five largest) before the original
goes, symlink left; a drive not connected waits. Started: SantoshiKoncert (360 GB of files) then five folders to
/Volumes/Video_Marko/From MacBook (MANTRA_MANIFEST file-moves.md). Checked by a capture of the window. Marko to try the
panes and the buttons.

## 6.11.2026: a file viewer with many panes, Quick Look, controlled from Python

"now there is a chance to update my application downloader copier to also be a file viewer, and the same command can be executed inside my application. You're going to close Pathfinder. Update my application, download that and copier, and it can open any number of folders at the same time, creating many vertical windows. Now, for this case, only two, and I can double-click any file, and it will open up in its viewer now you can create this code so you can through the Python API control it. Open any folder and list the folders I need to watch with multiple views: icon view and list view. If I'm in icon view, I have a slider at the top to enlarge icons, or a list view with all details. Please update it so in the future it's easy for me and for you to show me the folders I need to check, and then I'll check everything and let you know what's going on please also use the previewer mechanism from the Mac's itself. There will be a preview mode. A preview mode means that when I click on one file, the preview will open in full screen. When it's finished, I just press the down arrow or up arrow to go through the three files, and it should play those files. Then I press Escape, and the preview window will exit. That's exactly the same preview window in Finder, which is activated with the spacebar"

**Status:** saved first (6.11.2026). Path Finder closed.
**Status (6.11.2026, ~02:15):** v6 built by GitHub (run 42142202400, green; release v6 Latest), installed and signed
"Mantra Apps", running. Any number of panes as columns (ADD PANE | REMOVE PANE), each with ICONS (real thumbnails, a
frame of every video, SIZE slider) | LIST (NAME SIZE KIND MODIFIED TIME, sortable by a click on the title, names wrap)
| PREVIEW; double click opens a folder or the file in its app; Space = Finder's Quick Look; PREVIEW on: one click opens
it full screen, ↓ ↑ go through the files of that pane and it plays, Escape closes. COPY → / MOVE → from the active pane
to the one at its right (← to the left). Python: `dlmon.py view open|add|go|mode|size|previewmode|select|preview|next|
prev|close|list`. Checked by window captures: LIST and ICONS of HIR_96 | HIR_98, preview full screen and next/close
from Python. Left showing HIR_96 (left) and HIR_98 (right) in LIST. Marko to try the arrow keys and Escape by hand in
the full-screen preview.

