#!/usr/bin/env python3
"""Run once on a machine with internet: downloads a photo for each entry in tools/assets.json
(lead image of the English Wikipedia article, Wikimedia Commons) into img/<key>.jpg, writes img/credits.json,
and saves the mp3quran.net reciter list as lib/reciters.json. Uses only the standard library plus macOS `sips`."""
import json, os, subprocess, urllib.parse, urllib.request
UA = {'User-Agent': 'RafiqAlbar/1.0 (personal app; github.com/rasheedelaaj-svg/rafiq-albar)'}
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r: return r.read()
def thumb(title):
    try:
        j = json.loads(get('https://en.wikipedia.org/api/rest_v1/page/summary/' + urllib.parse.quote(title.replace(' ', '_'))))
        if j.get('thumbnail'): return j['thumbnail']['source'], j['content_urls']['desktop']['page']
    except Exception: pass
    q = urllib.parse.urlencode({'action': 'query', 'generator': 'search', 'gsrsearch': title, 'gsrlimit': 5, 'prop': 'pageimages|info',
                                'inprop': 'url', 'piprop': 'thumbnail', 'pithumbsize': 640, 'format': 'json'})
    pages = sorted(json.loads(get('https://en.wikipedia.org/w/api.php?' + q)).get('query', {}).get('pages', {}).values(), key=lambda p: p.get('index', 99))
    for p in pages:
        if p.get('thumbnail'): return p['thumbnail']['source'], p['fullurl']
    return None, None
os.makedirs(os.path.join(root, 'img'), exist_ok=True)
credits, missing = {}, []
for a in json.load(open(os.path.join(root, 'tools', 'assets.json'))):
    out = os.path.join(root, 'img', a['key'] + '.jpg')
    try:
        src, page = thumb(a['title'])
        if not src: missing.append(a['title']); continue
        src = src.replace('/330px-', '/640px-').replace('/320px-', '/640px-')
        tmp = out + '.src'
        open(tmp, 'wb').write(get(src))
        subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '72', '-Z', '640', tmp, '--out', out], check=True, capture_output=True)
        os.remove(tmp)
        credits[a['key']] = {'title': a['title'], 'page': page, 'file': src}
        print('ok', a['key'])
    except Exception as e:
        missing.append(a['title']); print('FAIL', a['key'], e)
json.dump(credits, open(os.path.join(root, 'img', 'credits.json'), 'w'), ensure_ascii=False, indent=0)
r = json.loads(get('https://www.mp3quran.net/api/v3/reciters?language=ar'))
keep = [{'id': x['id'], 'name': x['name'], 'letter': x.get('letter', ''),
         'moshaf': [{'id': m['id'], 'name': m['name'], 'server': m['server'], 'surah_total': m['surah_total'], 'surah_list': m['surah_list']} for m in x['moshaf']]}
        for x in r['reciters']]
json.dump(keep, open(os.path.join(root, 'lib', 'reciters.json'), 'w'), ensure_ascii=False, separators=(',', ':'))
print('reciters', len(keep), 'missing photos:', missing)
