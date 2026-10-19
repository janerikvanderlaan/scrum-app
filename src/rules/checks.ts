import type { RuleId } from './catalog';

export type Role = 'Developer' | 'Product Owner' | 'Scrum Master';

export interface Member {
  name: string;
  role: Role;
}

export interface BacklogItem {
  id: string;
  title: string;
  points: number | null;
  /** Set by the Developers when they judge the item can't be Done within one Sprint. */
  markedBig: boolean;
}

/** A check that failed: which rule, what happened, and which part of the screen it is about. */
export interface Finding {
  rule: RuleId;
  detail: string;
  target: string;
}

export const POINTS = [1, 2, 3, 5, 8, 13, 20] as const;

const STORY = /^\s*as\b.+?\bwant\b.+?\bso\b/i;

/** TEAM-02: only the shape "As … want … so …" is checked, so short stories pass. */
export const isStory = (text: string): boolean => STORY.test(text);

/** Average of the given Sprint velocities, rounded to one decimal, or null when there are none. */
export const averageVelocity = (velocities: readonly number[]): number | null =>
  velocities.length ? Math.round((velocities.reduce((x, y) => x + y, 0) / velocities.length) * 10) / 10 : null;

/** SG-200: why an item is too big for one Sprint, or null when it fits. */
export function tooBigReason(item: BacklogItem, velocities: readonly number[]): string | null {
  const v = averageVelocity(velocities);
  if (item.markedBig) return 'the Developers marked it as too big';
  if (item.points && v !== null && item.points > v) return `its ${item.points} points are more than the average velocity of ${v}`;
  return null;
}

/** Team and goals stage, in the order the app asks them. */
export function teamChecks(team: { name: string; members: readonly Member[]; productGoal: string; dod: readonly string[] }): Finding[] {
  const count = (role: Role) => team.members.filter(m => m.role === role).length;
  const po = count('Product Owner'), sm = count('Scrum Master'), dev = count('Developer');
  const findings: Finding[] = [];
  if (po > 1) findings.push({ rule: 'SG-095', detail: `${team.name} has ${po} Product Owners`, target: 'members' });
  if (po === 0 || sm !== 1 || dev < 1)
    findings.push({ rule: 'SG-063', detail: `${team.name} needs exactly one Product Owner, one Scrum Master and at least one Developer`, target: 'members' });
  if (team.members.length > 10) findings.push({ rule: 'SG-068', detail: `${team.name} has ${team.members.length} people`, target: 'members' });
  if (!team.productGoal.trim()) findings.push({ rule: 'SG-194', detail: 'There is no Product Goal yet', target: 'pgoal' });
  if (team.dod.length === 0) findings.push({ rule: 'SG-240', detail: 'There is no Definition of Done yet', target: 'dod' });
  return findings;
}

/** Closing Sprint Planning, in the order the app asks them. */
export function planningChecks(goal: string, selected: readonly BacklogItem[], velocities: readonly number[]): Finding[] {
  const v = averageVelocity(velocities);
  const sized = selected.filter(b => b.points);
  const unsized = selected.length - sized.length;
  const total = sized.reduce((x, b) => x + (b.points ?? 0), 0);
  const findings: Finding[] = [];
  if (!goal.trim()) findings.push({ rule: 'SG-150', detail: 'Sprint Planning cannot close without a Sprint Goal', target: 'sgoal' });
  if (sized.length === 0 || unsized > 0)
    findings.push({
      rule: 'TEAM-03',
      detail: sized.length === 0 ? 'No sized user stories are selected for this Sprint' : `${unsized} selected stor${unsized > 1 ? 'ies are' : 'y is'} not sized`,
      target: 'forecast',
    });
  if (v !== null && total > v)
    findings.push({ rule: 'TEAM-03', detail: `The forecast of ${total} points is more than the average velocity of ${v} points`, target: 'forecast' });
  return findings;
}

/** Selecting one Product Backlog item for the Sprint. */
export function selectionChecks(item: BacklogItem, velocities: readonly number[]): Finding[] {
  const findings: Finding[] = [];
  if (!isStory(item.title)) findings.push({ rule: 'TEAM-02', detail: `“${item.title}” is not written as a user story`, target: `item-${item.id}` });
  const big = tooBigReason(item, velocities);
  if (big) findings.push({ rule: 'SG-200', detail: `“${item.title}” can't be Done within one Sprint: ${big}`, target: `item-${item.id}` });
  return findings;
}
