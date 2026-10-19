import Link from 'next/link';
import { PRODUCT_NAME, PRODUCT_TAGLINE } from '@/src/config/product';
import { listTeams } from '@/src/db/teams';
import { newTeam } from './actions';

export const dynamic = 'force-dynamic';

export default async function Home() {
  const teams = await listTeams();
  return (
    <main className="narrow">
      <h1>{PRODUCT_NAME}</h1>
      <p className="note">{PRODUCT_TAGLINE}</p>
      <section className="block">
        <h2>Teams</h2>
        {teams.length ? (
          <ul className="teams">
            {teams.map(t => <li key={t.id}><Link href={`/teams/${encodeURIComponent(t.id)}`}>{t.name}</Link></li>)}
          </ul>
        ) : <p className="note">No teams yet.</p>}
        <form action={newTeam} className="row">
          <input name="name" placeholder="Team name" aria-label="Team name" required />
          <button className="btn">Create team</button>
        </form>
      </section>
      <p className="note">The full workflow is still in the <a href="/prototype/index.html">clickable prototype</a> while the screens move into the app.</p>
    </main>
  );
}
