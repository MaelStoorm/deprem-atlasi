// WebView'a DevTools üzerinden bağlanıp sayfanın durumunu yazar
(async()=>{
  const list=await (await fetch('http://127.0.0.1:9222/json')).json();
  const t=list.find(x=>x.type==='page')||list[0];
  const ws=new WebSocket(t.webSocketDebuggerUrl);await new Promise(r=>ws.onopen=r);
  let id=0;const ev=(expr)=>new Promise(r=>{const i=++id;ws.addEventListener('message',function f(m){const d=JSON.parse(m.data);if(d.id===i){ws.removeEventListener('message',f);r(d.result)}});ws.send(JSON.stringify({id:i,method:'Runtime.evaluate',params:{expression:expr,returnByValue:true}}));});
  const expr=`(()=>{const q=s=>document.querySelector(s);const box=e=>{if(!e)return null;const r=e.getBoundingClientRect();return [Math.round(r.x),Math.round(r.y),Math.round(r.width),Math.round(r.height)]};
   const svg=q('#harita svg');return JSON.stringify({harita:box(q('#harita')),sar:box(q('#harita-sar')),svg:box(svg),svgVB:svg&&svg.getAttribute('viewBox'),paths:document.querySelectorAll('#harita path').length,
   gs:[...document.querySelectorAll('#harita svg g[id]')].slice(0,14).map(g=>g.id+':'+g.childElementCount+':'+(box(g)||[]).join('x')),
   sarTr:getComputedStyle(q('#harita-sar')).transform})})()`;
  console.log(JSON.stringify(await ev(expr)));ws.close();
})().catch(e=>{console.log('CDP hata',e.message)});
