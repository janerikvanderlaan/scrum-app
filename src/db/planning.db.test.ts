import { afterAll, describe, expect, it } from 'vitest';
import { closePool, pool } from './client';
import { addBacklogItem, deselectItem, getPlanning, selectItem, setMarkedBig, setSprintGoal } from './planning';
import { createTeam, getTeam } from './teams';

afterAll(async () => {
  await pool().query("delete from teams where name like 'DB test%'");
  await closePool();
});

describe('planning', () => {
  it('keeps the backlog in order and the selection per Sprint', async () => {
    const id = await createTeam('DB test planning');
    await addBacklogItem(id, 'As a user I want A so that B', 3);
    await addBacklogItem(id, 'Unsized item', null);
    let p = await getPlanning(id, 1);
    expect(p.backlog.map(b => [b.title, b.points, b.markedBig])).toEqual([['As a user I want A so that B', 3, false], ['Unsized item', null, false]]);
    const [a, b] = p.backlog.map(x => Number(x.id));
    await selectItem(id, 1, a);
    await selectItem(id, 1, a);
    await selectItem(id, 2, b);
    await setMarkedBig(id, b, true);
    p = await getPlanning(id, 1);
    expect(p.selected).toEqual([a]);
    expect(p.backlog[1].markedBig).toBe(true);
    await deselectItem(id, 1, a);
    expect((await getPlanning(id, 1)).selected).toEqual([]);
  });

  it('cannot select another team’s item', async () => {
    const mine = await createTeam('DB test mine'), other = await createTeam('DB test other');
    await addBacklogItem(other, 'Their item', 1);
    const theirs = Number((await getPlanning(other, 1)).backlog[0].id);
    await selectItem(mine, 1, theirs);
    expect((await getPlanning(mine, 1)).selected).toEqual([]);
  });

  it('averages only the last three Sprints, oldest first', async () => {
    const id = await createTeam('DB test velocity');
    for (const [sprint, points] of [[-4, 2], [-3, 14], [-2, 17], [-1, 16]]) await pool().query('insert into velocities values ($1, $2, $3)', [id, sprint, points]);
    expect((await getPlanning(id, 1)).velocities).toEqual([14, 17, 16]);
  });

  it('stores the Sprint Goal on the team', async () => {
    const id = await createTeam('DB test goal');
    await setSprintGoal(id, 'Ship the account page');
    expect((await getTeam(id))?.sprintGoal).toBe('Ship the account page');
  });
});
