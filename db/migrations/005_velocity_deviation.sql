-- How far, in percent, the forecast may go above the average velocity before Sprint Planning is stopped.
alter table teams add column velocity_deviation integer not null default 0 check (velocity_deviation between 0 and 100);
