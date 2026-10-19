import { describe, expect, it } from 'vitest';
import {
  RULES, averageVelocity, countKinds, followsScrum, isStory, kindFor, kindLabel, needsDecision,
  planningChecks, selectionChecks, teamChecks, tooBigReason,
  type BacklogItem, type ExceptionRecord, type Member,
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
  it('needs at least one sized story', () => expect(planningChecks('Goal', [], [10])[0].detail).toMatch(/No sized/));
  it('blocks unsized stories', () => expect(planningChecks('Goal', [item(), item({ id: 'a2', points: null })], [10])[0].detail).toBe('1 selected story is not sized'));
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
});
