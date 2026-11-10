// Regenerates core/schema.js from core/schema.sql.
import fs from 'node:fs';
const root = new URL('..', import.meta.url);
const sql = fs.readFileSync(new URL('core/schema.sql', root), 'utf8');
fs.writeFileSync(new URL('core/schema.js', root),
  `// Generated from schema.sql by \`node local/gen-schema.js\`.\nexport const SCHEMA = ${JSON.stringify(sql)};\n`);
