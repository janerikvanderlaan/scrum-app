import type { ExceptionRecord, Finding } from '@/src/rules';

export const TIER_LABEL = { rule: 'Guide rule · blocked', guidance: 'Guide guidance · warning', confirm: 'Guide guidance · confirm', team: 'Team agreement · blocked' };

export const plural = (n: number, word: string, many = `${word}s`) => `${n} ${n === 1 ? word : many}`;

/**
 * Props for a flagged part of the screen: red while a decision about it is open,
 * amber once an override is logged for it, blue for an accepted warning.
 */
export function flag(base: string, target: string, pending: Finding | undefined, log: readonly ExceptionRecord[]) {
  if (pending?.target === target) return { className: `${base} flag-pending` };
  const rules = [...new Set(log.filter(o => o.target === target).map(o => o.rule))];
  if (!rules.length) return { className: base };
  const kind = log.some(o => o.target === target && o.kind === 'override') ? 'flag-override' : 'flag-warning';
  return { className: `${base} ${kind}`, 'data-exception': `Exception: ${rules.join(', ')}` };
}
