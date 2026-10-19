'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import {
  addDodItem, addMember, getTeam, listExceptions, logException, removeDodItem, removeMember,
  setMemberRole, setProductGoal, setStage, ROLES, type Team,
} from '@/src/db/teams';
import { RULES, kindFor, pendingFindings, reasonIsValid, teamChecks, type Role, type RuleId } from '@/src/rules';
import { CURRENT_USER, STAGES } from '@/src/workflow';

const text = (form: FormData, key: string) => String(form.get(key) ?? '').trim();
const teamPath = (id: string) => `/teams/${encodeURIComponent(id)}`;

async function loadTeam(id: string): Promise<Team> {
  const team = await getTeam(id);
  if (!team) throw new Error(`Unknown team ${id}`);
  return team;
}

async function pendingForTeam(team: Team) {
  return pendingFindings(teamChecks(team), await listExceptions(team.id, team.sprintNumber), team.sprintNumber);
}

/** Moves on to Sprint Planning when nothing is left to decide, otherwise asks about the next finding. */
async function continueToPlanning(team: Team): Promise<never> {
  if ((await pendingForTeam(team)).length) redirect(`${teamPath(team.id)}?decide=1`);
  await setStage(team.id, 1);
  revalidatePath(teamPath(team.id));
  redirect(teamPath(team.id));
}

export async function startPlanning(teamId: string) {
  await continueToPlanning(await loadTeam(teamId));
}

export async function decide(teamId: string, form: FormData) {
  const team = await loadTeam(teamId);
  const rule = text(form, 'rule') as RuleId, target = text(form, 'target'), detail = text(form, 'detail'), reason = text(form, 'reason');
  // Only a finding that is really pending can be decided, so the log can't hold made-up entries.
  const finding = (await pendingForTeam(team)).find(f => f.rule === rule && f.target === target && f.detail === detail);
  if (!finding || !(rule in RULES)) redirect(`${teamPath(team.id)}?decide=1`);
  const kind = kindFor(rule);
  if (!reasonIsValid(kind, reason)) redirect(`${teamPath(team.id)}?decide=1&error=reason`);
  await logException(team.id, { rule, kind, reason, who: CURRENT_USER, target, detail, sprint: team.sprintNumber, stage: STAGES[team.stage], day: null });
  await continueToPlanning(team);
}

export async function backToTeam(teamId: string) {
  await setStage(teamId, 0);
  revalidatePath(teamPath(teamId));
}

export async function saveProductGoal(teamId: string, form: FormData) {
  await setProductGoal(teamId, text(form, 'productGoal'));
  revalidatePath(teamPath(teamId));
}

export async function addTeamMember(teamId: string, form: FormData) {
  const name = text(form, 'name'), role = text(form, 'role') as Role;
  if (name && ROLES.includes(role)) await addMember(teamId, name, role);
  revalidatePath(teamPath(teamId));
}

export async function changeRole(teamId: string, memberId: number, form: FormData) {
  const role = text(form, 'role') as Role;
  if (ROLES.includes(role)) await setMemberRole(teamId, memberId, role);
  revalidatePath(teamPath(teamId));
}

export async function deleteMember(teamId: string, memberId: number) {
  await removeMember(teamId, memberId);
  revalidatePath(teamPath(teamId));
}

export async function addDod(teamId: string, form: FormData) {
  const item = text(form, 'text');
  if (item) await addDodItem(teamId, item);
  revalidatePath(teamPath(teamId));
}

export async function deleteDod(teamId: string, itemId: number) {
  await removeDodItem(teamId, itemId);
  revalidatePath(teamPath(teamId));
}
