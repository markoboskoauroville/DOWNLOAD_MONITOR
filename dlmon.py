#!/usr/bin/env python3
"""
dlmon.py, the hands of the Download Monitor: start the page, put a download on
it, run a Hugging Face download that shows there. From any chat, any folder.

    dlmon.py up                         start the monitor (127.0.0.1:8833) if it is not up
    dlmon.py open                       up, and the page in Chrome
    dlmon.py hf <repo> [--name "..."]   download a Hugging Face repo (snapshot_download) into
                                        ~/.cache/huggingface/hub, showing on the page; blocks
                                        until done, so run it in the background or its own tab
    dlmon.py add <id> --name "..." [--want-mb N] [--repo org/name] [--log file.log]
                                        watch a download someone else started: its repo's blobs,
                                        and/or a log with tqdm lines
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


def http(path, data=None, timeout=3):
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


def hf(repo, name=None):
    """snapshot_download with a tqdm log the monitor reads, and a job file."""
    jid = repo.replace('/', '--')
    log = os.path.join(LOGS, jid + '.log')
    write_job(jid, name=name or repo.split('/')[-1], repo=repo, log=log, want_mb=repo_size_mb(repo))
    up()
    print('downloading %s, watch %s' % (repo, URL))
    # resume_download: the part already down stays in blobs/<sha>.incomplete and a
    # broken connection (this line drops one every hour or so) continues from there
    code = ('import time, sys\nfrom huggingface_hub import snapshot_download\n'
            'for i in range(40):\n'
            '    try:\n'
            '        print("DONE", snapshot_download(%r, resume_download=True), flush=True); sys.exit(0)\n'
            '    except SystemExit: raise\n'
            '    except Exception as e:\n'
            '        print("RETRY %%d: %%s" %% (i + 1, str(e)[:160]), flush=True); time.sleep(15)\n'
            'sys.exit(1)\n') % repo
    with open(log, 'a') as fh:
        r = subprocess.run([PYTHON, '-c', code], stdout=fh, stderr=subprocess.STDOUT)
    if r.returncode == 0:
        write_job(jid, done=True, done_at=time.time())
        print('done: %s' % repo)
    else:
        print('failed: see %s' % log)
    return r.returncode


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
        sys.exit(hf(args[0], name))
    elif cmd == 'add':
        jid = args[0]
        name = flag(args, '--name', jid)
        want = flag(args, '--want-mb')
        repo = flag(args, '--repo')
        log = flag(args, '--log')
        if want is None and repo:
            want = repo_size_mb(repo)
        p = write_job(jid, name=name, want_mb=float(want) if want else None, repo=repo,
                      log=os.path.abspath(log) if log else None)
        up()
        print('watching %s (%s)' % (jid, p))
    elif cmd == 'report':
        jid, have, want = args[0], float(args[1]), float(args[2])
        name = flag(args, '--name')
        write_job(jid, name=name, have_mb=have, want_mb=want, done='--done' in args)
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
            print('%-24s %5.1f%%  %6.0f/%6.0f MB  %s' % (j['name'], j['pct'] or 0, j['have_mb'], j['want_mb'],
                                                       'done' if j['done'] else ('%d s left' % j['eta_s'] if j['eta_s'] else '')))
    else:
        sys.exit('unknown command %s' % cmd)


if __name__ == '__main__':
    main(sys.argv[1:])
