#!/usr/bin/env python3
"""
copier.py, the engine behind COPY and MOVE in Download, Copy and Move (Mantra).

Marko, 5.11.2026: "copy the system of Pathfinder to show what's moving and the speed and put everything in
the queue. We are not moving files multiple at the same time. Everything is in the queue."

ONE QUEUE, ONE AT A TIME. A copy or move is a job file in ~/.download_monitor/jobs/<id>.json with
"kind": "copy" | "move", "src", "dst", "order" (when it was queued) and "state":
    queued     waits its turn (the head of the queue is the one running)
    paused     holds the queue at its place: nothing after it starts until START or CANCEL
    cancelled  taken out of the queue; what was copied stays at the destination
    done       copied (and for a move: verified, the original gone, a symlink left in its place)
    failed     stopped with a reason; START puts it back in the queue and it resumes
A drive that is not mounted (the source or the destination under /Volumes/<name>) is not a failure: the job stays
QUEUED, "drive not connected", and the queue goes on by itself when the drive is back (pulled out mid-copy too).
This runner is ONE process (pid in ~/.download_monitor/copier.pid), detached from the server, so quitting the window
or restarting the server does not stop a copy. It takes the first job in order; when none is left it exits. The
server starts it again whenever the queue has work (monitor.py ensure_copier).

THE RUNNER NEVER WRITES THE JOB FILE (the server and dlmon.py own it). It writes its progress to
~/.download_monitor/copy/<id>.json: phase, current file, bytes done / total, files done / total, speed, eta, result.

RESUMABLE. Each file is written to "<name>.dlmon-part" beside its place and renamed when whole; its times and mode
are set from the original. A file already at the destination with the same size and the same modification time is
counted as done and not copied again (so a stopped copy, ours or an rsync -a, goes on where it stopped). A
.dlmon-part left by a pause is continued from its last byte.

A MOVE deletes the original only after verification: every source file at the destination with the same size, the
same count, the same total bytes, and the MD5 of the five largest files equal on both sides. Then the original is
renamed aside, a symlink to the new place is made at the old path (Ableton and Resolve keep finding their files while
the drive is connected), and the renamed original is deleted. Any failure keeps the original and fails the job.

    copier.py            run the queue (the server starts it; running it twice is harmless: the pid file says)
"""

import hashlib
import json
import os
import shutil
import signal
import sys
import time

HOME = os.path.expanduser('~')
DIR = os.path.join(HOME, '.download_monitor')
JOBS = os.path.join(DIR, 'jobs')
STATUS = os.path.join(DIR, 'copy')
PIDFILE = os.path.join(DIR, 'copier.pid')
CHUNK = 8 * 1024 * 1024
PART = '.dlmon-part'
SKIP_NAMES = {'.DS_Store'}            # Finder writes these by itself; copied, but not counted in the verification
os.makedirs(JOBS, exist_ok=True)
os.makedirs(STATUS, exist_ok=True)

STOP = False


class Stopped(Exception):
    pass


class DriveMissing(Exception):
    """The drive of the source or the destination is not mounted: the job waits, QUEUED, it does not fail."""


def drive_of(path):
    """/Volumes/<name> for a path on an external drive, else None."""
    parts = os.path.abspath(path).split('/')
    return '/'.join(parts[:3]) if len(parts) > 2 and parts[1] == 'Volumes' else None


def missing_drive(*paths):
    for p in paths:
        d = drive_of(p)
        if d and not os.path.ismount(d):
            return d
    return None


def on_term(_sig, _frm):
    global STOP
    STOP = True


def safe(jid):
    return ''.join(c if c.isalnum() or c in '_.-' else '_' for c in jid)


def pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, TypeError, ValueError):
        return False


def read_json(p):
    try:
        with open(p) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def write_json(p, d):
    tmp = p + '.tmp'
    with open(tmp, 'w') as fh:
        json.dump(d, fh, indent=1)
    os.replace(tmp, p)


def status_path(jid):
    return os.path.join(STATUS, safe(jid) + '.json')


