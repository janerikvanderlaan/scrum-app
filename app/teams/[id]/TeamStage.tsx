import { AutoSubmitSelect } from '@/app/components/AutoSubmitSelect';
import { ROLES, type Team } from '@/src/db/teams';
import type { ExceptionRecord, Finding } from '@/src/rules';
import { addDod, addTeamMember, changeRole, deleteDod, deleteMember, saveProductGoal, saveVelocityDeviation, startPlanning } from './actions';
import { DEVIATIONS, flag } from './flags';

export function TeamStage({ team, pending, log }: { team: Team; pending?: Finding; log: readonly ExceptionRecord[] }) {
  return (
    <>
      <div><span className="eyebrow">Stage 1 of 6</span><h1>Set up {team.name}</h1></div>

      <section {...flag('block', 'members', pending, log)}>
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
                    <AutoSubmitSelect key={m.role} name="role" defaultValue={m.role} aria-label={`Accountability of ${m.name}`}>
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

      <section {...flag('block', 'pgoal', pending, log)}>
        <h2>Product Goal</h2>
        <form action={saveProductGoal.bind(null, team.id)} className="stack">
          <textarea name="productGoal" defaultValue={team.productGoal} placeholder="The future state of the product the team plans against." aria-label="Product Goal" />
          <div><button className="btn ghost">Save Product Goal</button></div>
        </form>
      </section>

      <section {...flag('block', 'dod', pending, log)}>
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

      <section className="block">
        <h2>Team settings</h2>
        <form action={saveVelocityDeviation.bind(null, team.id)} className="row">
          <label htmlFor="deviation">Maximum deviation from average velocity</label>
          <AutoSubmitSelect id="deviation" key={team.velocityDeviation} name="deviation" defaultValue={team.velocityDeviation}>
            {DEVIATIONS.map(d => <option key={d} value={d}>{d}%</option>)}
          </AutoSubmitSelect>
        </form>
        <p className="note">Sprint Planning stops a forecast, and an item counts as too big for one Sprint, above the average velocity plus this percentage.</p>
      </section>

      <form action={startPlanning.bind(null, team.id)}><button className="btn" id="next">Start Sprint {team.sprintNumber} Planning</button></form>
    </>
  );
}
