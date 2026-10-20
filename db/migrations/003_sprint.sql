-- The running Sprint: working day, Sprint Backlog order and progress, Daily Scrums and Definition of Done checks.
alter table teams add column sprint_day integer not null default 1 check (sprint_day >= 1);
-- Sprint length in working days; a team setting later (F-03).
alter table teams add column sprint_length integer not null default 10 check (sprint_length between 1 and 20);
alter table teams add column order_confirmed_by text;

alter table sprint_items add column position integer;
alter table sprint_items add column status text not null default 'todo' check (status in ('todo', 'doing', 'done'));
-- Definition of Done lines ticked for this item.
alter table sprint_items add column dod_checked integer[] not null default '{}';

create table daily_scrums (
  team_id text not null references teams(id) on delete cascade,
  sprint integer not null,
  day integer not null,
  held boolean not null,
  primary key (team_id, sprint, day)
);
