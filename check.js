// node check.js — asserts the pure math in app.html
const fs=require('fs'),assert=require('assert');
const src=fs.readFileSync(__dirname+'/app.html','utf8').split('// CORE-START')[1].replace(/^.*\n/,'').split('// CORE-END')[0];
const C=new Function(src+';return{prayerTimes,bearing,distance,toUTM,fromUTM,parseCoord,formats,side,toMGRS,parseCoordStrict,projSeg,isGap,trackStats,reverseRoute,routeProgress,toGPX,tilesIn,qLoc,qFind,QPAGE,QJUZ,QSTART}')();
const hm=h=>`${String(Math.floor(h)).padStart(2,'0')}:${String(Math.round(h%1*60)).padStart(2,'0')}`;
const t=C.prayerTimes(2026,10,29,24.7136,46.6753,3,'umm');console.log('Riyadh',Object.fromEntries(Object.entries(t).map(([k,v])=>[k,hm(v)])));
const near=(a,b,e)=>assert(Math.abs(a-b)<e,`${a} vs ${b}`);
const q=C.bearing([24.7136,46.6753],[21.4225,39.8262]);near(q,243.5,1.5);
near(C.distance([24.7136,46.6753],[21.4225,39.8262])/1000,790,15);
const u=C.toUTM(24.4539,54.3773);const back=C.fromUTM(u.zone,false,u.x,u.y);near(back[0],24.4539,1e-6);near(back[1],54.3773,1e-6);
for(const[s,exp]of[['24.4539, 54.3773',[24.4539,54.3773]],['24°27\'14.0"N 54°22\'38.3"E',[24.4539,54.3773]],['24°27.234\'N 54°22.638\'E',[24.4539,54.3773]],
 ['https://www.google.com/maps/@24.4539,54.3773,15z',[24.4539,54.3773]],['https://maps.google.com/?q=24.4539,54.3773',[24.4539,54.3773]],
 [`${u.zone}R ${Math.round(u.x)} ${Math.round(u.y)}`,[24.4539,54.3773]],['E 54.3773 N 24.4539',[24.4539,54.3773]],['٢٤٫٤٥٣٩، ٥٤٫٣٧٧٣',[24.4539,54.3773]],['-33.8688, 151.2093',[-33.8688,151.2093]],['33°52\'S 151°12\'E',[-33.8667,151.2]]]){
 const c=C.parseCoord(s);assert(c,'parse failed: '+s);near(c[0],exp[0],1e-3);near(c[1],exp[1],1e-3)}
assert.equal(C.parseCoord('hello'),null);
assert.equal(C.side(90,0),'يمينك');assert.equal(C.side(270,0),'يسارك');assert.equal(C.side(10,350),'قدامك');assert.equal(C.side(180,0),'وراك');
assert.equal(C.toMGRS(24.4539,54.3773),'40R BN 34124 07001');assert.equal(C.toMGRS(-33.8688,151.2093),'56H LH 34368 50948');
// the user's own examples
for(const[s,exp]of[['28.391972, 46.336194',[28.391972,46.336194]],['28°23\'31.1"N 46°20\'10.3"E',[28.391972,46.336194]],['28°23.5183\'N 46°20.1716\'E',[28.391972,46.336194]],['28 23.5183 N 46 20.1716 E',[28.391972,46.336194]]]){
 const c=C.parseCoordStrict(s);assert(c,'strict failed: '+s);near(c[0],exp[0],2e-5);near(c[1],exp[1],2e-5)}
