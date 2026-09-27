"""Minimal App Store Connect API client for the DotBar listing.

Reads the API key from .release.env (ASC_KEY, ASC_KEY_ID, ASC_ISSUER). Needs `pip install "pyjwt[crypto]"`.
Import it (`from asc import *`) from a small script; see APPSTORE.md for what still needs the web UI.
"""
import hashlib, json, os, time, urllib.request, urllib.error
import jwt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV = {}
for line in open(os.path.join(ROOT, '.release.env')):
    line = line.strip()
    if '=' in line and not line.startswith('#'):
        k, v = line.split('=', 1)
        ENV[k.replace('export ', '').strip()] = os.path.expandvars(os.path.expanduser(v.strip().strip('"').strip("'")))

APP_ID = '6814083243'
BASE = 'https://api.appstoreconnect.apple.com'


def token():
    now = int(time.time())
    return jwt.encode({'iss': ENV['ASC_ISSUER'], 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'},
                      open(ENV['ASC_KEY']).read(), algorithm='ES256', headers={'kid': ENV['ASC_KEY_ID'], 'typ': 'JWT'})


def call(method, path, body=None, raw=False):
    url = path if path.startswith('http') else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            txt = r.read().decode()
            return json.loads(txt) if txt and not raw else txt
    except urllib.error.HTTPError as e:
        raise SystemExit(f'{method} {path} -> HTTP {e.code}: {e.read().decode()[:1500]}')


def upload_screenshot(set_id, path):
    """Reserve, upload and commit one screenshot into an appScreenshotSet."""
    data = open(path, 'rb').read()
    res = call('POST', '/v1/appScreenshots', {'data': {'type': 'appScreenshots',
        'attributes': {'fileName': os.path.basename(path), 'fileSize': len(data)},
        'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': set_id}}}}})
    sid = res['data']['id']
    for op in res['data']['attributes']['uploadOperations']:
        chunk = data[op['offset']:op['offset'] + op['length']]
        req = urllib.request.Request(op['url'], data=chunk, method=op['method'],
                                     headers={h['name']: h['value'] for h in op['requestHeaders']})
        urllib.request.urlopen(req, timeout=120).read()
    call('PATCH', f'/v1/appScreenshots/{sid}', {'data': {'type': 'appScreenshots', 'id': sid,
        'attributes': {'uploaded': True, 'sourceFileChecksum': hashlib.md5(data).hexdigest()}}})
    return sid
