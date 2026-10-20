import { execFileSync } from 'node:child_process';
import { expect, test, type Page } from '@playwright/test';

// Team Atlas from the seed, with items 1, 2 and 4 of the Product Backlog in the Sprint.
const RESET = 'As a customer I want to reset my password by email so that I can sign in again without calling support';
const STATUS = 'As a customer I want to see my order status on my account page so that I know when my order arrives';
const title = (p: Page) => p.locator('#dlg-title');
const card = (p: Page, col: string, text: string) => p.locator(`[data-col="${col}"] .card`, { hasText: text });

async function confirmBy(p: Page, member: string) {
  await p.selectOption('[aria-label="Team member who confirms"]', { label: member });
  await p.click('#confirm-order');
}

let errors: string[] = [];
test.beforeEach(async ({ page }) => {
  execFileSync('node', ['scripts/seed.mjs', '--reset']);
  errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('/teams/atlas');
  await page.click('#next');
  for (const n of [1, 2, 4]) {
    await page.getByRole('button', { name: `Select item ${n}`, exact: true }).click();
    await expect(page.getByRole('button', { name: `Remove item ${n}`, exact: true })).toBeVisible();
  }
  await page.fill('[aria-label="Sprint Goal"]', 'Customers help themselves with their account');
  await page.click('text=Save Sprint Goal');
  await page.waitForLoadState('networkidle');
  await page.click('#next');
  await expect(page.locator('h1')).toHaveText('Sprint 1');
});
test.afterEach(() => expect(errors).toEqual([]));

test('the order is set by the Developers and confirmed by a Developer', async ({ page }) => {
  await expect(page.locator('main .eyebrow')).toHaveText('Stage 3 of 6 · working day 1 of 10');
  // Test round 4, issue 1: Start says why it can't go ahead yet instead of doing nothing.
  await card(page, 'todo', RESET).getByRole('button', { name: 'Start' }).click();
  await expect(title(page)).toHaveText('A Developer has not confirmed the Sprint Backlog order yet. Confirm it before starting work');
  await expect(page.locator('section.flag-pending h2')).toHaveText('Sprint Backlog order');
  await page.click('#ov-cancel');
  await expect(card(page, 'todo', RESET)).toBeVisible();
  await page.getByRole('button', { name: 'Move item 1 down' }).click();
  await expect(page.locator('[data-order-item]').first()).toContainText(STATUS);

  await confirmBy(page, 'Mara Visser (Product Owner)');
  await expect(title(page)).toHaveText('Mara Visser is the Product Owner. A Developer confirms the Sprint Backlog order');
  await page.click('#ov-cancel');
  await confirmBy(page, 'Lena Smit (Developer)');
  await expect(page.locator('#order-confirmed')).toHaveText('Order confirmed by Lena Smit. Start items from the top.');
  await expect(page.getByRole('button', { name: 'Move item 1 down' })).toHaveCount(0);
});

test('items start from the top and are Done only when the Definition of Done is met', async ({ page }) => {
  await confirmBy(page, 'Lena Smit (Developer)');
  await card(page, 'todo', STATUS).getByRole('button', { name: 'Start' }).click();
  await expect(title(page)).toHaveText(`“${STATUS}” is not the next item; “${RESET}” is on top`);
  await page.click('#ov-cancel');

  await card(page, 'todo', RESET).getByRole('button', { name: 'Start' }).click();
  await card(page, 'doing', RESET).getByRole('link', { name: 'Check Done' }).click();
  await page.check('text=Code reviewed by another Developer');
  await page.click('#mark-done');
  await expect(title(page)).toHaveText(`4 Definition of Done items are not met for “${RESET}”`);
  await page.click('#ov-cancel');

  await card(page, 'doing', RESET).getByRole('link', { name: 'Check Done' }).click();
  await expect(page.getByLabel('Code reviewed by another Developer')).toBeChecked();
  for (const box of await page.locator('input[name="dod"]').all()) await box.check();
  await page.click('#mark-done');
  await expect(card(page, 'done', RESET)).toContainText('Done');
  await expect(page.locator('header .tag')).toHaveText('Following the Scrum Guide');
});

