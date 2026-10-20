import { execFileSync } from 'node:child_process';
import { expect, test, type Page } from '@playwright/test';

// Test round 3 (Jan Erik, 2026-10-20), on the seeded Team Atlas: average velocity 15.7,
// item 3 not a user story and marked too big, item 6 unsized.
const title = (p: Page) => p.locator('#dlg-title');
const override = async (p: Page, expected: string, reason = 'Agreed with the whole team today') => {
  await expect(title(p)).toHaveText(expected);
  if (await p.locator('#ov-reason').count()) await p.fill('#ov-reason', reason);
  await p.click('#ov-go');
};
const selectItem = async (p: Page, n: number) => p.getByRole('button', { name: `Select item ${n}`, exact: true }).click();
const selected = (p: Page, n: number) => expect(p.getByRole('button', { name: `Remove item ${n}`, exact: true })).toBeVisible();
async function setGoal(p: Page) {
  await p.fill('[aria-label="Sprint Goal"]', 'Customers help themselves with their account');
  await p.click('text=Save Sprint Goal');
  await p.waitForLoadState('networkidle');
}

let errors: string[] = [];
test.beforeEach(async ({ page }) => {
  execFileSync('node', ['scripts/seed.mjs', '--reset']);
  errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('/teams/atlas');
});
test.afterEach(() => expect(errors).toEqual([]));

test('issue 1: an override is resolved once the team fixes its cause', async ({ page }) => {
  const role = page.locator('[aria-label="Accountability of Lena Smit"]');
  await role.selectOption('Product Owner');
  await page.waitForLoadState('networkidle');
  await page.click('#next');
  await override(page, 'Team Atlas has 2 Product Owners');
  await expect(page.locator('h1')).toHaveText('Sprint 1 Planning');
  await expect(page.locator('header .tag')).toHaveText('Not following the Scrum Guide');

  await page.click('#back');
  await role.selectOption('Developer');
  await expect(page.locator('.log li.resolved')).toContainText('Resolved');
  await expect(page.locator('.log')).toContainText('0 Guide rule overrides · 0 team agreement overrides · 0 accepted warnings · 1 resolved');
  await expect(page.locator('header .tag')).toHaveText('Following the Scrum Guide');

  // If the problem comes back, the same override counts again.
  await role.selectOption('Product Owner');
  await expect(page.locator('.log li.resolved')).toHaveCount(0);
  await expect(page.locator('header .tag')).toHaveText('Not following the Scrum Guide');
});

test('issues 2 and 4: unsized stories get a clear message that clears once they are sized', async ({ page }) => {
  await page.click('#next');
  await setGoal(page);
  await selectItem(page, 6);
  await selected(page, 6);
  await page.click('#next');
  await expect(title(page)).toHaveText('There are User Stories without sizing added to the Sprint');
  await page.click('#ov-cancel');

  await page.locator('[aria-label="Size of item 6"]').selectOption('3');
  await page.waitForLoadState('networkidle');
  await page.click('#next');
  await expect(page.locator('h1')).toHaveText('Sprint 1');
  await expect(page.locator('[data-order-item]')).toHaveCount(1);
});

test('issue 5: an overloaded Sprint is stopped, and the Sprint shows every selected story', async ({ page }) => {
  await page.click('#next');
  await setGoal(page);
  for (const n of [1, 2]) { await selectItem(page, n); await selected(page, n); }
  await selectItem(page, 3);
  await override(page, '“Replace the legacy payment provider” is not written as a user story');
  await override(page, '“Replace the legacy payment provider” can\'t be Done within one Sprint: the Developers marked it as too big');
  await selected(page, 3);
  await selectItem(page, 4);
  await selected(page, 4);

  await page.click('#next');
  await override(page, 'The forecast of 31 points is more than the average velocity of 15.7 points');
  await expect(page.locator('h1')).toHaveText('Sprint 1');
  await expect(page.locator('[data-order-item]')).toHaveCount(4);
  await expect(page.locator('[data-col="todo"] .card')).toHaveCount(4);
});

test('issue 5: closing Sprint Planning with nothing selected says so, and the Sprint explains it is empty', async ({ page }) => {
  await page.click('#next');
  await setGoal(page);
  await page.click('#next');
  await override(page, 'No user stories are selected for this Sprint');
  await expect(page.locator('#empty-sprint')).toHaveText('No stories are in this Sprint. Go back to Sprint Planning to select them.');
});

test('issue 3: the team can allow a forecast a set percentage above the average velocity', async ({ page }) => {
  await page.selectOption('#deviation', '20');
  await page.waitForLoadState('networkidle');
  await expect(page.locator('#deviation')).toHaveValue('20');
  await page.click('#next');
  await setGoal(page);
  for (const n of [1, 2, 4, 5]) { await selectItem(page, n); await selected(page, n); }
  await expect(page.locator('#forecast')).toHaveText('Forecast 16 points');
  await expect(page.locator('.note', { hasText: 'limit 18.8 points with 20% deviation' })).toBeVisible();
  await page.click('#next');
  await expect(page.locator('h1')).toHaveText('Sprint 1');
});
