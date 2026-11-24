-- Run this in Supabase SQL Editor (Project -> SQL Editor -> New Query)

-- 1. Create private storage bucket for encrypted/compressed ZIP backups (up to 600 MB for Yearly plan; Monthly 100 MB enforced in cloud-backup function)
insert into storage.buckets (id, name, public, file_size_limit)
values ('user-backups', 'user-backups', false, 629145600)
on conflict (id) do update set file_size_limit = 629145600;

-- 2. Table storing verified Google Play subscriptions ($0.99/mo or $5.99/yr)
create table if not exists public.user_subscriptions (
  firebase_uid text primary key,
  product_id text not null,
  purchase_token text not null,
  status text not null default 'active',
  expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.user_subscriptions enable row level security;

-- Lock down direct client access; only the Edge Function (service_role) writes/reads
create policy "Deny all direct access to user_subscriptions"
  on public.user_subscriptions for all
  using (false)
  with check (false);

-- 3. Table storing latest ZIP backup metadata per Firebase UID
create table if not exists public.user_backup_metadata (
  firebase_uid text primary key,
  storage_path text not null,
  exported_at timestamptz not null,
  size_bytes bigint not null default 0,
  expense_count integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.user_backup_metadata enable row level security;

create policy "Deny all direct access to user_backup_metadata"
  on public.user_backup_metadata for all
  using (false)
  with check (false);
