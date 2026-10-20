import { describe, expect, it } from 'vitest';
import {
  type Rule, activeExceptions, resolveExceptions, velocityLimit,
  RULES, averageVelocity, countKinds, followsScrum, isStory, kindFor, kindLabel, needsDecision, pendingFindings, reasonIsValid,
  planningChecks, selectionChecks, teamChecks, tooBigReason, confirmOrderChecks, dailyChecks, doneChecks, nextItem, reviewChecks, startChecks,
  type BacklogItem, type SprintItem, type ExceptionRecord, type Member,
} from '.';

const item = (over: Partial<BacklogItem> = {}): BacklogItem => ({
  id: 'a1', title: 'As a customer I want to reset my password so that I can sign in', points: 5, markedBig: false, ...over,
});
const members = (po: number, sm: number, dev: number): Member[] => [
  ...Array.from({ length: po }, (_, i) => ({ name: `PO ${i}`, role: 'Product Owner' as const })),
  ...Array.from({ length: sm }, (_, i) => ({ name: `SM ${i}`, role: 'Scrum Master' as const })),
  ...Array.from({ length: dev }, (_, i) => ({ name: `Dev ${i}`, role: 'Developer' as const })),
];
const record = (over: Partial<ExceptionRecord>): ExceptionRecord => ({
  rule: 'SG-068', kind: 'warning', reason: '', who: 'You', target: 'members', detail: 'Team has 11 people',
  sprint: 1, stage: 'Team and goals', day: null, time: '10:00', ...over,
});

describe('catalog', () => {
  it('gives every rule a text and a known tier', () => {
    for (const r of Object.values(RULES)) {
      expect(r.text.length).toBeGreaterThan(10);
      expect(['rule', 'guidance', 'confirm', 'team']).toContain(r.tier);
    }
  });
});

describe('TEAM-02 user story format', () => {
  it.each([
    'As a customer I want to reset my password so that I can sign in',
    'As a picker want scanning so faster',
    '  as a buyer I WANT invoices SO I can pay later',
  ])('accepts %s', s => expect(isStory(s)).toBe(true));
  it.each(['Replace the legacy payment provider', 'Fix the login bug', 'As a user I want everything'])('rejects %s', s => expect(isStory(s)).toBe(false));
});

describe('average velocity', () => {
  it('rounds to one decimal', () => expect(averageVelocity([14, 17, 16])).toBe(15.7));
  it('is null without Sprints', () => expect(averageVelocity([])).toBeNull());
});

describe('SG-200 too big for one Sprint', () => {
  it('flags an item the Developers marked', () => expect(tooBigReason(item({ markedBig: true }), [14, 17, 16])).toMatch(/marked/));
  it('flags points above the average velocity', () => expect(tooBigReason(item({ points: 20 }), [14, 17, 16])).toMatch(/20 points .* 15.7/));
  it('lets an item at the average through', () => expect(tooBigReason(item({ points: 13 }), [13])).toBeNull());
  it('cannot judge size without velocity', () => expect(tooBigReason(item({ points: 20 }), [])).toBeNull());
  it('is checked when selecting, after the story format', () => {
    const f = selectionChecks(item({ title: 'Migrate the database', points: 20 }), [10, 12]);
    expect(f.map(x => x.rule)).toEqual(['TEAM-02', 'SG-200']);
    expect(f.every(x => x.target === 'item-a1')).toBe(true);
  });
});

describe('team checks', () => {
  const base = { name: 'Team Atlas', productGoal: 'Goal', dod: ['Tested'] };
  it('passes a Guide-shaped team', () => expect(teamChecks({ ...base, members: members(1, 1, 4) })).toEqual([]));
  it('blocks two Product Owners and a missing Scrum Master, and warns about size', () => {
    expect(teamChecks({ ...base, members: members(2, 0, 9) }).map(f => f.rule)).toEqual(['SG-095', 'SG-063', 'SG-068']);
  });
  it('blocks a team without Developers', () => expect(teamChecks({ ...base, members: members(1, 1, 0) }).map(f => f.rule)).toEqual(['SG-063']));
  it('asks for a Product Goal and a Definition of Done', () => {
    expect(teamChecks({ name: 'T', members: members(1, 1, 3), productGoal: ' ', dod: [] }).map(f => f.rule)).toEqual(['SG-194', 'SG-240']);
  });
});

