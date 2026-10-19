import pg from 'pg';

// One pool per server process. DATABASE_URL is a standard PostgreSQL connection string.
const globalForPool = globalThis as unknown as { pool?: pg.Pool };

export function pool(): pg.Pool {
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is not set');
  return (globalForPool.pool ??= new pg.Pool({ connectionString: process.env.DATABASE_URL }));
}

export async function closePool(): Promise<void> {
  await globalForPool.pool?.end();
  globalForPool.pool = undefined;
}
