-- Impor Anomali Wilayah - kategori "Pengecekan Pendapatan".
-- Admin memasukkan usaha dengan total_pendapatan ekstrem (>= batas atas / <=
-- batas bawah) ke list anomali utama sebagai kategori:
--   UW1 "Pendapatan Anomali Tinggi"
--   UW2 "Pendapatan Anomali Rendah"
-- Sumber: se2026_usaha (join se2026_keterangan_umum untuk kode_wilayah,
-- se2026_wilayah_tugas untuk nama kec/desa/sls). Khusus admin.

-- 1) Daftar usaha ekstrem berdasarkan ambang.
create or replace function public.get_usaha_pendapatan_ekstrem(
  p_jenis text,               -- 'tinggi' | 'rendah'
  p_batas numeric,
  p_limit integer default 300
)
returns table(
  assignment_id text,
  no_usaha integer,
  nama_subjek text,
  total_pendapatan numeric,
  kode_wilayah text,
  nama_kec text,
  nama_desa text,
  nama_sls text,
  sudah_anomali boolean
)
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_role text;
    v_kode text;
begin
    select p.role into v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        return;
    end if;
    if p_jenis not in ('tinggi', 'rendah') then
        raise exception 'jenis tidak valid: %', p_jenis;
    end if;
    v_kode := case when p_jenis = 'tinggi' then 'UW1' else 'UW2' end;

    return query
    select
        us.assignment_id,
        us.no_usaha,
        coalesce(nullif(btrim(us.nama_usaha), ''),
                 nullif(btrim(us.nama_komersial), ''),
                 'Usaha ' || us.no_usaha) as nama_subjek,
        us.total_pendapatan,
        left(ku.kode_wilayah, 16) as kode_wilayah,
        wt.nm_kec, wt.nm_desa, wt.nm_sls,
        exists (
            select 1 from public.anomali_pusat_temuan t
            where t.scope = 'usaha'
              and t.assignment_id = us.assignment_id
              and t.nama_subjek = coalesce(nullif(btrim(us.nama_usaha), ''),
                                           nullif(btrim(us.nama_komersial), ''),
                                           'Usaha ' || us.no_usaha)
              and t.kategori_kode = v_kode
              and t.is_active = true
        ) as sudah_anomali
    from public.se2026_usaha us
    join public.se2026_keterangan_umum ku on ku.assignment_id = us.assignment_id
    left join lateral (
        select w.nm_kec, w.nm_desa, w.nm_sls
        from public.se2026_wilayah_tugas w
        where w.id = left(ku.kode_wilayah, 16)
        limit 1
    ) wt on true
    where us.total_pendapatan is not null
      and coalesce(btrim(us.keberadaan_usaha), '') in ('1', '2')
      and (
          (p_jenis = 'tinggi' and us.total_pendapatan >= p_batas)
          or (p_jenis = 'rendah' and us.total_pendapatan <= p_batas)
      )
    order by
        case when p_jenis = 'tinggi' then us.total_pendapatan end desc nulls last,
        case when p_jenis = 'rendah' then us.total_pendapatan end asc nulls last
    limit greatest(p_limit, 1);
end;
$function$;

-- 2) Masukkan usaha terpilih ke anomali_pusat_temuan sebagai UW1/UW2.
create or replace function public.insert_anomali_usaha_pendapatan(
  p_jenis text,                -- 'tinggi' | 'rendah'
  p_items jsonb                -- array [{assignment_id, no_usaha}, ...]
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_role     text;
    v_kode     text;
    v_nama_kat text;
    v_desk     text;
    v_item     jsonb;
    v_aid      text;
    v_no       integer;
    v_count    integer := 0;
begin
    select p.role into v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        raise exception 'Hanya admin yang dapat memasukkan anomali';
    end if;
    if p_jenis not in ('tinggi', 'rendah') then
        raise exception 'jenis tidak valid: %', p_jenis;
    end if;

    if p_jenis = 'tinggi' then
        v_kode := 'UW1';
        v_nama_kat := 'Pendapatan Anomali Tinggi';
        v_desk := 'Total pendapatan usaha tergolong sangat tinggi (perlu dicek).';
    else
        v_kode := 'UW2';
        v_nama_kat := 'Pendapatan Anomali Rendah';
        v_desk := 'Total pendapatan usaha tergolong sangat rendah (perlu dicek).';
    end if;

    -- seed kategori; deskripsi_rule tidak ditimpa bila sudah ada (manual).
    insert into public.anomali_pusat_kategori (anomali_id, scope, kategori, deskripsi_rule)
    values (v_kode, 'usaha', v_nama_kat, v_desk)
    on conflict (anomali_id) do update set kategori = excluded.kategori;

    for v_item in select * from jsonb_array_elements(p_items)
    loop
        v_aid := v_item ->> 'assignment_id';
        v_no  := (v_item ->> 'no_usaha')::integer;

        insert into public.anomali_pusat_temuan (
            scope, assignment_id, nama_subjek,
            kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
            kategori_kode, kategori_nama, status_asal, link_fasih,
            is_active, imported_at, updated_at
        )
        select
            'usaha',
            us.assignment_id,
            coalesce(nullif(btrim(us.nama_usaha), ''),
                     nullif(btrim(us.nama_komersial), ''),
                     'Usaha ' || us.no_usaha),
            left(ku.kode_wilayah, 7),
            wt.nm_kec,
            left(ku.kode_wilayah, 10),
            wt.nm_desa,
            substring(ku.kode_wilayah from 11 for 4),
            substring(ku.kode_wilayah from 15 for 2),
            v_kode, v_nama_kat, null,
            'https://fasih-sm.bps.go.id/app/assignment-detail/'
              || us.assignment_id || '/edit',
            true, now(), now()
        from public.se2026_usaha us
        join public.se2026_keterangan_umum ku on ku.assignment_id = us.assignment_id
        left join lateral (
            select w.nm_kec, w.nm_desa
            from public.se2026_wilayah_tugas w
            where w.id = left(ku.kode_wilayah, 16)
            limit 1
        ) wt on true
        where us.assignment_id = v_aid and us.no_usaha = v_no
        on conflict (scope, assignment_id, nama_subjek, kategori_kode)
        do update set is_active = true, updated_at = now();

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$function$;

notify pgrst, 'reload schema';
