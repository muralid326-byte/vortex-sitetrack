-- ============================================================
-- VORTEX SITETRACK v5 MIGRATION
-- Adds: project codes, designations + PCS rate card, premium OT tier,
--       per-project pending / to-do list, and seeds the 24-man register.
-- Run AFTER upgrade_v4.sql. Safe to re-run.
-- ============================================================

-- ---------- 1. PROJECT CODE ----------
alter table public.sites add column if not exists code text;
create index if not exists sites_code_idx on public.sites (upper(code));

-- ---------- 2. DESIGNATIONS + RATE CARD (VQ-PCS2407021, 11 Jul 2024) ----------
-- Normal rate is stored here; OT 1.5x and Premium 2.0x come from settings.
insert into public.trades (name, rate, sort, active)
select v.name, v.rate, v.sort, true
from (values
  ('Supervisor',18.00,10),('WSHC',18.00,20),('Fire Watchman',16.00,30),
  ('General Labourer',13.00,40),('Manager',0.00,50),('QS',0.00,60),
  ('Foreman',0.00,70),('Driver',0.00,80)
) as v(name,rate,sort)
where not exists (select 1 from public.trades t where t.name = v.name);

update public.trades t set rate = v.rate
from (values ('Supervisor',18.00),('WSHC',18.00),('Fire Watchman',16.00),('General Labourer',13.00))
  as v(name,rate)
where t.name = v.name and coalesce(t.rate,0) = 0;

update public.settings set ot_multiplier = 1.5, holiday_multiplier = 2.0 where id = 1;

-- ---------- 3. PENDING / TO-DO LIST PER PROJECT ----------
create table if not exists public.todos (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid references public.sites(id) on delete cascade,
  title       text not null,
  detail      text,
  due_date    date,
  priority    text default 'normal' check (priority in ('low','normal','high')),
  status      text default 'open'   check (status in ('open','done')),
  assigned_to uuid references public.profiles(id),
  created_by  uuid references public.profiles(id) default auth.uid(),
  created_at  timestamptz default now(),
  done_at     timestamptz
);
create index if not exists todos_site_idx   on public.todos(site_id);
create index if not exists todos_status_idx on public.todos(status);

alter table public.todos enable row level security;

drop policy if exists todos_select on public.todos;
create policy todos_select on public.todos for select to authenticated using (true);

drop policy if exists todos_insert on public.todos;
create policy todos_insert on public.todos for insert to authenticated with check (true);

-- supervisors may tick items off; only admin can delete
drop policy if exists todos_update on public.todos;
create policy todos_update on public.todos for update to authenticated using (true) with check (true);

drop policy if exists todos_delete on public.todos;
create policy todos_delete on public.todos for delete to authenticated using (public.is_admin());

-- ---------- 4. WORKER REGISTER SEED ----------
-- ID and name are stored separately. Designation is left blank on purpose —
-- set it for each man in the app under Workers.
insert into public.workers (emp_no, name, active) values
  ('VES021','Muruganantham Muralidharan',      true),
  ('VES049','Bodavula Rajesh',                 true),
  ('VES051','Arputhadoss Christy Antony Jose', true),
  ('VEW004','Ahmed Sumon',                     true),
  ('VEW012','Jahangir',                        true),
  ('VEW017','Aravan Arjunan',                  true),
  ('VEW020','Moorthy Mahendran',               true),
  ('VEW024','Antony Dismal',                   true),
  ('VEW031','Phonlamai Adirek',                true),
  ('VEW034','Ahmed Raju',                      true),
  ('VEW054','Chokkalingam Vinoth',             true),
  ('VEW061','Somu Naresh Kumar',               true),
  ('VEW064','Selvam Aravind',                  true),
  ('VEW086','Balakrishnan Venkatesh',          true),
  ('VEW098','Karuppiah Alaguperumal',          true),
  ('VEW101','Karthikeyan Ragavan',             true),
  ('VEW102','Ravichandran Sivanantham',        true),
  ('VEW103','Loskor Juber Ahmed',              true),
  ('VEW131','Subramaniyan Satheesh Kumar',     true),
  ('VEW135','Chelladurai Reshman',             true),
  ('VEW136','Masilamani Iyyappan',             true),
  ('VTX002','Kumar Udhayaraj',                 true),
  ('VTX003','Rajaraman Ranjithkumar',          true),
  ('VTX',   'Arumugam Kumaravel',              true)
on conflict do nothing;

create index if not exists workers_empno_idx on public.workers (upper(emp_no));

-- ---------- 5. OVERHEAD / GENERAL COST CENTRE ----------
-- Daily office manpower (Manager, QS) is booked against this pseudo-project.
insert into public.sites (code, name, client_name, active)
select 'GEN','General / Overhead (Manager, QS, office)','Vortex Engineering', true
where not exists (select 1 from public.sites where upper(coalesce(code,'')) = 'GEN');
