// Sayfadaki betiklerin eski Android WebView'larda da çalışması için sözdizimi denetimi.
// Kullanım: node araclar/js-uyumluluk.js index.html [ecmaSürümü=2019]
// ES2019 (Chrome 73) üstü sözdizimi (??, ?., ||=, sınıf alanları...) ya da inset/aspect-ratio gibi yerleşim CSS'i
// bulunursa satırıyla yazar ve hata koduyla çıkar.
const acorn = require('acorn'), fs = require('fs');
const dosya = process.argv[2], surum = +process.argv[3] || 2019;
const h = fs.readFileSync(dosya, 'utf8');
const re = /<script(?![^>]*src=)[^>]*>([\s\S]*?)<\/script>/g;
let m, hata = 0;
while ((m = re.exec(h))) {
  const bas = h.slice(0, m.index + m[0].indexOf('>') + 1).split('\n').length - 1;
  try { acorn.parse(m[1], { ecmaVersion: surum, sourceType: 'script', allowReturnOutsideFunction: true }); }
  catch (e) { hata++; console.error(`${dosya}:${bas + e.loc.line}: ES${surum} dışı sözdizimi (${e.message})`); }
}
// Yerleşimi bozan yeni CSS: eski WebView'da (Chrome 87 öncesi) öğe boyutsuz kalır, harita görünmez
h.split('\n').forEach((satir, i) => {
  const b = satir.match(/(^|[^-\w])inset\s*:|aspect-ratio\s*:/);
  if (b) { hata++; console.error(`${dosya}:${i + 1}: eski WebView'da çalışmayan CSS (${b[0].trim()}); top/right/bottom/left kullanın`); }
});
if (hata) process.exit(1);
console.log(`${dosya}: betikler ES${surum} ile uyumlu`);
