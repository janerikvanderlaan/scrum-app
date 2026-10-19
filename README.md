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
| `app/` | The Next.js app: the team list and the Team and goals stage. The other stages move here from the prototype step by step. |
| `src/db/`, `db/migrations/` | Storage in PostgreSQL: teams, members, Definition of Done and the exception log. |
| `scripts/` | `migrate.mjs` applies the SQL migrations; `seed.mjs` adds the example teams Atlas and Borealis. |
| `public/prototype/` | The clickable prototype ("Sprint Gate"), kept as the reference for the workflow. |
| `e2e/` | Playwright browser tests. They reset the example teams before each run. |
| `.github/workflows/ci.yml` | CI: type check, unit tests, build, browser tests and the container image. |
| `Dockerfile` | One container image that runs on any cloud (Azure Container Apps first). |

## Rule tiers

- **Guide rule**: blocks. An override needs a reason and marks the Sprint as not following Scrum.
- **Guide guidance**: warns. Accepting is logged once per Sprint.
- **Team agreement**: blocks like a rule, but an override doesn't count against Scrum.

## Run it

The app needs PostgreSQL 16 or later. Point `DATABASE_URL` at an empty database, for example
`postgres://postgres:postgres@localhost:5432/scrum_app`.

```sh
npm ci
npm run db:migrate && npm run db:seed
npm run dev          # http://localhost:3000
npm test             # rules engine unit tests
npm run test:db      # database tests
npm run build && npm run test:e2e   # browser tests
```

There is no sign-in yet: everyone who can open the app sees every team, and exceptions are logged as "Team member".

Where Playwright can't download browsers, point it at an installed Chromium with `PW_CHROMIUM_PATH`.

### In a Dev Container or Codespace

`.devcontainer/` sets up Node, PostgreSQL 16 and Chromium for you, then migrates and seeds the database.

- **GitHub Codespaces:** on the repository page choose Code → Codespaces → Create codespace. Nothing to install.
- **VS Code on your own machine:** install Docker Desktop and the Dev Containers extension, open the folder and choose "Reopen in Container".

Then run `npm run dev` and open the forwarded port 3000. All the test commands above work as they are.

## Licence of the Guide text

Rule texts are quoted from the 2020 Scrum Guide by Ken Schwaber and Jeff Sutherland, licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
