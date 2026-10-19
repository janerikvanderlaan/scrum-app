import { PRODUCT_NAME, PRODUCT_TAGLINE } from '@/src/config/product';
import { RULES } from '@/src/rules';

export default function Home() {
  const rules = Object.entries(RULES);
  const guide = rules.filter(([, r]) => r.tier !== 'team').length;
  return (
    <main>
      <h1>{PRODUCT_NAME}</h1>
      <p>{PRODUCT_TAGLINE}</p>
      <p>
        The rules engine knows {guide} Scrum Guide rules and {rules.length - guide} team agreements.
        The full app is being built; until then the clickable prototype shows the workflow.
      </p>
      <p><a href="/prototype/index.html">Open the prototype</a></p>
    </main>
  );
}
