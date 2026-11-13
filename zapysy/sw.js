/* Записи занять: сторінка відкривається й без інтернету (відео — з IndexedDB) */
const C="ms-zapysy-v1";
self.addEventListener("install",e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(["./","./index.html"])).then(()=>self.skipWaiting()))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k.startsWith("ms-zapysy-")&&k!==C).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method!=="GET")return;
  const shell=r.mode==="navigate"||u.hostname.endsWith("fonts.googleapis.com")||u.hostname.endsWith("fonts.gstatic.com");
  if(!shell)return;
  e.respondWith(fetch(r).then(res=>{if(res.ok||res.type==="opaque"){const cp=res.clone();caches.open(C).then(c=>c.put(r.mode==="navigate"?"./index.html":r,cp))}return res})
    .catch(()=>caches.match(r.mode==="navigate"?"./index.html":r)));
});
