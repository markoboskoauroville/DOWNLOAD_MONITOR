#!/usr/bin/env python3
"""
DOWNLOAD MONITOR, a Flask page at http://127.0.0.1:8833 with live progress bars
for every download running on this Mac that told it, or that it can see.

Marko's request, 7.9.2026: "build this Flask app, open it in the web browser.
We can keep this in my David menu, Download Monitor. So in any chat, if there
are some downloads from this code, I can see the progress. I want to see
progress indicators moving, alive."

WHERE THE JOBS COME FROM: one json file per download in ~/.download_monitor/jobs/,
written by dlmon.py (next to this file) or by anyone:

    { "id": "whisper-medium", "name": "Whisper medium", "want_mb": 1520,
      "repo": "mlx-community/whisper-medium-mlx",      # a Hugging Face repo: its blobs count
      "log": "/path/to/a/tqdm.log",                     # a log with tqdm lines: the file in flight
      "have_mb": 0, "done": false }                     # or reported directly, POST /report

The page asks /progress every second (a setting on the page, kept in the
browser); the bars glide to their new width. Every job carries an "info" note:
what the file is, why it is downloaded, what it does on this Mac; the page shows
it in a box that opens under the bar.
Speed and ETA are measured here from the last minute of samples, so they are
true for whatever the source is. Nothing here needs the network or a key.

    monitor.py                     the server, in the foreground (the star starts it detached)
    GET  /                         the page
    GET  /progress                 the jobs as json
    GET  /health                   200 when up
    POST /report  {id, name, have_mb, want_mb, done}   a download reporting itself
    POST /control/<id>/pause       stop its worker; what is down stays (blobs/<etag>.incomplete)
    POST /control/<id>/start       start, or go on from where it stopped (resume_download)
    POST /control/<id>/restart     throw the repo's cache away and start from zero
    POST /forget/<id>              take a finished job off the page
    POST /quit                     stop the server

THE CONTROL (Marko, 7.9.2026: "make this monitor also the controller of the
download process, two ways back and forth: pause, start, restart, give me the
control"). A job with a "repo" is downloaded by a worker this server starts
(dlmon.py _worker: snapshot_download with resume_download=True, retried when the
line breaks); its pid is in the job file. Pause sends it SIGTERM and the partial
file stays in the cache as blobs/<etag>.incomplete; start picks it up from there;
restart deletes the repo's cache folder first. A download started elsewhere is
taken over with `dlmon.py takeover <id>` (its temp file moved into place), after
which the page controls it too.
"""

import glob
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

from flask import Flask, jsonify, request, Response

PORT = 8833
HOME = os.path.expanduser('~')
DIR = os.path.join(HOME, '.download_monitor')
JOBS = os.path.join(DIR, 'jobs')
HUB = os.path.join(HOME, '.cache', 'huggingface', 'hub')
LOGS = os.path.join(DIR, 'logs')
HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(JOBS, exist_ok=True)
os.makedirs(LOGS, exist_ok=True)

app = Flask(__name__)
LOCK = threading.Lock()
HISTORY = {}                 # id -> [(t, have_mb)], the last minute, for speed and eta
UNIT = {'k': 1e-3, 'M': 1.0, 'G': 1e3, '': 1e-6}


# ------------------------------------------------------------------ measuring

def mb_of(s):
    m = re.match(r'([\d.]+)([kMG]?)B?', s or '')
    return float(m.group(1)) * UNIT.get(m.group(2), 1.0) if m else 0.0


def blobs_mb(repo):
    d = os.path.join(HUB, 'models--' + repo.replace('/', '--'), 'blobs')
    if not os.path.isdir(d):
        return 0.0
    return sum(os.path.getsize(os.path.join(d, f)) for f in os.listdir(d)
               if not f.endswith('.incomplete')) / 1e6


def log_tail(path, n=4000):
    try:
        with open(path, 'rb') as fh:
            fh.seek(0, 2)
            fh.seek(max(0, fh.tell() - n))
            return fh.read().decode('utf-8', 'replace')
    except OSError:
        return ''


TQDM = re.compile(r'([\d.]+[kMG]?)/([\d.]+[kMG]?) \[[\d:]+<[\d:?]+, ([\d.]+[kMG]?B/s)\]')


LAST = {}                    # id -> the highest have seen, so a bar never steps back


