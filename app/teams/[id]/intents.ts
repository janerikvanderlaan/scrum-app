import { addBacklogItem, getPlanning, selectItem, type Planning } from '@/src/db/planning';
import { setStage, type Team } from '@/src/db/teams';
import { planningChecks, selectionChecks, teamChecks, type Finding } from '@/src/rules';

/**
 * Something the team wants to do that the rules engine checks first. While findings are open,
 * the intent travels in the URL and in the decision dialog, so the server can recheck it each step.
 */
export type Intent =
  | { kind: 'start-planning' }
  | { kind: 'add'; title: string; points: number | null }
  | { kind: 'select'; item: string }
  | { kind: 'close-planning' };

/** The stage an intent belongs to; it is ignored in any other stage. */
const STAGE: Record<Intent['kind'], number> = { 'start-planning': 0, add: 1, select: 1, 'close-planning': 1 };

export function parseIntent(get: (key: string) => string | null | undefined): Intent | null {
  const kind = get('decide');
  const points = Number(get('points'));
  switch (kind) {
    case 'start-planning':
    case 'close-planning':
      return { kind };
    case 'add': {
      const title = (get('title') ?? '').trim();
      return title ? { kind, title, points: Number.isInteger(points) && points > 0 ? points : null } : null;
    }
    case 'select': {
      const item = get('item');
      return item ? { kind, item } : null;
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
      return { decide: intent.kind, item: intent.item };
    default:
      return { decide: intent.kind };
  }
}

export function findingsFor(team: Team, planning: Planning, intent: Intent): Finding[] {
  if (team.stage !== STAGE[intent.kind]) return [];
  switch (intent.kind) {
    case 'start-planning':
      return teamChecks(team);
    case 'add':
      // A new item has no id yet, so its findings point at the add form.
      return selectionChecks({ id: 'new', title: intent.title, points: intent.points, markedBig: false }, planning.velocities)
        .filter(f => f.rule === 'TEAM-02')
        .map(f => ({ ...f, target: 'story-new' }));
    case 'select': {
      const item = planning.backlog.find(b => b.id === intent.item);
      return item && !planning.selected.includes(Number(item.id)) ? selectionChecks(item, planning.velocities) : [];
    }
    case 'close-planning':
      return planningChecks(team.sprintGoal, planning.backlog.filter(b => planning.selected.includes(Number(b.id))), planning.velocities);
  }
}

/** Carries out an intent once every finding is decided. */
export async function runIntent(team: Team, intent: Intent): Promise<void> {
  if (team.stage !== STAGE[intent.kind]) return;
  switch (intent.kind) {
    case 'start-planning':
      return setStage(team.id, 1);
    case 'add':
      return addBacklogItem(team.id, intent.title, intent.points);
    case 'select':
      return selectItem(team.id, team.sprintNumber, Number(intent.item));
    case 'close-planning':
      return setStage(team.id, 2);
  }
}

export async function loadPlanning(team: Team): Promise<Planning> {
  return getPlanning(team.id, team.sprintNumber);
}
