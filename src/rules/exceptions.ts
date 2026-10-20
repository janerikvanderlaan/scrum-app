import { RULES, isGuideRule, type RuleId } from './catalog';
import { TEAM_SETUP_RULES, type Finding } from './checks';

/** One logged exception: an accepted warning or a deliberate override with its reason. */
export interface ExceptionRecord {
  rule: RuleId;
  kind: 'warning' | 'override';
  reason: string;
  who: string;
  target: string;
  detail: string;
  sprint: number;
  stage: string;
  day: number | null;
  time: string;
}

/**
 * Whether a finding still needs a decision from the team. An exception already logged this Sprint
 * for the same rule, place and situation is not asked or logged again.
 */
export const needsDecision = (finding: Finding, log: readonly ExceptionRecord[], sprint: number): boolean =>
  !log.some(o => o.sprint === sprint && o.rule === finding.rule && o.target === finding.target && o.detail === finding.detail);

/** A logged exception, and whether the team has since fixed what it was about. */
export interface LoggedException extends ExceptionRecord {
  resolved: boolean;
}

/**
 * An exception about the team setup (members, Product Goal, Definition of Done) is resolved once the
 * matching check no longer fails: it stays in the log as history but no longer counts. If the problem
 * comes back, the same entry counts again. Exceptions about events (starting an item, a skipped
 * Daily Scrum) are facts and never resolve.
 */
export const resolveExceptions = (log: readonly ExceptionRecord[], teamFindings: readonly Finding[]): LoggedException[] =>
  log.map(o => ({
    ...o,
    resolved: TEAM_SETUP_RULES.includes(o.rule) && !teamFindings.some(f => f.rule === o.rule && f.target === o.target),
  }));

/** The exceptions that still count: everything not resolved. */
export const activeExceptions = <T extends { resolved?: boolean }>(log: readonly T[]): T[] => log.filter(o => !o.resolved);

/** Guidance and confirmations are accepted; Guide rules and team agreements are overridden. */
export const kindFor = (rule: RuleId): ExceptionRecord['kind'] =>
  RULES[rule].tier === 'guidance' || RULES[rule].tier === 'confirm' ? 'warning' : 'override';

export const kindLabel = (o: Pick<ExceptionRecord, 'rule' | 'kind'>): string =>
  o.kind === 'warning' ? 'Warning accepted' : isGuideRule(o.rule) ? 'Guide rule overridden' : 'Team agreement overridden';

export const countKinds = (log: readonly Pick<ExceptionRecord, 'rule' | 'kind'>[]) => ({
  guide: log.filter(o => o.kind === 'override' && isGuideRule(o.rule)).length,
  team: log.filter(o => o.kind === 'override' && !isGuideRule(o.rule)).length,
  warn: log.filter(o => o.kind === 'warning').length,
});

/** A Sprint follows the Scrum Guide as long as no Guide rule was overridden. */
export const followsScrum = (log: readonly Pick<ExceptionRecord, 'rule' | 'kind'>[]): boolean => countKinds(log).guide === 0;

/** The findings the team still has to decide on, in the order they are asked. */
export const pendingFindings = (findings: readonly Finding[], log: readonly ExceptionRecord[], sprint: number): Finding[] =>
  findings.filter(f => needsDecision(f, log, sprint));

/** Overriding a block takes a deliberate reason; accepting a warning doesn't. */
export const MIN_REASON_LENGTH = 10;
export const reasonIsValid = (kind: ExceptionRecord['kind'], reason: string): boolean =>
  kind === 'warning' || reason.trim().length >= MIN_REASON_LENGTH;
