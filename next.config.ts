import type { NextConfig } from 'next';

// The container build sets NEXT_STANDALONE=1 to get a minimal server; local runs and tests use "next start".
// GitHub Codespaces serves the app on a forwarded *.app.github.dev address. The dev server only serves its
// scripts to known hosts, and Server Actions reject requests whose origin differs from the forwarded host
// (which Codespaces sets to localhost), so allow this Codespace's own address there.
const codespaceHost = process.env.CODESPACE_NAME && process.env.GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN
  ? `${process.env.CODESPACE_NAME}-${process.env.PORT ?? 3000}.${process.env.GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}`
  : undefined;

const config: NextConfig = {
  allowedDevOrigins: ['*.app.github.dev'],
  ...(codespaceHost ? { experimental: { serverActions: { allowedOrigins: [codespaceHost] } } } : {}),
  ...(process.env.NEXT_STANDALONE === '1' ? { output: 'standalone' as const } : {}),
};

export default config;
