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


## 6.11.2026: a DASHBOARD row that turns every part of the window on and off

"please, now at the top there are buttons: On/Off, V6 Top, and there is a man space. We need to have different parts of the interface there to turn them on and off. I can even have a bare-bone version with only one folder, so whatever is shown on the screen can be turned off and on. Make a top section, let's call it the dashboard. It should be one line, one row, grayed out if it's not active, and green with softif buttons to disable parts of the user interface"

**Status:** saved first (6.11.2026).
**Status (6.11.2026, ~03:15):** v7 built by GitHub (run 42148103596, green; release v7 Latest), installed and signed
"Mantra Apps", running. The first row is the DASHBOARD, one line: ON | OFF, then PANES | TOOLBAR | NAV | PATH | VIEWS |
STATUS | QUEUE | DOWNLOADS · 1 PANE (green = shown, grey = hidden), then v7 TOP ✕. 1 PANE is the bare bone (one pane,
only its files) and gives everything back when pressed again; every choice is remembered. Python: `dlmon.py view
show|hide <part>`, `view layout bare|full`, `view parts`. Checked by window captures: full, bare bone, and TOOLBAR /
PATH / QUEUE off. Left in FULL with HIR_96 (left) and HIR_98 (right) in LIST. Marko to try the words by hand.



## 6.11.2026: every media detail of every file, from MediaInfo, in the list view

"let's continue. Update our app. Download, copy, move Because this is mostly used for media work, I need all media details. Find the repository media info and let it read all possible media info inside the file. In list view, I can see all this info for each file."

**Status:** saved first (6.11.2026).
**Status (6.11.2026, ~03:45):** v8 to v10 built by GitHub (v10: run 42152019244, green; release v10 Latest), installed and
signed "Mantra Apps". MediaArea's MediaInfo 26.05 (github.com/MediaArea/MediaInfo, its own universal Mac command line,
needs only system libraries) is inside the app, put there by the workflow. Follow-ups the same night, Marko: "my media
info wants to be only in one line ... without report. I need to have a horizontal scroller ... I want to have each file
on one line", "the most important field is time ... Then resolution, then frame per second, then bitrate, and then
codec", and "when I'm previewing my files with spacebar, I need to be able to jump between panes". So LIST (v10): one
line per file, nothing wraps, the pane scrolls sideways; columns NAME · TIME · RES · FPS · BIT RATE · CODEC · SIZE ·
DEPTH · COLOUR · SCAN · AUDIO · TIMECODE · WRITTEN BY · TRACKS · KIND · MODIFIED, each as wide as its longest value, a
media column empty for the whole folder left out, every title sorts. In the preview ↑ ↓ = file, ← → = the pane at the
left / right plays its file; a click in another pane takes the preview there (`dlmon.py view left|right`). Checked by
window captures (two panes, one pane wide) and the jump from Python. Marko to try ← → by hand in the full-screen preview.

## 6.11.2026 (~04:00): solo on the DASHBOARD

"please add one more button at the top of all the pins. Call it Barre. It means only pins are left. Also, one trick: second press on any part of the interface switcher dashboard. It's actually soloing that part. So we have solo in that sense. You don't need to build Barre because Barre can be anything. First press is disabling that part. Second press is soloing that part"

**Status:** saved first (6.11.2026). Read as: "pins" = panes, "Barre" = bare; no new button, solo of PANES is the bare one.
**Status (6.11.2026, ~04:15):** v11 built by GitHub (run 42152482750, green), installed, signed "Mantra Apps". Each
DASHBOARD word: first press hides its part, second press SOLOs it (the word reads SOLO …, green; NAV/PATH/VIEWS/
TOOLBAR/STATUS keep the panes under them), third press brings everything back as it was. No BARE button: SOLO PANES is
it. `dlmon.py view solo <part>|off` and `view press <part>`. Checked from Python (hide -> solo -> back for PATH, QUEUE,
VIEWS) and by a window capture (SOLO VIEWS). Marko to try it by hand.


## 6.11.2026: a filter text box next to NAME in every pane

"one more modification: next to the name in the panes where we list the files, add a text box. The text box is a simple filter. Whatever is in the text box in the pane just shows that file with the same pattern. That's easy"

**Status:** saved first (6.11.2026).
**Status (6.11.2026, ~03:55):** v12 built (run 42152857156 green, Latest), installed: the FILTER box sits next to NAME in
LIST (and above the grid in ICONS); every word typed must be in the name, any case, `*` and `?` allowed, Escape or ✕
clears, not remembered; `dlmon.py view filter [words] [--pane N]`; checked from Python (9x16 shows 4 of 8).

## 6.11.2026: the line between panes can be dragged

"for the line between panes, please let me drag it left, right, whatever is needed"

**Status:** v13 (Panes.share, PaneDivider in Panes.swift): grab the line, drag left or right, the two panes beside it give
and take width (each keeps 200 pt), remembered; double click shares equally again; `dlmon.py view share 30 70`.


