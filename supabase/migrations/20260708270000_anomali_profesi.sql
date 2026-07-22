-- Impor Anomali Wilayah - kategori "Profesi Tanpa Usaha" (UW4).
-- Admin melihat anggota keluarga yang punya profesi + daftar usaha di
-- assignment yang sama. Bila ada profesi tapi belum ada usaha, admin bisa
-- menandai (catatan -> respons konfirmasi ke petugas). Khusus admin.
-- Sumber: se2026_anggota_keluarga (no_urut, nama_dtsen, profesi[kode]).

-- 1) Daftar anggota berprofesi + agregat usaha per assignment.
create or replace function public.get_anggota_profesi(
  p_query text default null,
  p_petugas text default null,
  p_profesi text default null,
  p_tanpa_usaha boolean default false,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table(
  assignment_id text,
  no_urut integer,
  nama_subjek text,
  profesi text,
  kode_wilayah text,
  nama_kec text,
  nama_desa text,
  nama_sls text,
  status_text text,
  nama_petugas text,
  jumlah_usaha integer,
  daftar_usaha text,
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
    v_ptg  text;
    v_prof text;
begin
    select p.role into v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        return;
    end if;

    v_q    := nullif(btrim(coalesce(p_query, '')), '');
    v_ptg  := nullif(btrim(coalesce(p_petugas, '')), '');
    v_prof := nullif(btrim(coalesce(p_profesi, '')), '');

    return query
    select
        ak.assignment_id,
        ak.no_urut::integer,
        coalesce(nullif(btrim(ak.nama_dtsen), ''), 'Anggota ' || ak.no_urut)
          as nama_subjek,
        btrim(ak.profesi) as profesi,
        left(ku.kode_wilayah, 16) as kode_wilayah,
        wt.nm_kec, wt.nm_desa, wt.nm_sls,
        al.status_text,
        ppl.nama as nama_petugas,
        uu.jml as jumlah_usaha,
        uu.daftar as daftar_usaha,
        exists (
            select 1 from public.anomali_pusat_temuan t
            where t.scope = 'keluarga'
              and t.assignment_id = ak.assignment_id
              and t.nama_subjek = coalesce(nullif(btrim(ak.nama_dtsen), ''),
                                           'Anggota ' || ak.no_urut)
              and t.kategori_kode = 'UW4'
              and t.is_active = true
        ) as sudah_anomali,
        (select r.keterangan
         from public.anomali_pusat_respons r
         where r.sumber = 'pusat_baru' and r.scope = 'keluarga'
           and r.assignment_id = ak.assignment_id
           and r.nama_subjek = coalesce(nullif(btrim(ak.nama_dtsen), ''),
                                        'Anggota ' || ak.no_urut)
           and r.kategori_kode = 'UW4'
           and r.jenis_respons = 'konfirmasi'
         order by r.updated_at desc
         limit 1) as komentar_admin
    from public.se2026_anggota_keluarga ak
    join public.se2026_keterangan_umum ku on ku.assignment_id = ak.assignment_id
    left join public.se2026_assignment_list al on al.assignment_id = ak.assignment_id
    left join lateral (
        select w.nm_kec, w.nm_desa, w.nm_sls, w.ppl_id
        from public.se2026_wilayah_tugas w
        where w.id = left(ku.kode_wilayah, 16)
        limit 1
    ) wt on true
    left join public.se2026_petugas ppl on ppl.id = wt.ppl_id
    left join lateral (
        select count(*)::integer as jml,
               string_agg(
                   coalesce(nullif(btrim(u2.nama_usaha), ''),
                            'Usaha ' || u2.no_usaha), ', ' order by u2.no_usaha
               ) as daftar
        from public.se2026_usaha u2
        where u2.assignment_id = ak.assignment_id
    ) uu on true
    where nullif(btrim(ak.profesi), '') is not null
      and (v_ptg is null or ppl.nama = v_ptg)
      and (v_prof is null or btrim(ak.profesi) = v_prof)
      and (not p_tanpa_usaha or coalesce(uu.jml, 0) = 0)
      and (
        v_q is null
        or ak.nama_dtsen ilike '%' || v_q || '%'
        or btrim(ak.profesi) = v_q
      )
    order by ak.assignment_id, ak.no_urut::integer
    offset greatest(p_offset, 0)
    limit greatest(p_limit, 1);
end;
$function$;

-- 2) Opsi filter: petugas + profesi (kode) yang ada di data.
create or replace function public.get_anggota_profesi_filter_options()
returns table(tipe text, nilai text)
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_role text;
begin
    select p.role into v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        return;
    end if;

    return query
    select 'profesi'::text, x.profesi
    from (
        select distinct btrim(ak.profesi) as profesi
        from public.se2026_anggota_keluarga ak
        where nullif(btrim(ak.profesi), '') is not null
    ) x
    union all
    select 'petugas'::text, y.nama
    from (
        select distinct ppl.nama
        from public.se2026_anggota_keluarga ak
        join public.se2026_keterangan_umum ku on ku.assignment_id = ak.assignment_id
        left join lateral (
            select w.ppl_id from public.se2026_wilayah_tugas w
            where w.id = left(ku.kode_wilayah, 16) limit 1
        ) wt on true
        join public.se2026_petugas ppl on ppl.id = wt.ppl_id
        where nullif(btrim(ak.profesi), '') is not null
    ) y
    where y.nama is not null
    order by 1, 2;
end;
$function$;

-- 3) Tandai satu anggota (UW4) + catatan admin (respons konfirmasi).
create or replace function public.insert_anomali_profesi(
  p_assignment_id text,
  p_no_urut integer,
  p_profesi_nama text,
  p_komentar text
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_role      text;
    v_admin_id  uuid;
    v_nama_subj text;
begin
    select p.id, p.role into v_admin_id, v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        raise exception 'Hanya admin yang dapat menandai anomali profesi';
    end if;
    if p_komentar is null or length(btrim(p_komentar)) = 0 then
        raise exception 'Catatan wajib diisi';
    end if;

    insert into public.anomali_pusat_kategori (anomali_id, scope, kategori, deskripsi_rule)
    values ('UW4', 'keluarga', 'Profesi Tanpa Usaha',
            'Anggota memiliki profesi namun usaha belum tercatat di assignment.')
    on conflict (anomali_id) do update set kategori = excluded.kategori;

    select coalesce(nullif(btrim(ak.nama_dtsen), ''), 'Anggota ' || ak.no_urut)
    into v_nama_subj
    from public.se2026_anggota_keluarga ak
    where ak.assignment_id = p_assignment_id and ak.no_urut::integer = p_no_urut;

    if v_nama_subj is null then
        raise exception 'Anggota tidak ditemukan';
    end if;

    insert into public.anomali_pusat_temuan (
        scope, assignment_id, nama_subjek,
        kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
        kategori_kode, kategori_nama, deskripsi_detail, status_asal, link_fasih,
        is_active, imported_at, updated_at
    )
    select
        'keluarga', ak.assignment_id, v_nama_subj,
        left(ku.kode_wilayah, 7), wt.nm_kec,
        left(ku.kode_wilayah, 10), wt.nm_desa,
        substring(ku.kode_wilayah from 11 for 4),
        substring(ku.kode_wilayah from 15 for 2),
        'UW4', 'Profesi Tanpa Usaha',
        'Profesi: ' || coalesce(nullif(btrim(p_profesi_nama), ''), btrim(ak.profesi))
          || ' · Usaha terdaftar: '
          || coalesce((select string_agg(coalesce(nullif(btrim(u2.nama_usaha), ''),
                                                  'Usaha ' || u2.no_usaha), ', ')
                       from public.se2026_usaha u2
                       where u2.assignment_id = ak.assignment_id), 'belum ada'),
        null,
        'https://fasih-sm.bps.go.id/app/assignment-detail/'
          || ak.assignment_id || '/edit',
        true, now(), now()
    from public.se2026_anggota_keluarga ak
    join public.se2026_keterangan_umum ku on ku.assignment_id = ak.assignment_id
    left join lateral (
        select w.nm_kec, w.nm_desa from public.se2026_wilayah_tugas w
        where w.id = left(ku.kode_wilayah, 16) limit 1
    ) wt on true
    where ak.assignment_id = p_assignment_id and ak.no_urut::integer = p_no_urut
    on conflict (scope, assignment_id, nama_subjek, kategori_kode)
    do update set
        deskripsi_detail = excluded.deskripsi_detail,
        is_active = true,
        updated_at = now();

    insert into public.anomali_pusat_respons (
        sumber, scope, assignment_id, nama_subjek, kategori_kode,
        petugas_id, jenis_respons, keterangan, updated_at
    ) values (
        'pusat_baru', 'keluarga', p_assignment_id, v_nama_subj, 'UW4',
        v_admin_id, 'konfirmasi', btrim(p_komentar), now()
    )
    on conflict on constraint anomali_pusat_respons_unique_key
    do update set
        jenis_respons = excluded.jenis_respons,
        keterangan    = excluded.keterangan,
        updated_at    = now();
end;
$function$;

-- 4) Tandai banyak sekaligus (catatan sama). p_items: [{assignment_id, no_urut, profesi_nama}]
create or replace function public.insert_anomali_profesi_batch(
  p_items jsonb,
  p_komentar text
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_item jsonb;
    v_count integer := 0;
begin
    for v_item in select * from jsonb_array_elements(p_items)
    loop
        perform public.insert_anomali_profesi(
            v_item ->> 'assignment_id',
            (v_item ->> 'no_urut')::integer,
            v_item ->> 'profesi_nama',
            p_komentar
        );
        v_count := v_count + 1;
    end loop;
    return v_count;
end;
$function$;

notify pgrst, 'reload schema';
