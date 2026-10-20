import Link from 'next/link';
import type { Sprint, SprintBacklogItem } from '@/src/db/sprint';
import type { Team } from '@/src/db/teams';
import type { ExceptionRecord, Finding, ItemStatus } from '@/src/rules';
import { confirmSprintOrder, goToNextDay, goToStage, holdDailyScrum, markDone, moveItem, startItem, startReview } from './actions';
import { flag } from './flags';

const COLUMNS: [ItemStatus, string][] = [['todo', 'To do'], ['doing', 'In progress'], ['done', 'Done']];

export function SprintStage({ team, sprint, pending, log, checking }: {
  team: Team; sprint: Sprint; pending?: Finding; log: readonly ExceptionRecord[]; checking?: string;
}) {
  const order = new Map(sprint.items.map((b, i) => [b.id, i + 1]));
  const heldToday = sprint.daily[sprint.day] === true;
  const dodItem = sprint.items.find(b => b.id === checking && b.status === 'doing');
  const days = Array.from({ length: sprint.length }, (_, i) => i + 1);

  const card = (b: SprintBacklogItem) => (
    <div key={b.id} {...flag('card', `item-${b.id}`, pending, log)} data-item={b.id}>
      <div className="row"><span className="mono">#{order.get(b.id)}</span><span className="note">{b.points ?? '?'} pts</span></div>
      <span>{b.title}</span>
      {b.status === 'todo' && (
        <form action={startItem.bind(null, team.id, b.id)}>
          <button className="btn ghost small" disabled={!sprint.confirmedBy} title={sprint.confirmedBy ? undefined : 'A Developer confirms the order first'}>Start</button>
        </form>
      )}
      {b.status === 'doing' && <Link className="btn ghost small" href={`?check=${b.id}`}>Check Done</Link>}
      {b.status === 'done' && <span className="tag tag-ok">Done</span>}
    </div>
  );

  return (
    <>
      <div><span className="eyebrow">Stage 3 of 6 · working day {sprint.day} of {sprint.length}</span><h1>Sprint {team.sprintNumber}</h1></div>
      <div className="callout info"><b>Sprint Goal:</b> {team.sprintGoal || 'none'}</div>

      <section {...flag('block', 'order', pending, log)}>
        <h2>Sprint Backlog order</h2>
        {sprint.confirmedBy
          ? <div className="callout ok" id="order-confirmed">Order confirmed by {sprint.confirmedBy}. Start items from the top.</div>
          : <p className="note">Put the items in priority order, top first. A Developer confirms the order before anyone starts work, because the Sprint Backlog belongs to the Developers.</p>}
        <div className="tbl">
          <table>
            <tbody>
              {sprint.items.map((b, i) => (
                <tr key={b.id} data-order-item={b.id}>
                  <td className="num mono">#{i + 1}</td>
                  <td>{b.title}</td>
                  <td className="nowrap">
                    {!sprint.confirmedBy && (
                      <div className="row tight">
                        <form action={moveItem.bind(null, team.id, b.id, -1)}><button className="btn quiet small" disabled={i === 0} aria-label={`Move item ${i + 1} up`}>↑</button></form>
                        <form action={moveItem.bind(null, team.id, b.id, 1)}><button className="btn quiet small" disabled={i === sprint.items.length - 1} aria-label={`Move item ${i + 1} down`}>↓</button></form>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {!sprint.confirmedBy && (
          <form action={confirmSprintOrder.bind(null, team.id)} className="row">
            <select name="member" aria-label="Team member who confirms" defaultValue="" required>
              <option value="" disabled>Who confirms the order?</option>
              {team.members.map(m => <option key={m.id} value={m.id}>{m.name} ({m.role})</option>)}
            </select>
            <button className="btn" id="confirm-order">Confirm order</button>
          </form>
        )}
      </section>

      <section className="block">
        <h2>Daily Scrum · 15 minutes</h2>
        <div {...flag('days', 'days', pending, log)}>
          {days.map(d => {
            const state = sprint.daily[d] === true ? 'held' : sprint.daily[d] === false ? 'skipped' : '';
            return <span key={d} {...flag(`day ${state} ${d === sprint.day ? 'today' : ''}`.trim(), `day-${d}`, pending, log)} title={`Day ${d}`}>{d}</span>;
          })}
        </div>
        <div className="row">
          {heldToday
            ? <span className="tag tag-ok">Daily Scrum held today</span>
            : <form action={holdDailyScrum.bind(null, team.id)}><button className="btn ghost" id="daily">Hold today&apos;s Daily Scrum</button></form>}
          {sprint.day < sprint.length && <form action={goToNextDay.bind(null, team.id)}><button className="btn quiet" id="nextday">Go to day {sprint.day + 1}</button></form>}
        </div>
      </section>

      {dodItem && (
        <section className="block dod-check">
          <h2>Definition of Done for “{dodItem.title}”</h2>
          <form action={markDone.bind(null, team.id, dodItem.id)} className="stack">
            {team.dod.length === 0 && <p className="note">The team has no Definition of Done yet.</p>}
            {team.dod.map(d => (
              <label key={d.id} className="check"><input type="checkbox" name="dod" value={d.id} defaultChecked={dodItem.dodChecked.includes(d.id)} /> {d.text}</label>
            ))}
            <div className="row"><button className="btn" id="mark-done">Mark Done</button><Link className="btn quiet" href="?">Cancel</Link></div>
          </form>
        </section>
      )}

      <section {...flag('block', 'board', pending, log)}>
        <h2>Sprint Backlog</h2>
        <div className="board">
          {COLUMNS.map(([status, label]) => (
            <div key={status} className="col" data-col={status}><b>{label}</b>{sprint.items.filter(b => b.status === status).map(card)}</div>
          ))}
        </div>
      </section>

      <div className="row">
        <form action={goToStage.bind(null, team.id, 1)}><button className="btn ghost" id="back">Back</button></form>
        <form action={startReview.bind(null, team.id)}><button className="btn" id="next">Go to Sprint Review</button></form>
      </div>
    </>
  );
}
