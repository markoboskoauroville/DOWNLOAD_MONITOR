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

The page asks /progress every two seconds; the bars glide to their new width.
Speed and ETA are measured here from the last minute of samples, so they are
true for whatever the source is. Nothing here needs the network or a key.

    monitor.py                     the server, in the foreground (the star starts it detached)
    GET  /                         the page
    GET  /progress                 the jobs as json
    GET  /health                   200 when up
    POST /report  {id, name, have_mb, want_mb, done}   a download reporting itself
    POST /forget/<id>              take a finished job off the page
    POST /quit                     stop the server
"""

import glob
import json
import os
import re
import threading
import time

from flask import Flask, jsonify, request, Response

PORT = 8833
HOME = os.path.expanduser('~')
DIR = os.path.join(HOME, '.download_monitor')
JOBS = os.path.join(DIR, 'jobs')
HUB = os.path.join(HOME, '.cache', 'huggingface', 'hub')
os.makedirs(JOBS, exist_ok=True)

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


def measure(job):
    """have_mb, want_mb, done for one job, from whatever it names."""
    have = float(job.get('have_mb') or 0)
    want = float(job.get('want_mb') or 0)
    done = bool(job.get('done'))
    if job.get('repo'):
        have = max(have, blobs_mb(job['repo']))
    if job.get('log'):
        t = log_tail(job['log'])
        if '\nDONE' in t or t.startswith('DONE'):
            done = True
        m = TQDM.findall(t)
        if m and not done:
            cur_have, cur_want, _speed = m[-1]
            have += mb_of(cur_have)                  # the file in flight is in a tmp dir, not in blobs
            if not want:
                want = mb_of(cur_want)
        if 'Traceback' in t or 'Error' in t.split('\n')[-1]:
            job['error'] = t.strip().split('\n')[-1][:160]
    if want and have >= want - 0.5:
        done = True
    if done and want:
        have = want
    return have, want, done


def speed_eta(jid, have, want, done):
    now = time.time()
    h = HISTORY.setdefault(jid, [])
    h.append((now, have))
    del h[:-40]
    h[:] = [(t, v) for t, v in h if now - t <= 90]
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
            out.append({'id': j['id'], 'name': j.get('name') or j['id'], 'have_mb': round(have, 1),
                        'want_mb': round(want, 1), 'pct': round(100 * have / want, 1) if want else None,
                        'speed_mbs': round(speed, 3), 'eta_s': int(eta) if eta else None, 'done': done,
                        'error': j.get('error'), 'started': j.get('started'), 'done_at': j.get('done_at')})
            total_have += have
            total_want += want
    return {'jobs': out, 'total_have_mb': round(total_have, 1), 'total_want_mb': round(total_want, 1),
            'total_pct': round(100 * total_have / total_want, 1) if total_want else None,
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
        cur.update({k: v for k, v in j.items() if k in ('name', 'have_mb', 'want_mb', 'done', 'repo', 'log')})
        save_job(cur)
    return jsonify(ok=True)


@app.post('/forget/<jid>')
def forget(jid):
    with LOCK:
        for j in load_jobs():
            if j['id'] == jid:
                os.remove(j['_path'])
                HISTORY.pop(jid, None)
    return jsonify(ok=True)


@app.post('/quit')
def quit_():
    threading.Timer(0.3, lambda: os._exit(0)).start()
    return jsonify(ok=True)


PAGE = r'''<!doctype html><html><head><meta charset="utf-8"><title>Download Monitor</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
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
    transition:width 1.9s linear;position:relative;overflow:hidden}
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
  @keyframes shine{from{background-position:-220px 0}to{background-position:calc(100% + 220px) 0}}
</style></head><body><div id="wrap">
  <div id="top"><b>DOWNLOAD MONITOR</b><span id="clock">…</span></div>
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
                       '<div class="bar"><i></i><span class="pct"></span></div>';
        box.appendChild(el);
      }
      const pct = j.pct == null ? 0 : Math.min(100, j.pct);
      el.className = 'job' + (j.done ? ' done' : '') + (j.error ? ' error' : '') + (!j.done && !j.speed_mbs ? ' stale' : '');
      el.querySelector('.name').innerHTML = j.name + (j.done ? ' <span class="forget" onclick="forget(\'' + j.id + '\')">clear</span>' : '');
      el.querySelector('.meta').textContent = j.error ? j.error :
        j.done ? 'done' + (j.done_at ? ' at ' + doneAt(j.done_at) : '') + '  ·  ' + mb(j.want_mb) :
        mb(j.have_mb) + ' of ' + (j.want_mb ? mb(j.want_mb) : '?') +
        (j.speed_mbs ? '  ·  ' + speed(j.speed_mbs) : '  ·  waiting') +
        (j.eta_s != null ? '  ·  ' + fmt(j.eta_s) + ' left' : '');
      el.querySelector('i').style.width = pct + '%';
      el.querySelector('.pct').textContent = j.pct == null ? '' : pct.toFixed(1) + '%';
    }
    for (const el of [...box.children]) if (!seen.has(el.id.slice(2))) el.remove();
    document.getElementById('empty').hidden = p.jobs.length > 0;
    document.getElementById('all').hidden = p.jobs.length < 2;
    if (p.total_pct != null) {
      document.getElementById('allbar').style.width = Math.min(100, p.total_pct) + '%';
      document.getElementById('allpct').textContent = p.total_pct.toFixed(1) + '%';
      const left = p.jobs.filter(j => !j.done && j.eta_s != null).map(j => j.eta_s);
      document.getElementById('allmeta').textContent = mb(p.total_have_mb) + ' of ' + mb(p.total_want_mb) +
        (left.length ? '  ·  last one in ' + fmt(Math.max(...left)) : '');
    }
    document.getElementById('clock').textContent = p.clock;
  }
  async function tick() {
    try { const r = await fetch('/progress'); paint(await r.json()); }
    catch (e) { document.getElementById('clock').textContent = 'monitor not answering'; }
  }
  async function forget(id) { await fetch('/forget/' + id, {method: 'POST'}); tick(); }
  tick(); setInterval(tick, 2000);
</script></body></html>'''


@app.get('/')
def page():
    return Response(PAGE, mimetype='text/html')


if __name__ == '__main__':
    with open(os.path.join(DIR, 'monitor.pid'), 'w') as fh:
        fh.write(str(os.getpid()))
    app.run(host='127.0.0.1', port=PORT, debug=False, threaded=True)
