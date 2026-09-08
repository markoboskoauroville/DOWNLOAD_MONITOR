#!/usr/bin/env python3
"""
dlmon.py, the hands of the Download Monitor: start the page, put a download on
it, run a Hugging Face download that shows there. From any chat, any folder.

    dlmon.py up                         start the monitor (127.0.0.1:8833) if it is not up
    dlmon.py open                       up, and the page in Chrome
    dlmon.py hf <repo> [--name "..."]   download a Hugging Face repo into ~/.cache/huggingface/hub
                                        under the monitor's control: a worker the server owns,
                                        resumable; returns at once, the page shows it
    dlmon.py pause|start|restart <id>   the same buttons as on the page
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

Nothing here needs a key. The repo sizes come from the Hub when the network
is there; a download shows without them too, counting up.
"""

import json
import os
import subprocess
import sys
import time
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


def worker(repo, log):
    """The download itself, as the monitor's child: snapshot_download with
    resume_download=True (the partial file stays in blobs/<etag>.incomplete, so
    a pause, a broken line or a restart of this Mac all continue from there),
    retried when the line breaks. Prints DONE when the whole repo is in."""
    from huggingface_hub import snapshot_download
    for i in range(60):
        try:
            print('DONE', snapshot_download(repo, resume_download=True), flush=True)
            return 0
        except KeyboardInterrupt:
            return 130
        except Exception as e:                                 # noqa: BLE001
            print('RETRY %d: %s' % (i + 1, str(e)[:160]), flush=True)
            time.sleep(15)
    return 1


def hf(repo, name=None, info=None):
    jid = repo.replace('/', '--')
    write_job(jid, name=name or repo.split('/')[-1], repo=repo, want_mb=repo_size_mb(repo), foreign=False, info=info)
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
    hub = os.path.join(HOME, '.cache', 'huggingface', 'hub')
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
        sys.exit(hf(args[0], name, info))
    elif cmd == 'info':
        write_job(args[0], info=' '.join(args[1:]))
    elif cmd == '_worker':
        sys.exit(worker(args[0], args[1]))
    elif cmd in ('pause', 'start', 'restart'):
        if not up():
            sys.exit('monitor did not start')
        print(http('/control/%s/%s' % (args[0], cmd), {}))
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
        for f in os.listdir(JOBS):
            with open(os.path.join(JOBS, f)) as fh:
                if json.load(fh).get('done'):
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