def repo_dir(repo):
    return os.path.join(HUB, 'models--' + repo.replace('/', '--'))


def blob_sizes_mb(repo, incomplete=False):
    d = os.path.join(repo_dir(repo), 'blobs')
    if not os.path.isdir(d):
        return []
    return [os.path.getsize(os.path.join(d, f)) / 1e6 for f in os.listdir(d)
            if f.endswith('.incomplete') == incomplete]


def pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, TypeError, ValueError):
        return False


def in_flight_mb(tail, blobs):
    """What the log's tqdm lines say is still coming: huggingface_hub downloads
    several files at once, so the tail holds one bar per file; the last line of
    each (keyed by its total) counts. A file that has reached its total and
    already sits in the blobs is not counted twice."""
    latest = {}
    for have, want, _speed in TQDM.findall(tail):
        latest[want] = have
    total = 0.0
    for want, have in latest.items():
        w, h = mb_of(want), mb_of(have)
        if h >= w - 0.5 and any(abs(b - w) <= max(1.0, w * 0.02) for b in blobs):
            continue                                            # finished and moved into blobs
        total += min(h, w)
    return total


def measure(job):
    """have_mb, want_mb, done for one job, from whatever it names."""
    have = float(job.get('have_mb') or 0)
    want = float(job.get('want_mb') or 0)
    done = bool(job.get('done'))
    blobs = blob_sizes_mb(job['repo']) if job.get('repo') else []
    partial = sum(blob_sizes_mb(job['repo'], incomplete=True)) if job.get('repo') else 0.0
    if blobs or partial:
        have = max(have, sum(blobs) + partial)
    if job.get('log') and not partial:                          # a foreign download: only its log knows
        t = log_tail(job['log'], 6000)
        if '\nDONE' in t or t.startswith('DONE'):
            done = True
        elif TQDM.search(t):
            have += in_flight_mb(t, blobs)                      # the files in flight are in a tmp dir
            if not want:
                want = sum(mb_of(w) for w in {m[1] for m in TQDM.findall(t)})
        last = t.strip().split('\n')[-1]
        if 'Traceback' in t or 'Error' in last:
            job['error'] = last[:160]
    if want and have >= want - 0.5:
        done = True
    if done and want:
        have = want
    if job.get('_reset'):
        LAST.pop(job['id'], None)
    have = max(have, LAST.get(job['id'], 0.0)) if not done else have
    LAST[job['id']] = have
    return have, want, done


def state_of(job, done):
    """done | running | paused | stopped | waiting: what the page's buttons show."""
    if done:
        return 'done'
    if job.get('pid') and pid_alive(job['pid']):
        return 'running'
    if job.get('state') == 'paused':
        return 'paused'
    if job.get('pid') or job.get('state') == 'stopped':
        return 'stopped'                                        # a worker died, or the server restarted
    if job.get('log') or job.get('have_mb'):
        return 'running' if job.get('foreign') else 'waiting'   # someone else's download
    return 'waiting'


def speed_eta(jid, have, want, done):
    now = time.time()
    h = HISTORY.setdefault(jid, [])
    if not h or have != h[-1][1] or now - h[-1][0] > 20:
        h.append((now, have))
    h[:] = [(t, v) for t, v in h if now - t <= 300][-200:]
    if done or len(h) < 2:
        return 0.0, None
    (t0, v0), (t1, v1) = h[0], h[-1]
    if t1 - t0 < 1 or v1 <= v0:
        return 0.0, None
    speed = (v1 - v0) / (t1 - t0)                    # MB/s
    return speed, ((want - have) / speed if want and speed > 0 else None)


def load_jobs():
    jobs = []
    for p in sorted(glob.glob(os.path.join(JOBS, '*.json')), key=os.path.getmtime):
        try:
            with open(p) as fh:
                j = json.load(fh)
            j.setdefault('id', os.path.splitext(os.path.basename(p))[0])
            j['_path'] = p
            jobs.append(j)
        except (OSError, ValueError):
            continue
    return jobs


def save_job(j):
    p = os.path.join(JOBS, re.sub(r'[^A-Za-z0-9_.-]', '_', j['id']) + '.json')
    with open(p, 'w') as fh:
        json.dump({k: v for k, v in j.items() if not k.startswith('_')}, fh, indent=1)
    return p


