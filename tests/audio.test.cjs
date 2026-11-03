const fs=require('fs'),vm=require('vm'),assert=require('assert');
const html=fs.readFileSync(require('path').join(__dirname,'../app/Resources/index.html'),'utf8');
const elements=new Map(),messages=[],media=[],jobs=new Map(); let now=10000,id=0;
function el(){return {style:{setProperty(){}},dataset:{},classList:{toggle(){},add(){},remove(){},contains(){return false}},setAttribute(k,v){this[k]=v},appendChild(){},add(){},querySelector(){return el()},hidden:true,textContent:'',value:'',tagName:'BODY'};}
function get(s){if(!elements.has(s))elements.set(s,el());return elements.get(s)}
class Audio{constructor(src){this.src=src;this.currentTime=0;this.volume=1;this.paused=true;this.plays=0;media.push(this)}play(){this.paused=false;this.plays++;return Promise.resolve()}pause(){this.paused=true}}
class AudioContext{constructor(){this.currentTime=0;this.state='running';this.sampleRate=44100;this.destination={}}createGain(){return {gain:{value:0,setTargetAtTime(v){this.value=v},cancelScheduledValues(){},setValueAtTime(v){this.value=v},linearRampToValueAtTime(){},exponentialRampToValueAtTime(){}},connect(){}}}createBuffer(channels,length){return {getChannelData:()=>new Float32Array(length)}}createBufferSource(){return {connect(){},start(){this.starts=(this.starts||0)+1},stop(){this.stopped=true},disconnect(){}}}createOscillator(){return {frequency:{value:0},connect(g){return g},start(){},stop(){this.stopped=true},disconnect(){}}}}
const ctx={console,Audio,Option:function(){},Date:{now:()=>now},setInterval:f=>{jobs.set(++id,f);return id},clearInterval:i=>jobs.delete(i),setTimeout:f=>{jobs.set(++id,f);return id},clearTimeout:i=>jobs.delete(i),localStorage:{getItem:()=>null,setItem(){}},document:{querySelector:get,querySelectorAll:()=>[],createElement:el,addEventListener(){},body:el(),activeElement:el()},window:{AudioContext,webkit:{messageHandlers:{tm:{postMessage:m=>messages.push(m)}}}}};vm.createContext(ctx);
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1],ctx);
const run=s=>vm.runInContext(s,ctx);
assert.equal(run('S.sound'),'figjam');
run('$("#vol").oninput({target:{value:"37"}})');assert.equal(run('S.vol'),.37);assert.equal(get('#volValue').textContent,'37%');assert(Math.abs(media[0].volume-.1369)<1e-9);assert.equal(messages.at(-1).type,'volume');
const loop=run('volumePreviewSource');assert(loop.loop);assert.equal(loop.starts,1);
run('$("#vol").onpointerdown()');
for(let percent=38;percent<=80;percent++) run(`$("#vol").oninput({target:{value:"${percent}"}})`);
assert.strictEqual(run('volumePreviewSource'),loop);assert.equal(loop.starts,1);assert(!loop.stopped);
assert(Math.abs(run('master.gain.value')-.64)<1e-9);
run('$("#vol").oninput({target:{value:"0"}})');assert.strictEqual(run('volumePreviewSource'),loop);assert.equal(run('master.gain.value'),0);
run('$("#vol").oninput({target:{value:"45"}})');assert.strictEqual(run('volumePreviewSource'),loop);assert.equal(loop.starts,1);
run('finishVolumeAdjustment()'); jobs.get(run('volumePreviewStopTimer'))();assert(loop.stopped);assert.equal(run('volumePreviewSource'),null);
run('remaining=6000;start()');assert.equal(media[0].plays,0);now+=1000;run('tick()');assert.equal(media[0].plays,1);now+=1000;run('tick()');assert.equal(media[0].plays,1);
run('pause()');assert(media[0].paused);assert.equal(run('remaining'),4000);
run('start()');assert.equal(media[0].plays,2);assert.equal(media[0].currentTime,1);
run('adjust(1)');assert(media[0].paused);
run('remaining=3000;pause();remaining=3000;start()');assert.equal(media[0].currentTime,2);
run('$("#mute").onclick()');assert.equal(media[0].volume,0);assert.equal(messages.at(-1).vol,0);
now+=3000;run('tick()');assert(media[0].paused);assert.equal(media[1].plays,1);assert.equal(media[1].volume,0);run('done()');assert.equal(media[1].plays,1);
run('stopAlarm()');assert(media[1].paused);assert.equal(jobs.size,0);
run('$("#vol").oninput({target:{value:"0"}})');assert.equal(media[0].volume,0);assert.equal(media[1].volume,0);assert.equal(get('#volValue').textContent,'0%');assert(run('volumePreviewSource.loop'));assert.equal(run('master.gain.value'),0);
run('$("#mute").onclick()');assert.equal(run('S.vol'),.5);assert.equal(media[0].volume,.25);
run('$("#preview").onclick()');assert(!media[0].paused);assert.equal(get('#preview').textContent,'듣기 중지');run('$("#preview").onclick()');assert(media[0].paused);assert.equal(jobs.size,0);
console.log('PASS: volume 0/37/50%, live native volume, mute, countdown once, pause/resume offset, add time, completion once, stop, preview cancellation, continuous slider loop, unchanged playback across 43 volume changes and mute, idle cleanup');
