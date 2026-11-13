-- Записи занять + календар: хмарний вміст і адмін (пошта + пароль).
-- Виконати один раз: Supabase → SQL Editor → вставити → Run.
create table if not exists public.ms_admins (email text primary key, salt text not null, pass_hash text not null);
alter table public.ms_admins enable row level security;   -- напряму недоступна

create table if not exists public.ms_content (id int primary key default 1, data jsonb not null, updated_at timestamptz not null default now());
alter table public.ms_content enable row level security;  -- лише через функції нижче

-- Адмінів додає окремий приватний файл (insert into public.ms_admins ...), його в репозиторій не кладемо.

create or replace function public.ms_admin_ok(p_email text, p_pass text) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.ms_admins a where a.email = lower(trim(p_email))
    and a.pass_hash = encode(sha256(convert_to(a.salt || coalesce(p_pass, ''), 'UTF8')), 'hex'));
$$;

create or replace function public.ms_content_get() returns jsonb
  language sql stable security definer set search_path = public as $$
  select data from public.ms_content where id = 1;
$$;

create or replace function public.ms_content_set(p_email text, p_pass text, p_data jsonb) returns timestamptz
  language plpgsql security definer set search_path = public as $$
declare t timestamptz := now();
begin
  if not public.ms_admin_ok(p_email, p_pass) then raise exception 'not admin'; end if;
  if p_data is null or jsonb_typeof(p_data -> 'lessons') <> 'array' then raise exception 'bad data'; end if;
  insert into public.ms_content (id, data, updated_at) values (1, p_data, t)
    on conflict (id) do update set data = excluded.data, updated_at = t;
  return t;
end;
$$;

revoke all on function public.ms_admin_ok(text, text) from public;
revoke all on function public.ms_content_get() from public;
revoke all on function public.ms_content_set(text, text, jsonb) from public;
grant execute on function public.ms_admin_ok(text, text) to anon, authenticated;
grant execute on function public.ms_content_get() to anon, authenticated;
grant execute on function public.ms_content_set(text, text, jsonb) to anon, authenticated;
