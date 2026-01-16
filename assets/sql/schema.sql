-- Table Definition for groundcheck_list
create table if not exists public.groundcheck_list (
    idsbr text not null primary key,
    perusahaan_id text,
    nama_usaha text,
    alamat_usaha text,
    kode_wilayah text,
    
    -- Wilayah Details
    kdprov text,
    kdkab text,
    kdkec text,
    kddesa text,
    nmprov text,
    nmkab text,
    nmkec text,
    nmdesa text,

    -- Business Details
    status_perusahaan text,
    skala_usaha text,
    kegiatan_usaha text,
    sumber_data text,

    -- Coordinates (Initial)
    latitude text,
    longitude text,
    latlong_status text,

    -- Groundcheck Results
    gcs_result text,
    gcid text,
    gc_username text,
    latitude_gc text,
    longitude_gc text,
    latlong_status_gc text,
    
    -- Scoring & Metadata
    skor_kalo text,
    rank_nama text,
    rank_alamat text,
    history_ref_profiling_id text,

    -- Flags (Boolean or Text)
    allow_cancel boolean,
    allow_edit boolean,
    allow_flagging boolean,

    updated_at timestamp with time zone default timezone('utc'::text, now())
);

-- Enable Row Level Security (RLS) if needed, currently disabled for global access as per previous context
alter table public.groundcheck_list enable row level security;

-- Policy to allow all access (adjust as needed for production)
create policy "Enable all access for authenticated users" on public.groundcheck_list
for all using (true) with check (true);
