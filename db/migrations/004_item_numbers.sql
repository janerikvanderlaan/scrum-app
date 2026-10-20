-- A stable number per Product Backlog item within its team, shown as US-<number>. It never changes when the order does.
alter table backlog_items add column number integer;

update backlog_items b set number = n.rn
  from (select id, row_number() over (partition by team_id order by position, id) as rn from backlog_items) n
 where b.id = n.id;

create function set_backlog_item_number() returns trigger language plpgsql as $$
begin
  if new.number is null then
    perform pg_advisory_xact_lock(hashtext('backlog_items:' || new.team_id));
    select coalesce(max(number), 0) + 1 into new.number from backlog_items where team_id = new.team_id;
  end if;
  return new;
end $$;

create trigger backlog_item_number before insert on backlog_items for each row execute function set_backlog_item_number();

alter table backlog_items alter column number set not null;
alter table backlog_items add constraint backlog_items_team_number unique (team_id, number);
