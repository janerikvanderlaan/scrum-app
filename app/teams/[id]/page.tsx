import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getTeam, listExceptions } from '@/src/db/teams';
import { followsScrum, pendingFindings } from '@/src/rules';
import { STAGES } from '@/src/workflow';
import { goToStage } from './actions';
import { DecisionDialog } from './DecisionDialog';
import { ExceptionLog } from './ExceptionLog';
import { findingsFor, intentFields, loadTeamData, parseIntent } from './intents';
import { PlanningStage } from './PlanningStage';
import { SprintStage } from './SprintStage';
import { TeamStage } from './TeamStage';

export const dynamic = 'force-dynamic';

export default async function TeamPage({ params, searchParams }: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  const team = await getTeam(decodeURIComponent(id));
  if (!team) notFound();
  const [log, data] = await Promise.all([listExceptions(team.id, team.sprintNumber), loadTeamData(team)]);
  const intent = parseIntent(key => query[key]);
  const pending = intent ? pendingFindings(findingsFor(team, data, intent), log, team.sprintNumber)[0] : undefined;

  return (
    <div className="shell">
      <header className="top">
        <div><Link href="/" className="crumb">Teams</Link> / <b>{team.name}</b></div>
        <span className={followsScrum(log) ? 'tag tag-ok' : 'tag tag-block'}>{followsScrum(log) ? 'Following the Scrum Guide' : 'Not following the Scrum Guide'}</span>
      </header>
      <ol className="stages" aria-label="Sprint stages">
        {STAGES.map((s, i) => (
          <li key={s} className={i === team.stage ? 'current' : i < team.stage ? 'done' : ''}>
            {i < team.stage ? <form action={goToStage.bind(null, team.id, i)}><button className="stage-link">{s}</button></form> : s}
          </li>
        ))}
      </ol>

      <div className="work">
        <main>
          {team.stage === 0 && <TeamStage team={team} pending={pending} log={log} />}
          {team.stage === 1 && <PlanningStage team={team} planning={data.planning} pending={pending} log={log} />}
          {team.stage === 2 && <SprintStage team={team} sprint={data.sprint} pending={pending} log={log} checking={query.check} />}
          {team.stage >= 3 && (
            <>
              <div><span className="eyebrow">Stage {team.stage + 1} of 6</span><h1>Sprint {team.sprintNumber} Review</h1></div>
              <section className="block">
                <p className="note">The Sprint Review moves into the app next. Until then it lives in the <a href="/prototype/index.html">prototype</a>.</p>
                <form action={goToStage.bind(null, team.id, 2)}><button className="btn ghost">Back to the Sprint</button></form>
              </section>
            </>
          )}
        </main>
        <ExceptionLog sprint={team.sprintNumber} log={log} />
      </div>

      {pending && intent && <DecisionDialog teamId={team.id} finding={pending} fields={intentFields(intent)} error={query.error} />}
    </div>
  );
}
