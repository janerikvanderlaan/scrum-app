// Adds the two example teams from the prototype, unless they already exist.
// With --reset the example teams are deleted first, so tests start from the same state.
import pg from 'pg';

const teams = [
  {
    id: 'atlas', name: 'Team Atlas',
    productGoal: 'Customers can manage their own account without calling support, cutting account-related calls by half.',
    members: [['Mara Visser', 'Product Owner'], ['Joost Bakker', 'Scrum Master'], ['Lena Smit', 'Developer'], ['Ravi Kapoor', 'Developer'], ['Sofie de Wit', 'Developer'], ['Tom Hendriks', 'Developer']],
    velocities: [14, 17, 16],
    backlog: [
      ['As a customer I want to reset my password by email so that I can sign in again without calling support', 5],
      ['As a customer I want to see my order status on my account page so that I know when my order arrives', 3],
      ['Replace the legacy payment provider', 20, true],
      ['As a security officer I want to see failed sign-ins so that I can spot attacks early', 3],
      ['As a customer I want to download my invoices as PDF so that I can file them for my accounts', 5],
      ['As a customer I want to close my account so that my personal data is removed', null],
    ],
    dod: ['Code reviewed by another Developer', 'Automated tests pass in the pipeline', 'Tested by the team, no open defects', 'Deployed to the acceptance environment', 'User documentation updated'],
  },
  {
    id: 'borealis', name: 'Team Borealis', productGoal: '',
    members: [['Erik Jansen', 'Product Owner'], ['Noor Amrani', 'Product Owner'], ['Pieter Vos', 'Developer'], ['Anna Kok', 'Developer'], ['Daan Mulder', 'Developer'], ['Fleur Bos', 'Developer'],
      ['Sem Dekker', 'Developer'], ['Julia Peters', 'Developer'], ['Luuk Willems', 'Developer'], ['Iris Meijer', 'Developer'], ['Bram Koster', 'Developer']],
    velocities: [10, 12],
    backlog: [
      ['Migrate the warehouse database', 20, true],
      ['As an order picker I want to scan barcodes in the picking app so that I pick the right product', 5],
      ['As a store manager I want a daily stock report so that I can reorder on time', null],
    ],
    dod: [],
  },
];

const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
try {
  if (process.argv.includes('--reset')) await client.query('delete from teams where id = any($1)', [teams.map(t => t.id)]);
  for (const t of teams) {
    const { rowCount } = await client.query('insert into teams (id, name, product_goal) values ($1, $2, $3) on conflict do nothing', [t.id, t.name, t.productGoal]);
    if (!rowCount) continue;
    for (const [i, [name, role]] of t.members.entries()) await client.query('insert into members (team_id, name, role, position) values ($1, $2, $3, $4)', [t.id, name, role, i]);
    for (const [i, text] of t.dod.entries()) await client.query('insert into dod_items (team_id, text, position) values ($1, $2, $3)', [t.id, text, i]);
    // Example velocities count as Sprints before the first one in the app, so they get negative numbers.
    for (const [i, points] of t.velocities.entries()) await client.query('insert into velocities (team_id, sprint, points) values ($1, $2, $3)', [t.id, i - t.velocities.length, points]);
    for (const [i, [title, points, big]] of t.backlog.entries())
      await client.query('insert into backlog_items (team_id, title, points, marked_big, position) values ($1, $2, $3, $4, $5)', [t.id, title, points, !!big, i]);
    console.log(`seeded ${t.name}`);
  }
} finally {
  await client.end();
}
