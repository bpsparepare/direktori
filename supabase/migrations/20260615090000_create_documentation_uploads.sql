create table if not exists public.documentation_uploads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  kategori text not null check (
    kategori in (
      'koordinasi',
      'pendataan',
      'pengawasan',
      'pertemuan',
      'lainnya',
      'bukti paket data'
    )
  ),
  keterangan text null,
  link_file text not null,
  nama_file text not null,
  created_at timestamp with time zone not null default now()
);

create index if not exists documentation_uploads_user_id_idx
on public.documentation_uploads (user_id, created_at desc);

alter table public.documentation_uploads enable row level security;

drop policy if exists "documentation_uploads_select_own" on public.documentation_uploads;
create policy "documentation_uploads_select_own"
on public.documentation_uploads
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = documentation_uploads.user_id
      and u.auth_uid = auth.uid()
  )
);

drop policy if exists "documentation_uploads_insert_own" on public.documentation_uploads;
create policy "documentation_uploads_insert_own"
on public.documentation_uploads
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users u
    where u.id = documentation_uploads.user_id
      and u.auth_uid = auth.uid()
  )
);
