-- Совиний кошик: рейтинг рівнів (перша спроба, бали → час → дата).
-- Виконати один раз: Supabase → SQL Editor → New query → вставити весь файл → Run.
-- Потрібні вже виконані owl-progress.sql (owl_saves) і owl-admin.sql (owl_admin_ok).

create table if not exists public.owl_attempts (
  id          bigserial primary key,
  email       text not null,
  level       integer not null,
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  pts         integer,
  correct     integer,
  lives       integer,
  won         boolean,
  sec         integer,          -- час гри (секундомір гри)
  server_sec  integer,          -- скільки пройшло на сервері між стартом і фінішем
  sus         boolean not null default false,   -- підозріло швидко / дані не сходяться
  hidden      boolean not null default false    -- приховано адміном
);
create index if not exists owl_attempts_lvl on public.owl_attempts(level, started_at);
create index if not exists owl_attempts_email on public.owl_attempts(email);
alter table public.owl_attempts enable row level security;   -- напряму недоступна, лише через функції

create table if not exists public.owl_lb_hidden (email text primary key);
alter table public.owl_lb_hidden enable row level security;

-- початок раунду: сервер сам ставить час старту
create or replace function public.owl_round_start(p_email text, p_level integer)
returns bigint language plpgsql security definer set search_path = public as $$
declare e text := lower(trim(coalesce(p_email,''))); rid bigint;
begin
  if p_level is null or p_level < 0 or p_level > 11 then return null; end if;
  if not exists (select 1 from public.owl_saves where email = e) then return null; end if;
  -- не більше 120 стартів на годину з однієї пошти
  if (select count(*) from public.owl_attempts where email = e and started_at > now() - interval '1 hour') >= 120 then return null; end if;
  insert into public.owl_attempts(email, level) values (e, p_level) returning id into rid;
  return rid;
end $$;

-- кінець раунду: бали рахує сервер (правильні + сердечка, якщо перемога), час перевіряється
create or replace function public.owl_round_finish(p_id bigint, p_email text, p_correct integer, p_lives integer, p_won boolean, p_sec integer)
returns boolean language plpgsql security definer set search_path = public as $$
declare a public.owl_attempts; e text := lower(trim(coalesce(p_email,''))); ss integer; c integer; l integer; w boolean; s integer; bad boolean;
begin
  select * into a from public.owl_attempts where id = p_id and email = e and finished_at is null for update;
  if not found then return false; end if;
  ss := floor(extract(epoch from now() - a.started_at));
  c := greatest(0, least(coalesce(p_correct,0), 50));
  w := coalesce(p_won,false);
  l := case when w then greatest(0, least(coalesce(p_lives,0), 3)) else 0 end;
  s := greatest(0, coalesce(p_sec, ss));
  bad := ss > 7200                       -- раунд «висів» понад 2 години
      or s > ss + 3                       -- гра не може тривати довше, ніж пройшло на сервері
      or (c > 0 and s < ceil(c * 0.8))    -- менше 0,8 с на правильну відповідь — нереально
      or (c > 0 and ss < ceil(c * 0.8) + 2)
      or (w and c < 1);
  update public.owl_attempts set finished_at = now(), pts = c + l, correct = c, lives = l, won = w,
    sec = least(s, ss), server_sec = ss, sus = bad where id = p_id;
  return not bad;
end $$;

