-- Teams, their members and Definition of Done, and the exception log.
create table teams (
  id text primary key,
  name text not null,
  product_goal text not null default '',
  sprint_number integer not null default 1,
  stage integer not null default 0,
  created_at timestamptz not null default now()
);

create table members (
  id serial primary key,
  team_id text not null references teams(id) on delete cascade,
  name text not null,
  role text not null check (role in ('Developer', 'Product Owner', 'Scrum Master')),
  position integer not null
);

create table dod_items (
  id serial primary key,
  team_id text not null references teams(id) on delete cascade,
  text text not null,
  position integer not null
);

create table exceptions (
  id serial primary key,
  team_id text not null references teams(id) on delete cascade,
  sprint integer not null,
  rule text not null,
  kind text not null check (kind in ('warning', 'override')),
  reason text not null default '',
  who text not null,
  target text not null,
  detail text not null,
  stage text not null,
  day integer,
  created_at timestamptz not null default now()
);

create index exceptions_team_sprint on exceptions (team_id, sprint);
