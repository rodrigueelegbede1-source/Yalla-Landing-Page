#!/usr/bin/env node
/**
 * Vérifie que chaque colonne attendue par les entités TypeORM existe bien
 * dans les migrations SQL.
 *
 * Pourquoi ce script : le projet tourne avec `synchronize: false`, donc TypeORM
 * ne valide RIEN au démarrage. Un désalignement entité/SQL ne se manifeste qu'à
 * la première requête touchant la colonne fautive — souvent en production.
 * Le piège le plus courant est une propriété camelCase sans `name:` explicite :
 * TypeORM cherche alors « dateCreation » quand le SQL déclare « date_creation ».
 *
 * Usage : node scripts/audit-schema.js   (code de sortie 1 si désalignement)
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SQL_DIR = path.join(ROOT, 'database', 'migrations');
const ENT_DIR = path.join(ROOT, 'backend', 'src', 'entities');

// ── 1. Colonnes déclarées dans les migrations ──────────────────────────────
const sql = fs.readdirSync(SQL_DIR).sort()
  .map(f => fs.readFileSync(path.join(SQL_DIR, f), 'utf8')).join('\n');

const tables = {};
const CREATE = /CREATE TABLE (?:IF NOT EXISTS )?([a-z_]+)\s*\(([\s\S]*?)\n\);/gi;
for (let m; (m = CREATE.exec(sql));) {
  const cols = [];
  for (let line of m[2].split('\n')) {
    line = line.trim().replace(/,$/, '');
    if (!line || line.startsWith('--')) continue;
    if (/^(PRIMARY|FOREIGN|UNIQUE|CHECK|CONSTRAINT|EXCLUDE)\b/i.test(line)) continue;
    const c = line.match(/^"?([a-z_]+)"?\s/i);
    if (c) cols.push(c[1]);
  }
  tables[m[1]] = cols;
}
// colonnes ajoutées après coup
for (const a of sql.matchAll(/ALTER TABLE ([a-z_]+)[\s\S]*?ADD COLUMN (?:IF NOT EXISTS )?([a-z_]+)/gi)) {
  if (tables[a[1]] && !tables[a[1]].includes(a[2])) tables[a[1]].push(a[2]);
}

// ── 2. Colonnes attendues par les entités ──────────────────────────────────
const problems = [];
const DECO = /@(Column|CreateDateColumn|UpdateDateColumn|PrimaryGeneratedColumn|PrimaryColumn)\(([^;]*?)\)\s*(?:@\w+\([^)]*\)\s*)*?([a-zA-Z_]\w*)[?!]?\s*:/g;

for (const file of fs.readdirSync(ENT_DIR).filter(f => f.endsWith('.entity.ts'))) {
  const src = fs.readFileSync(path.join(ENT_DIR, file), 'utf8');
  for (const block of src.split(/@Entity\(/).slice(1)) {
    const table = (block.match(/^'([a-z_]+)'/) || [])[1];
    if (!table) continue;
    const known = tables[table];

    for (let d; (d = DECO.exec(block));) {
      const [, , args, prop] = d;
      const named = (args.match(/name:\s*'([a-z_0-9]+)'/) || [])[1];
      const col = named || prop;
      if (!known) { problems.push({ table, col, prop, file, kind: 'table absente du SQL' }); continue; }
      if (!known.includes(col)) {
        problems.push({
          table, col, prop, file,
          kind: /[A-Z]/.test(prop) && !named ? 'camelCase sans name:' : 'colonne absente du SQL',
        });
      }
    }
    for (const j of block.matchAll(/@JoinColumn\(\{\s*name:\s*'([a-z_0-9]+)'/g)) {
      if (known && !known.includes(j[1])) {
        problems.push({ table, col: j[1], prop: '(relation)', file, kind: 'clé étrangère absente du SQL' });
      }
    }
  }
}

// ── 3. Verdict ─────────────────────────────────────────────────────────────
const nbCols = Object.values(tables).reduce((a, c) => a + c.length, 0);
console.log(`Tables SQL : ${Object.keys(tables).length}   Colonnes SQL : ${nbCols}`);

if (!problems.length) {
  console.log('\x1b[32m✓ Aucun désalignement entité/SQL\x1b[0m');
  process.exit(0);
}
console.log(`\x1b[31m✗ ${problems.length} désalignement(s) :\x1b[0m`);
for (const p of problems) console.log(`  [${p.kind}] ${p.table}.${p.col} — propriété ${p.prop} (${p.file})`);
process.exit(1);
