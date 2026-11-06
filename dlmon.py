#!/usr/bin/env python3
"""
dlmon.py, the hands of Download, Copy and Move (Mantra), once the Download Monitor: start the page, put a download on
it, run a Hugging Face download that shows there. From any chat, any folder.

    dlmon.py up                         start the monitor (127.0.0.1:8833) if it is not up
    dlmon.py open                       up, and the page in Chrome
    dlmon.py hf <repo> [--name "..."] [--into <hub>]   download a Hugging Face repo into ~/.cache/huggingface/hub,
                                        or into another Hugging Face cache folder (the voice engines:
                                        ~/Developer/VOICE_ENGINES/hub, since 14.9.2026)
                                        under the monitor's control: a worker the server owns,
                                        resumable; returns at once, the page shows it
    dlmon.py copy SRC DST [--name "..."] [--info "..."]
    dlmon.py move SRC DST [--name "..."] [--info "..."]
                                        a file or a whole folder into THE ONE QUEUE of Download, Copy and
                                        Move (Mantra): one copy or move at a time, the rest wait in order.
                                        DST is the new full path (DST ending in / = into that folder).
                                        A move deletes the original only after verification (count, bytes,
                                        MD5 of the five largest) and leaves a symlink at the old path.
                                        Marko, 5.11.2026: "Everything is in the queue". Engine: copier.py
    dlmon.py queue                      the copy / move queue in order, with bytes, speed, time left
    dlmon.py cancel <id>                take a copy / move out of the queue (what is copied stays)
    dlmon.py pause|start|restart <id>   the same buttons as on the page (pause holds the copy queue)
    dlmon.py info <id> "text"           the note under the bar: what this file is, why we download
                                        it, what it will do on this Mac, why we need it. **bold**
                                        allowed. hf and add take it as --info "..." too. Marko,
                                        7.9.2026: "I uncollapse and I see what is this file, why we
                                        are downloading it, what it will do on my system"
    dlmon.py takeover <id>              a download some other process started (added with
                                        --repo and --log): its process is stopped, the temp file
                                        it was writing is moved into the cache as the resumable
                                        partial, and the monitor's own worker goes on from there.
                                        Nothing already down is lost
    dlmon.py add <id> --name "..." [--want-mb N] [--repo org/name] [--log file.log] [--file path]
                                        watch a download someone else started: its repo's blobs,
                                        a log with tqdm lines, or (--file) any file growing on
                                        disk, a curl or a browser download. THE RULE, Marko,
                                        8.9.2026: every download on this Mac is registered here
                                        before it starts, so the Download Monitor sees it
    dlmon.py report <id> <have_mb> <want_mb> [--name "..."] [--done]
                                        a download reporting itself (any script can curl this too)
    dlmon.py done <id>                  mark it done
    dlmon.py forget <id> | clear        take one, or every finished one, off the page
    dlmon.py list                       what the page shows, in the terminal
    dlmon.py down                       stop the monitor

  THE VIEWER (v6, 6.11.2026; Marko: "so in the future it's easy for me and for you to show me the folders I need to
  check"). The window Download, Copy and Move (Mantra) is started if it is not running; panes are numbered from 1, left
  to right; --pane N acts on one pane, without it on every pane.
    dlmon.py view open <folder> [<folder> ...] [--mode icons|list]
                                        the panes become these folders, one column each, the window in front
    dlmon.py view add <folder>          one more pane at the right
    dlmon.py view remove                the last pane goes (one always stays)
    dlmon.py view go <folder> [--pane N]   that pane (default: the active one) shows this folder
    dlmon.py view mode icons|list [--pane N]
    dlmon.py view size <48..512> [--pane N]   the icon size (and ICONS)
    dlmon.py view previewmode on|off [--pane N]   PREVIEW: one click on a file opens it full screen
    dlmon.py view select <file>         select it (in the pane showing its folder, else the active pane goes there)
    dlmon.py view preview <file> [--window]   Finder's Quick Look on it, full screen (--window: the small panel);
                                        Up / Down in it go to the file before / after, Escape closes
    dlmon.py view next | prev           the file after / before in that pane (the preview follows), as Down / Up
    dlmon.py view close                 close the preview
    dlmon.py view list                  what every pane shows: folder, mode, size, selection, the preview
    dlmon.py view show|hide <part>      a part of the window (v7, the DASHBOARD row): panes, toolbar, nav, path, views,
                                        status, queue, downloads; or bare (1 PANE)
    dlmon.py view layout bare|full      bare: one pane, only its files; full: every part (and the panes back from bare)
    dlmon.py view parts                 each part on or off
    dlmon.py view info on|off|full [--pane N]   INFO (v8): the whole MediaInfo report under every video, sound and
                                        picture in LIST (full: every field, mediainfo --Full); off: the details line only

Nothing here needs a key. The repo sizes come from the Hub when the network
is there; a download shows without them too, counting up.
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser('~')
DIR = os.path.join(HOME, '.download_monitor')
JOBS = os.path.join(DIR, 'jobs')
LOGS = os.path.join(DIR, 'logs')
URL = 'http://127.0.0.1:8833'
PYTHON = sys.executable
os.makedirs(JOBS, exist_ok=True)
os.makedirs(LOGS, exist_ok=True)


def http(path, data=None, timeout=20):
    req = urllib.request.Request(URL + path, data=json.dumps(data).encode() if data is not None else None,
                                 headers={'Content-Type': 'application/json'}, method='POST' if data is not None else 'GET')
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or '{}')


def alive():
    try:
        return bool(http('/health').get('ok'))
    except Exception:                                          # noqa: BLE001
        return False


def up():
    if alive():
        return True
    log = open(os.path.join(DIR, 'monitor.log'), 'a')
    subprocess.Popen([PYTHON, os.path.join(HERE, 'monitor.py')], stdout=log, stderr=log,
                     start_new_session=True)
    for _ in range(50):
        if alive():
            return True
        time.sleep(0.2)
    return False


def job_path(jid):
    return os.path.join(JOBS, ''.join(c if c.isalnum() or c in '_.-' else '_' for c in jid) + '.json')


def write_job(jid, **fields):
    p = job_path(jid)
    j = {'id': jid, 'started': time.time()}
    if os.path.isfile(p):
        with open(p) as fh:
            j.update(json.load(fh))
    j.update({k: v for k, v in fields.items() if v is not None})
    with open(p, 'w') as fh:
        json.dump(j, fh, indent=1)
    return p


def repo_size_mb(repo):
    try:
        from huggingface_hub import HfApi
        info = HfApi().model_info(repo, files_metadata=True)
        return round(sum((s.size or 0) for s in info.siblings) / 1e6, 1)
    except Exception:                                          # noqa: BLE001
        return None


def flag(args, name, default=None):
    if name in args:
        i = args.index(name)
        v = args[i + 1]
        del args[i:i + 2]
        return v
    return default


def worker(repo, log, hub=None):
    """The download itself, as the monitor's child: snapshot_download with
    resume_download=True (the partial file stays in blobs/<etag>.incomplete, so
    a pause, a broken line or a restart of this Mac all continue from there),
    retried when the line breaks. Prints DONE when the whole repo is in. `hub`
    is the cache folder to land in (the job's "hub"); none means the default."""
    from huggingface_hub import snapshot_download
    for i in range(60):
        try:
            print('DONE', snapshot_download(repo, resume_download=True, cache_dir=hub or None), flush=True)
            return 0
        except KeyboardInterrupt:
            return 130
        except Exception as e:                                 # noqa: BLE001
            print('RETRY %d: %s' % (i + 1, str(e)[:160]), flush=True)
            time.sleep(15)
    return 1


def hf(repo, name=None, info=None, hub=None):
    jid = repo.replace('/', '--')
    if hub:
        hub = os.path.abspath(os.path.expanduser(hub))
        os.makedirs(hub, exist_ok=True)
    write_job(jid, name=name or repo.split('/')[-1], repo=repo, want_mb=repo_size_mb(repo), foreign=False, info=info, hub=hub)
    if not up():
        sys.exit('monitor did not start')
    print(http('/control/%s/start' % jid, {}))
    print('downloading %s, watch %s' % (repo, URL))
    return 0


def takeover(jid):
    """Stop the process that is downloading this job's repo (found by the repo
    name on its command line), move the temp file(s) it was writing (found
    with lsof; huggingface_hub without resume writes to hub/tmpXXXX) into the
    cache as blobs/<etag>.incomplete, and let the monitor's worker continue."""
    from huggingface_hub import HfApi, hf_hub_url, get_hf_file_metadata
    p = job_path(jid)
    with open(p) as fh:
        j = json.load(fh)
    repo = j['repo']
    hub = j.get('hub') or os.path.join(HOME, '.cache', 'huggingface', 'hub')
    rdir = os.path.join(hub, 'models--' + repo.replace('/', '--'))
    pids = [int(x) for x in subprocess.run(['pgrep', '-f', 'snapshot_download\\(.%s' % repo],
                                           capture_output=True, text=True).stdout.split()]
    tmps = []
    for pid in pids:
        out = subprocess.run(['lsof', '-p', str(pid)], capture_output=True, text=True).stdout
        tmps += [l.split()[-1] for l in out.splitlines() if '/hub/tmp' in l]
    tmps = sorted(set(tmps))
    for pid in pids:
        try:
            os.kill(pid, 15)
        except OSError:
            pass
    time.sleep(1.0)
    # which temp file is which file of the repo: by the size in flight, from the log
    files = HfApi().model_info(repo, files_metadata=True).siblings
    have_by_total = {}
    if j.get('log') and os.path.isfile(j['log']):
        import re
        tail = open(j['log'], 'rb').read()[-8000:].decode('utf-8', 'replace')
        for have, want, _s in re.findall(r'([\d.]+[kMG]?)/([\d.]+[kMG]?) \[[\d:]+<[\d:?]+, ([\d.]+[kMG]?B/s)\]', tail):
            have_by_total[want] = have
    unit = {'k': 1e3, 'M': 1e6, 'G': 1e9, '': 1}

    def bytes_of(s):
        import re
        m = re.match(r'([\d.]+)([kMG]?)', s)
        return float(m.group(1)) * unit[m.group(2)]
    moved = []
    os.makedirs(os.path.join(rdir, 'blobs'), exist_ok=True)
    for tmp in tmps:
        size = os.path.getsize(tmp)
        # the repo file whose total matches a bar in the log whose "have" is nearest this temp file
        best = None
        for total, have in have_by_total.items():
            if abs(bytes_of(have) - size) < 60e6:
                cands = [f for f in files if f.size and abs(f.size - bytes_of(total)) < 0.02 * f.size]
                if cands:
                    best = cands[0]
        if best is None:                                          # one file in flight: the biggest not yet in blobs
            done_sizes = [os.path.getsize(os.path.join(rdir, 'blobs', b)) for b in os.listdir(os.path.join(rdir, 'blobs'))]
            cands = [f for f in sorted(files, key=lambda f: -(f.size or 0)) if f.size and f.size > size and f.size not in done_sizes]
            best = cands[0] if cands else None
        if best is None:
            print('could not place %s (%d MB); left where it is' % (tmp, size / 1e6))
            continue
        etag = get_hf_file_metadata(hf_hub_url(repo, best.rfilename)).etag
        dest = os.path.join(rdir, 'blobs', etag + '.incomplete')
        os.replace(tmp, dest)
        moved.append('%s (%d MB of %d) -> %s' % (best.rfilename, size / 1e6, best.size / 1e6, os.path.basename(dest)[:20]))
    j.update({'foreign': False, 'state': 'paused', 'pid': None, 'log': os.path.join(LOGS, jid + '.log')})
    with open(p, 'w') as fh:
        json.dump(j, fh, indent=1)
    print('stopped %s, moved:\n  %s' % (pids, '\n  '.join(moved) or 'nothing'))
    if up():
        print(http('/control/%s/start' % jid, {}))


APP = '/Applications/Download, Copy and Move (Mantra).app'


def app_running():
    return subprocess.run(['pgrep', '-f', APP + '/Contents/MacOS/'], capture_output=True).returncode == 0


def view(args):
    """dlmon.py view ...: a command for the window, through the server (POST /view); the window answers within a second."""
    if not args:
        sys.exit('dlmon.py view open|add|remove|go|mode|size|previewmode|select|preview|next|prev|close|list|show|hide|layout|parts|info')
    sub, args = args[0], list(args[1:])
    pane = flag(args, '--pane')
    mode = flag(args, '--mode')
    window = '--window' in args
    args = [a for a in args if a != '--window']
    if not up():
        sys.exit('monitor did not start')
    if not app_running():
        subprocess.run(['open', '-g', APP])                       # the window itself comes forward for open / preview
        for _ in range(40):
            time.sleep(0.25)
            if http('/view/state').get('age_s') is not None and http('/view/state')['age_s'] < 3:
                break
    if sub == 'parts':
        s = (http('/view/state').get('state') or {}).get('parts')
        if not s:
            sys.exit('the window has not reported yet (is Download, Copy and Move (Mantra) open?)')
        for k in ('panes', 'toolbar', 'nav', 'path', 'views', 'status', 'queue', 'downloads'):
            print('%-10s %s' % (k, 'on' if s.get(k) else 'off'))
        print('%-10s %s' % ('bare', 'on (1 PANE)' if s.get('bare') else 'off'))
        return
    if sub == 'list':
        st = http('/view/state')
        s = st.get('state')
        if not s:
            sys.exit('the window has not reported yet (is Download, Copy and Move (Mantra) open?)')
        for p in s['panes']:
            mark = '*' if p['pane'] == s['active'] else ' '
            print('%s pane %d  %-5s%s%s%s  %d items  %s' % (mark, p['pane'], p['mode'].upper(),
                  ('  icons %d' % p['icon_size']) if p['mode'] == 'icons' else '', '  PREVIEW' if p['preview'] else '',
                  ('  INFO %s' % p['info'].upper()) if p.get('info', 'off') != 'off' else '', p['items'], p['path']))
            for f in p['selected'][:20]:
                print('        selected: %s' % f)
        pv = s.get('preview') or {}
        print('preview: %s' % (('%s%s' % (pv.get('file'), '  (full screen)' if pv.get('full') else '')) if pv.get('open') else 'closed'))
        return
    path = lambda a: os.path.abspath(os.path.expanduser(a))
    c = {'action': sub}
    if pane:
        c['pane'] = int(pane)
    if sub == 'open':
        if not args:
            sys.exit('dlmon.py view open <folder> [<folder> ...]')
        c['folders'] = [path(a) for a in args]
        bad = [f for f in c['folders'] if not os.path.isdir(f)]
        if bad:
            sys.exit('not a folder: ' + ', '.join(bad))
        if mode:
            c['mode'] = mode
    elif sub in ('add', 'go'):
        if len(args) != 1 or not os.path.isdir(path(args[0])):
            sys.exit('dlmon.py view %s <folder>' % sub)
        c['folder'] = path(args[0])
    elif sub == 'mode':
        if not args or args[0] not in ('icons', 'list'):
            sys.exit('dlmon.py view mode icons|list [--pane N]')
        c['mode'] = args[0]
    elif sub == 'size':
        if not args:
            sys.exit('dlmon.py view size <48..512> [--pane N]')
        c['size'] = int(args[0])
    elif sub == 'previewmode':
        c['on'] = not args or args[0] not in ('off', '0', 'no')
    elif sub in ('select', 'preview'):
        if len(args) != 1 or not os.path.exists(path(args[0])):
            sys.exit('dlmon.py view %s <file>' % sub)
        c['file'] = path(args[0])
        c['full'] = not window
    elif sub == 'info':
        if not args or args[0] not in ('on', 'off', 'full'):
            sys.exit('dlmon.py view info on|off|full [--pane N]')
        c['info'] = args[0]
    elif sub in ('show', 'hide'):
        if len(args) != 1:
            sys.exit('dlmon.py view %s panes|toolbar|nav|path|views|status|queue|downloads|bare' % sub)
        c['part'] = args[0]
    elif sub == 'layout':
        if not args or args[0] not in ('bare', 'full'):
            sys.exit('dlmon.py view layout bare|full')
        c['layout'] = args[0]
    elif sub not in ('close', 'remove', 'front', 'next', 'prev'):
        sys.exit('unknown view command %s' % sub)
    seq = http('/view', c)['seq']
    for _ in range(40):
        r = http('/view/done/%d' % seq)
        if r.get('done'):
            print(r['said'])
            return
        time.sleep(0.25)
    sys.exit('sent (%d), but the window did not answer in 10 s' % seq)


def main(argv):
    if not argv:
        print(__doc__)
        return
    cmd, args = argv[0], list(argv[1:])
    if cmd == 'up':
        print('monitor %s at %s' % ('up' if up() else 'did not start', URL))
    elif cmd == 'open':
        up()
        subprocess.run(['open', '-a', 'Google Chrome', URL])
    elif cmd == 'down':
        try:
            http('/quit', {})
            print('monitor stopped')
        except Exception:                                      # noqa: BLE001
            print('monitor was not up')
    elif cmd == 'hf':
        name = flag(args, '--name')
        info = flag(args, '--info')
        into = flag(args, '--into')
        sys.exit(hf(args[0], name, info, into))
    elif cmd == 'info':
        write_job(args[0], info=' '.join(args[1:]))
    elif cmd == '_worker':
        sys.exit(worker(args[0], args[1], args[2] if len(args) > 2 else None))
    elif cmd in ('copy', 'move'):
        name = flag(args, '--name')
        info = flag(args, '--info')
        if len(args) != 2:
            sys.exit('dlmon.py %s SRC DST' % cmd)
        if not up():
            sys.exit('monitor did not start')
        try:
            r = http('/copy', {'mode': cmd, 'src': os.path.abspath(os.path.expanduser(args[0])),
                               'dst': (os.path.abspath(os.path.expanduser(args[1])) + ('/' if args[1].endswith('/') else '')),
                               'name': name, 'info': info}, timeout=600)
        except urllib.error.HTTPError as e:
            sys.exit('%s: %s' % (cmd, json.loads(e.read().decode() or '{}').get('error', e)))
        print('%s queued: %s  (watch it in Download, Copy and Move (Mantra), or dlmon.py queue)' % (cmd, ', '.join(r['ids'])))
    elif cmd == 'queue':
        if not up():
            sys.exit('monitor did not start')
        rows = [j for j in http('/progress')['jobs'] if j.get('kind') in ('copy', 'move')]
        for j in sorted(rows, key=lambda j: (j.get('queue_pos') is None, j.get('queue_pos') or 0, -(j.get('order') or 0))):
            pos = ('#%d' % j['queue_pos']) if j.get('queue_pos') else '  '
            sp = ('  %.1f MB/s' % j['speed_mbs']) if j.get('speed_mbs') else ''
            left = ('  %d:%02d:%02d left, ready at %s' % (j['eta_s'] // 3600, j['eta_s'] % 3600 // 60, j['eta_s'] % 60, j['eta_at'])) if j.get('eta_s') else ''
            print('%s %-4s %-20s %5.1f%%  %.2f/%.2f GB  %d/%d files%s%s%s' % (
                pos, j['kind'].upper(), (j.get('phase') or j['state']).upper()[:20], j['pct'] or 0, j['have_mb'] / 1e3,
                j['want_mb'] / 1e3, j.get('files_done') or 0, j.get('files_total') or 0, sp, left,
                ('  ' + j['error']) if j.get('error') else ''))
            print('     %s -> %s%s%s' % (j['src'], j['dst'], ('\n     now: ' + j['current']) if j.get('current') else '',
                                    ('\n     ' + j['note']) if j.get('note') and j['state'] != 'done' else ''))
    elif cmd == 'cancel':
        if not up():
            sys.exit('monitor did not start')
        print(http('/control/%s/cancel' % args[0], {}))
    elif cmd in ('pause', 'start', 'restart'):
        if not up():
            sys.exit('monitor did not start')
        print(http('/control/%s/%s' % (args[0], cmd), {}))
    elif cmd == 'view':
        view(args)
    elif cmd == 'takeover':
        takeover(args[0])
    elif cmd == 'add':
        jid = args[0]
        name = flag(args, '--name', jid)
        want = flag(args, '--want-mb')
        repo = flag(args, '--repo')
        log = flag(args, '--log')
        path = flag(args, '--file')                # a plain download: the file growing on disk
        info = flag(args, '--info')
        if want is None and repo:
            want = repo_size_mb(repo)
        p = write_job(jid, name=name, want_mb=float(want) if want else None, repo=repo,
                      log=os.path.abspath(log) if log else None, file=os.path.abspath(path) if path else None,
                      foreign=bool(log or path), info=info)
        up()
        print('watching %s (%s)' % (jid, p))
    elif cmd == 'report':
        jid, have, want = args[0], float(args[1]), float(args[2])
        name = flag(args, '--name')
        info = flag(args, '--info')
        write_job(jid, name=name, have_mb=have, want_mb=want, done='--done' in args, info=info)
        up()
    elif cmd == 'done':
        write_job(args[0], done=True, done_at=time.time())
    elif cmd == 'forget':
        try:
            os.remove(job_path(args[0]))
        except OSError:
            pass
    elif cmd == 'clear':
        # 'clear' takes the finished rows; 'clear --all' every row, stopping what still runs
        everything = '--all' in args
        if everything and alive():
            http('/forget_many', {'all': True})
        else:
            for f in os.listdir(JOBS):
                with open(os.path.join(JOBS, f)) as fh:
                    if everything or json.load(fh).get('done'):
                        os.remove(os.path.join(JOBS, f))
    elif cmd == 'list':
        if not up():
            sys.exit('monitor did not start')
        p = http('/progress')
        for j in p['jobs']:
            left = ('%d:%02d left (%s)' % (j['eta_s'] // 60, j['eta_s'] % 60, j['eta_at'])) if j.get('eta_s') else j['state']
            print('%-26s %5.1f%%  %6.0f/%6.0f MB  %s' % (j['name'], j['pct'] or 0, j['have_mb'], j['want_mb'],
                                                       'done' if j['done'] else left))
        if p.get('last_eta_at'):
            print('%-26s %5.1f%%  last one at %s' % ('ALL', p['total_pct'], p['last_eta_at']))
    else:
        sys.exit('unknown command %s' % cmd)


if __name__ == '__main__':
    main(sys.argv[1:])
