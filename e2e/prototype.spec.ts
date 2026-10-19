import { expect, test, type Page } from '@playwright/test';

// Drives the clickable prototype through the gates that the rules engine now owns.
const dialog = (p: Page) => p.locator('#dlg-title');
const override = async (p: Page, reason: string) => {
  if (await p.locator('#ov-reason').count()) await p.fill('#ov-reason', reason);
  await p.click('#ov-go');
};

let errors: string[] = [];
test.beforeEach(async ({ page }) => {
  errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('/prototype/index.html');
});
test.afterEach(() => expect(errors).toEqual([]));

test('home page links to the prototype', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('link', { name: 'Open the prototype' })).toHaveAttribute('href', '/prototype/index.html');
});

test('an accepted warning or logged override is asked only once', async ({ page }) => {
  await page.click('[data-team="borealis"]');
  await page.click('#next');
  for (const r of ['Two POs during handover', 'No Scrum Master hired yet', '', 'Product Goal workshop next week', 'DoD agreed in first Retro'])
    await override(page, r);
  await expect(page.locator('#log')).toContainText('4 Guide rule overrides · 0 team agreement overrides · 1 accepted warning');
  await page.click('#back');
  await page.click('#next');
  await expect(page.locator('h1')).toContainText('Sprint 1 Planning');
  await expect(page.locator('#log')).toContainText('4 Guide rule overrides · 0 team agreement overrides · 1 accepted warning');
});

test('the story check only needs "As … want … so …"', async ({ page }) => {
  await page.click('#next');
  await page.fill('#story-new', 'As a picker want scanning so faster');
  await page.click('#story-add');
  await expect(dialog(page)).toHaveCount(0);
  await expect(page.locator('tbody')).toContainText('As a picker want scanning so faster');
});

test('items too big for one Sprint are blocked when selected', async ({ page }) => {
  await page.click('#next');
  await page.fill('#story-new', 'As a buyer I want to pay by invoice so that I can order on account');
  await page.selectOption('#story-pts', '20');
  await page.click('#story-add');
  await page.locator('[data-sel]').last().click();
  await expect(dialog(page)).toContainText('its 20 points are more than the average velocity of 15.7');
  await page.click('#ov-cancel');
  await page.click('[data-big="a1"]');
  await page.click('#sel-a1');
  await expect(dialog(page)).toContainText('the Developers marked it as too big');
  await page.click('#ov-cancel');
  await page.click('[data-big="a1"]');
  await page.click('#sel-a1');
  await expect(page.locator('#sel-a1')).toBeChecked();
});

test('a full Sprint reaches the summary with exception counts', async ({ page }) => {
  await page.click('#next');
  await page.fill('#sgoal', 'Customers help themselves');
  for (const id of ['a1', 'a2', 'a4']) await page.click(`#sel-${id}`);
  await page.click('#next');
  await page.selectOption('#confirmer', 'Mara Visser');
  await page.click('#confirm-order');
  await expect(dialog(page)).toContainText('A Developer confirms the Sprint Backlog order');
  await page.click('#ov-cancel');
  await page.selectOption('#confirmer', 'Lena Smit');
  await page.click('#confirm-order');
  for (let d = 1; d < 10; d++) { await page.click('#daily'); await page.click('#nextday'); }
  await page.click('#daily');
  await page.click('[data-start="a1"]');
  await page.click('[data-done="a1"]');
  for (let i = 0; i < 5; i++) await page.check(`#dod-${i}`);
  await page.click('#mark-done');
  await page.click('#next');
  await override(page, '');
  await page.click('#met-yes');
  await page.click('#next');
  await page.fill('#act-new', 'As a Developer I want our own test environment so that testing stays in the team');
  await page.selectOption('#act-pts', '3');
  await page.click('#act-add');
  await page.click('#next');
  const metrics = page.locator('.metric');
  await expect(metrics.filter({ hasText: 'Guide rule overrides' })).toContainText('0');
  await expect(metrics.filter({ hasText: 'Team agreement overrides' })).toContainText('0');
  await expect(metrics.filter({ hasText: 'Accepted warnings' })).toContainText('1');
});
