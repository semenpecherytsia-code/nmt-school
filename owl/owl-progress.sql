-- Совиний кошик: прогрес гри за поштою (вхід без листа).
-- Виконати один раз: Supabase → SQL Editor → New query → вставити весь файл → Run.
create table if not exists public.owl_saves (
  email      text primary key,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.owl_saves enable row level security;  -- напряму таблиця недоступна, лише через функції нижче

create or replace function public.owl_load(p_email text) returns jsonb
  language sql stable security definer set search_path = public as $$
  select data from public.owl_saves where email = lower(trim(p_email));
$$;

create or replace function public.owl_save(p_email text, p_data jsonb) returns void
  language plpgsql security definer set search_path = public as $$
begin
  if p_email is null or position('@' in p_email) = 0 or length(p_email) > 200 then
    raise exception 'bad email';
  end if;
  if pg_column_size(p_data) > 200000 then
    raise exception 'too big';
  end if;
  insert into public.owl_saves (email, data, updated_at)
  values (lower(trim(p_email)), p_data, now())
  on conflict (email) do update set data = excluded.data, updated_at = now();
end;
$$;

revoke all on function public.owl_load(text) from public;
revoke all on function public.owl_save(text, jsonb) from public;
grant execute on function public.owl_load(text) to anon, authenticated;
grant execute on function public.owl_save(text, jsonb) to anon, authenticated;
