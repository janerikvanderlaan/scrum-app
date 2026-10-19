import { expect, test, type Page } from '@playwright/test';

// Needs a database with the example teams: npm run db:migrate && npm run db:seed.
const title = (p: Page) => p.locator('#dlg-title');
const override = async (p: Page, expected: string, reason: string) => {
  await expect(title(p)).toHaveText(expected);
  if (reason) await p.fill('#ov-reason', reason);
  await p.click('#ov-go');
};

let errors: string[] = [];
test.beforeEach(({ page }) => {
  errors = [];
  page.on('pageerror', e => errors.push(e.message));
});
test.afterEach(() => expect(errors).toEqual([]));

test('a new team is blocked until it has accountabilities, a Product Goal and a Definition of Done', async ({ page }) => {
  await page.goto('/');
  const name = `Team ${Date.now()}`;
  await page.fill('[aria-label="Team name"]', name);
  await page.click('text=Create team');
  await expect(page.locator('h1')).toHaveText(`Set up ${name}`);

  for (const [who, role] of [['Mara', 'Product Owner'], ['Joost', 'Scrum Master'], ['Lena', 'Developer']]) {
    await page.fill('[aria-label="New member name"]', who);
    await page.selectOption('[aria-label="New member accountability"]', role);
    await page.click('text=Add member');
    await expect(page.locator('tbody')).toContainText(who);
  }
  await page.click('#next');
  await expect(title(page)).toHaveText('There is no Product Goal yet');
  await page.click('#ov-cancel');

  await page.fill('[aria-label="Product Goal"]', 'Customers manage their own account');
  await page.click('text=Save Product Goal');
  await page.fill('[aria-label="New Definition of Done item"]', 'Tested by the team');
  await page.click('form:has([aria-label="New Definition of Done item"]) button');
  await expect(page.locator('.dod')).toContainText('Tested by the team');
  await page.click('#next');
  await expect(page.locator('h1')).toHaveText('Sprint 1 Planning');
  await expect(page.locator('.log')).toContainText('No exceptions in this Sprint');
});

test('overrides need a reason, are logged once and survive going back', async ({ page }) => {
  await page.goto('/teams/borealis');
  await page.click('#next');
  await expect(title(page)).toHaveText('Team Borealis has 2 Product Owners');
  await expect(page.locator('#ov-go')).toHaveText('Override and log');
  await expect(page.locator('#ov-reason')).toHaveAttribute('minlength', '10');

  await override(page, 'Team Borealis has 2 Product Owners', 'Two POs share the role during handover');
  await override(page, 'Team Borealis needs exactly one Product Owner, one Scrum Master and at least one Developer', 'No Scrum Master hired yet');
  await override(page, 'Team Borealis has 11 people', '');
  await override(page, 'There is no Product Goal yet', 'Product Goal workshop is next week');
  await override(page, 'There is no Definition of Done yet', 'DoD agreed in the first Retro');
  await expect(page.locator('h1')).toHaveText('Sprint 1 Planning');
  const tally = '4 Guide rule overrides · 0 team agreement overrides · 1 accepted warning';
  await expect(page.locator('.log')).toContainText(tally);
  await expect(page.locator('header .tag')).toHaveText('Not following the Scrum Guide');

  await page.click('#back');
  await expect(page.locator('section[data-exception="Exception: SG-095, SG-063, SG-068"]')).toBeVisible();
  await page.click('#next');
  await expect(page.locator('h1')).toHaveText('Sprint 1 Planning');
  await expect(page.locator('.log')).toContainText(tally);
});
