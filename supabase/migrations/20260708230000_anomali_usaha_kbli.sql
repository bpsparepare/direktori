-- Impor Anomali Wilayah - kategori "Salah Penentuan KBLI" (UW3).
-- Admin memeriksa kbli_akhir vs keg_utama/produk di se2026_usaha; bila janggal,
-- admin menandai + memberi catatan koreksi. Catatan disimpan sebagai respons
-- admin 'konfirmasi' pada anomali sehingga muncul ke petugas (dan menjadi
-- "perlu ditindaklanjuti"). Khusus admin.

-- 1) Daftar usaha dengan KBLI/keg_utama/produk (untuk penilaian admin).
create or replace function public.get_usaha_kbli(
  p_query text default null,
  p_limit integer default 200
)
returns table(
  assignment_id text,
  no_usaha integer,
  nama_subjek text,
  kbli text,
  keg_utama text,
  produk text,
  jenis_usaha text,
  kode_wilayah text,
  nama_kec text,
  nama_desa text,
  nama_sls text,
  sudah_anomali boolean,
  komentar_admin text
)
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_role text;
    v_q    text;
begin
    select p.role into v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        return;
    end if;

    v_q := nullif(btrim(coalesce(p_query, '')), '');

    return query
    select
        us.assignment_id,
        us.no_usaha,
        coalesce(nullif(btrim(us.nama_usaha), ''),
                 nullif(btrim(us.nama_komersial), ''),
                 'Usaha ' || us.no_usaha) as nama_subjek,
        us.kbli_akhir,
        us.keg_utama,
        us.produk,
        us.jenis_usaha,
        left(ku.kode_wilayah, 16) as kode_wilayah,
        wt.nm_kec, wt.nm_desa, wt.nm_sls,
        exists (
            select 1 from public.anomali_pusat_temuan t
            where t.scope = 'usaha'
              and t.assignment_id = us.assignment_id
              and t.nama_subjek = coalesce(nullif(btrim(us.nama_usaha), ''),
                                           nullif(btrim(us.nama_komersial), ''),
                                           'Usaha ' || us.no_usaha)
              and t.kategori_kode = 'UW3'
              and t.is_active = true
        ) as sudah_anomali,
        (select r.keterangan
         from public.anomali_pusat_respons r
         where r.sumber = 'pusat_baru' and r.scope = 'usaha'
           and r.assignment_id = us.assignment_id
           and r.nama_subjek = coalesce(nullif(btrim(us.nama_usaha), ''),
                                        nullif(btrim(us.nama_komersial), ''),
                                        'Usaha ' || us.no_usaha)
           and r.kategori_kode = 'UW3'
           and r.jenis_respons = 'konfirmasi'
         order by r.updated_at desc
         limit 1) as komentar_admin
    from public.se2026_usaha us
    join public.se2026_keterangan_umum ku on ku.assignment_id = us.assignment_id
    left join lateral (
        select w.nm_kec, w.nm_desa, w.nm_sls
        from public.se2026_wilayah_tugas w
        where w.id = left(ku.kode_wilayah, 16)
        limit 1
    ) wt on true
    where coalesce(btrim(us.keberadaan_usaha), '') in ('1', '2')
      and (
        v_q is null
        or us.nama_usaha ilike '%' || v_q || '%'
        or us.nama_komersial ilike '%' || v_q || '%'
        or us.kbli_akhir ilike '%' || v_q || '%'
        or us.keg_utama ilike '%' || v_q || '%'
        or us.produk ilike '%' || v_q || '%'
      )
    order by us.assignment_id, us.no_usaha
    limit greatest(p_limit, 1);
end;
$function$;

-- 2) Tandai usaha sebagai anomali UW3 + simpan catatan admin (respons konfirmasi).
create or replace function public.insert_anomali_kbli(
  p_assignment_id text,
  p_no_usaha integer,
  p_komentar text
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_role       text;
    v_admin_id   uuid;
    v_nama_subj  text;
begin
    select p.id, p.role into v_admin_id, v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        raise exception 'Hanya admin yang dapat menandai anomali KBLI';
    end if;
    if p_komentar is null or length(btrim(p_komentar)) = 0 then
        raise exception 'Catatan koreksi KBLI wajib diisi';
    end if;

    insert into public.anomali_pusat_kategori (anomali_id, scope, kategori, deskripsi_rule)
    values ('UW3', 'usaha', 'Salah Penentuan KBLI',
            'KBLI kemungkinan tidak sesuai kegiatan utama/produk usaha.')
    on conflict (anomali_id) do update set kategori = excluded.kategori;

    select coalesce(nullif(btrim(us.nama_usaha), ''),
                    nullif(btrim(us.nama_komersial), ''),
                    'Usaha ' || us.no_usaha)
    into v_nama_subj
    from public.se2026_usaha us
    where us.assignment_id = p_assignment_id and us.no_usaha = p_no_usaha;

    if v_nama_subj is null then
        raise exception 'Usaha tidak ditemukan';
    end if;

    insert into public.anomali_pusat_temuan (
        scope, assignment_id, nama_subjek,
        kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
        kategori_kode, kategori_nama, deskripsi_detail, status_asal, link_fasih,
        is_active, imported_at, updated_at
    )
    select
        'usaha', us.assignment_id, v_nama_subj,
        left(ku.kode_wilayah, 7), wt.nm_kec,
        left(ku.kode_wilayah, 10), wt.nm_desa,
        substring(ku.kode_wilayah from 11 for 4),
        substring(ku.kode_wilayah from 15 for 2),
        'UW3', 'Salah Penentuan KBLI',
        'KBLI: ' || coalesce(nullif(btrim(us.kbli_akhir), ''), '-')
          || ' · Keg utama: ' || coalesce(nullif(btrim(us.keg_utama), ''), '-')
          || ' · Produk: ' || coalesce(nullif(btrim(us.produk), ''), '-'),
        null,
        'https://fasih-sm.bps.go.id/app/assignment-detail/'
          || us.assignment_id || '/edit',
        true, now(), now()
    from public.se2026_usaha us
    join public.se2026_keterangan_umum ku on ku.assignment_id = us.assignment_id
    left join lateral (
        select w.nm_kec, w.nm_desa from public.se2026_wilayah_tugas w
        where w.id = left(ku.kode_wilayah, 16) limit 1
    ) wt on true
    where us.assignment_id = p_assignment_id and us.no_usaha = p_no_usaha
    on conflict (scope, assignment_id, nama_subjek, kategori_kode)
    do update set
        deskripsi_detail = excluded.deskripsi_detail,
        is_active = true,
        updated_at = now();

    -- Catatan admin sebagai respons 'konfirmasi' -> muncul & jadi tindak lanjut
    -- bagi petugas.
    insert into public.anomali_pusat_respons (
        sumber, scope, assignment_id, nama_subjek, kategori_kode,
        petugas_id, jenis_respons, keterangan, updated_at
    ) values (
        'pusat_baru', 'usaha', p_assignment_id, v_nama_subj, 'UW3',
        v_admin_id, 'konfirmasi', btrim(p_komentar), now()
    )
    on conflict on constraint anomali_pusat_respons_unique_key
    do update set
        jenis_respons = excluded.jenis_respons,
        keterangan    = excluded.keterangan,
        updated_at    = now();
end;
$function$;

notify pgrst, 'reload schema';
