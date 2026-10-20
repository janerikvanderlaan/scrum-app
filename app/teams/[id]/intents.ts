import { addBacklogItem, getPlanning, selectItem, type Planning } from '@/src/db/planning';
import { confirmOrder, getSprint, nextDay, recordDaily, setOrder, setStatus, type Sprint } from '@/src/db/sprint';
import { listExceptions, setStage, type Team } from '@/src/db/teams';
import {
  confirmOrderChecks, dailyChecks, doneChecks, planningChecks, resolveExceptions, reviewChecks, selectionChecks, startChecks, teamChecks,
  type Finding, type LoggedException,
} from '@/src/rules';

/**
 * Something the team wants to do that the rules engine checks first. While findings are open,
 * the intent travels in the URL and in the decision dialog, so the server can recheck it each step.
 */
export type Intent =
  | { kind: 'start-planning' }
  | { kind: 'add'; title: string; points: number | null }
  | { kind: 'select'; item: string }
  | { kind: 'close-planning' }
  | { kind: 'confirm-order'; member: string }
  | { kind: 'start-item'; item: string }
  | { kind: 'done-item'; item: string }
  | { kind: 'next-day' }
  | { kind: 'start-review' };

/** What the checks look at besides the team itself. */
export interface TeamData {
  planning: Planning;
  sprint: Sprint;
}

/** The stage an intent belongs to; it is ignored in any other stage. */
const STAGE: Record<Intent['kind'], number> = {
  'start-planning': 0, add: 1, select: 1, 'close-planning': 1,
  'confirm-order': 2, 'start-item': 2, 'done-item': 2, 'next-day': 2, 'start-review': 2,
};

export function parseIntent(get: (key: string) => string | null | undefined): Intent | null {
  const kind = get('decide');
  const points = Number(get('points'));
  switch (kind) {
    case 'start-planning':
    case 'close-planning':
    case 'next-day':
    case 'start-review':
      return { kind };
    case 'add': {
      const title = (get('title') ?? '').trim();
      return title ? { kind, title, points: Number.isInteger(points) && points > 0 ? points : null } : null;
    }
    case 'select':
    case 'start-item':
    case 'done-item': {
      const item = get('item');
      return item ? { kind, item } : null;
    }
    case 'confirm-order': {
      const member = get('member');
      return member ? { kind, member } : null;
    }
    default:
      return null;
  }
}

/** The fields that carry an intent, for the URL query and the dialog's hidden inputs. */
export function intentFields(intent: Intent): Record<string, string> {
  switch (intent.kind) {
    case 'add':
      return { decide: intent.kind, title: intent.title, points: intent.points ? String(intent.points) : '' };
    case 'select':
    case 'start-item':
    case 'done-item':
      return { decide: intent.kind, item: intent.item };
    case 'confirm-order':
      return { decide: intent.kind, member: intent.member };
    default:
      return { decide: intent.kind };
  }
}

const memberFor = (team: Team, id: string) => team.members.find(m => String(m.id) === id);
const itemFor = (sprint: Sprint, id: string) => sprint.items.find(b => b.id === id);

/** Whether the intent can still be carried out at all; checks only run for intents that can. */
function applies(team: Team, { sprint }: TeamData, intent: Intent): boolean {
  if (team.stage !== STAGE[intent.kind]) return false;
  switch (intent.kind) {
    case 'confirm-order':
      return !sprint.confirmedBy && !!memberFor(team, intent.member);
    case 'start-item':
      return itemFor(sprint, intent.item)?.status === 'todo';
    case 'done-item':
      return itemFor(sprint, intent.item)?.status === 'doing';
    case 'next-day':
      return sprint.day < sprint.length;
    default:
      return true;
  }
}

export function findingsFor(team: Team, data: TeamData, intent: Intent): Finding[] {
  if (!applies(team, data, intent)) return [];
  const { planning, sprint } = data;
  switch (intent.kind) {
    case 'start-planning':
      return teamChecks(team);
    case 'add':
      // A new item has no id yet, so its findings point at the add form.
      return selectionChecks({ id: 'new', title: intent.title, points: intent.points, markedBig: false }, planning.velocities, team.velocityDeviation)
        .filter(f => f.rule === 'TEAM-02')
        .map(f => ({ ...f, target: 'story-new' }));
    case 'select': {
      const item = planning.backlog.find(b => b.id === intent.item);
      return item && !planning.selected.includes(Number(item.id)) ? selectionChecks(item, planning.velocities, team.velocityDeviation) : [];
    }
    case 'close-planning':
      return planningChecks(team.sprintGoal, planning.backlog.filter(b => planning.selected.includes(Number(b.id))), planning.velocities, team.velocityDeviation);
    case 'confirm-order':
      return confirmOrderChecks(memberFor(team, intent.member)!);
    case 'start-item':
      return startChecks(sprint.items, intent.item, sprint.confirmedBy);
    case 'done-item': {
      const item = itemFor(sprint, intent.item)!;
      return doneChecks(item, team.dod.length, team.dod.filter(d => item.dodChecked.includes(d.id)).length);
    }
    case 'next-day':
      return dailyChecks(sprint.day, sprint.daily[sprint.day] === true);
    case 'start-review':
      return reviewChecks(sprint.day, sprint.length, sprint.daily[sprint.day] === true, sprint.items);
  }
}

/** Carries out an intent once every finding is decided. */
export async function runIntent(team: Team, data: TeamData, intent: Intent): Promise<void> {
  if (!applies(team, data, intent)) return;
  const { planning, sprint } = data, n = team.sprintNumber;
  switch (intent.kind) {
    case 'start-planning':
      return setStage(team.id, 1);
    case 'add':
      return addBacklogItem(team.id, intent.title, intent.points);
    case 'select':
      return selectItem(team.id, n, Number(intent.item));
    case 'close-planning':
      // The Sprint Backlog starts in Product Backlog order; the Developers can change it before they confirm it.
      if (!sprint.confirmedBy) await setOrder(team.id, n, planning.backlog.map(b => Number(b.id)).filter(id => planning.selected.includes(id)));
      return setStage(team.id, 2);
    case 'confirm-order':
      return confirmOrder(team.id, memberFor(team, intent.member)!.name);
    case 'start-item':
      return setStatus(team.id, n, Number(intent.item), 'doing');
    case 'done-item':
      return setStatus(team.id, n, Number(intent.item), 'done');
    case 'next-day':
      await recordDaily(team.id, n, sprint.day, false);
      return nextDay(team.id);
    case 'start-review':
      await recordDaily(team.id, n, sprint.day, false);
      return setStage(team.id, 3);
  }
}

export async function loadTeamData(team: Team): Promise<TeamData> {
  const [planning, sprint] = await Promise.all([getPlanning(team.id, team.sprintNumber), getSprint(team.id, team.sprintNumber)]);
  return { planning, sprint };
}

/** This Sprint's exception log, with team setup exceptions marked resolved once the team fixed them. */
export async function loadLog(team: Team): Promise<LoggedException[]> {
  return resolveExceptions(await listExceptions(team.id, team.sprintNumber), teamChecks(team));
}
