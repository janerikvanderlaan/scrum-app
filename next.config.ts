import type { NextConfig } from 'next';

// The container build sets NEXT_STANDALONE=1 to get a minimal server; local runs and tests use "next start".
const config: NextConfig = process.env.NEXT_STANDALONE === '1' ? { output: 'standalone' } : {};

export default config;
