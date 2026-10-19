# scrum-app

A Scrum trainer for one Scrum Team, built on the rules of the [2020 Scrum Guide](https://scrumguides.org/scrum-guide.html).
It guides the team through the Sprint, blocks deviations from the Guide unless the team overrides them with a
reason, and logs every exception so the team can learn from it in the Retrospective.

The product name is not final. It lives in one place, [`src/config/product.ts`](src/config/product.ts), or can be set
with `NEXT_PUBLIC_PRODUCT_NAME`. Code, packages and cloud resources use the neutral name `scrum-app`.

## What's here

| Path | What it is |
|---|---|
| `src/rules/` | The rules engine: Guide rules, guidance and team agreements as pure TypeScript functions, with unit tests. No UI or storage, so the app and future integrations (Jira, Azure DevOps) share it. |
| `app/` | The Next.js app. For now a start page; the workflow screens move here from the prototype step by step. |
| `public/prototype/` | The clickable prototype ("Sprint Gate"), kept as the reference for the workflow. |
| `e2e/` | Playwright browser tests. |
| `.github/workflows/ci.yml` | CI: type check, unit tests, build, browser tests and the container image. |
| `Dockerfile` | One container image that runs on any cloud (Azure Container Apps first). |

## Rule tiers

- **Guide rule**: blocks. An override needs a reason and marks the Sprint as not following Scrum.
- **Guide guidance**: warns. Accepting is logged once per Sprint.
- **Team agreement**: blocks like a rule, but an override doesn't count against Scrum.

## Run it

```sh
npm ci
npm run dev          # http://localhost:3000
npm test             # rules engine unit tests
npm run build && npm run test:e2e   # browser tests
```

Where Playwright can't download browsers, point it at an installed Chromium with `PW_CHROMIUM_PATH`.

## Licence of the Guide text

Rule texts are quoted from the 2020 Scrum Guide by Ken Schwaber and Jeff Sutherland, licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
