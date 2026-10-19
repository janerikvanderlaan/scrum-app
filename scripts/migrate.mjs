// Applies db/migrations/*.sql in name order, once each. Usage: DATABASE_URL=... node scripts/migrate.mjs
import { readdir, readFile } from 'node:fs/promises';
import pg from 'pg';

const dir = new URL('../db/migrations/', import.meta.url);
const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
try {
  await client.query('create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())');
  const done = new Set((await client.query('select name from schema_migrations')).rows.map(r => r.name));
  for (const name of (await readdir(dir)).filter(f => f.endsWith('.sql')).sort()) {
    if (done.has(name)) continue;
    await client.query('begin');
    await client.query(await readFile(new URL(name, dir), 'utf8'));
    await client.query('insert into schema_migrations (name) values ($1)', [name]);
    await client.query('commit');
    console.log(`applied ${name}`);
  }
} catch (e) {
  await client.query('rollback').catch(() => {});
  throw e;
} finally {
  await client.end();
}
