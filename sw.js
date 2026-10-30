// app files: network first (bypassing the HTTP cache) so updates show right away, cache as offline fallback.
// map tiles and libraries: cache first, in their own cache that survives app updates.
const V='barr-38',T='barr-tiles',FILES=['./','index.html','manifest.webmanifest','icon.svg','lib/leaflet-rotate.js','lib/pmtiles.js','lib/protomaps-leaflet.js','lib/quran.json','lib/amiri-quran.woff2'];
self.addEventListener('install',e=>e.waitUntil(Promise.all([caches.open(V).then(c=>c.addAll(FILES)),
  caches.open(T).then(c=>c.addAll(['https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js','https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css'])).catch(()=>{})]).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V&&k!==T).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{const r=e.request;if(r.method!=='GET')return;
  if(new URL(r.url).origin===location.origin)e.respondWith(fetch(r.url,{cache:'no-store'}).then(res=>{const c=res.clone();caches.open(V).then(x=>x.put(r,c));return res}).catch(()=>caches.match(r,{ignoreSearch:true})));
  // offline-map downloads (byte ranges of one huge file) and weather (must be fresh) skip this cache; the app stores both itself
  else if(!r.headers.has('range')&&!/build\.protomaps\.com|open-meteo\.com/.test(r.url))e.respondWith(caches.match(r).then(hit=>hit||fetch(r).then(res=>{const c=res.clone();caches.open(T).then(x=>x.put(r,c));return res})))});
