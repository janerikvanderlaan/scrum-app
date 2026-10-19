import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// Unit tests need nothing; *.db.test.ts files need DATABASE_URL and run with "npm run test:db".
const db = process.env.VITEST_DB === '1';

export default defineConfig({
  resolve: { alias: { '@': fileURLToPath(new URL('.', import.meta.url)) } },
  test: db
    ? { include: ['src/**/*.db.test.ts'], globalSetup: ['src/db/global-setup.ts'], fileParallelism: false }
    : { include: ['src/**/*.test.ts'], exclude: ['src/**/*.db.test.ts', 'node_modules/**'] },
});
