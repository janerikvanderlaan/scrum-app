import type { NextConfig } from 'next';

// The container build sets NEXT_STANDALONE=1 to get a minimal server; local runs and tests use "next start".
// The dev server only serves its scripts to known hosts, so allow GitHub Codespaces' forwarded URLs.
const config: NextConfig = {
  allowedDevOrigins: ['*.app.github.dev'],
  ...(process.env.NEXT_STANDALONE === '1' ? { output: 'standalone' as const } : {}),
};

export default config;
