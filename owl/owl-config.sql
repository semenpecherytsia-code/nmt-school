-- Совиний кошик: налаштування рівнів від адміна (сховати рівні, назви, правила, вирази).
-- Виконати один раз: Supabase → SQL Editor → New query → вставити весь файл → Run.
-- Потрібна функція owl_admin_ok із owl-admin.sql (вже виконано раніше).

create table if not exists public.owl_config (
  key        text primary key,
  data       jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by text
);
create table if not exists public.owl_config_history (
  id         bigserial primary key,
  key        text not null,
  data       jsonb not null,
  saved_at   timestamptz not null default now(),
  saved_by   text
);
alter table public.owl_config enable row level security;          -- напряму недоступні, лише через функції
alter table public.owl_config_history enable row level security;

-- читати можуть усі гравці
create or replace function public.owl_config_get() returns jsonb
  language sql stable security definer set search_path = public as $$
  select coalesce((select data from public.owl_config where key = 'levels'), '{}'::jsonb);
$$;

-- зберігати може лише адмін із правильним паролем
create or replace function public.owl_config_set(p_email text, p_pass text, p_data jsonb) returns void
  language plpgsql security definer set search_path = public as $$
begin
  if not public.owl_admin_ok(p_email, p_pass) then raise exception 'not admin'; end if;
  if jsonb_typeof(p_data) <> 'object' or pg_column_size(p_data) > 400000 then raise exception 'bad data'; end if;
  insert into public.owl_config(key, data, updated_at, updated_by)
    values ('levels', p_data, now(), lower(trim(p_email)))
    on conflict (key) do update set data = excluded.data, updated_at = now(), updated_by = excluded.updated_by;
  insert into public.owl_config_history(key, data, saved_by) values ('levels', p_data, lower(trim(p_email)));
end;
$$;

revoke all on function public.owl_config_get() from public;
revoke all on function public.owl_config_set(text, text, jsonb) from public;
grant execute on function public.owl_config_get() to anon, authenticated;
grant execute on function public.owl_config_set(text, text, jsonb) to anon, authenticated;
