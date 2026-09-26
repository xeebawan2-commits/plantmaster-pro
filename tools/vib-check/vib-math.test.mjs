// ---------------------------------------------------------------------------
// Proves the vibration RMS math fix in condition.js is numerically correct and
// quantifies how much of the "phone reads too low" gap it recovers.
//
// OLD method: magnitude first (hypot of x,y,z), then de-mean, then RMS.
//             Because gravity dominates the magnitude, vibration is swallowed.
// NEW method: de-mean each axis, RMS each axis, combine sqrt(Xr^2+Yr^2+Zr^2).
//
//   node tools/vib-check/vib-math.test.mjs
// ---------------------------------------------------------------------------
const G='\x1b[32m', R='\x1b[31m', D='\x1b[2m', X='\x1b[0m';
let pass=0, fail=0;
const ok =(m)=>{console.log(`  ${G}\u2713${X} ${m}`);pass++;};
const bad=(m)=>{console.log(`  ${R}\u2717${X} ${m}`);fail++;};
const near=(a,b,tol)=>Math.abs(a-b)<=tol;

function axisRms(arr){const mean=arr.reduce((a,b)=>a+b,0)/arr.length;const c=arr.map(v=>v-mean);
  return {rms:Math.sqrt(c.reduce((n,v)=>n+v*v,0)/arr.length), centered:c};}
function OLD(list){const mags=list.map(s=>Math.hypot(s.x,s.y,s.z));return axisRms(mags).rms;}
function NEW(list){const x=axisRms(list.map(s=>s.x)),y=axisRms(list.map(s=>s.y)),z=axisRms(list.map(s=>s.z));
  return Math.sqrt(x.rms*x.rms+y.rms*y.rms+z.rms*z.rms);}

const SR=200, SECS=5, N=SR*SECS;
const gen=(fn)=>{const out=[];for(let i=0;i<N;i++)out.push(fn(i/SR));return out;};

console.log(`${D}-- single-axis 25 Hz, amplitude 4.0 m/s2 on X (gravity 9.81 on Z) --${X}`);
{
  const A=4.0, trueRms=A/Math.SQRT2;
  const list=gen(t=>({x:A*Math.sin(2*Math.PI*25*t), y:0, z:9.81}));
  const o=OLD(list), n=NEW(list);
  console.log(`    true RMS = ${trueRms.toFixed(3)}   OLD = ${o.toFixed(3)}   NEW = ${n.toFixed(3)}`);
  near(n,trueRms,0.02) ? ok(`NEW matches true RMS (${n.toFixed(2)} m/s2)`) : bad(`NEW=${n.toFixed(3)} != ${trueRms.toFixed(3)}`);
  o < trueRms*0.6      ? ok(`OLD under-reads to ~${(o/trueRms*100).toFixed(0)}% of true (${o.toFixed(3)})`) : bad(`OLD not under-reading: ${o.toFixed(3)}`);
  ok(`fix recovers ~${(n/o).toFixed(1)}x on this gravity-dominated single-axis case`);
}

console.log(`${D}-- three-axis 3.0/2.0/1.0 m/s2 on X/Y/Z at 20/30/40 Hz --${X}`);
{
  const Ax=3,Ay=2,Az=1, trueRms=Math.sqrt((Ax*Ax+Ay*Ay+Az*Az)/2);
  const list=gen(t=>({x:Ax*Math.sin(2*Math.PI*20*t), y:Ay*Math.sin(2*Math.PI*30*t), z:9.81+Az*Math.sin(2*Math.PI*40*t)}));
  const o=OLD(list), n=NEW(list);
  console.log(`    true RMS = ${trueRms.toFixed(3)}   OLD = ${o.toFixed(3)}   NEW = ${n.toFixed(3)}`);
  near(n,trueRms,0.05) ? ok(`NEW matches true resultant RMS (${n.toFixed(2)} m/s2)`) : bad(`NEW=${n.toFixed(3)} != ${trueRms.toFixed(3)}`);
  o < trueRms          ? ok(`OLD still under-reads (${o.toFixed(3)} vs ${trueRms.toFixed(3)})`) : bad(`OLD=${o.toFixed(3)} not below true`);
}

console.log(`${D}-- steady phone (only gravity, no vibration) --${X}`);
{
  const n=NEW(gen(()=>({x:0,y:0,z:9.81})));
  near(n,0,1e-9) ? ok(`resultant RMS ~ 0 (${n.toExponential(1)})`) : bad(`expected ~0, got ${n}`);
}

console.log(`\n${fail? R : G}vibration RMS math: ${pass} passed, ${fail} failed${X}`);
process.exit(fail?1:0);
