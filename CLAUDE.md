# Working on scrum-app

- Jan Erik is the Product Owner and architect. Agents work as the Developers. Work comes from the Product Backlog doc; "req:" means build now, "futreq:" means add to the backlog.
- Every rule lives in `src/rules/` as a pure function with a unit test. UI code calls the engine and never re-implements a check.
- Rule IDs (SG-xxx) come from the research project's traceability sheet; quote Guide text exactly and keep the CC BY-SA attribution.
- Keep the product name only in `src/config/product.ts`; use `scrum-app` everywhere else.
- Stay cloud-portable: containers and standard services only (PostgreSQL, OpenID Connect), no cloud-only features in the core.
- Schema changes go in a new numbered file in `db/migrations/`; never edit an applied migration.
- Before pushing (with `DATABASE_URL` set): `npm run typecheck && npm test && npm run test:db && npm run build && npm run test:e2e`.
