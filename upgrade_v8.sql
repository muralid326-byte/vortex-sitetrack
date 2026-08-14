-- ============================================================
-- VORTEX SITETRACK v8 MIGRATION
-- Adds the project lifecycle: yet to start / ongoing / completed,
-- plus JCC and invoice close-out tracking.
-- Run AFTER v4 to v7. Safe to re-run.
-- ============================================================

alter table public.sites
  add column if not exists status            text default 'ongoing',
  add column if not exists completed_date    date,
  add column if not exists jcc_submitted     boolean default false,
  add column if not exists jcc_date          date,
  add column if not exists invoice_submitted boolean default false,
  add column if not exists invoice_date      date;

-- existing rows: anything switched off was effectively finished
update public.sites set status = case when coalesce(active,true) then 'ongoing' else 'completed' end
where status is null;

alter table public.sites drop constraint if exists sites_status_check;
alter table public.sites add constraint sites_status_check
  check (status in ('to_start','ongoing','completed'));

create index if not exists sites_status_idx on public.sites(status);
