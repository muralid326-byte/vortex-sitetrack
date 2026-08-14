-- ============================================================
-- VORTEX SITETRACK v7 MIGRATION
-- Adds: working times, lunch, lorry driver, work stage and
--       start / expected / completion dates on each work.
-- Run AFTER v4, v5 and v6. Safe to re-run.
-- ============================================================

-- ---------- 1. EXTRA DETAIL ON EACH DAILY REPORT ----------
-- One JSON column holds start and end time, break, driver, stage,
-- progress and expected completion, so future additions need no migration.
alter table public.daily_reports add column if not exists meta jsonb default '{}'::jsonb;

-- ---------- 2. THE WORK ITSELF ----------
alter table public.work_items
  add column if not exists start_date   date,
  add column if not exists end_date     date,
  add column if not exists expected_end date,
  add column if not exists progress_pct numeric;

alter table public.work_items add column if not exists status text default 'ongoing';
update public.work_items set status = 'ongoing'
  where status is null or status not in ('to_start','ongoing','completed','on-hold');

alter table public.work_items drop constraint if exists work_items_status_check;
alter table public.work_items add constraint work_items_status_check
  check (status in ('to_start','ongoing','completed','on-hold'));

-- ---------- 3. PER-PERSON ACCESS ----------
-- Null means the person follows the role default set under Access.
alter table public.profiles add column if not exists perms jsonb;

-- an admin may edit anyone's access; nobody may promote themselves
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles
  for update to authenticated
  using (public.is_admin() or id = auth.uid())
  with check (public.is_admin() or id = auth.uid());

create or replace function public.guard_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.role  := old.role;
    new.perms := old.perms;
    new.active := old.active;
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_profile_fields on public.profiles;
create trigger trg_guard_profile_fields before update on public.profiles
  for each row execute function public.guard_profile_fields();
