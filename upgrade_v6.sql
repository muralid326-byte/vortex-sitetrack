-- ============================================================
-- VORTEX SITETRACK v6 MIGRATION
-- Adds admin-controlled visibility, and locks money tables to admins
-- at the database level. Run AFTER upgrade_v4.sql and upgrade_v5.sql.
-- Safe to re-run.
-- ============================================================

-- ---------- 1. WHAT EACH ROLE MAY SEE ----------
-- Edited from the app under Access. Defaults hide all costing from supervisors.
alter table public.settings add column if not exists perms jsonb default '{}'::jsonb;

update public.settings
set perms = jsonb_build_object('supervisor', jsonb_build_object(
      'costs',   false,
      'rates',   false,
      'entry',   true,
      'mine',    true,
      'todo',    true,
      'workers', true,
      'addproj', true
    ))
where id = 1 and (perms is null or perms = '{}'::jsonb);

-- ---------- 2. MONEY TABLES: ADMIN ONLY ----------
-- Hiding figures in the interface is not enough on its own. These policies mean
-- the database itself will not hand cost data to a supervisor's session.
alter table public.project_costs enable row level security;

drop policy if exists project_costs_select on public.project_costs;
create policy project_costs_select on public.project_costs
  for select to authenticated using (public.is_admin());

drop policy if exists project_costs_write on public.project_costs;
create policy project_costs_write on public.project_costs
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists variations_select on public.variations;
create policy variations_select on public.variations
  for select to authenticated using (public.is_admin());

-- ---------- 3. WORKER PAY RATES ----------
-- A supervisor may read the register (he needs names and designations) but the
-- rate column is only useful to the office, so writing it stays admin-only.
create or replace function public.guard_worker_rate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    if tg_op = 'INSERT' then
      new.rate := 0;
    else
      new.rate := old.rate;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_worker_rate on public.workers;
create trigger trg_guard_worker_rate before insert or update on public.workers
  for each row execute function public.guard_worker_rate();