describe('planning checks', () => {
  it('needs a Sprint Goal', () => expect(planningChecks('', [item()], [10]).map(f => f.rule)).toEqual(['SG-150']));
  // Test round 3, issues 2, 4 and 5: an empty selection and unsized stories get their own messages.
  it('needs at least one selected story', () => expect(planningChecks('Goal', [], [10])[0].detail).toBe('No user stories are selected for this Sprint'));
  it('blocks unsized stories', () =>
    expect(planningChecks('Goal', [item({ points: null })], [10])[0].detail).toBe('There are User Stories without sizing added to the Sprint'));
  it('blocks unsized stories next to sized ones', () =>
    expect(planningChecks('Goal', [item(), item({ id: 'a2', points: null })], [10])[0].detail).toBe('There are User Stories without sizing added to the Sprint'));
  it('blocks a forecast above the average velocity', () => {
    expect(planningChecks('Goal', [item({ points: 8 }), item({ id: 'a2', points: 8 })], [14, 17, 16])[0].detail).toMatch(/16 points .* 15.7/);
  });
  it('passes a forecast within the average', () => expect(planningChecks('Goal', [item({ points: 8 })], [10])).toEqual([]));
});

describe('exception log', () => {
  const finding = { rule: 'SG-068' as const, detail: 'Team has 11 people', target: 'members' };
  it('asks once per rule, place and situation in a Sprint', () => {
    expect(needsDecision(finding, [], 1)).toBe(true);
    expect(needsDecision(finding, [record({})], 1)).toBe(false);
    expect(needsDecision(finding, [record({ sprint: 0 })], 1)).toBe(true);
    expect(needsDecision({ ...finding, detail: 'Team has 12 people' }, [record({})], 1)).toBe(true);
  });
  it('accepts warnings and overrides blocks', () => {
    expect(kindFor('SG-068')).toBe('warning');
    expect(kindFor('SG-238')).toBe('warning');
    expect(kindFor('SG-095')).toBe('override');
    expect(kindFor('TEAM-01')).toBe('override');
  });
  it('counts and labels each kind', () => {
    const log = [record({}), record({ rule: 'SG-095', kind: 'override' }), record({ rule: 'TEAM-02', kind: 'override' })];
    expect(countKinds(log)).toEqual({ guide: 1, team: 1, warn: 1 });
    expect(log.map(kindLabel)).toEqual(['Warning accepted', 'Guide rule overridden', 'Team agreement overridden']);
  });
  it('only Guide rule overrides stop a Sprint following Scrum', () => {
    expect(followsScrum([record({}), record({ rule: 'TEAM-01', kind: 'override' })])).toBe(true);
    expect(followsScrum([record({ rule: 'SG-164', kind: 'override' })])).toBe(false);
  });
  it('keeps only the findings still to decide, in order', () => {
    const other = { rule: 'SG-194' as const, detail: 'There is no Product Goal yet', target: 'pgoal' };
    expect(pendingFindings([finding, other], [record({})], 1)).toEqual([other]);
  });
  it('needs a reason of at least 10 characters to override, none to accept a warning', () => {
    expect(reasonIsValid('override', 'too short')).toBe(false);
    expect(reasonIsValid('override', 'Coach starts next month')).toBe(true);
    expect(reasonIsValid('warning', '')).toBe(true);
  });
});

