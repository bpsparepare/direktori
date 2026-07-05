-- Skema baru anomali pusat, dibangun dari awal berdasarkan struktur export
-- excel Fasih ("Data Mikro Kasus Anomali Usaha/Keluarga"). Tidak menyentuh
-- tabel/keterangan lama (se2026_anomali_pusat, se2026_anomali_pusat_keterangan).
--
-- Kunci desain:
-- - assignment_id SAJA tidak cukup untuk scope 'usaha' (1 assignment bisa
--   punya lebih dari 1 usaha) -> kunci kasus = (scope, assignment_id,
--   nama_subjek, kategori_kode).
-- - "Nama Anomali" mentah dari file ("Jumlah Anomali Data 1 (Biaya Produksi
--   Dominan) belum ditindaklanjuti") memuat status di dalam kalimat -> di-
--   parse jadi kategori_kode + kategori_nama yang stabil, status asli
--   disimpan terpisah di status_asal (informasi, bukan kunci).
-- - Re-import file baru tidak boleh menghapus respons/keterangan petugas
--   yang sudah ada -> temuan disegarkan lewat soft-refresh (is_active),
--   respons disimpan di tabel terpisah dengan kunci alami yang sama.

-- ============================================================
-- 1. TEMUAN (hasil import, disegarkan tiap kali file baru diunggah)
-- ============================================================
create table public.anomali_pusat_temuan (
  id bigint generated always as identity primary key,
  scope text not null check (scope in ('usaha', 'keluarga')),
  assignment_id text not null,
  nama_subjek text not null,

  kode_prov text,
  nama_provinsi text,
  kode_kab text,
  nama_kab text,
  kode_kec text,
  nama_kec text,
  kode_desa text,
  nama_desa text,
  kode_sls text,
  sub_sls text,
  kode_wilayah text generated always as (
    coalesce(kode_kec, '') || coalesce(kode_desa, '') ||
    coalesce(kode_sls, '') || coalesce(sub_sls, '')
  ) stored,

  kategori_kode text not null,
  kategori_nama text not null,
  status_asal text,

  id_petugas_asal text,
  email_petugas_asal text,
  link_fasih text,

  is_active boolean not null default true,
  imported_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (scope, assignment_id, nama_subjek, kategori_kode)
);

create index idx_anomali_pusat_temuan_wilayah
  on public.anomali_pusat_temuan (kode_wilayah);
create index idx_anomali_pusat_temuan_scope_active
  on public.anomali_pusat_temuan (scope, is_active);

-- ============================================================
-- 2. RESPONS PETUGAS (persisten, tidak ikut ter-refresh oleh import)
-- ============================================================
create table public.anomali_pusat_respons (
  id bigint generated always as identity primary key,
  scope text not null check (scope in ('usaha', 'keluarga')),
  assignment_id text not null,
  nama_subjek text not null,
  kategori_kode text not null,
  petugas_id uuid not null references public.se2026_petugas(id),
  jenis_respons text not null check (jenis_respons in ('perbaikan', 'konfirmasi_valid')),
  keterangan text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (scope, assignment_id, nama_subjek, kategori_kode, petugas_id),
  check (
    jenis_respons <> 'konfirmasi_valid'
    or (keterangan is not null and length(trim(keterangan)) > 0)
  )
);

-- ============================================================
-- 3. IMPORT BATCH (parsing + soft-refresh)
-- ============================================================
-- p_rows: array JSON, tiap elemen field mentah dari 1 baris excel:
--   assignment_id, nama_subjek, kode_prov, nama_provinsi, kode_kab, nama_kab,
--   kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
--   nama_anomali, tindak_lanjut, id_petugas, email_petugas, link_fasih
create or replace function public.import_anomali_pusat_batch(
  p_scope text,
  p_rows jsonb
)
returns table(diperbarui integer, dinonaktifkan integer)
language plpgsql
security definer
as $function$
declare
    v_row           jsonb;
    v_nama_anomali  text;
    v_kategori_kode text;
    v_kategori_nama text;
    v_count         integer := 0;
    v_deactivated   integer := 0;
