create table if not exists public.staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now()
);

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.staff where user_id = auth.uid());
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.episodes (
  id text primary key check (id ~ '^[a-z0-9]+([-_][a-z0-9]+)*$' and char_length(id) <= 80),
  title text not null check (char_length(title) between 1 and 160),
  youtube_id text not null check (youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
  aired_on date,
  category text check (char_length(category) <= 40),
  summary text check (char_length(summary) <= 600),
  published boolean not null default true,
  notified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'bekuldott' check (source in ('bekuldott', 'sajat')),
  kind text not null default 'story' check (kind in ('story', 'request')),
  status text not null default 'beerkezett' check (status in ('beerkezett', 'otlet', 'forgatas', 'vagas', 'kesz', 'elvetve')),
  name text check (char_length(name) <= 80),
  class_name text check (char_length(class_name) <= 20),
  contact text check (char_length(contact) <= 120),
  topic text not null check (char_length(topic) between 1 and 200),
  details text check (char_length(details) <= 4000),
  link text check (char_length(link) <= 500),
  note text check (char_length(note) <= 4000),
  episode_id text references public.episodes(id) on delete set null on update cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.push_subscriptions (
  endpoint text primary key check (endpoint ~ '^https://' and char_length(endpoint) <= 1000),
  p256dh text not null check (char_length(p256dh) <= 200),
  auth text not null check (char_length(auth) <= 100),
  created_at timestamptz not null default now()
);

drop trigger if exists episodes_updated_at on public.episodes;
create trigger episodes_updated_at before update on public.episodes
  for each row execute function public.set_updated_at();

drop trigger if exists stories_updated_at on public.stories;
create trigger stories_updated_at before update on public.stories
  for each row execute function public.set_updated_at();

create index if not exists episodes_order_idx on public.episodes (aired_on desc nulls last, created_at desc);
create index if not exists stories_status_idx on public.stories (status, created_at desc);

alter table public.staff enable row level security;
alter table public.episodes enable row level security;
alter table public.stories enable row level security;
alter table public.push_subscriptions enable row level security;

drop policy if exists "staff sees staff" on public.staff;
create policy "staff sees staff" on public.staff
  for select to authenticated using (public.is_staff());

drop policy if exists "anyone reads published episodes" on public.episodes;
create policy "anyone reads published episodes" on public.episodes
  for select to anon, authenticated using (published or public.is_staff());

drop policy if exists "staff inserts episodes" on public.episodes;
create policy "staff inserts episodes" on public.episodes
  for insert to authenticated with check (public.is_staff());

drop policy if exists "staff updates episodes" on public.episodes;
create policy "staff updates episodes" on public.episodes
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "staff deletes episodes" on public.episodes;
create policy "staff deletes episodes" on public.episodes
  for delete to authenticated using (public.is_staff());

drop policy if exists "anyone submits stories" on public.stories;
create policy "anyone submits stories" on public.stories
  for insert to anon, authenticated
  with check (source = 'bekuldott' and status = 'beerkezett' and note is null and episode_id is null);

drop policy if exists "staff adds stories" on public.stories;
create policy "staff adds stories" on public.stories
  for insert to authenticated with check (public.is_staff());

drop policy if exists "staff reads stories" on public.stories;
create policy "staff reads stories" on public.stories
  for select to authenticated using (public.is_staff());

drop policy if exists "staff updates stories" on public.stories;
create policy "staff updates stories" on public.stories
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "staff deletes stories" on public.stories;
create policy "staff deletes stories" on public.stories
  for delete to authenticated using (public.is_staff());

create or replace function public.push_subscribe(p_endpoint text, p_p256dh text, p_auth text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.push_subscriptions (endpoint, p256dh, auth)
  values (p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth;
$$;

create or replace function public.push_unsubscribe(p_endpoint text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_subscriptions where endpoint = p_endpoint;
$$;

create or replace function public.push_targets()
returns setof public.push_subscriptions
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'not staff' using errcode = '42501';
  end if;
  return query select * from public.push_subscriptions;
end;
$$;

create or replace function public.push_remove(p_endpoints text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'not staff' using errcode = '42501';
  end if;
  delete from public.push_subscriptions where endpoint = any (p_endpoints);
end;
$$;

create or replace function public.push_count()
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'not staff' using errcode = '42501';
  end if;
  return (select count(*) from public.push_subscriptions);
end;
$$;

revoke all on public.staff, public.episodes, public.stories, public.push_subscriptions from anon, authenticated;
grant select on public.staff to authenticated;
grant select on public.episodes to anon, authenticated;
grant insert, update, delete on public.episodes to authenticated;
grant insert on public.stories to anon, authenticated;
grant select, update, delete on public.stories to authenticated;

revoke execute on function public.push_targets(), public.push_remove(text[]), public.push_count() from public, anon;
grant execute on function public.is_staff() to anon, authenticated;
grant execute on function public.push_subscribe(text, text, text), public.push_unsubscribe(text) to anon, authenticated;
grant execute on function public.push_targets(), public.push_remove(text[]), public.push_count() to authenticated;

insert into public.episodes (id, title, youtube_id, created_at)
values
  ('erdei-iskola-7-evfolyam', 'Erdei iskola, 7. évfolyam', 'Uu-Bblt1ZDE', now() - interval '3 minutes'),
  ('aradi-vertanuk', 'Aradi vértanúk', '-ELn2qGqOfA', now() - interval '2 minutes'),
  ('bubblehub_dok', 'Bubble hub + DÖK', 'RO4DFEYFavw', now() - interval '1 minute'),
  ('projectweek', 'Science Project Week', '4ZmK71TnYvI', now())
on conflict (id) do nothing;