def queue():
    """The copy and move jobs still to do, in their order."""
    out = []
    for f in os.listdir(JOBS):
        if not f.endswith('.json'):
            continue
        j = read_json(os.path.join(JOBS, f))
        if not j or j.get('kind') not in ('copy', 'move'):
            continue
        if j.get('state') not in ('queued', 'paused'):
            continue
        st = read_json(status_path(j['id'])) or {}
        if st.get('result') in ('done', 'failed') and st.get('run') == j.get('run'):
            continue                                                  # finished; the server has not written it yet
        out.append(j)
    return sorted(out, key=lambda j: j.get('order') or 0)


def job_state(jid):
    j = read_json(os.path.join(JOBS, safe(jid) + '.json'))
    return j.get('state') if j else 'gone'


# ------------------------------------------------------------------ the plan

def walk(src):
    """(files, dirs, links) under src, each as a path relative to src; files with their size."""
    files, dirs, links = [], [], []
    if os.path.islink(src) or os.path.isfile(src):
        return [('', os.path.getsize(src))], [], []
    for root, ds, fs in os.walk(src):
        rel = os.path.relpath(root, src)
        rel = '' if rel == '.' else rel
        for d in list(ds):
            p = os.path.join(root, d)
            if os.path.islink(p):
                links.append(os.path.join(rel, d))
                ds.remove(d)
            else:
                dirs.append(os.path.join(rel, d))
        for f in fs:
            p = os.path.join(root, f)
            r = os.path.join(rel, f)
            if os.path.islink(p):
                links.append(r)
            elif os.path.isfile(p):
                files.append((r, os.path.getsize(p)))
    return files, dirs, links


def join(base, rel):
    return os.path.join(base, rel) if rel else base


class Progress:
    def __init__(self, job):
        self.job = job
        self.p = status_path(job['id'])
        self.d = {'id': job['id'], 'run': job.get('run'), 'pid': os.getpid(), 'phase': 'planning', 'started': time.time(),
                  'bytes_done': 0, 'bytes_total': 0, 'files_done': 0, 'files_total': 0, 'current': None,
                  'speed_bps': 0, 'eta_s': None, 'result': None, 'reason': None}
        old = read_json(self.p)
        if old and old.get('run') == job.get('run'):
            self.d['started'] = old.get('started') or self.d['started']
        self.samples = []
        self.last = 0
        self.save()

    def set(self, **kw):
        self.d.update(kw)

    def tick(self, done_bytes, total_bytes, force=False):
        now = time.time()
        if self.d.get('phase') == 'copying':
            self.d['bytes_done'] = done_bytes
        self.samples.append((now, done_bytes))
        self.samples = [(t, b) for t, b in self.samples if now - t <= 20]
        (t0, b0) = self.samples[0]
        if now - t0 >= 1 and done_bytes > b0:
            self.d['speed_bps'] = (done_bytes - b0) / (now - t0)
            self.d['eta_s'] = int((total_bytes - done_bytes) / self.d['speed_bps']) if self.d['speed_bps'] else None
        if force or now - self.last >= 0.5:
            self.last = now
            self.save()
        if STOP:
            raise Stopped()

    def reset_rate(self):
        self.samples = []
        self.d['speed_bps'] = 0
        self.d['eta_s'] = None

    def save(self):
        self.d['at'] = time.time()
        write_json(self.p, self.d)


# ------------------------------------------------------------------ copying

def copy_file(s, d, size, pr, base):
    """One file, chunk by chunk into d.dlmon-part (continued if it is there), then renamed into place."""
    try:
        sst = os.stat(s)
        if os.path.isfile(d) and not os.path.islink(d):
            dst_st = os.stat(d)
            if dst_st.st_size == sst.st_size and int(dst_st.st_mtime) == int(sst.st_mtime):
                return size                                           # already there, whole: resume skips it
        part = os.path.join(os.path.dirname(d), os.path.basename(d) + PART)
        start = os.path.getsize(part) if os.path.isfile(part) else 0
        if start > size:
            os.remove(part)
            start = 0
        with open(s, 'rb') as fi, open(part, 'ab' if start else 'wb') as fo:
            fi.seek(start)
            done = start
            pr.tick(base + done, pr.d['bytes_total'])
            while True:
                b = fi.read(CHUNK)
                if not b:
                    break
                fo.write(b)
                done += len(b)
                pr.tick(base + done, pr.d['bytes_total'])
            fo.flush()
            os.fsync(fo.fileno())
        if os.path.getsize(part) != sst.st_size:
            raise OSError('%s: %d bytes written, the original has %d' % (s, os.path.getsize(part), sst.st_size))
        shutil.copystat(s, part, follow_symlinks=False)
        os.replace(part, d)
        return size
    except Stopped:
        raise


