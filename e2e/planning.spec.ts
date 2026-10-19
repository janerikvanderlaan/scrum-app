import { execFileSync } from 'node:child_process';
import { expect, test, type Page } from '@playwright/test';

// Team Atlas from the seed: average velocity 15.7, item 3 marked too big, item 6 unsized.
const title = (p: Page) => p.locator('#dlg-title');
const row = (p: Page, n: number) => p.locator('tbody tr').nth(n - 1);
const selectItem = (p: Page, n: number) => p.getByRole('button', { name: `Select item ${n}`, exact: true }).click();

let errors: string[] = [];
test.beforeEach(async ({ page }) => {
  // Every test starts from the seeded Team Atlas.
  execFileSync('node', ['scripts/seed.mjs', '--reset']);
  errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('/teams/atlas');
  await page.click('#next');
  await expect(page.locator('h1')).toHaveText('Sprint 1 Planning');
});
test.afterEach(() => expect(errors).toEqual([]));

test('stories must follow the format, and each new item is asked about once', async ({ page }) => {
  await page.fill('[aria-label="New user story"]', 'Fix the login bug');
  await page.click('text=Add to Product Backlog');
  await expect(title(page)).toHaveText('“Fix the login bug” is not written as a user story');
  await page.click('#ov-cancel');
  await expect(page.locator('tbody')).not.toContainText('Fix the login bug');

  await page.fill('[aria-label="New user story"]', 'As a picker want scanning so faster');
  await page.selectOption('[aria-label="Story points"]', '2');
  await page.click('text=Add to Product Backlog');
  await expect(row(page, 7)).toContainText('As a picker want scanning so faster');
  await expect(title(page)).toHaveCount(0);
});

test('items too big for one Sprint are blocked when selected', async ({ page }) => {
  await selectItem(page, 3);
  await expect(title(page)).toHaveText('“Replace the legacy payment provider” is not written as a user story');
  await page.click('#ov-cancel');

  await row(page, 1).getByRole('button', { name: 'Mark too big' }).click();
  await expect(row(page, 1)).toContainText('Too big for one Sprint · marked');
  await selectItem(page, 1);
  await expect(title(page)).toContainText('the Developers marked it as too big');
  await page.click('#ov-cancel');
  await row(page, 1).getByRole('button', { name: 'Unmark too big' }).click();
  await selectItem(page, 1);
  await expect(page.getByRole('button', { name: 'Remove item 1' })).toHaveAttribute('aria-pressed', 'true');
});

test('closing Sprint Planning needs a Sprint Goal, sized stories and a forecast within velocity', async ({ page }) => {
  for (const n of [1, 2, 4, 5]) await selectItem(page, n);
  await expect(page.locator('#forecast')).toHaveText('Forecast 16 points');
  await page.click('#next');
  await expect(title(page)).toHaveText('Sprint Planning cannot close without a Sprint Goal');
  await page.click('#ov-cancel');

  await page.fill('[aria-label="Sprint Goal"]', 'Customers help themselves with their account');
  await page.click('text=Save Sprint Goal');
  await page.click('#next');
  await expect(title(page)).toHaveText('The forecast of 16 points is more than the average velocity of 15.7 points');
  await page.click('#ov-cancel');

  await page.getByRole('button', { name: 'Remove item 5' }).click();
  await selectItem(page, 6);
  await page.click('#next');
  await expect(title(page)).toHaveText('1 selected story is not sized');
  await page.fill('#ov-reason', 'Sizing it in the first Daily Scrum');
  await page.click('#ov-go');
  await expect(page.locator('h1')).toHaveText('Sprint 1');
  await expect(page.locator('.log')).toContainText('0 Guide rule overrides · 1 team agreement override · 0 accepted warnings');
  await expect(page.locator('header .tag')).toHaveText('Following the Scrum Guide');
});

// Test round 1, issue 2: there was no way to size or resize an item already on the Product Backlog.
test('items on the Product Backlog can be sized and resized', async ({ page }) => {
  const size = page.locator('[aria-label="Size of item 6"]');
  await expect(size).toHaveValue('');
  await size.selectOption('5');
  await page.waitForLoadState('networkidle');
  await expect(size).toHaveValue('5');
  await page.reload();
  await expect(size).toHaveValue('5');
  await size.selectOption('');
  await page.waitForLoadState('networkidle');
  await page.reload();
  await expect(size).toHaveValue('');
});
