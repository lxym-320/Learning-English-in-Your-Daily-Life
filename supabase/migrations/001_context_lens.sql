-- Context Lens: account, collection and spaced-review sync schema.
-- Run this file once in Supabase Dashboard → SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.study_contexts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sentence text not null,
  translation text not null default '',
  source_title text,
  source_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  next_review_at timestamptz not null default now(),
  interval_days integer not null default 0 check (interval_days >= 0),
  ease_factor real not null default 2.5 check (ease_factor >= 1.3),
  repetitions integer not null default 0 check (repetitions >= 0),
  last_rating integer check (last_rating between 0 and 2),
  deleted_at timestamptz
);

create table if not exists public.study_words (
  id uuid primary key default gen_random_uuid(),
  context_id uuid not null references public.study_contexts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  word text not null,
  meaning text not null default '',
  review_hint text not null default '',
  phonetic text,
  meanings jsonb not null default '[]'::jsonb,
  next_review_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists study_contexts_user_updated_idx on public.study_contexts(user_id, updated_at desc);
create index if not exists study_contexts_due_idx on public.study_contexts(user_id, next_review_at) where deleted_at is null;
create index if not exists study_words_user_word_idx on public.study_words(user_id, lower(word)) where deleted_at is null;
create index if not exists study_words_context_idx on public.study_words(context_id) where deleted_at is null;

create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
drop trigger if exists contexts_set_updated_at on public.study_contexts;
create trigger contexts_set_updated_at before update on public.study_contexts
for each row execute function public.set_updated_at();
drop trigger if exists words_set_updated_at on public.study_words;
create trigger words_set_updated_at before update on public.study_words
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name)
  values(new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict(id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.study_contexts enable row level security;
alter table public.study_words enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles for select using ((select auth.uid()) = id);
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles for update using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "contexts_select_own" on public.study_contexts;
create policy "contexts_select_own" on public.study_contexts for select using ((select auth.uid()) = user_id);
drop policy if exists "contexts_insert_own" on public.study_contexts;
create policy "contexts_insert_own" on public.study_contexts for insert with check ((select auth.uid()) = user_id);
drop policy if exists "contexts_update_own" on public.study_contexts;
create policy "contexts_update_own" on public.study_contexts for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "contexts_delete_own" on public.study_contexts;
create policy "contexts_delete_own" on public.study_contexts for delete using ((select auth.uid()) = user_id);

drop policy if exists "words_select_own" on public.study_words;
create policy "words_select_own" on public.study_words for select using ((select auth.uid()) = user_id);
drop policy if exists "words_insert_own" on public.study_words;
create policy "words_insert_own" on public.study_words for insert with check ((select auth.uid()) = user_id);
drop policy if exists "words_update_own" on public.study_words;
create policy "words_update_own" on public.study_words for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "words_delete_own" on public.study_words;
create policy "words_delete_own" on public.study_words for delete using ((select auth.uid()) = user_id);

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles, public.study_contexts, public.study_words to authenticated;