begin
    if p_scope not in ('usaha', 'keluarga') then
        raise exception 'scope tidak valid: %', p_scope;
    end if;

    update public.anomali_pusat_temuan
    set is_active = false, updated_at = now()
    where scope = p_scope;
    get diagnostics v_deactivated = row_count;

    for v_row in select * from jsonb_array_elements(p_rows)
    loop
        v_nama_anomali := v_row ->> 'nama_anomali';

        select mm[1], mm[2]
        into v_kategori_kode, v_kategori_nama
        from regexp_matches(
            coalesce(v_nama_anomali, ''),
            'Anomali\s+(?:Data\s+)?(\d+)\s*\(([^)]*)\)'
        ) as mm;

        if v_kategori_kode is null then
            v_kategori_kode := 'lainnya';
            v_kategori_nama := coalesce(v_nama_anomali, '-');
        end if;

        insert into public.anomali_pusat_temuan (
            scope, assignment_id, nama_subjek,
            kode_prov, nama_provinsi, kode_kab, nama_kab,
            kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
            kategori_kode, kategori_nama, status_asal,
            id_petugas_asal, email_petugas_asal, link_fasih,
            is_active, imported_at, updated_at
        ) values (
            p_scope,
            v_row ->> 'assignment_id',
            v_row ->> 'nama_subjek',
            v_row ->> 'kode_prov', v_row ->> 'nama_provinsi',
            v_row ->> 'kode_kab', v_row ->> 'nama_kab',
            v_row ->> 'kode_kec', v_row ->> 'nama_kec',
            v_row ->> 'kode_desa', v_row ->> 'nama_desa',
            v_row ->> 'kode_sls', v_row ->> 'sub_sls',
            v_kategori_kode, v_kategori_nama,
            v_row ->> 'tindak_lanjut',
            nullif(v_row ->> 'id_petugas', '-'),
            nullif(v_row ->> 'email_petugas', '-'),
            v_row ->> 'link_fasih',
            true, now(), now()
        )
        on conflict (scope, assignment_id, nama_subjek, kategori_kode)
        do update set
            nama_provinsi       = excluded.nama_provinsi,
            nama_kab            = excluded.nama_kab,
            nama_kec            = excluded.nama_kec,
            nama_desa           = excluded.nama_desa,
            kode_kec            = excluded.kode_kec,
            kode_desa           = excluded.kode_desa,
            kode_sls            = excluded.kode_sls,
            sub_sls             = excluded.sub_sls,
            kategori_nama       = excluded.kategori_nama,
            status_asal         = excluded.status_asal,
            id_petugas_asal     = excluded.id_petugas_asal,
            email_petugas_asal  = excluded.email_petugas_asal,
            link_fasih          = excluded.link_fasih,
            is_active           = true,
            updated_at          = now();

        v_count := v_count + 1;
    end loop;

    return query select v_count, v_deactivated;
end;
$function$;

-- ============================================================
-- 4. UPSERT RESPONS (2 pilihan petugas: perbaikan / konfirmasi_valid)
-- ============================================================
create or replace function public.upsert_anomali_pusat_respons(
  p_scope text,
  p_assignment_id text,
  p_nama_subjek text,
  p_kategori_kode text,
  p_jenis_respons text,
  p_keterangan text default null
)
returns void
language plpgsql
security definer
as $function$
declare
    v_petugas_id uuid;
begin
    if p_jenis_respons not in ('perbaikan', 'konfirmasi_valid') then
        raise exception 'jenis_respons tidak valid: %', p_jenis_respons;
    end if;

    if p_jenis_respons = 'konfirmasi_valid'
       and (p_keterangan is null or length(trim(p_keterangan)) = 0) then
        raise exception 'Keterangan wajib diisi untuk konfirmasi data benar';
    end if;

    select p.id into v_petugas_id
    from public.se2026_petugas p
    join public.users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;

    if v_petugas_id is null then
        raise exception 'Petugas tidak ditemukan';
    end if;

    insert into public.anomali_pusat_respons (
        scope, assignment_id, nama_subjek, kategori_kode,
        petugas_id, jenis_respons, keterangan, updated_at
    ) values (
        p_scope, p_assignment_id, p_nama_subjek, p_kategori_kode,
        v_petugas_id, p_jenis_respons, p_keterangan, now()
    )
    on conflict (scope, assignment_id, nama_subjek, kategori_kode, petugas_id)
    do update set
        jenis_respons = excluded.jenis_respons,
        keterangan    = excluded.keterangan,
        updated_at    = now();
end;
$function$;

