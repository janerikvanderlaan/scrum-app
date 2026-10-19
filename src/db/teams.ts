import type { ExceptionRecord, Member, Role, RuleId } from '@/src/rules';
import { pool } from './client';

export interface TeamSummary {
  id: string;
  name: string;
}

export interface Team extends TeamSummary {
  productGoal: string;
  sprintNumber: number;
  stage: number;
  members: (Member & { id: number })[];
  dod: { id: number; text: string }[];
}

export const ROLES: readonly Role[] = ['Developer', 'Product Owner', 'Scrum Master'];

export async function listTeams(): Promise<TeamSummary[]> {
  const { rows } = await pool().query('select id, name from teams order by created_at, name');
  return rows;
}

export async function getTeam(id: string): Promise<Team | null> {
  const db = pool();
  const { rows } = await db.query('select id, name, product_goal, sprint_number, stage from teams where id = $1', [id]);
  if (!rows[0]) return null;
  const [members, dod] = await Promise.all([
    db.query('select id, name, role from members where team_id = $1 order by position, id', [id]),
    db.query('select id, text from dod_items where team_id = $1 order by position, id', [id]),
  ]);
  const t = rows[0];
  return { id: t.id, name: t.name, productGoal: t.product_goal, sprintNumber: t.sprint_number, stage: t.stage, members: members.rows, dod: dod.rows };
}

/** Creates a team with a URL-friendly id derived from its name, and returns the id. */
export async function createTeam(name: string): Promise<string> {
  const base = name.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'team';
  for (let n = 1; ; n++) {
    const id = n === 1 ? base : `${base}-${n}`;
    const { rowCount } = await pool().query('insert into teams (id, name) values ($1, $2) on conflict do nothing', [id, name]);
    if (rowCount) return id;
  }
}

export async function setProductGoal(teamId: string, goal: string): Promise<void> {
  await pool().query('update teams set product_goal = $2 where id = $1', [teamId, goal]);
}

export async function addMember(teamId: string, name: string, role: Role): Promise<void> {
  await pool().query(
    'insert into members (team_id, name, role, position) values ($1, $2, $3, (select coalesce(max(position), -1) + 1 from members where team_id = $1))',
    [teamId, name, role],
  );
}

export async function setMemberRole(teamId: string, memberId: number, role: Role): Promise<void> {
  await pool().query('update members set role = $3 where team_id = $1 and id = $2', [teamId, memberId, role]);
}

export async function removeMember(teamId: string, memberId: number): Promise<void> {
  await pool().query('delete from members where team_id = $1 and id = $2', [teamId, memberId]);
}

export async function addDodItem(teamId: string, text: string): Promise<void> {
  await pool().query(
    'insert into dod_items (team_id, text, position) values ($1, $2, (select coalesce(max(position), -1) + 1 from dod_items where team_id = $1))',
    [teamId, text],
  );
}

export async function removeDodItem(teamId: string, itemId: number): Promise<void> {
  await pool().query('delete from dod_items where team_id = $1 and id = $2', [teamId, itemId]);
}

export async function setStage(teamId: string, stage: number): Promise<void> {
  await pool().query('update teams set stage = $2 where id = $1', [teamId, stage]);
}

export async function listExceptions(teamId: string, sprint: number): Promise<ExceptionRecord[]> {
  const { rows } = await pool().query(
    `select rule, kind, reason, who, target, detail, sprint, stage, day, to_char(created_at, 'HH24:MI') as time
       from exceptions where team_id = $1 and sprint = $2 order by created_at, id`,
    [teamId, sprint],
  );
  return rows.map(r => ({ ...r, rule: r.rule as RuleId }));
}

export async function logException(teamId: string, e: Omit<ExceptionRecord, 'time'>): Promise<void> {
  await pool().query(
    'insert into exceptions (team_id, sprint, rule, kind, reason, who, target, detail, stage, day) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)',
    [teamId, e.sprint, e.rule, e.kind, e.reason, e.who, e.target, e.detail, e.stage, e.day],
  );
}
