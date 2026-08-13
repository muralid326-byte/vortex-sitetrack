-- ============================================================
-- VORTEX SITETRACK v4 MIGRATION
-- Adds: worker register + attendance, report approval workflow,
--       DPR photos (storage), variation / VO register.
-- Run the whole file once in Supabase → SQL Editor. Safe to re-run.
-- ============================================================

-- ---------- 0. helper: is the caller an active admin? ----------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and coalesce(active, true)
  );
$$;

-- ---------- 1. WORKER REGISTER ----------
create table if not exists public.workers (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  emp_no     text,                                   -- work permit / FIN / employee no.
  trade      text,                                   -- must match a row in trades.name
  site_id    uuid references public.sites(id) on delete set null,
  rate       numeric default 0,                      -- 0 / null = fall back to trade rate
  active     boolean default true,
  created_at timestamptz default now()
);
create index if not exists workers_site_idx on public.workers(site_id);

alter table public.workers enable row level security;

drop policy if exists workers_select on public.workers;
create policy workers_select on public.workers
  for select to authenticated using (true);

-- supervisors may add a man who turns up on site; only admin can edit or remove
drop policy if exists workers_insert on public.workers;
create policy workers_insert on public.workers
  for insert to authenticated with check (true);

drop policy if exists workers_update on public.workers;
create policy workers_update on public.workers
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists workers_delete on public.workers;
create policy workers_delete on public.workers
  for delete to authenticated using (public.is_admin());

-- only admin may set a worker's own pay rate
create or replace function public.guard_worker_rate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    if tg_op = 'INSERT' then new.rate := 0; end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_worker_rate on public.workers;
create trigger trg_guard_worker_rate before insert on public.workers
  for each row execute function public.guard_worker_rate();

-- ---------- 2. APPROVAL WORKFLOW + PHOTOS ON DAILY REPORTS ----------
alter table public.daily_reports
  add column if not exists status      text default 'submitted',
  add column if not exists reviewed_by uuid references public.profiles(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text,
  add column if not exists photos      jsonb default '[]'::jsonb;

update public.daily_reports set status = 'submitted' where status is null;

alter table public.daily_reports drop constraint if exists daily_reports_status_check;
alter table public.daily_reports add constraint daily_reports_status_check
  check (status in ('submitted','approved','rejected'));

create index if not exists daily_reports_status_idx on public.daily_reports(status);

-- a supervisor may correct his own report until it is approved; admin may edit anything
drop policy if exists dr_update on public.daily_reports;
create policy dr_update on public.daily_reports
  for update to authenticated
  using      (public.is_admin() or (supervisor_id = auth.uid() and coalesce(status,'submitted') <> 'approved'))
  with check (public.is_admin() or (supervisor_id = auth.uid() and coalesce(status,'submitted') <> 'approved'));

drop policy if exists dr_delete on public.daily_reports;
create policy dr_delete on public.daily_reports
  for delete to authenticated
  using (public.is_admin() or (supervisor_id = auth.uid() and coalesce(status,'submitted') = 'submitted'));

-- a supervisor cannot approve his own report; correcting a rejected one re-submits it
create or replace function public.guard_report_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    if old.status = 'rejected' and new.status = 'submitted' then
      new.reviewed_by := null; new.reviewed_at := null; new.review_note := null;
    else
      new.status      := old.status;
      new.reviewed_by := old.reviewed_by;
      new.reviewed_at := old.reviewed_at;
      new.review_note := old.review_note;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_report_status on public.daily_reports;
create trigger trg_guard_report_status before update on public.daily_reports
  for each row execute function public.guard_report_status();

-- ---------- 3. VARIATION / VO REGISTER ----------
create table if not exists public.variations (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references public.sites(id) on delete cascade,
  vo_no       text,
  vo_date     date default current_date,
  description text,
  amount      numeric not null default 0,
  status      text default 'pending' check (status in ('pending','approved','rejected')),
  created_by  uuid references public.profiles(id) default auth.uid(),
  created_at  timestamptz default now()
);
create index if not exists variations_site_idx on public.variations(site_id);

alter table public.variations enable row level security;

drop policy if exists variations_select on public.variations;
create policy variations_select on public.variations
  for select to authenticated using (true);

drop policy if exists variations_write on public.variations;
create policy variations_write on public.variations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- 4. PHOTO STORAGE ----------
insert into storage.buckets (id, name, public)
values ('dpr-photos', 'dpr-photos', false)
on conflict (id) do nothing;

drop policy if exists dpr_photos_read on storage.objects;
create policy dpr_photos_read on storage.objects
  for select to authenticated using (bucket_id = 'dpr-photos');

drop policy if exists dpr_photos_write on storage.objects;
create policy dpr_photos_write on storage.objects
  for insert to authenticated with check (bucket_id = 'dpr-photos');

drop policy if exists dpr_photos_delete on storage.objects;
create policy dpr_photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'dpr-photos' and (owner = auth.uid() or public.is_admin()));

-- ---------- 5. seed the register from trades already in use (optional) ----------
-- Nothing is seeded automatically. Add workers in the app under the Workers tab,
-- or bulk-insert here, e.g.:
-- insert into public.workers (name, emp_no, trade) values
--   ('Rajesh Kumar','G1234567X','General Worker'),
--   ('Anbu Selvan','G7654321Y','Welder');
