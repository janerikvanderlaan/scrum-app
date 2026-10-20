import { afterAll, describe, expect, it } from 'vitest';
import { closePool, pool } from './client';
import { addBacklogItem, getPlanning, selectItem } from './planning';
import { confirmOrder, getSprint, nextDay, recordDaily, setDodChecked, setOrder, setStatus } from './sprint';
import { addDodItem, createTeam, getTeam } from './teams';

afterAll(async () => {
  await pool().query("delete from teams where name like 'DB test%'");
  await closePool();
});

async function teamWithSprint(name: string) {
  const id = await createTeam(name);
  for (const t of ['A', 'B', 'C']) await addBacklogItem(id, t, 3);
  const ids = (await getPlanning(id, 1)).backlog.map(b => Number(b.id));
  for (const i of ids) await selectItem(id, 1, i);
  return { id, ids };
}

describe('sprint', () => {
  it('keeps the Developers’ order and each item’s progress', async () => {
    const { id, ids: [a, b, c] } = await teamWithSprint('DB test sprint order');
    let s = await getSprint(id, 1);
    expect(s.items.map(x => [x.title, x.status])).toEqual([['A', 'todo'], ['B', 'todo'], ['C', 'todo']]);
    expect([s.day, s.length, s.confirmedBy]).toEqual([1, 10, null]);
    await setOrder(id, 1, [c, a, b]);
    await confirmOrder(id, 'Lena');
    await setStatus(id, 1, c, 'doing');
    s = await getSprint(id, 1);
    expect(s.items.map(x => x.title)).toEqual(['C', 'A', 'B']);
    expect(s.items[0].status).toBe('doing');
    expect(s.confirmedBy).toBe('Lena');
  });

  it('only stores Definition of Done lines of the item’s own team', async () => {
    const { id, ids: [a] } = await teamWithSprint('DB test sprint dod');
    const other = await createTeam('DB test sprint dod other');
    await addDodItem(id, 'Reviewed');
    await addDodItem(other, 'Foreign');
    const mine = (await getTeam(id))!.dod[0].id, foreign = (await getTeam(other))!.dod[0].id;
    await setDodChecked(id, 1, a, [mine, foreign]);
    expect((await getSprint(id, 1)).items[0].dodChecked).toEqual([mine]);
  });

  it('never turns a held Daily Scrum into a skipped one, and stops at the last day', async () => {
    const { id } = await teamWithSprint('DB test sprint daily');
    await recordDaily(id, 1, 1, true);
    await recordDaily(id, 1, 1, false);
    await recordDaily(id, 1, 2, false);
    expect((await getSprint(id, 1)).daily).toEqual({ 1: true, 2: false });
    await pool().query('update teams set sprint_length = 2 where id = $1', [id]);
    await nextDay(id);
    await nextDay(id);
    expect((await getSprint(id, 1)).day).toBe(2);
  });
  // Test round 2, issue 2: stories have a stable ID per team that doesn't change with the order.
  it('numbers backlog items per team and keeps the number when the order changes', async () => {
    const { id, ids: [a, b, c] } = await teamWithSprint('DB test sprint keys');
    const other = await createTeam('DB test sprint keys other');
    await addBacklogItem(other, 'Other team item', 1);
    expect((await getPlanning(other, 1)).backlog.map(x => x.key)).toEqual(['US-1']);
    await setOrder(id, 1, [c, a, b]);
    expect((await getSprint(id, 1)).items.map(x => [x.title, x.key])).toEqual([['C', 'US-3'], ['A', 'US-1'], ['B', 'US-2']]);
    await addBacklogItem(id, 'D', 2);
    expect((await getPlanning(id, 1)).backlog.map(x => x.key)).toEqual(['US-1', 'US-2', 'US-3', 'US-4']);
  });
});