def progress():
    out = []
    total_have = total_want = 0.0
    with LOCK:
        for j in load_jobs():
            have, want, done = measure(j)
            speed, eta = speed_eta(j['id'], have, want, done)
            if done and not j.get('done'):
                j['done'] = True
                j['done_at'] = time.time()
                save_job(j)
            st = state_of(j, done)
            if st == 'stopped' and j.get('state') == 'running':
                j['state'] = 'stopped'
                save_job(j)
            out.append({'id': j['id'], 'name': j.get('name') or j['id'], 'have_mb': round(have, 1),
                        'want_mb': round(want, 1), 'pct': round(100 * have / want, 1) if want else None,
                        'speed_mbs': round(speed, 3), 'eta_s': int(eta) if eta else None,
                        'eta_at': time.strftime('%H:%M', time.localtime(time.time() + eta)) if eta else None,
                        'done': done,
                        'state': st, 'control': bool(j.get('repo')) and not j.get('foreign'),
                        'info': j.get('info'), 'repo': j.get('repo'),
                        'error': j.get('error'), 'started': j.get('started'), 'done_at': j.get('done_at')})
            total_have += have
            total_want += want
    left = [j['eta_s'] for j in out if not j['done'] and j['eta_s']]
    return {'jobs': out, 'total_have_mb': round(total_have, 1), 'total_want_mb': round(total_want, 1),
            'total_pct': round(100 * total_have / total_want, 1) if total_want else None,
            'last_eta_s': max(left) if left else None,
            'last_eta_at': time.strftime('%H:%M', time.localtime(time.time() + max(left))) if left else None,
            'clock': time.strftime('%H:%M:%S'), 'at': time.time()}


# ------------------------------------------------------------------ routes

@app.get('/health')
def health():
    return jsonify(ok=True, port=PORT, jobs=len(load_jobs()))


@app.get('/progress')
def get_progress():
    return jsonify(progress())


@app.post('/report')
def report():
    j = request.get_json(force=True, silent=True) or {}
    if not j.get('id'):
        return jsonify(error='id required'), 400
    with LOCK:
        cur = {x['id']: x for x in load_jobs()}.get(j['id'], {'id': j['id'], 'started': time.time()})
        cur.update({k: v for k, v in j.items() if k in ('name', 'have_mb', 'want_mb', 'done', 'repo', 'log', 'info')})
        save_job(cur)
    return jsonify(ok=True)


def find_job(jid):
    for j in load_jobs():
        if j['id'] == jid:
            return j
    return None


def start_worker(j):
    """The download, as a child of this server: dlmon.py _worker <repo> <log>."""
    if j.get('pid') and pid_alive(j['pid']):
        return j
    log = j.get('log') or os.path.join(LOGS, re.sub(r'[^A-Za-z0-9_.-]', '_', j['id']) + '.log')
    fh = open(log, 'a')
    p = subprocess.Popen([sys.executable, os.path.join(HERE, 'dlmon.py'), '_worker', j['repo'], log],
                         stdout=fh, stderr=subprocess.STDOUT, start_new_session=True)
    j.update({'pid': p.pid, 'log': log, 'state': 'running', 'foreign': False, 'error': None,
              'started': j.get('started') or time.time()})
    j.pop('done', None)
    j.pop('done_at', None)
    save_job(j)
    return j


def stop_worker(j, state='paused'):
    pid = j.get('pid')
    if pid and pid_alive(pid):
        try:
            os.killpg(os.getpgid(int(pid)), signal.SIGTERM)
        except OSError:
            try:
                os.kill(int(pid), signal.SIGTERM)
            except OSError:
                pass
        for _ in range(30):
            if not pid_alive(pid):
                break
            time.sleep(0.1)
    j['state'] = state
    j['pid'] = None
    save_job(j)
    return j


