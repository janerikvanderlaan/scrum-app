import type { BacklogItem } from '@/src/rules';
import { pool } from './client';

export interface PlanningItem extends BacklogItem {
  /** Stable identifier within the team, such as US-3. */
  key: string;
  improvement: boolean;
}

export interface Planning {
  backlog: PlanningItem[];
  selected: number[];
  /** Points Done in the last three finished Sprints, oldest first. */
  velocities: number[];
}

export const itemKey = (number: number) => `US-${number}`;

const toItem = (r: { id: number; number: number; title: string; points: number | null; marked_big: boolean; improvement: boolean }): PlanningItem =>
  ({ id: String(r.id), key: itemKey(r.number), title: r.title, points: r.points, markedBig: r.marked_big, improvement: r.improvement });

export async function getPlanning(teamId: string, sprint: number): Promise<Planning> {
  const db = pool();
  const [backlog, selected, velocities] = await Promise.all([
    db.query('select id, number, title, points, marked_big, improvement from backlog_items where team_id = $1 order by position, id', [teamId]),
    db.query('select item_id from sprint_items where team_id = $1 and sprint = $2', [teamId, sprint]),
    db.query('select points from (select sprint, points from velocities where team_id = $1 order by sprint desc limit 3) v order by sprint', [teamId]),
  ]);
  return {
    backlog: backlog.rows.map(toItem),
    selected: selected.rows.map(r => r.item_id),
    velocities: velocities.rows.map(r => r.points),
  };
}

export async function setSprintGoal(teamId: string, goal: string): Promise<void> {
  await pool().query('update teams set sprint_goal = $2 where id = $1', [teamId, goal]);
}

export async function addBacklogItem(teamId: string, title: string, points: number | null): Promise<void> {
  await pool().query(
    'insert into backlog_items (team_id, title, points, position) values ($1, $2, $3, (select coalesce(max(position), -1) + 1 from backlog_items where team_id = $1))',
    [teamId, title, points],
  );
}

export async function setMarkedBig(teamId: string, itemId: number, markedBig: boolean): Promise<void> {
  await pool().query('update backlog_items set marked_big = $3 where team_id = $1 and id = $2', [teamId, itemId, markedBig]);
}

export async function setPoints(teamId: string, itemId: number, points: number | null): Promise<void> {
  await pool().query('update backlog_items set points = $3 where team_id = $1 and id = $2', [teamId, itemId, points]);
}

export async function selectItem(teamId: string, sprint: number, itemId: number): Promise<void> {
  await pool().query(
    'insert into sprint_items (team_id, sprint, item_id) select $1, $2, id from backlog_items where team_id = $1 and id = $3 on conflict do nothing',
    [teamId, sprint, itemId],
  );
}

export async function deselectItem(teamId: string, sprint: number, itemId: number): Promise<void> {
  await pool().query('delete from sprint_items where team_id = $1 and sprint = $2 and item_id = $3', [teamId, sprint, itemId]);
}