describe('Sprint checks', () => {
  const items: SprintItem[] = [
    { id: 'a', title: 'Top story', status: 'done' },
    { id: 'b', title: 'Second story', status: 'todo' },
    { id: 'c', title: 'Third story', status: 'todo' },
  ];
  it('lets only a Developer confirm the order (SG-216)', () => {
    expect(confirmOrderChecks({ name: 'Lena', role: 'Developer' })).toEqual([]);
    expect(confirmOrderChecks({ name: 'Mara', role: 'Product Owner' })[0]).toMatchObject({ rule: 'SG-216', detail: 'Mara is the Product Owner. A Developer confirms the Sprint Backlog order' });
  });
  it('starts items from the top (TEAM-01)', () => {
    expect(nextItem(items)?.id).toBe('b');
    expect(startChecks(items, 'b')).toEqual([]);
    expect(startChecks(items, 'c')[0]).toMatchObject({ rule: 'TEAM-01', detail: '“Third story” is not the next item; “Second story” is on top', target: 'item-c' });
  });
  it('needs every Definition of Done line before Done (SG-233)', () => {
    expect(doneChecks(items[1], 5, 5)).toEqual([]);
    expect(doneChecks(items[1], 5, 4)[0].detail).toBe('1 Definition of Done item is not met for “Second story”');
    expect(doneChecks(items[1], 5, 2)[0].detail).toMatch(/^3 Definition of Done items are not met/);
  });
  it('asks about a working day without a Daily Scrum (SG-164)', () => {
    expect(dailyChecks(3, true)).toEqual([]);
    expect(dailyChecks(3, false)[0]).toMatchObject({ rule: 'SG-164', detail: 'Day 3 has no Daily Scrum yet', target: 'day-3' });
  });
  it('checks days left, today’s Daily Scrum and open items before the Review, in that order', () => {
    expect(reviewChecks(4, 10, false, items).map(f => f.rule)).toEqual(['SG-125', 'SG-164', 'SG-238']);
    expect(reviewChecks(9, 10, true, items)[0].detail).toBe('The Sprint has 1 working day left');
    expect(reviewChecks(10, 10, true, items)[0].detail).toBe('2 Sprint Backlog items are not Done. Start the Sprint Review anyway?');
    expect(reviewChecks(10, 10, true, items.map(b => ({ ...b, status: 'done' as const })))).toEqual([]);
  });
  it('treats an open-items warning as a confirmation, logged as a warning', () => expect(kindFor('SG-238')).toBe('warning'));
  // Test round 2, issue 5: the SG-238 question also says what returning to the Product Backlog means.
  it('explains what happens to items that are not Done', () => {
    const rule: Rule = RULES['SG-238'];
    expect(rule.explain).toMatch(/reconsider the story’s priority, size and value/);
  });
});

// Test round 3, issue 3: the team may allow a forecast above the average velocity.
describe('velocity deviation', () => {
  it('raises the limit by the percentage', () => expect(velocityLimit([10], 20)).toBe(12));
  it('keeps the average when the setting is 0%', () => expect(velocityLimit([14, 17, 16])).toBe(15.7));
  it('lets a forecast within the deviation through', () => expect(planningChecks('Goal', [item({ points: 12 })], [10], 20)).toEqual([]));
  it('names the limit when the forecast goes over it', () =>
    expect(planningChecks('Goal', [item({ points: 13 })], [10], 20)[0].detail).toBe('The forecast of 13 points is more than 12 points (average velocity 10 plus 20%)'));
  it('uses the deviation for too-big items as well', () => {
    expect(tooBigReason(item({ points: 12 }), [10], 20)).toBeNull();
    expect(tooBigReason(item({ points: 13 }), [10], 20)).toBe('its 13 points are more than 12 points (average velocity 10 plus 20%)');
  });
});

// Test round 3, issue 1: an override about the team setup is resolved once the team fixes it.
describe('resolved exceptions', () => {
  const po: ExceptionRecord = { rule: 'SG-095', kind: 'override', reason: 'Two POs during handover', who: 'You', target: 'members', detail: 'Atlas has 2 Product Owners', sprint: 1, stage: 'Team and goals', day: null, time: '10:00' };
  const late: ExceptionRecord = { ...po, rule: 'TEAM-01', target: 'item-1', detail: 'not the next item' };
  it('resolves a team setup override once its check passes', () => {
    const log = resolveExceptions([po, late], []);
    expect(log.map(o => o.resolved)).toEqual([true, false]);
    expect(followsScrum(activeExceptions(log))).toBe(true);
  });
  it('keeps it open while the problem is still there', () =>
    expect(resolveExceptions([po], [{ rule: 'SG-095', target: 'members', detail: 'Atlas has 3 Product Owners' }])[0].resolved).toBe(false));
});