@app.post('/control/<jid>/<action>')
def control(jid, action):
    with LOCK:
        j = find_job(jid)
        if not j:
            return jsonify(error='no such job'), 404
        if not j.get('repo'):
            return jsonify(error='only a job with a repo can be controlled; report-only jobs cannot'), 400
        if j.get('foreign'):
            return jsonify(error='started elsewhere: dlmon.py takeover %s first' % jid), 400
        if action == 'pause':
            stop_worker(j, 'paused')
        elif action == 'start':
            start_worker(j)
        elif action == 'restart':
            stop_worker(j, 'paused')
            shutil.rmtree(repo_dir(j['repo']), ignore_errors=True)
            try:
                os.remove(j['log'])
            except (OSError, TypeError):
                pass
            LAST.pop(jid, None)
            HISTORY.pop(jid, None)
            start_worker(j)
        else:
            return jsonify(error='pause | start | restart'), 400
    return jsonify(ok=True, state=state_of(j, False))


@app.post('/forget/<jid>')
def forget(jid):
    with LOCK:
        for j in load_jobs():
            if j['id'] == jid:
                if j.get('pid') and pid_alive(j['pid']):
                    stop_worker(j, 'stopped')
                os.remove(j['_path'])
                HISTORY.pop(jid, None)
                LAST.pop(jid, None)
    return jsonify(ok=True)


@app.post('/quit')
def quit_():
    threading.Timer(0.3, lambda: os._exit(0)).start()
    return jsonify(ok=True)


