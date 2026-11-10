// Eski Chromium sürümüyle sayfayı açar, "Haritayı Aç"a basar ve ekran görüntüsü alır
const puppeteer = require('puppeteer');
(async () => {
  const b = await puppeteer.launch({ args: ['--no-sandbox'] });
  const p = await b.newPage();
  const hatalar = [];
  p.on('pageerror', e => hatalar.push(String(e.message)));
  p.on('console', m => { if (m.type() === 'error') hatalar.push(m.text()); });
  await p.setViewport({ width: 393, height: 851, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  await p.goto('file://' + process.cwd() + '/index.html');
  await new Promise(r => setTimeout(r, 3000));
  const fs = require('fs');
  await p.screenshot({ path: process.argv[2] + '-acilis.png' });
  await p.evaluate(() => { const b = document.querySelector('#basla'); if (b) b.click(); });
  await new Promise(r => setTimeout(r, 4000));
  await p.screenshot({ path: process.argv[2] + '-harita.png' });
  fs.writeFileSync(process.argv[2] + '-bilgi.txt', (await b.version()) + '\n' + hatalar.join('\n'));
  await b.close();
})();