def copy_tree(src, dst, pr):
    files, dirs, links = walk(src)
    total = sum(sz for _, sz in files)
    pr.set(phase='copying', bytes_total=total, files_total=len(files))
    single = os.path.isfile(src) and not os.path.islink(src)
    if single:
        os.makedirs(os.path.dirname(dst) or '.', exist_ok=True)
    else:
        os.makedirs(dst, exist_ok=True)
        for r in dirs:
            os.makedirs(join(dst, r), exist_ok=True)
    done = 0
    for i, (r, sz) in enumerate(files):
        pr.set(current=r or os.path.basename(src), files_done=i)
        done += copy_file(join(src, r), join(dst, r), sz, pr, done)
        pr.tick(done, total)
    for r in links:
        d = join(dst, r)
        if not os.path.lexists(d):
            os.symlink(os.readlink(join(src, r)), d)
    if not single:
        for r in sorted(dirs, key=len, reverse=True) + ['']:          # folder times last, deepest first
            try:
                shutil.copystat(join(src, r), join(dst, r))
            except OSError:
                pass
    pr.set(files_done=len(files), current=None)
    pr.tick(done, total, force=True)
    return files


# ------------------------------------------------------------------ verifying

def md5(path, pr, base, total):
    h = hashlib.md5()
    n = 0
    with open(path, 'rb') as fh:
        while True:
            b = fh.read(CHUNK)
            if not b:
                break
            h.update(b)
            n += len(b)
            pr.tick(base + n, total)
    return h.hexdigest(), n


def verify(src, dst, files, pr):
    """Count, total bytes, and the MD5 of the five largest files on both sides. Returns None or the reason."""
    counted = [(r, sz) for r, sz in files if os.path.basename(r or src) not in SKIP_NAMES]
    have_n, have_b, missing = 0, 0, []
    for r, sz in counted:
        d = join(dst, r)
        if os.path.isfile(d) and os.path.getsize(d) == os.path.getsize(join(src, r)):
            have_n += 1
            have_b += os.path.getsize(d)
        else:
            missing.append(r)
    src_b = sum(os.path.getsize(join(src, r)) for r, _ in counted)
    if have_n != len(counted) or have_b != src_b:
        return 'verification: %d of %d files, %d of %d bytes at the destination (first missing: %s)' % (
            have_n, len(counted), have_b, src_b, (missing[:1] or ['?'])[0])
    big = sorted(counted, key=lambda x: -x[1])[:5]
    total = 2 * sum(sz for _, sz in big)
    pr.reset_rate()
    pr.set(phase='verifying', verify_total=total, verify_done=0)
    base = 0
    for r, sz in big:
        pr.set(current='MD5 ' + (r or os.path.basename(src)))
        a, n = md5(join(src, r), pr_v(pr), base, total)
        base += n
        b, n = md5(join(dst, r), pr_v(pr), base, total)
        base += n
        if a != b:
            return 'verification: MD5 differs for %s (%s here, %s there)' % (r, a[:8], b[:8])
    pr.set(verify_done=total, current=None)
    return None


class pr_v:
    """The verification's own bar: verify_done of verify_total, with speed and time left."""
    def __init__(self, pr):
        self.pr = pr

    def tick(self, done, total, force=False):
        self.pr.set(verify_done=done)
        self.pr.tick(done, total, force)


# ------------------------------------------------------------------ a job

def same_volume(a, b):
    try:
        return os.stat(a).st_dev == os.stat(os.path.dirname(b.rstrip('/')) or '/').st_dev
    except OSError:
        return False


