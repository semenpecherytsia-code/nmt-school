-- Совиний кошик: прогрес гри для кожного акаунта.
-- Виконати один раз: Supabase → SQL Editor → New query → вставити весь файл → Run.
create table if not exists public.owl_progress (
  user_id    uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  email      text,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.owl_progress enable row level security;

drop policy if exists "owl: read own" on public.owl_progress;
create policy "owl: read own" on public.owl_progress
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "owl: insert own" on public.owl_progress;
create policy "owl: insert own" on public.owl_progress
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "owl: update own" on public.owl_progress;
create policy "owl: update own" on public.owl_progress
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