-- ============================================================
-- 5. BACA DAFTAR ANOMALI PUSAT (scoping sama pola dgn get_anomali_wilayah)
-- ============================================================
create or replace function public.get_anomali_pusat_v2(
  p_scope text default null,
  p_kategori_kode text default null,
  p_pengawas_id text default null,
  p_petugas_id text default null,
  p_limit integer default 500,
  p_offset integer default 0
)
returns table(
  id bigint,
  scope text,
  assignment_id text,
  nama_subjek text,
  kode_wilayah text,
  nama_kec text,
  nama_desa text,
  kategori_kode text,
  kategori_nama text,
  status_asal text,
  link_fasih text,
  my_jenis_respons text,
  my_keterangan text,
  jumlah_respons integer
)
language plpgsql
security definer
as $function$
declare
    v_petugas_id text;
    v_role       text;
    v_where      text;
    v_sql        text;
begin
    select p.id::text, p.role
    into   v_petugas_id, v_role
    from   users u
    join   se2026_petugas p on p.user_id = u.id
    where  u.auth_uid = auth.uid()
      and  p.is_active = true
    limit  1;

    if v_petugas_id is null then
        return;
    end if;

    v_sql := $q$
        select
            t.id, t.scope, t.assignment_id, t.nama_subjek,
            t.kode_wilayah, t.nama_kec, t.nama_desa,
            t.kategori_kode, t.kategori_nama, t.status_asal, t.link_fasih,
            r_mine.jenis_respons, r_mine.keterangan,
            (select count(*)::integer from public.anomali_pusat_respons r2
             where r2.scope = t.scope and r2.assignment_id = t.assignment_id
               and r2.nama_subjek = t.nama_subjek and r2.kategori_kode = t.kategori_kode)
        from public.anomali_pusat_temuan t
        left join public.anomali_pusat_respons r_mine
          on r_mine.scope = t.scope
         and r_mine.assignment_id = t.assignment_id
         and r_mine.nama_subjek = t.nama_subjek
         and r_mine.kategori_kode = t.kategori_kode
         and r_mine.petugas_id = (select p.id from se2026_petugas p
                                   join users u on u.id = p.user_id
                                   where u.auth_uid = auth.uid() limit 1)
        where t.is_active = true
    $q$;

    if v_role = 'pendata' then
        v_where := format(
            ' and left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
            v_petugas_id);
    elsif v_role = 'pengawas' then
        if p_petugas_id is not null then
            v_where := format(
                ' and left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
        else
            v_where := format(
                ' and left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                v_petugas_id);
        end if;
    elsif v_role = 'admin' then
        if p_petugas_id is not null then
            v_where := format(
                ' and left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
        elsif p_pengawas_id is not null then
            v_where := format(
                ' and left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                p_pengawas_id);
        else
            v_where := '';
        end if;
    else
        return;
    end if;

    v_sql := v_sql || v_where;

    if p_scope is not null then
        v_sql := v_sql || format(' and t.scope = %L', p_scope);
    end if;
    if p_kategori_kode is not null then
        v_sql := v_sql || format(' and t.kategori_kode = %L', p_kategori_kode);
    end if;

    v_sql := v_sql || format(
        ' order by t.kode_wilayah, t.assignment_id limit %s offset %s',
        p_limit, p_offset);

    return query execute v_sql;
end;
$function$;

-- ============================================================
-- 6. BACA SEMUA RESPONS (thread multi-petugas per kasus, utk detail sheet)
-- ============================================================
create or replace function public.get_anomali_pusat_respons(
  p_scope text,
  p_assignment_id text,
  p_nama_subjek text,
  p_kategori_kode text
)
returns table(
  petugas_id uuid,
  nama_petugas text,
  role text,
  jenis_respons text,
  keterangan text,
  updated_at timestamptz
)
language plpgsql
security definer
as $function$
begin
    return query
    select
        r.petugas_id,
        p.nama as nama_petugas,
        p.role,
        r.jenis_respons,
        r.keterangan,
        r.updated_at
    from public.anomali_pusat_respons r
    join public.se2026_petugas p on p.id = r.petugas_id
    where r.scope = p_scope
      and r.assignment_id = p_assignment_id
      and r.nama_subjek = p_nama_subjek
      and r.kategori_kode = p_kategori_kode
    order by r.updated_at desc;
end;
$function$;
