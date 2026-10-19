import { afterAll, describe, expect, it } from 'vitest';
import { closePool, pool } from './client';
import {
  addDodItem, addMember, createTeam, getTeam, listExceptions, logException, removeMember, setMemberRole, setProductGoal, setStage,
} from './teams';

// Runs against a real PostgreSQL database: DATABASE_URL=... npm run test:db
afterAll(async () => {
  await pool().query("delete from teams where name like 'DB test%'");
  await closePool();
});

describe('teams', () => {
  it('creates teams with unique, URL-friendly ids', async () => {
    const a = await createTeam('DB test Ünicorn Squad');
    const b = await createTeam('DB test Ünicorn Squad');
    expect(a).toBe('db-test-unicorn-squad');
    expect(b).toBe('db-test-unicorn-squad-2');
  });

  it('stores members, Product Goal, Definition of Done and stage', async () => {
    const id = await createTeam('DB test store');
    await addMember(id, 'Mara', 'Product Owner');
    await addMember(id, 'Lena', 'Developer');
    await addMember(id, 'Ravi', 'Developer');
    await setProductGoal(id, 'Customers help themselves');
    await addDodItem(id, 'Tested');
    await setStage(id, 1);
    let team = await getTeam(id);
    expect(team?.members.map(m => m.name)).toEqual(['Mara', 'Lena', 'Ravi']);
    await setMemberRole(id, team!.members[1].id, 'Scrum Master');
    await removeMember(id, team!.members[2].id);
    team = await getTeam(id);
    expect(team).toMatchObject({ productGoal: 'Customers help themselves', stage: 1, sprintNumber: 1, dod: [{ text: 'Tested' }] });
    expect(team?.members.map(m => [m.name, m.role])).toEqual([['Mara', 'Product Owner'], ['Lena', 'Scrum Master']]);
  });

  it('returns null for an unknown team', async () => expect(await getTeam('no-such-team')).toBeNull());
});

describe('exception log', () => {
  it('keeps exceptions per team and Sprint, oldest first', async () => {
    const id = await createTeam('DB test log');
    const base = { who: 'Team member', target: 'members', stage: 'Team and goals', day: null, reason: '' } as const;
    await logException(id, { ...base, rule: 'SG-068', kind: 'warning', detail: '11 people', sprint: 1 });
    await logException(id, { ...base, rule: 'SG-095', kind: 'override', detail: '2 POs', sprint: 1, reason: 'Handover this month' });
    await logException(id, { ...base, rule: 'SG-095', kind: 'override', detail: '2 POs', sprint: 2, reason: 'Still in handover' });
    const log = await listExceptions(id, 1);
    expect(log.map(o => o.rule)).toEqual(['SG-068', 'SG-095']);
    expect(log[1]).toMatchObject({ kind: 'override', reason: 'Handover this month', sprint: 1, day: null });
    expect(log[1].time).toMatch(/^\d\d:\d\d$/);
  });
});