PAGE = r'''<!doctype html><html><head><meta charset="utf-8"><title>Download Monitor</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="icon" type="image/svg+xml" href="/favicon.svg">
<style>
  html,body{margin:0;background:#0f1217;color:#f2f2f2;font:15px/1.4 -apple-system,Helvetica,sans-serif}
  #wrap{max-width:900px;margin:0 auto;padding:22px 26px 40px}
  #top{display:flex;justify-content:space-between;align-items:baseline;color:#8a8f99;font-size:12px;letter-spacing:.08em}
  #top b{color:#f2f2f2;font-size:13px;letter-spacing:.14em}
  #clock{font-variant-numeric:tabular-nums}
  .job{margin:22px 0 0}
  .row{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:6px}
  .name{font-size:17px}
  .meta{color:#9aa1ad;font-size:13px;font-variant-numeric:tabular-nums;text-align:right}
  .bar{height:22px;background:#1c222b;border-radius:11px;overflow:hidden;position:relative}
  .bar i{display:block;height:100%;width:0;border-radius:11px;
    background:linear-gradient(90deg,#2f8f52,#3fb862 70%,#7fe09a);
    transition:width .9s linear;position:relative;overflow:hidden}
  .bar i:after{content:"";position:absolute;inset:0;
    background:linear-gradient(90deg,transparent 0,rgba(255,255,255,.18) 50%,transparent 100%);
    background-size:220px 100%;animation:shine 1.6s linear infinite}
  .job.done .bar i{background:linear-gradient(90deg,#3f7fb8,#5aa0e0);box-shadow:0 0 14px rgba(90,160,224,.5)}
  .job.done .bar i:after{animation:none}
  .job.error .bar i{background:#b84040}
  .pct{position:absolute;right:10px;top:0;line-height:22px;font-size:12px;color:#e8ecf2;font-variant-numeric:tabular-nums;text-shadow:0 0 4px #000}
  .job.stale .bar i:after{animation:none}
  #all{margin-top:34px;padding-top:18px;border-top:1px solid #222a35}
  #all .name{color:#e9dcc0}
  #empty{color:#8a8f99;margin-top:40px;text-align:center}
  .forget{color:#5a6270;font-size:12px;cursor:pointer;margin-left:10px}
  .forget:hover{color:#e08a8a}
  .ctl{display:inline-flex;gap:6px;margin-left:12px;vertical-align:middle}
  .ctl button{border:0;border-radius:7px;padding:3px 10px;font-size:12px;cursor:pointer;color:#fff;background:#3a4250}
  .ctl button:hover{background:#4a5468}
  .ctl button.go{background:#2f8f52}.ctl button.go:hover{background:#3fb862}
  .ctl button.pause{background:#8a6a2a}.ctl button.pause:hover{background:#b08a3a}
  .ctl button.redo{background:#5a3a3a}.ctl button.redo:hover{background:#b84040}
  .state{font-size:12px;color:#9aa1ad;margin-left:8px;letter-spacing:.06em}
  .job.paused .bar i{background:linear-gradient(90deg,#8a6a2a,#c9a04a)}
  .job.paused .bar i:after,.job.stopped .bar i:after{animation:none}
  .job.stopped .bar i{background:linear-gradient(90deg,#5a3a3a,#9a5a5a)}
  details{margin-top:7px}
  summary{cursor:pointer;color:#8a8f99;font-size:12px;letter-spacing:.06em;list-style:none;display:inline-block}
  summary::-webkit-details-marker{display:none}
  summary:before{content:"▸ ";color:#5a6270}
  details[open] summary:before{content:"▾ "}
  summary:hover{color:#e9dcc0}
  .info{margin:8px 0 2px;padding:12px 16px;background:#141922;border-left:3px solid #3a4250;border-radius:6px;
    color:#c9d0da;font-size:14px;line-height:1.5;white-space:pre-wrap}
  .info b{color:#e9dcc0}
  .info .repo{display:block;margin-top:8px;color:#8a8f99;font-size:12px;font-family:Menlo,monospace}
  #set{display:flex;gap:10px;align-items:baseline;color:#8a8f99;font-size:12px}
  #set select{background:#1c222b;color:#f2f2f2;border:1px solid #2a323f;border-radius:6px;padding:2px 6px;font-size:12px}
  @keyframes shine{from{background-position:-220px 0}to{background-position:calc(100% + 220px) 0}}
</style></head><body><div id="wrap">
  <div id="top"><b>DOWNLOAD MONITOR</b>
    <span id="set">refresh every <select id="every" onchange="setEvery(this.value)">
      <option value="1">1 s</option><option value="2">2 s</option><option value="5">5 s</option>
      <option value="10">10 s</option><option value="30">30 s</option></select>
      <span id="clock">…</span></span></div>
  <div id="jobs"></div>
  <div id="empty" hidden>Nothing is downloading. <code>dlmon.py hf &lt;repo&gt;</code> starts one that shows here.</div>
  <div id="all" hidden>
    <div class="row"><span class="name">ALL</span><span class="meta" id="allmeta"></span></div>
    <div class="bar"><i id="allbar"></i><span class="pct" id="allpct"></span></div>
  </div>
</div><script>
  const fmt = s => { if (s == null) return ''; s = Math.round(s); const h = Math.floor(s/3600), m = Math.floor(s%3600/60), x = s%60;
    return (h ? h + ':' : '') + String(m).padStart(h ? 2 : 1, '0') + ':' + String(x).padStart(2, '0'); };
  const mb = v => v >= 1000 ? (v/1000).toFixed(2) + ' GB' : Math.round(v) + ' MB';
  const speed = v => v >= 1 ? v.toFixed(2) + ' MB/s' : Math.round(v*1000) + ' kB/s';
  const doneAt = t => { const d = new Date(t*1000); return d.getHours().toString().padStart(2,'0') + ':' + d.getMinutes().toString().padStart(2,'0'); };
  let lastAt = 0;
  function paint(p) {
    lastAt = Date.now();
    const box = document.getElementById('jobs');
    const seen = new Set();
    for (const j of p.jobs) {
      seen.add(j.id);
      let el = document.getElementById('j-' + j.id);
      if (!el) {
        el = document.createElement('div'); el.id = 'j-' + j.id; el.className = 'job';
        el.innerHTML = '<div class="row"><span class="name"></span><span class="meta"></span></div>' +
                       '<div class="bar"><i></i><span class="pct"></span></div>' +
                       '<details><summary>what is this, and why</summary><div class="info"></div></details>';
        box.appendChild(el);
      }
      const pct = j.pct == null ? 0 : Math.min(100, j.pct);
      el.className = 'job ' + j.state + (j.error ? ' error' : '') + (j.state === 'running' && !j.speed_mbs ? ' stale' : '');
      let ctl = '';
      if (j.control) {
        const b = (a, cls, label) => '<button class="' + cls + '" onclick="control(\'' + j.id + '\',\'' + a + '\')">' + label + '</button>';
        if (j.state === 'running') ctl += b('pause', 'pause', '❚❚ pause');
        else if (!j.done) ctl += b('start', 'go', '▶ ' + (j.have_mb > 1 ? 'continue' : 'start'));
        ctl += b('restart', 'redo', '↻ restart');
      }
      el.querySelector('.name').innerHTML = j.name +
        '<span class="state">' + (j.state === 'running' ? '' : j.state.toUpperCase()) + '</span>' +
        (ctl ? '<span class="ctl">' + ctl + '</span>' : '') +
        (j.done ? ' <span class="forget" onclick="forget(\'' + j.id + '\')">clear</span>' : '');
      el.querySelector('.meta').textContent = j.error ? j.error :
        j.done ? 'done' + (j.done_at ? ' at ' + doneAt(j.done_at) : '') + '  ·  ' + mb(j.want_mb) :
        mb(j.have_mb) + ' of ' + (j.want_mb ? mb(j.want_mb) : '?') +
        (j.state !== 'running' ? '' : (j.speed_mbs ? '  ·  ' + speed(j.speed_mbs) : '  ·  waiting')) +
        (j.state === 'running' && j.eta_s != null ? '  ·  ' + fmt(j.eta_s) + ' left (' + j.eta_at + ')' : '');
      el.querySelector('i').style.width = pct + '%';
      el.querySelector('.pct').textContent = j.pct == null ? '' : pct.toFixed(1) + '%';
      const info = el.querySelector('.info');
      const text = (j.info || 'No note was written for this download.').replace(/&/g, '&amp;').replace(/</g, '&lt;')
        .replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
      const html = text + (j.repo ? '<span class="repo">' + j.repo + '  ·  ~/.cache/huggingface/hub</span>' : '');
      if (info.dataset.html !== html) { info.innerHTML = html; info.dataset.html = html; }
    }
    for (const el of [...box.children]) if (!seen.has(el.id.slice(2))) el.remove();
    document.getElementById('empty').hidden = p.jobs.length > 0;
    document.getElementById('all').hidden = p.jobs.length < 2;
    if (p.total_pct != null) {
      document.getElementById('allbar').style.width = Math.min(100, p.total_pct) + '%';
      document.getElementById('allpct').textContent = p.total_pct.toFixed(1) + '%';
      document.getElementById('allmeta').textContent = mb(p.total_have_mb) + ' of ' + mb(p.total_want_mb) +
        (p.last_eta_s != null ? '  ·  last one in ' + fmt(p.last_eta_s) + ' (' + p.last_eta_at + ')' : '');
    }
    document.getElementById('clock').textContent = p.clock;
  }
  async function tick() {
    try { const r = await fetch('/progress'); paint(await r.json()); }
    catch (e) { document.getElementById('clock').textContent = 'monitor not answering'; }
  }
  async function forget(id) { await fetch('/forget/' + id, {method: 'POST'}); tick(); }
  async function control(id, action) {
    if (action === 'restart' && !confirm('Restart from zero? What is already down is thrown away.')) return;
    const r = await fetch('/control/' + id + '/' + action, {method: 'POST'});
    if (!r.ok) { const e = await r.json(); alert(e.error || 'could not ' + action); }
    tick();
  }
  let timer = null;
  function setEvery(v) {
    v = Math.max(1, parseInt(v, 10) || 1);
    try { localStorage.setItem('every', v); } catch (e) {}
    document.getElementById('every').value = String(v);
    if (timer) clearInterval(timer);
    timer = setInterval(tick, v * 1000);
  }
  let saved = 1; try { saved = parseInt(localStorage.getItem('every'), 10) || 1; } catch (e) {}
  tick(); setEvery(saved);
</script></body></html>'''


FAVICON = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
           '<rect width="64" height="64" rx="14" fill="#0f1217"/>'
           '<path d="M32 10v28" stroke="#3fb862" stroke-width="7" stroke-linecap="round"/>'
           '<path d="M19 27l13 13 13-13" fill="none" stroke="#3fb862" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>'
           '<path d="M12 44v6a4 4 0 0 0 4 4h32a4 4 0 0 0 4-4v-6" fill="none" stroke="#7fe09a" stroke-width="6" stroke-linecap="round"/>'
           '</svg>')


@app.get('/favicon.svg')
def favicon():
    return Response(FAVICON, mimetype='image/svg+xml')


@app.get('/favicon.ico')
def favicon_ico():
    return Response(FAVICON, mimetype='image/svg+xml')


@app.get('/')
def page():
    return Response(PAGE, mimetype='text/html')


if __name__ == '__main__':
    with open(os.path.join(DIR, 'monitor.pid'), 'w') as fh:
        fh.write(str(os.getpid()))
    app.run(host='127.0.0.1', port=PORT, debug=False, threaded=True)