-- рейтинг рівня. p_period: 'week' (з понеділка, київський час (EET)) або 'all'.
-- У рейтинг іде лише перша (зарахована) спроба кожного гравця; порядок: бали ↓, час ↑, хто раніше.
create or replace function public.owl_lb(p_level integer, p_period text, p_email text default '')
returns table(pos integer, pid text, name text, pts integer, sec integer, at timestamptz, tries integer, me boolean)
language sql stable security definer set search_path = public as $$
  with lim as (
    select case when p_period = 'week'
      then (date_trunc('week', now() at time zone 'EET')) at time zone 'EET'
      else '-infinity'::timestamptz end as t0
  ), ok as (
    select a.* from public.owl_attempts a, lim
    where a.level = p_level and a.finished_at is not null and not a.sus and not a.hidden
      and a.started_at >= lim.t0
      and a.email not in (select email from public.owl_lb_hidden)
  ), firsts as (
    select distinct on (email) * from ok order by email, started_at asc
  ), cnt as (
    select email, count(*)::int n from ok group by email
  ), ranked as (
    select row_number() over (order by f.pts desc, f.sec asc, f.finished_at asc)::int as pos,
      left(md5('owl' || f.email), 12) as pid,
      coalesce(nullif(left(trim(s.data->>'nick'), 16), ''),
        case when position('@' in f.email) > 3 then left(f.email, 2) || '***' || substr(f.email, position('@' in f.email))
             else '***' || substr(f.email, position('@' in f.email)) end) as name,
      f.pts, f.sec, f.finished_at as at, cnt.n as tries,
      f.email = lower(trim(coalesce(p_email,''))) as me
    from firsts f join cnt on cnt.email = f.email left join public.owl_saves s on s.email = f.email
  )
  select * from ranked where pos <= 50 or me order by pos;
$$;

-- усі спроби гравця на рівні (за датою); counted = саме вона в рейтингу.
-- Звичайний гравець бачить лише свої спроби, адмін (з паролем) — усіх.
drop function if exists public.owl_lb_tries(integer, text, text);
create or replace function public.owl_lb_tries(p_level integer, p_pid text, p_period text, p_email text, p_pass text default null)
returns table(id bigint, pts integer, sec integer, at timestamptz, won boolean, counted boolean)
language plpgsql stable security definer set search_path = public as $$
declare e text := lower(trim(coalesce(p_email,'')));
begin
  if e = '' or (left(md5('owl' || e), 12) <> p_pid and not public.owl_admin_ok(p_email, coalesce(p_pass,''))) then
    raise exception 'not allowed';
  end if;
  return query
  with lim as (
    select case when p_period = 'week'
      then (date_trunc('week', now() at time zone 'EET')) at time zone 'EET'
      else '-infinity'::timestamptz end as t0
  ), mine as (
    select a.* from public.owl_attempts a, lim
    where a.level = p_level and left(md5('owl' || a.email), 12) = p_pid
      and a.finished_at is not null and not a.sus and not a.hidden and a.started_at >= lim.t0
  ), f as (select min(mine.started_at) t from mine)
  select m.id, m.pts, m.sec, m.finished_at, m.won, m.started_at = f.t from mine m, f order by m.started_at asc limit 100;
end $$;

-- адмін: сховати / показати спробу (p_id) або всього гравця (p_pid)
create or replace function public.owl_lb_hide(p_email text, p_pass text, p_id bigint, p_pid text, p_hidden boolean)
returns boolean language plpgsql security definer set search_path = public as $$
declare e text;
begin
  if not public.owl_admin_ok(p_email, p_pass) then raise exception 'not admin'; end if;
  if p_id is not null then update public.owl_attempts set hidden = coalesce(p_hidden, true) where id = p_id; end if;
  if p_pid is not null then
    select email into e from public.owl_attempts where left(md5('owl' || email), 12) = p_pid limit 1;
    if e is null then return false; end if;
    if coalesce(p_hidden, true) then insert into public.owl_lb_hidden(email) values (e) on conflict do nothing;
    else delete from public.owl_lb_hidden where email = e; end if;
  end if;
  return true;
end $$;

revoke all on function public.owl_round_start(text, integer) from public;
revoke all on function public.owl_round_finish(bigint, text, integer, integer, boolean, integer) from public;
revoke all on function public.owl_lb(integer, text, text) from public;
revoke all on function public.owl_lb_tries(integer, text, text, text, text) from public;
revoke all on function public.owl_lb_hide(text, text, bigint, text, boolean) from public;
grant execute on function public.owl_round_start(text, integer) to anon, authenticated;
grant execute on function public.owl_round_finish(bigint, text, integer, integer, boolean, integer) to anon, authenticated;
grant execute on function public.owl_lb(integer, text, text) to anon, authenticated;
grant execute on function public.owl_lb_tries(integer, text, text, text, text) to anon, authenticated;
grant execute on function public.owl_lb_hide(text, text, bigint, text, boolean) to anon, authenticated;
