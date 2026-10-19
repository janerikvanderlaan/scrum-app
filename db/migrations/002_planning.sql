-- Product Backlog, Sprint Goal, the Sprint's selected items and past velocities.
alter table teams add column sprint_goal text not null default '';

create table backlog_items (
  id serial primary key,
  team_id text not null references teams(id) on delete cascade,
  title text not null,
  points integer check (points > 0),
  marked_big boolean not null default false,
  improvement boolean not null default false,
  position integer not null,
  created_at timestamptz not null default now()
);

create table sprint_items (
  team_id text not null references teams(id) on delete cascade,
  sprint integer not null,
  item_id integer not null references backlog_items(id) on delete cascade,
  primary key (team_id, sprint, item_id)
);

-- Points Done per finished Sprint; the average of the last three is the team's velocity.
create table velocities (
  team_id text not null references teams(id) on delete cascade,
  sprint integer not null,
  points integer not null check (points >= 0),
  primary key (team_id, sprint)
);
