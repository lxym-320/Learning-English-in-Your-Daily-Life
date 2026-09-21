-- Run this migration if 001_context_lens.sql was already applied.
alter table public.study_words
  add column if not exists meanings jsonb not null default '[]'::jsonb;

alter table public.study_words
  add column if not exists next_review_at timestamptz not null default now();
