/* Petit serveur statique pour prévisualiser la landing page en local.
   Usage : node server.js   →   http://localhost:4180 */
const http = require('http');
const fs   = require('fs');
const path = require('path');
const { gzip } = require('zlib');

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
  '.ico' : 'image/x-icon',
  '.txt' : 'text/plain; charset=utf-8',
  '.xml' : 'application/xml; charset=utf-8'
};

http.createServer((req, res) => {
  let url;
  try { url = decodeURIComponent(req.url.split('?')[0]); }
  catch { res.writeHead(400).end('Adresse invalide'); return; }
  const rel = url === '/' ? 'index.html' : url.replace(/^\/+/, '');
  const file = path.resolve(ROOT, rel);

  if (!file.startsWith(ROOT + path.sep) || rel.includes('\0')) {
    res.writeHead(403).end('Accès interdit'); return;
  }

  const send = (status, type, buf) => {
    const headers = { 'Content-Type': type, 'Cache-Control': 'no-store', Vary: 'Accept-Encoding' };
    if (req.method === 'HEAD') { res.writeHead(status, headers).end(); return; }
    if (/^(text\/|application\/xml)/.test(type) && /\bgzip\b/.test(req.headers['accept-encoding'] || '')) {
      gzip(buf, (err, compressed) => {
        if (err) { res.writeHead(500).end('Erreur de prévisualisation'); return; }
        res.writeHead(status, { ...headers, 'Content-Encoding': 'gzip' }).end(compressed);
      });
    } else res.writeHead(status, headers).end(buf);
  };
  const notFound = () => fs.readFile(path.join(ROOT, '404.html'), (err, buf) => {
    send(404, err ? TYPES['.txt'] : TYPES['.html'], err ? Buffer.from('404') : buf);
  });
  const type = TYPES[path.extname(file).toLowerCase()];
  if (!type || rel.split(/[\\/]/).some(part => part.startsWith('.'))) { notFound(); return; }
  fs.readFile(file, (err, buf) => err ? notFound() : send(200, type, buf));
}).listen(PORT, '127.0.0.1', () => console.log(`Aperçu → http://127.0.0.1:${PORT}  (racine : ${ROOT})`));
