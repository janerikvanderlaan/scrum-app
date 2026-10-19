import { execFileSync } from 'node:child_process';

// Browser tests change the example teams, so every run starts from freshly seeded ones.
export default function globalSetup() {
  execFileSync('node', ['scripts/migrate.mjs'], { stdio: 'inherit' });
  execFileSync('node', ['scripts/seed.mjs', '--reset'], { stdio: 'inherit' });
}
