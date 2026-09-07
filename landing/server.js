/* Petit serveur statique pour prévisualiser la landing page en local.
   Usage : node server.js   →   http://localhost:4180 */
const http = require('http');
const fs   = require('fs');
const path = require('path');

// Racine servie : le dossier passé en argument, sinon celui du script.
// Permet de servir la landing (défaut) ou les maquettes sans dupliquer ce fichier.
const ROOT = path.resolve(process.argv[2] || __dirname);
const PORT = Number(process.env.PORT) || Number(process.argv[3]) || 4180;

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css' : 'text/css; charset=utf-8',
  '.js'  : 'text/javascript; charset=utf-8',
  '.svg' : 'image/svg+xml',
  '.png' : 'image/png',
  '.jpg' : 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.ico' : 'image/x-icon'
};

http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const rel = url === '/' ? 'index.html' : url.replace(/^\/+/, '');
  const file = path.join(ROOT, rel);

  // On ne sert rien en dehors du dossier.
  if (!file.startsWith(ROOT)) { res.writeHead(403).end('Forbidden'); return; }

  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }).end('404'); return; }
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Cache-Control': 'no-store'
    });
    res.end(buf);
  });
}).listen(PORT, () => console.log(`Yalla → http://localhost:${PORT}  (racine : ${ROOT})`));
