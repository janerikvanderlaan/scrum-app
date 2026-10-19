import { execFileSync } from 'node:child_process';

// Database tests share one database, so migrations run once before any of them.
export default function setup() {
  execFileSync('node', ['scripts/migrate.mjs'], { stdio: 'inherit' });
}