test('each working day needs a Daily Scrum', async ({ page }) => {
  await page.click('#nextday');
  await expect(title(page)).toHaveText('Day 1 has no Daily Scrum yet');
  await page.fill('#ov-reason', 'Half the team was at a training');
  await page.click('#ov-go');
  await expect(page.locator('main .eyebrow')).toHaveText('Stage 3 of 6 · working day 2 of 10');
  await expect(page.locator('.days .day[title^="Day 1:"]')).toHaveClass(/skipped/);
  await expect(page.locator('header .tag')).toHaveText('Not following the Scrum Guide');

  await page.click('#daily');
  await expect(page.locator('.tag', { hasText: 'Daily Scrum held today' })).toBeVisible();
  await page.click('#nextday');
  await expect(page.locator('.days .day[title^="Day 2:"]')).toHaveClass(/held/);
  await expect(page.locator('main .eyebrow')).toHaveText('Stage 3 of 6 · working day 3 of 10');
});

test('the Sprint Review waits for the end of the Sprint, today’s Daily Scrum and Done items', async ({ page }) => {
  await page.click('#next');
  await expect(title(page)).toHaveText('The Sprint has 9 working days left');
  await page.fill('#ov-reason', 'Stakeholders are only available today');
  await page.click('#ov-go');
  await expect(title(page)).toHaveText('Day 1 has no Daily Scrum yet');
  await page.fill('#ov-reason', 'We go straight to the Review');
  await page.click('#ov-go');
  await expect(title(page)).toHaveText('3 Sprint Backlog items are not Done. Start the Sprint Review anyway?');
  // Test round 2, issue 5.
  await expect(page.locator('#dlg-explain')).toContainText('They may decide not to finish the remaining work');
  await page.click('#ov-go');
  await expect(page.locator('h1')).toHaveText('Sprint 1 Review');
  await expect(page.locator('.log')).toContainText('2 Guide rule overrides');
});

// Test round 2 (Jan Erik, 2026-10-20).
test('the Sprint Backlog shows as a board with three styled columns', async ({ page }) => {
  await expect(page.locator('.board')).toHaveCSS('display', 'grid');
  await expect(page.locator('.board .col > b')).toHaveText(['To do', 'In progress', 'Done']);
  await expect(page.locator('[data-col="todo"] .card')).toHaveCount(3);
});

test('stories keep their ID when the order changes', async ({ page }) => {
  await expect(page.locator('[data-order-item] .item-key')).toHaveText(['US-1', 'US-2', 'US-4']);
  await page.getByRole('button', { name: 'Move item 1 down' }).click();
  await expect(page.locator('[data-order-item] .item-key')).toHaveText(['US-2', 'US-1', 'US-4']);
  await expect(card(page, 'todo', RESET)).toContainText('US-1 · #2');
});

test('each day shows whether the Daily Scrum was held', async ({ page }) => {
  const day = (n: number) => page.locator(`.days .day[title^="Day ${n}:"]`);
  await expect(page.locator('.legend')).toContainText('Daily Scrum held');
  await expect(day(1)).toHaveAttribute('data-state', 'open');
  await expect(day(2)).toHaveAttribute('data-state', 'upcoming');
  await page.click('#daily');
  await expect(day(1)).toHaveAttribute('data-state', 'held');
  await expect(day(1)).toContainText('✓');
  await page.click('#nextday');
  await expect(day(2)).toHaveAttribute('data-state', 'open');
  await page.click('#nextday');
  await page.fill('#ov-reason', 'Half the team was at a training');
  await page.click('#ov-go');
  await expect(day(2)).toHaveAttribute('data-state', 'skipped');
  await expect(day(2)).toContainText('✗');
});

test('all Definition of Done items can be ticked or cleared at once', async ({ page }) => {
  await confirmBy(page, 'Lena Smit (Developer)');
  await card(page, 'todo', RESET).getByRole('button', { name: 'Start' }).click();
  await card(page, 'doing', RESET).getByRole('link', { name: 'Check Done' }).click();
  const all = page.getByLabel('All Definition of Done items'), boxes = page.locator('input[name="dod"]');
  await all.check();
  for (const box of await boxes.all()) await expect(box).toBeChecked();
  await all.uncheck();
  for (const box of await boxes.all()) await expect(box).not.toBeChecked();
  await boxes.first().check();
  await expect(all).not.toBeChecked();
  await all.check();
  await page.click('#mark-done');
  await expect(card(page, 'done', RESET)).toContainText('Done');
});
