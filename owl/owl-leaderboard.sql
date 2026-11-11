-- Совиний кошик: рейтинг тижня. Виконати один раз: Supabase → SQL Editor → New query → вставити весь файл → Run.
-- Повертає топ-20 гравців за очками цього тижня. Пошту показує частково прихованою (se***@gmail.com).
create or replace function public.owl_leaderboard(p_week text, p_email text default '')
returns table(name text, pts integer, me boolean)
language sql stable security definer set search_path = public as $$
  select
    case when position('@' in email) > 3
         then left(email, 2) || '***' || substr(email, position('@' in email))
         else '***' || substr(email, position('@' in email)) end as name,
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