def run_job(j):
    src, dst, kind = j['src'], j['dst'], j['kind']
    pr = Progress(j)
    try:
        gone = missing_drive(src, dst)
        if gone:
            raise DriveMissing(gone)
        if not os.path.lexists(src):
            raise OSError('the source is not there: %s' % src)
        if kind == 'move' and os.path.islink(src):
            raise OSError('the source is already a symlink (moved before?): %s' % src)
        real_s, real_d = os.path.realpath(src), os.path.realpath(dst)
        if real_d == real_s or real_d.startswith(real_s.rstrip('/') + '/'):
            raise OSError('the destination is inside the source')
        parent = os.path.dirname(dst.rstrip('/'))
        os.makedirs(parent, exist_ok=True)                              # e.g. /Volumes/X/From MacBook/Documents
        if os.path.isdir(src) and os.path.isfile(dst):
            raise OSError('the destination is a file, the source a folder')
        if kind == 'move' and same_volume(src, dst) and not os.path.lexists(dst):
            pr.set(phase='moving', current=os.path.basename(src))
            pr.save()
            files, _, _ = walk(src)
            os.rename(src, dst)
            os.symlink(dst, src)
            tot = sum(sz for _, sz in files)
            pr.set(phase='done', result='done', bytes_done=tot, bytes_total=tot, files_done=len(files),
                   files_total=len(files), note='same disk: renamed in place, symlink left at the old path')
            pr.save()
            return
        # room on the destination for what is still to come
        files, _, _ = walk(src)
        need = 0
        for r, sz in files:
            d = join(dst, r)
            if not (os.path.isfile(d) and os.path.getsize(d) == sz):
                need += sz - (os.path.getsize(d + PART) if os.path.isfile(d + PART) else 0)
        st = os.statvfs(parent)
        if need > st.f_bavail * st.f_frsize:
            raise OSError('not enough room: %.1f GB to write, %.1f GB free at %s' % (
                need / 1e9, st.f_bavail * st.f_frsize / 1e9, parent))
        files = copy_tree(src, dst, pr)
        if kind == 'copy':
            pr.set(phase='done', result='done')
            pr.save()
            return
        why = verify(src, dst, files, pr)
        if why:
            raise OSError(why + '; the original is kept')
        if job_state(j['id']) not in ('queued',):
            raise Stopped()
        pr.set(phase='deleting the original', current=src)
        pr.save()
        aside = src.rstrip('/') + '.dlmon-moved'
        os.rename(src, aside)
        try:
            os.symlink(dst, src.rstrip('/'))
        except OSError:
            os.rename(aside, src)                                        # put it back: nothing lost
            raise
        if os.path.isdir(aside) and not os.path.islink(aside):
            shutil.rmtree(aside)
        else:
            os.remove(aside)
        pr.set(phase='done', result='done', current=None, note='verified; the original replaced by a symlink to %s' % dst)
        pr.save()
    except Stopped:
        pr.set(phase='paused', speed_bps=0, eta_s=None)
        pr.save()
        raise
    except DriveMissing as e:
        pr.set(phase='drive not connected', reason='%s is not connected' % e, speed_bps=0, eta_s=None)
        pr.save()
        raise
    except Exception as e:                                              # noqa: BLE001
        gone = missing_drive(src, dst)
        if gone:                                                        # pulled out mid-copy: wait, resume later
            pr.set(phase='drive not connected', reason='%s is not connected' % gone, speed_bps=0, eta_s=None)
            pr.save()
            raise DriveMissing(gone)
        pr.set(phase='failed', result='failed', reason=str(e)[:300], speed_bps=0, eta_s=None)
        pr.save()


def main():
    old = read_json(PIDFILE) if os.path.isfile(PIDFILE) else None
    if old and old.get('pid') != os.getpid() and pid_alive(old.get('pid')):
        return 0                                                        # one runner only
    write_json(PIDFILE, {'pid': os.getpid(), 'started': time.time()})
    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)
    try:
        while not STOP:
            q = queue()
            if not q or q[0].get('state') == 'paused':
                break                                                   # empty, or held by a paused job
            j = q[0]
            write_json(PIDFILE, {'pid': os.getpid(), 'started': time.time(), 'job': j['id']})
            try:
                run_job(j)
            except (Stopped, DriveMissing):
                break                                                   # the server starts the runner again
    finally:
        cur = read_json(PIDFILE)
        if cur and cur.get('pid') == os.getpid():
            os.remove(PIDFILE)
    return 0


if __name__ == '__main__':
    sys.exit(main())
