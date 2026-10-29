// node check.js — asserts the pure math in app.html
const fs=require('fs'),assert=require('assert');
const src=fs.readFileSync(__dirname+'/app.html','utf8').split('// CORE-START')[1].replace(/^.*\n/,'').split('// CORE-END')[0];
const C=new Function(src+';return{prayerTimes,bearing,distance,toUTM,fromUTM,parseCoord,formats,side,toMGRS}')();
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
console.log(C.formats([24.4539,54.3773]));console.log('ok');