for(const s of['28°63\'31"N 46°20\'10"E','28°23\'71"N 46°20\'10"E','95, 46','28, 190','-28.1 N, 46 E'])assert.equal(C.parseCoordStrict(s),null,'should reject '+s);
// round trip through every display format
for(const c of[[28.391972,46.336194],[-12.5,-77.03]]){const f=C.formats(c);for(const i of[0,1,2,3]){const b=C.parseCoord(f[i][1]);assert(b,f[i][1]);near(b[0],c[0],2e-4);near(b[1],c[1],2e-4)}}
// a recorded drive: east 3 km, north 2 km, then back west crossing the first leg's line of travel
const O=[28,46],mv=(dx,dy)=>[O[0]+dy/111320,O[1]+dx/(111320*Math.cos(O[0]*Math.PI/180))];
let clk=0;const step=(a,b,n)=>Array.from({length:n},(_,i)=>({c:mv(a[0]+(b[0]-a[0])*i/n,a[1]+(b[1]-a[1])*i/n),t:(clk+=10000),s:10}));
const leg1=step([0,0],[3000,0],30),leg2=step([3000,0],[3000,1000],10),leg3=step([3000,1000],[1500,-500],20);
const segs=[[...leg1,...leg2,...leg3]];
const st=C.trackStats(segs);near(st.dist,3000+1000+Math.hypot(1500,1500)-Math.hypot(75,75),40);near(st.max,10,.01);assert(st.moving>0&&st.avg>5);
const route=C.reverseRoute(segs);near(route[route.length-1].cum,st.dist,1);
assert.deepEqual(route[0].c,leg3[leg3.length-1].c);
// start of the way back is on leg3 reversed; the point where leg3 crosses leg1 must match leg3 while you're still on it
let k=0,pr=C.routeProgress(route,mv(1600,-400),k);assert(pr&&pr.xt<5,'on leg3');k=pr.k;
const cross=mv(2000,0);pr=C.routeProgress(route,cross,k);assert(pr.along<Math.hypot(1500,1500)+5,'crossing matched the current leg, along='+pr.along);
// off track
pr=C.routeProgress(route,mv(1600,-200),0);assert(pr.xt>100);
// gaps: a jump splits; reverse keeps the gap flagged
assert(C.isGap({c:[28,46],t:0},{c:[28.1,46],t:5000}));assert(!C.isGap({c:[28,46],t:0},{c:[28.0001,46],t:5000}));assert(C.isGap({c:[28,46],t:0},{c:[28,46],t:120000}));
const r2=C.reverseRoute([[{c:[28,46],t:0},{c:[28,46.001],t:1}],[{c:[28,46.01],t:9},{c:[28,46.011],t:10}]]);assert.deepEqual(r2.map(p=>p.gap),[false,false,true,false]);
pr=C.routeProgress(r2,[28,46.005],0);assert(pr.k!==1,'never matches across a gap');
const g=C.toGPX([{n:'المخيم <1>',c:[28.391972,46.336194],cat:'camp',note:'جنب الطلحة'}],[{name:'رحلة',segs}]);assert(g.includes('المخيم &lt;1&gt;')&&g.includes('<type>camp</type>')&&(g.match(/<trkpt/g)||[]).length===60);
// 46.7E 24.7N at z14: x=floor(226.7/360*16384)=10317, y=floor((1-asinh(tan 24.7°)/π)/2*16384)=7031; z0 is one tile; a small box gives a few tiles per zoom
assert.deepEqual(C.tilesIn([46.7,24.7,46.7,24.7],14,14),[[14,10317,7031]]);assert.equal(C.tilesIn([-180,-85,180,85],0,0).length,1);assert.equal(C.tilesIn([46,24,47,25],0,4).length,5);
// mushaf: page 2 opens Al-Baqarah, juz 30 opens An-Naba, page 604 ends with An-Nas, 6236 ayahs
assert.deepEqual(C.qLoc(C.QPAGE[2]),[2,1]);assert.deepEqual(C.qLoc(C.QJUZ[30]),[78,1]);assert.deepEqual(C.qLoc(6236),[114,6]);assert.equal(C.QSTART[114],6237);
assert.equal(C.qFind(C.QPAGE,6236),604);assert.equal(C.qFind(C.QPAGE,1),1);assert.equal(C.qFind(C.QJUZ,C.QSTART[1]+141),2,'2:142 starts juz 2');assert.deepEqual(C.qLoc(C.QJUZ[2]),[2,142]);
console.log('ok');
