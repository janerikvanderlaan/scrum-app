import type { NextConfig } from 'next';

// The container build sets NEXT_STANDALONE=1 to get a minimal server; local runs and tests use "next start".
// GitHub Codespaces serves the app on a forwarded *.app.github.dev address. The dev server only serves its
// scripts to known hosts, so allow those. Server Actions reject a request whose origin differs from the
// forwarded host; the Codespaces proxy forwards the public host but can rewrite the origin to localhost, so
// inside a Codespace both the local and the public address count as this app's own.
const port = process.env.PORT ?? '3000';
const codespaceOrigins = process.env.CODESPACE_NAME && process.env.GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN
  ? [`localhost:${port}`, `${process.env.CODESPACE_NAME}-${port}.${process.env.GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}`]
  : undefined;

const config: NextConfig = {
  allowedDevOrigins: ['*.app.github.dev'],
  ...(codespaceOrigins ? { experimental: { serverActions: { allowedOrigins: codespaceOrigins } } } : {}),
  ...(process.env.NEXT_STANDALONE === '1' ? { output: 'standalone' as const } : {}),
};

export default config;