## 6.11.2026: the title bar becomes the status window with every pane's full path; the panes button counts 1 to 5

"the text at the top of this window, I don't need it. I know that's the Download, Copy and Move application at the top. We're going to use it as a status window at the top. You need to write the full path of everything that's in the paths. That means there will be a full path, then a pipe, then a full path, and so on, depending on how many paths we have in our pain dashboard part, it needs to show one pain when there is only one pain. I click again, then there will be two pains, then I can click again, and until five. Five is the maximum number of pains. To quickly jump to the number of pains, I just long press and the dialog pops up, and I just choose my number"

**Status:** saved first (6.11.2026).

**Status (6.11.2026, ~04:00):** v13 (drag the line between panes) and v14 (status window at the top with every pane's full path
parted by pipes; the panes word counts 1 to 5 on a click, a long press asks the number; `dlmon.py view count N`) built by
GitHub, installed.

## 6.11.2026: right-click on a column title: choose and reorder the columns in a dialog

"right-click on any pane column give me option to disable some of the columns and also to reorder them. So, new dialog opening up for reordering, enabling disabling certain columns"

**Status:** saved first (6.11.2026).
**Status (6.11.2026, ~04:05):** v15 built by GitHub (run 42153576474 green, Latest): right-click a column title or a file =
every column with a tick, "Columns…" opens the dialog (ON/OFF, drag, ▲ ▼, RESET, DONE), one choice for all panes,
remembered; `dlmon.py view columns [reset|dialog|close|key ...]`.

## 6.11.2026: no title bar until the mouse is at the top; the whole path fits, its end first

"you can further reduce the user interface size by removing the top bar with all these buttons from iOS and macOS: red, yellow, green. When I hover over my parts at the top, then it shows up You need to fit the whole path at the top. Put the three dots for the beginning of the path, and then show as much as you can from the end. The end is the most important; the beginning is not so important"

**Status:** saved first (6.11.2026).
**Status (6.11.2026, ~04:10):** v16 built (run 42153732774 green, Latest): no title bar, the red/yellow/green buttons appear while the
mouse is in the top 30 pt, the top line drags the window; the paths line fits every pane's full path, each cut at its
beginning with … and the end kept (short paths keep their room).

## 6.11.2026: the preview never has black bars

"please, when you invite preview, it can be in full screen, but never with the black bars on the left and right. Black bars are not an option. Only if I click on this preview window as it is in the macOS full screen, then it goes with these black bars. But I don't want to see black bars when I right-click on any file"

**Status:** saved first (6.11.2026).
**Status (6.11.2026, ~04:20):** v17 (the preview is never macOS full screen: the panel gets the shape of the video, so a 9x16 is a tall
window with no bars, refitted for every file; right-click a file = Preview) installed and checked by a window list
(743 x 1346 for a 9x16). v18/v19: the bare title bar; the paths line was hidden under the system title bar, being fixed.

## 6.11.2026: Command-I = information about the file

"I wanted to know what works in this application. Spacebar is preview, as we said, never with the black bars. Also, Command-I is showing information about the file at the top. It shows the full path under that, Media Info Report, and before all that, Date Created, Date Modified"

**Status:** saved first (6.11.2026). Plan: Command-I opens (and closes) an Info window that follows the selection: Date Created, Date Modified, the full path, then the MediaInfo report (FULL for every field).
**Status (6.11.2026, ~04:25):** v20 built by GitHub (run 42154953168 green, Latest), installed and signed. Command-I (or `dlmon.py view
info [file|close|full|normal]`) opens the Info window, which follows the selection of the pane you work in: DATE
CREATED, DATE MODIFIED, SIZE, FULL PATH, then MEDIA INFO REPORT (FULL = every field); Command-I or Escape closes it.
The title bar is gone: the paths of all panes sit in the title row, each cut at the beginning with … and its end kept
(checked by window capture), the red/yellow/green buttons show while the mouse is in the top 30 pt. Marko to try.

## 6.11.2026: live size and write speed on a file still being written

"now let's upgrade our download copy and move mantra while the file is written on the disk, until it's finished on the left side, it means the file name needs to be updated to accommodate this. It's just in real time showing me how many bytes are coming and what the size of the file is at the moment, and also in parentheses, the speed of writing"

**Status:** saved first (6.11.2026). Plan: a file that is still growing in a pane shows its name with the live size and, in parentheses, the write speed (bytes per second), updated in real time, until it stops growing; then the plain name again.
**Status (6.11.2026):** v21 written (Panes.swift: a 1-second tick per pane finds files that grow; the line shows `name   size · exact bytes (speed/s)` in amber, in LIST and ICONS; three quiet seconds and the plain name returns). Pushed; GitHub compiles it, then installed and tested with a growing test file.
