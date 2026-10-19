'use server';

import { redirect } from 'next/navigation';
import { createTeam } from '@/src/db/teams';

export async function newTeam(form: FormData) {
  const name = String(form.get('name') ?? '').trim();
  if (!name) return;
  redirect(`/teams/${encodeURIComponent(await createTeam(name))}`);
}
