import { AutoSubmitSelect } from '@/app/components/AutoSubmitSelect';
import type { Planning } from '@/src/db/planning';
import type { Team } from '@/src/db/teams';
import { POINTS, averageVelocity, isStory, tooBigReason, type ExceptionRecord, type Finding } from '@/src/rules';
import { addStory, closePlanning, deselect, goToStage, resize, saveSprintGoal, select, toggleTooBig } from './actions';
import { flag, plural } from './flags';

export function PlanningStage({ team, planning, pending, log }: { team: Team; planning: Planning; pending?: Finding; log: readonly ExceptionRecord[] }) {
  const v = averageVelocity(planning.velocities);
  const isSelected = (id: string) => planning.selected.includes(Number(id));
  const forecast = planning.backlog.filter(b => isSelected(b.id)).reduce((x, b) => x + (b.points ?? 0), 0);
  return (
    <>
      <div><span className="eyebrow">Stage 2 of 6 · timebox 4 h for a 2-week Sprint</span><h1>Sprint {team.sprintNumber} Planning</h1></div>

      <section {...flag('block', 'sgoal', pending, log)}>
        <h2>Why is this Sprint valuable?</h2>
        <form action={saveSprintGoal.bind(null, team.id)} className="stack">
          <textarea name="sprintGoal" defaultValue={team.sprintGoal} placeholder="The single objective for this Sprint." aria-label="Sprint Goal" />
          <div className="row"><button className="btn ghost">Save Sprint Goal</button><span className="note">Product Goal: {team.productGoal || 'not set'}</span></div>
        </form>
      </section>

      <section className="block">
        <h2>What can be Done this Sprint?</h2>
        <p className="note">Developers select items, ordered by the Product Owner.</p>
        <div className="tbl">
          <table>
            <thead><tr><th /><th>Order</th><th>ID</th><th>Product Backlog item</th><th>Points</th><th /></tr></thead>
            <tbody>
              {planning.backlog.map((b, i) => {
                const big = tooBigReason(b, planning.velocities), chosen = isSelected(b.id);
                return (
                  <tr key={b.id} {...flag(chosen ? 'chosen' : '', `item-${b.id}`, pending, log)} data-item={b.id}>
                    <td>
                      <form action={(chosen ? deselect : select).bind(null, team.id, b.id)}>
                        <button className={chosen ? 'btn pick on' : 'btn pick'} aria-pressed={chosen} aria-label={`${chosen ? 'Remove' : 'Select'} item ${i + 1}`}>{chosen ? 'Selected' : 'Select'}</button>
                      </form>
                    </td>
                    <td className="num">{i + 1}</td>
                    <td className="mono item-key nowrap">{b.key}</td>
                    <td>{b.improvement && <span className="tag tag-ok">Improvement</span>} {b.title}</td>
                    <td>
                      <form action={resize.bind(null, team.id, b.id)}>
                        <AutoSubmitSelect key={b.points ?? ''} name="points" defaultValue={b.points ?? ''} aria-label={`Size of item ${i + 1}`}>
                          <option value="">Not sized</option>{POINTS.map(p => <option key={p}>{p}</option>)}
                        </AutoSubmitSelect>
                      </form>
                    </td>
                    <td>
                      <div className="row tight">
                        {big && <span className="tag tag-warn" title={big}>Too big for one Sprint{b.markedBig ? ' · marked' : ''}</span>}
                        {!isStory(b.title) && <span className="tag tag-warn">Not a user story</span>}
                        <form action={toggleTooBig.bind(null, team.id, b.id, !b.markedBig)}>
                          <button className="btn quiet small" title="Developers mark items that can't be Done within one Sprint">{b.markedBig ? 'Unmark too big' : 'Mark too big'}</button>
                        </form>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div {...flag('row', 'forecast', pending, log)}>
          <span className={`tag ${v === null ? 'tag-warn' : forecast > v ? 'tag-block' : 'tag-ok'}`} id="forecast">Forecast {forecast} points</span>
          <span className="note">{v === null ? 'No velocity yet: it is measured from the first Sprint.' : `Average velocity ${v} points over the last ${plural(planning.velocities.length, 'Sprint')}`}</span>
        </div>
        <form action={addStory.bind(null, team.id)} {...flag('row', 'story-new', pending, log)}>
          <input name="title" placeholder="As a … I want to … so that …" aria-label="New user story" required />
          <select name="points" aria-label="Story points" defaultValue=""><option value="">Not sized</option>{POINTS.map(p => <option key={p}>{p}</option>)}</select>
          <button className="btn ghost">Add to Product Backlog</button>
        </form>
      </section>

      <section className="block">
        <h2>How will the chosen work get done?</h2>
        <p className="note">The Developers plan the work themselves. Nobody outside the Developers assigns tasks.</p>
      </section>

      <div className="row">
        <form action={goToStage.bind(null, team.id, 0)}><button className="btn ghost" id="back">Back</button></form>
        <form action={closePlanning.bind(null, team.id)}><button className="btn" id="next">Close Sprint Planning and start the Sprint</button></form>
      </div>
    </>
  );
}
