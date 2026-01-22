-- Create app_versions table
create table if not exists public.app_versions (
    id uuid not null default gen_random_uuid(),
    version text not null,
    build_number int not null,
    force_update boolean not null default false,
    download_url text, -- Default/Web URL
    android_url text, -- Play Store / Direct APK
    windows_url text, -- Microsoft Store / Exe
    ios_url text, -- App Store
    release_notes text,
    created_at timestamptz not null default now(),
    constraint app_versions_pkey primary key (id)
);

-- Enable RLS
alter table public.app_versions enable row level security;

-- Create policy to allow read access for everyone (public)
create policy "Allow public read access"
    on public.app_versions
    for select
    using (true);

-- Create policy to allow insert/update/delete for authenticated users only (admins)
-- Assuming you have an admin role or specific users. For now, let's restrict to authenticated.
-- Adjust this based on your actual auth requirements.
create policy "Allow authenticated insert/update"
    on public.app_versions
    for all
    using (auth.role() = 'authenticated')
    with check (auth.role() = 'authenticated');

-- Comment on table
comment on table public.app_versions is 'Stores application version information for update checks';
