// Adds the two example teams from the prototype, unless they already exist.
// With --reset the example teams are deleted first, so tests start from the same state.
import pg from 'pg';

const teams = [
  {
    id: 'atlas', name: 'Team Atlas',
    productGoal: 'Customers can manage their own account without calling support, cutting account-related calls by half.',
    members: [['Mara Visser', 'Product Owner'], ['Joost Bakker', 'Scrum Master'], ['Lena Smit', 'Developer'], ['Ravi Kapoor', 'Developer'], ['Sofie de Wit', 'Developer'], ['Tom Hendriks', 'Developer']],
    dod: ['Code reviewed by another Developer', 'Automated tests pass in the pipeline', 'Tested by the team, no open defects', 'Deployed to the acceptance environment', 'User documentation updated'],
  },
  {
    id: 'borealis', name: 'Team Borealis', productGoal: '',
    members: [['Erik Jansen', 'Product Owner'], ['Noor Amrani', 'Product Owner'], ['Pieter Vos', 'Developer'], ['Anna Kok', 'Developer'], ['Daan Mulder', 'Developer'], ['Fleur Bos', 'Developer'],
      ['Sem Dekker', 'Developer'], ['Julia Peters', 'Developer'], ['Luuk Willems', 'Developer'], ['Iris Meijer', 'Developer'], ['Bram Koster', 'Developer']],
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
    console.log(`seeded ${t.name}`);
  }
} finally {
  await client.end();
}
