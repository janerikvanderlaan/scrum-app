import type { ItemStatus, SprintItem } from '@/src/rules';
import { pool } from './client';

export interface SprintBacklogItem extends SprintItem {
  points: number | null;
  /** Ids of the Definition of Done lines ticked for this item. */
  dodChecked: number[];
}

export interface Sprint {
  day: number;
  length: number;
  confirmedBy: string | null;
  /** In the Developers' order, top first. */
  items: SprintBacklogItem[];
  /** Per working day: true when the Daily Scrum was held, false when the team went on without one. */
  daily: Record<number, boolean>;
}

export async function getSprint(teamId: string, sprint: number): Promise<Sprint> {
  const db = pool();
  const [team, items, daily] = await Promise.all([
    db.query('select sprint_day, sprint_length, order_confirmed_by from teams where id = $1', [teamId]),
    db.query(
      `select b.id, b.title, b.points, s.status, s.dod_checked from sprint_items s join backlog_items b on b.id = s.item_id
        where s.team_id = $1 and s.sprint = $2 order by s.position nulls last, b.position, b.id`,
      [teamId, sprint],
    ),
    db.query('select day, held from daily_scrums where team_id = $1 and sprint = $2', [teamId, sprint]),
  ]);
  const t = team.rows[0] ?? { sprint_day: 1, sprint_length: 10, order_confirmed_by: null };
  return {
    day: t.sprint_day,
    length: t.sprint_length,
    confirmedBy: t.order_confirmed_by,
    items: items.rows.map(r => ({ id: String(r.id), title: r.title, points: r.points, status: r.status, dodChecked: r.dod_checked })),
    daily: Object.fromEntries(daily.rows.map(r => [r.day, r.held])),
  };
}

/** Writes the Sprint Backlog order, top first; only items of this team's Sprint are touched. */
export async function setOrder(teamId: string, sprint: number, itemIds: readonly number[]): Promise<void> {
  await pool().query(
    `update sprint_items s set position = o.n from unnest($3::int[]) with ordinality as o(item_id, n)
      where s.team_id = $1 and s.sprint = $2 and s.item_id = o.item_id`,
    [teamId, sprint, itemIds],
  );
}

export async function confirmOrder(teamId: string, by: string): Promise<void> {
  await pool().query('update teams set order_confirmed_by = $2 where id = $1', [teamId, by]);
}

export async function setStatus(teamId: string, sprint: number, itemId: number, status: ItemStatus): Promise<void> {
  await pool().query('update sprint_items set status = $4 where team_id = $1 and sprint = $2 and item_id = $3', [teamId, sprint, itemId, status]);
}

export async function setDodChecked(teamId: string, sprint: number, itemId: number, dodIds: readonly number[]): Promise<void> {
  await pool().query(
    `update sprint_items set dod_checked = array(select id from dod_items where team_id = $1 and id = any($4::int[]) order by id)
      where team_id = $1 and sprint = $2 and item_id = $3`,
    [teamId, sprint, itemId, dodIds],
  );
}

export async function recordDaily(teamId: string, sprint: number, day: number, held: boolean): Promise<void> {
  // A held Daily Scrum is never turned back into a skipped one.
  await pool().query(
    `insert into daily_scrums (team_id, sprint, day, held) values ($1, $2, $3, $4)
     on conflict (team_id, sprint, day) do update set held = daily_scrums.held or excluded.held`,
    [teamId, sprint, day, held],
  );
}

/** Moves to the next working day, never past the last one. */
export async function nextDay(teamId: string): Promise<void> {
  await pool().query('update teams set sprint_day = least(sprint_day + 1, sprint_length) where id = $1', [teamId]);
}
