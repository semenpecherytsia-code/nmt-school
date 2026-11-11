-- Совиний кошик: нікнейми. Виконати один раз: Supabase → SQL Editor → New query → вставити весь файл → Run.
-- 1) перевірка, чи нікнейм вільний; 2) рейтинг тижня показує нікнейм (якщо його немає — приховану пошту).

create or replace function public.owl_nick_free(p_nick text, p_email text default '')
returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from public.owl_saves
    where lower(trim(data->>'nick')) = lower(trim(coalesce(p_nick, '')))
      and email <> lower(trim(coalesce(p_email, '')))
  );
$$;
revoke all on function public.owl_nick_free(text, text) from public;
grant execute on function public.owl_nick_free(text, text) to anon, authenticated;

create or replace function public.owl_leaderboard(p_week text, p_email text default '')
returns table(name text, pts integer, me boolean)
language sql stable security definer set search_path = public as $$
  select
    coalesce(nullif(left(trim(data->>'nick'), 16), ''),
      case when position('@' in email) > 3
           then left(email, 2) || '***' || substr(email, position('@' in email))
           else '***' || substr(email, position('@' in email)) end) as name,
    (data->'lb'->>'pts')::integer as pts,
    email = lower(trim(coalesce(p_email, ''))) as me
  from public.owl_saves
  where data->'lb'->>'week' = p_week
    and (data->'lb'->>'pts') ~ '^[0-9]{1,7}$'
    and (data->'lb'->>'pts')::integer > 0
  order by 2 desc, updated_at asc
  limit 20;
$$;
revoke all on function public.owl_leaderboard(text, text) from public;
grant execute on function public.owl_leaderboard(text, text) to anon, authenticated;
