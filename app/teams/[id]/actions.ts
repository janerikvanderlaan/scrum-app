'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { deselectItem, setMarkedBig, setPoints, setSprintGoal } from '@/src/db/planning';
import { getSprint, recordDaily, setDodChecked, setOrder } from '@/src/db/sprint';
import {
  addDodItem, addMember, getTeam, logException, removeDodItem, removeMember,
  setMemberRole, setProductGoal, setStage, setVelocityDeviation, ROLES, type Team,
} from '@/src/db/teams';
import { POINTS, RULES, activeExceptions, kindFor, pendingFindings, reasonIsValid, type Role, type RuleId } from '@/src/rules';
import { CURRENT_USER, STAGES } from '@/src/workflow';
import { DEVIATIONS } from './flags';
import { findingsFor, intentFields, loadLog, loadTeamData, parseIntent, runIntent, type Intent } from './intents';

const text = (form: FormData, key: string) => String(form.get(key) ?? '').trim();
const teamPath = (id: string) => `/teams/${encodeURIComponent(id)}`;
const decidePath = (id: string, intent: Intent, extra: Record<string, string> = {}) =>
  `${teamPath(id)}?${new URLSearchParams({ ...intentFields(intent), ...extra })}`;

async function loadTeam(id: string): Promise<Team> {
  const team = await getTeam(id);
  if (!team) throw new Error(`Unknown team ${id}`);
  return team;
}

async function pendingFor(team: Team, intent: Intent) {
  const findings = findingsFor(team, await loadTeamData(team), intent);
  return pendingFindings(findings, activeExceptions(await loadLog(team)), team.sprintNumber);
}

/** Carries out the intent when nothing is left to decide, otherwise asks about the next finding. */
async function proceed(team: Team, intent: Intent): Promise<never> {
  if ((await pendingFor(team, intent)).length) redirect(decidePath(team.id, intent));
  await runIntent(team, await loadTeamData(team), intent);
  revalidatePath(teamPath(team.id));
  redirect(teamPath(team.id));
}

export async function decide(teamId: string, form: FormData) {
  const team = await loadTeam(teamId);
  const intent = parseIntent(key => form.get(key) as string | null);
  if (!intent) redirect(teamPath(team.id));
  const rule = text(form, 'rule') as RuleId, target = text(form, 'target'), detail = text(form, 'detail'), reason = text(form, 'reason');
  // Only a finding that is really pending can be decided, so the log can't hold made-up entries.
  const finding = (await pendingFor(team, intent)).find(f => f.rule === rule && f.target === target && f.detail === detail);
  if (!finding || !(rule in RULES)) redirect(decidePath(team.id, intent));
  const kind = kindFor(rule);
  if (!reasonIsValid(kind, reason)) redirect(decidePath(team.id, intent, { error: 'reason' }));
  const day = team.stage === 2 ? (await getSprint(team.id, team.sprintNumber)).day : null;
  await logException(team.id, { rule, kind, reason, who: CURRENT_USER, target, detail, sprint: team.sprintNumber, stage: STAGES[team.stage], day });
  await proceed(team, intent);
}

export async function startPlanning(teamId: string) {
  await proceed(await loadTeam(teamId), { kind: 'start-planning' });
}

export async function addStory(teamId: string, form: FormData) {
  const title = text(form, 'title'), points = Number(text(form, 'points'));
  if (!title) return;
  await proceed(await loadTeam(teamId), { kind: 'add', title, points: Number.isInteger(points) && points > 0 ? points : null });
}

export async function select(teamId: string, itemId: string) {
  await proceed(await loadTeam(teamId), { kind: 'select', item: itemId });
}

export async function closePlanning(teamId: string) {
  await proceed(await loadTeam(teamId), { kind: 'close-planning' });
}

export async function confirmSprintOrder(teamId: string, form: FormData) {
  const member = text(form, 'member');
  if (member) await proceed(await loadTeam(teamId), { kind: 'confirm-order', member });
}

export async function startItem(teamId: string, itemId: string) {
  await proceed(await loadTeam(teamId), { kind: 'start-item', item: itemId });
}

/** Saves the ticked Definition of Done lines, then marks the item Done through the checks. */
export async function markDone(teamId: string, itemId: string, form: FormData) {
  const team = await loadTeam(teamId);
  await setDodChecked(team.id, team.sprintNumber, Number(itemId), form.getAll('dod').map(Number));
  await proceed(team, { kind: 'done-item', item: itemId });
}

export async function goToNextDay(teamId: string) {
  await proceed(await loadTeam(teamId), { kind: 'next-day' });
}

export async function startReview(teamId: string) {
  await proceed(await loadTeam(teamId), { kind: 'start-review' });
}

export async function holdDailyScrum(teamId: string) {
  const team = await loadTeam(teamId);
  if (team.stage === 2) await recordDaily(team.id, team.sprintNumber, (await getSprint(team.id, team.sprintNumber)).day, true);
  revalidatePath(teamPath(teamId));
}

/** Moves a Sprint Backlog item one place up or down, until a Developer confirms the order. */
export async function moveItem(teamId: string, itemId: string, by: -1 | 1) {
  const team = await loadTeam(teamId);
  const sprint = await getSprint(team.id, team.sprintNumber);
  const ids = sprint.items.map(b => Number(b.id)), i = ids.indexOf(Number(itemId)), j = i + by;
  if (team.stage === 2 && !sprint.confirmedBy && i >= 0 && j >= 0 && j < ids.length) {
    [ids[i], ids[j]] = [ids[j], ids[i]];
    await setOrder(team.id, team.sprintNumber, ids);
  }
  revalidatePath(teamPath(teamId));
}

export async function deselect(teamId: string, itemId: string) {
  const team = await loadTeam(teamId);
  await deselectItem(team.id, team.sprintNumber, Number(itemId));
  revalidatePath(teamPath(teamId));
}

/** The Developers mark an item too big for one Sprint; a marked item leaves the Sprint selection. */
export async function toggleTooBig(teamId: string, itemId: string, markedBig: boolean) {
  const team = await loadTeam(teamId);
  await setMarkedBig(team.id, Number(itemId), markedBig);
  if (markedBig) await deselectItem(team.id, team.sprintNumber, Number(itemId));
  revalidatePath(teamPath(teamId));
}

/** Sizes or resizes a Product Backlog item; an empty choice makes it unsized again. */
export async function resize(teamId: string, itemId: string, form: FormData) {
  const points = Number(text(form, 'points'));
  await setPoints(teamId, Number(itemId), (POINTS as readonly number[]).includes(points) ? points : null);
  revalidatePath(teamPath(teamId));
}

export async function saveSprintGoal(teamId: string, form: FormData) {
  await setSprintGoal(teamId, text(form, 'sprintGoal'));
  revalidatePath(teamPath(teamId));
}

export async function goToStage(teamId: string, stage: number) {
  const team = await loadTeam(teamId);
  // Going back is always allowed; going forward only through the checks.
  if (stage < team.stage) await setStage(team.id, stage);
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

export async function saveVelocityDeviation(teamId: string, form: FormData) {
  const percent = Number(text(form, 'deviation'));
  if ((DEVIATIONS as readonly number[]).includes(percent)) await setVelocityDeviation(teamId, percent);
  revalidatePath(teamPath(teamId));
}
