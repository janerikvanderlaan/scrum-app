import Link from 'next/link';
import { notFound } from 'next/navigation';
import { AutoSubmitSelect } from '@/app/components/AutoSubmitSelect';
import { getTeam, listExceptions, ROLES } from '@/src/db/teams';
import {
  MIN_REASON_LENGTH, RULES, countKinds, followsScrum, kindFor, kindLabel, pendingFindings, teamChecks,
  type ExceptionRecord, type Finding,
} from '@/src/rules';
import { STAGES } from '@/src/workflow';
import {
  addDod, addTeamMember, backToTeam, changeRole, decide, deleteDod, deleteMember, saveProductGoal, startPlanning,
} from './actions';

export const dynamic = 'force-dynamic';

const TIER_LABEL = { rule: 'Guide rule · blocked', guidance: 'Guide guidance · warning', confirm: 'Guide guidance · confirm', team: 'Team agreement · blocked' };

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`;

/** Red while a decision is open about this part of the screen, amber once an exception is logged for it. */
function flag(target: string, pending: Finding | undefined, log: readonly ExceptionRecord[]) {
  if (pending?.target === target) return { className: 'block flag-pending' };
  const rules = [...new Set(log.filter(o => o.target === target).map(o => o.rule))];
  if (!rules.length) return { className: 'block' };
  return { className: `block ${log.some(o => o.target === target && o.kind === 'override') ? 'flag-override' : 'flag-warning'}`, 'data-exception': `Exception: ${rules.join(', ')}` };
}

export default async function TeamPage({ params, searchParams }: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ decide?: string; error?: string }>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  const team = await getTeam(decodeURIComponent(id));
  if (!team) notFound();
  const log = await listExceptions(team.id, team.sprintNumber);
  const pending = team.stage === 0 && query.decide ? pendingFindings(teamChecks(team), log, team.sprintNumber)[0] : undefined;
  const kc = countKinds(log);

  return (
    <div className="shell">
      <header className="top">
        <div><Link href="/" className="crumb">Teams</Link> / <b>{team.name}</b></div>
        <span className={followsScrum(log) ? 'tag tag-ok' : 'tag tag-block'}>{followsScrum(log) ? 'Following the Scrum Guide' : 'Not following the Scrum Guide'}</span>
      </header>
      <ol className="stages" aria-label="Sprint stages">
        {STAGES.map((s, i) => <li key={s} className={i === team.stage ? 'current' : i < team.stage ? 'done' : ''}>{s}</li>)}
      </ol>

      <div className="work">
        <main>
          {team.stage === 0 ? (
            <>
              <div><span className="eyebrow">Stage 1 of 6</span><h1>Set up {team.name}</h1></div>

              <section {...flag('members', pending, log)}>
                <h2>Scrum Team</h2>
                <p className="note">One Product Owner, one Scrum Master and Developers, typically 10 or fewer people.</p>
                <table>
                  <thead><tr><th>Name</th><th>Accountability</th><th /></tr></thead>
                  <tbody>
                    {team.members.map(m => (
                      <tr key={m.id}>
                        <td>{m.name}</td>
                        <td>
                          <form action={changeRole.bind(null, team.id, m.id)}>
                            <AutoSubmitSelect name="role" defaultValue={m.role} aria-label={`Accountability of ${m.name}`}>
                              {ROLES.map(r => <option key={r}>{r}</option>)}
                            </AutoSubmitSelect>
                          </form>
                        </td>
                        <td><form action={deleteMember.bind(null, team.id, m.id)}><button className="btn quiet" aria-label={`Remove ${m.name}`}>Remove</button></form></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <form action={addTeamMember.bind(null, team.id)} className="row">
                  <input name="name" placeholder="Name" aria-label="New member name" required />
                  <select name="role" aria-label="New member accountability" defaultValue="Developer">{ROLES.map(r => <option key={r}>{r}</option>)}</select>
                  <button className="btn ghost">Add member</button>
                </form>
              </section>

              <section {...flag('pgoal', pending, log)}>
                <h2>Product Goal</h2>
                <form action={saveProductGoal.bind(null, team.id)} className="stack">
                  <textarea name="productGoal" defaultValue={team.productGoal} placeholder="The future state of the product the team plans against." aria-label="Product Goal" />
                  <div><button className="btn ghost">Save Product Goal</button></div>
                </form>
              </section>

              <section {...flag('dod', pending, log)}>
                <h2>Definition of Done</h2>
                {team.dod.length ? (
                  <ol className="dod">
                    {team.dod.map(d => (
                      <li key={d.id}>{d.text} <form action={deleteDod.bind(null, team.id, d.id)} className="inline"><button className="btn quiet" aria-label={`Remove ${d.text}`}>Remove</button></form></li>
                    ))}
                  </ol>
                ) : <p className="note">No Definition of Done yet.</p>}
                <form action={addDod.bind(null, team.id)} className="row">
                  <input name="text" placeholder="Add a quality measure, for example: Security scan passes" aria-label="New Definition of Done item" required />
                  <button className="btn ghost">Add</button>
                </form>
              </section>

              <form action={startPlanning.bind(null, team.id)}><button className="btn" id="next">Start Sprint {team.sprintNumber} Planning</button></form>
            </>
          ) : (
            <>
              <div><span className="eyebrow">Stage {team.stage + 1} of 6</span><h1>Sprint {team.sprintNumber} Planning</h1></div>
              <section className="block">
                <p className="note">Sprint Planning moves into the app next. Until then it lives in the <a href="/prototype/index.html">prototype</a>.</p>
                <form action={backToTeam.bind(null, team.id)}><button className="btn ghost">Back to Team and goals</button></form>
              </section>
            </>
          )}
        </main>

        <aside className="log" aria-label="Exception log">
          <h2>Exception log · Sprint {team.sprintNumber}</h2>
          {log.length ? (
            <>
              <p className="note">{plural(kc.guide, 'Guide rule override')} · {plural(kc.team, 'team agreement override')} · {plural(kc.warn, 'accepted warning')}</p>
              <ul>
                {log.map((o, i) => (
                  <li key={i} className={o.kind}>
                    <span><span className="mono">{o.rule}</span> · {kindLabel(o)}</span>
                    <b>{o.detail}</b>
                    <q>{RULES[o.rule].text}</q>
                    {o.reason && <span>Reason: {o.reason}</span>}
                    <span className="note">{o.who} · {o.stage}{o.day ? ` · day ${o.day}` : ''} · {o.time}</span>
                  </li>
                ))}
              </ul>
            </>
          ) : <p className="note">No exceptions in this Sprint. Every block you override or warning you accept lands here and goes to the Retrospective.</p>}
        </aside>
      </div>

      {pending && (
        <div className="modal" role="dialog" aria-modal="true" aria-labelledby="dlg-title">
          <form action={decide.bind(null, team.id)} className="dialog">
            <span className="eyebrow">{pending.rule} · {TIER_LABEL[RULES[pending.rule].tier]}</span>
            <h2 id="dlg-title">{pending.detail}</h2>
            <q>{RULES[pending.rule].text}</q>
            <input type="hidden" name="rule" value={pending.rule} />
            <input type="hidden" name="target" value={pending.target} />
            <input type="hidden" name="detail" value={pending.detail} />
            {kindFor(pending.rule) === 'override' && (
              <>
                <label htmlFor="ov-reason">Why does the team need to go ahead anyway?</label>
                <textarea id="ov-reason" name="reason" required minLength={MIN_REASON_LENGTH} autoFocus
                  placeholder="For example: our coach starts next month and takes the Scrum Master role." />
                {query.error === 'reason' && <p className="error">Give a reason of at least {MIN_REASON_LENGTH} characters.</p>}
              </>
            )}
            <div className="row end">
              <Link href={`/teams/${encodeURIComponent(team.id)}`} className="btn ghost" id="ov-cancel">Cancel</Link>
              <button className={kindFor(pending.rule) === 'override' ? 'btn danger' : 'btn'} id="ov-go">
                {kindFor(pending.rule) === 'override' ? 'Override and log' : 'Continue'}
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
