-- The Stack Method: partner logins. Run once after stack-admin.sql.
-- People listed here can open the Stack Method admin only (not the Medic Hero admin).
create table if not exists public.stack_admins (
  email text primary key,
  added_at timestamptz not null default now()
);
alter table public.stack_admins enable row level security;
drop policy if exists "stack owner manages team" on public.stack_admins;
create policy "stack owner manages team" on public.stack_admins for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create or replace function public.stack_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.is_admin(), false)
      or exists (select 1 from stack_admins a where lower(a.email) = lower(auth.jwt() ->> 'email'))
$$;
revoke all on function public.stack_is_admin() from public;
grant execute on function public.stack_is_admin() to authenticated;

alter policy "stack admin settings" on public.stack_settings using (public.stack_is_admin()) with check (public.stack_is_admin());
alter policy "stack admin reads events" on public.stack_events using (public.stack_is_admin());
alter policy "stack admin clears events" on public.stack_events using (public.stack_is_admin());
alter policy "stack admin sales" on public.stack_sales using (public.stack_is_admin()) with check (public.stack_is_admin());
-- After this file, re-run the stack_stats function from stack-admin.sql (it calls stack_is_admin).
