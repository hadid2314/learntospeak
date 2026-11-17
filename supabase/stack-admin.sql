-- The Stack Method: admin back end. Run once in the Supabase SQL editor.
-- Uses the existing public.admins table and public.is_admin() from the Medic Hero setup.

create table if not exists public.stack_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.stack_events (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  kind text not null,
  label text,
  ref text,
  device text
);
create index if not exists stack_events_at_idx on public.stack_events (at);

create table if not exists public.stack_sales (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  product text not null,
  amount numeric(10,2) not null default 0,
  note text
);

alter table public.stack_settings enable row level security;
alter table public.stack_events enable row level security;
alter table public.stack_sales enable row level security;

drop policy if exists "stack read settings" on public.stack_settings;
create policy "stack read settings" on public.stack_settings for select using (true);
drop policy if exists "stack admin settings" on public.stack_settings;
create policy "stack admin settings" on public.stack_settings for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "stack log event" on public.stack_events;
create policy "stack log event" on public.stack_events for insert to anon, authenticated
  with check (
    kind in ('view','click')
    and char_length(coalesce(label,'')) <= 60
    and char_length(coalesce(ref,'')) <= 80
    and char_length(coalesce(device,'')) <= 10
  );
drop policy if exists "stack admin reads events" on public.stack_events;
create policy "stack admin reads events" on public.stack_events for select to authenticated using (public.is_admin());
drop policy if exists "stack admin clears events" on public.stack_events;
create policy "stack admin clears events" on public.stack_events for delete to authenticated using (public.is_admin());

drop policy if exists "stack admin sales" on public.stack_sales;
create policy "stack admin sales" on public.stack_sales for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create or replace function public.stack_stats(days int default 30) returns json
language sql stable security definer set search_path = public as $$
  select case when not public.is_admin() then null else json_build_object(
    'daily', (
      select coalesce(json_agg(json_build_object('day', to_char(g.day,'YYYY-MM-DD'),
        'views', (select count(*) from stack_events e where e.kind='view' and e.at >= g.day and e.at < g.day + interval '1 day'),
        'buys',  (select count(*) from stack_events e where e.kind='click' and e.label like 'buy:%' and e.at >= g.day and e.at < g.day + interval '1 day')
      ) order by g.day), '[]'::json)
      from generate_series(date_trunc('day', now()) - make_interval(days => greatest(days,1) - 1), date_trunc('day', now()), interval '1 day') as g(day)
    ),
    'clicks', (
      select coalesce(json_agg(c), '[]'::json) from (
        select label, count(*)::int as n from stack_events
        where kind='click' and at >= now() - make_interval(days => days)
        group by label order by n desc limit 40) c
    ),
    'refs', (
      select coalesce(json_agg(r), '[]'::json) from (
        select coalesce(nullif(ref,''),'Direct') as ref, count(*)::int as n from stack_events
        where kind='view' and at >= now() - make_interval(days => days)
        group by 1 order by n desc limit 10) r
    ),
    'devices', (
      select coalesce(json_agg(d), '[]'::json) from (
        select coalesce(nullif(device,''),'unknown') as device, count(*)::int as n from stack_events
        where kind='view' and at >= now() - make_interval(days => days)
        group by 1 order by n desc) d
    ),
    'totals', json_build_object(
      'views', (select count(*) from stack_events where kind='view' and at >= now() - make_interval(days => days)),
      'buys',  (select count(*) from stack_events where kind='click' and label like 'buy:%' and at >= now() - make_interval(days => days)),
      'today', (select count(*) from stack_events where kind='view' and at >= date_trunc('day', now())),
      'sales_count', (select count(*) from stack_sales where at >= now() - make_interval(days => days)),
      'sales_total', (select coalesce(sum(amount),0) from stack_sales where at >= now() - make_interval(days => days))
    )
  ) end
$$;
revoke all on function public.stack_stats(int) from public;
grant execute on function public.stack_stats(int) to authenticated;
