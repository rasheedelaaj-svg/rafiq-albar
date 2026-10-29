// app files: network first (bypassing the HTTP cache) so updates show right away, cache as offline fallback.
// map tiles and libraries: cache first, in their own cache that survives app updates.
const V='barr-28',T='barr-tiles',FILES=['./','index.html','manifest.webmanifest','icon.svg'];
self.addEventListener('install',e=>e.waitUntil(Promise.all([caches.open(V).then(c=>c.addAll(FILES)),
  caches.open(T).then(c=>c.addAll(['https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js','https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css',
  'https://cdn.jsdelivr.net/npm/leaflet-rotate@0.2.8/dist/leaflet-rotate.js','https://cdn.jsdelivr.net/npm/pmtiles@4.4.1/dist/pmtiles.js','https://cdn.jsdelivr.net/npm/protomaps-leaflet@5.1.0/dist/protomaps-leaflet.js'])).catch(()=>{})]).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V&&k!==T).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{const r=e.request;if(r.method!=='GET')return;
  if(new URL(r.url).origin===location.origin)e.respondWith(fetch(r.url,{cache:'no-store'}).then(res=>{const c=res.clone();caches.open(V).then(x=>x.put(r,c));return res}).catch(()=>caches.match(r,{ignoreSearch:true})));
  // offline-map downloads use byte ranges of one huge file: never cache those, the app stores them itself
  else if(!r.headers.has('range')&&!r.url.includes('build.protomaps.com'))e.respondWith(caches.match(r).then(hit=>hit||fetch(r).then(res=>{const c=res.clone();caches.open(T).then(x=>x.put(r,c));return res})))});
