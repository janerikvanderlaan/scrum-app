import type { Finding, Member } from './checks';

export type ItemStatus = 'todo' | 'doing' | 'done';

/** A Sprint Backlog item, in the order the Developers put it. */
export interface SprintItem {
  id: string;
  title: string;
  status: ItemStatus;
}

/** The item the Developers start next: the highest one that hasn't started. */
export const nextItem = <T extends SprintItem>(items: readonly T[]): T | undefined => items.find(b => b.status === 'todo');

/** SG-216: the Sprint Backlog is the Developers' plan, so a Developer confirms its order. */
export function confirmOrderChecks(member: Member): Finding[] {
  return member.role === 'Developer'
    ? []
    : [{ rule: 'SG-216', detail: `${member.name} is the ${member.role}. A Developer confirms the Sprint Backlog order`, target: 'order' }];
}

/** TEAM-01: items start from the top, in the confirmed order. */
export function startChecks(items: readonly SprintItem[], id: string, confirmedBy: string | null = null): Finding[] {
  const top = nextItem(items), item = items.find(b => b.id === id);
  if (!item) return [];
  const findings: Finding[] = [];
  if (!confirmedBy)
    findings.push({ rule: 'SG-216', detail: 'A Developer has not confirmed the Sprint Backlog order yet. Confirm it before starting work', target: 'order' });
  if (top && item.id !== top.id)
    findings.push({ rule: 'TEAM-01', detail: `“${item.title}” is not the next item; “${top.title}” is on top`, target: `item-${item.id}` });
  return findings;
}

/** SG-233: an item is Done only when it meets every line of the Definition of Done. */
export function doneChecks(item: SprintItem, dodLines: number, linesMet: number): Finding[] {
  const missing = dodLines - linesMet;
  return missing > 0
    ? [{ rule: 'SG-233', detail: `${missing} Definition of Done item${missing > 1 ? 's are' : ' is'} not met for “${item.title}”`, target: `item-${item.id}` }]
    : [];
}

/** SG-164: every working day has a Daily Scrum, so leaving a day without one is an exception. */
export function dailyChecks(day: number, heldToday: boolean): Finding[] {
  return heldToday ? [] : [{ rule: 'SG-164', detail: `Day ${day} has no Daily Scrum yet`, target: `day-${day}` }];
}

/** Ending the Sprint and starting the Sprint Review, in the order the app asks them. */
export function reviewChecks(day: number, length: number, heldToday: boolean, items: readonly SprintItem[]): Finding[] {
  const left = length - day, open = items.filter(b => b.status !== 'done').length;
  const findings: Finding[] = [];
  if (left > 0) findings.push({ rule: 'SG-125', detail: `The Sprint has ${left} working day${left > 1 ? 's' : ''} left`, target: 'days' });
  findings.push(...dailyChecks(day, heldToday));
  if (open > 0)
    findings.push({ rule: 'SG-238', detail: `${open} Sprint Backlog item${open > 1 ? 's are' : ' is'} not Done. Start the Sprint Review anyway?`, target: 'board' });
  return findings;
}
