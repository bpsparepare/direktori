-- Impor Anomali Wilayah - kategori "Kepemilikan Aset Tidak Wajar" (UW5).
-- Admin melihat aset tiap keluarga (se2026_keluarga); nilai yang melewati
-- ambang wajar disorot. Keluarga dgn >=1 aset melewati ambang bisa ditandai.
-- Ambang (>= = anomali): tabung3kg 4, tabung5kg 3, kulkas 3, ac 3, emas 100,
-- laptop 4, motor 5, mobil 3, lahan 4, rumah 3.

create or replace function public.get_keluarga_aset(
  p_query text default null,
  p_petugas text default null,
  p_hanya_anomali boolean default false,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table(
  assignment_id text,
  nama_kk text,
  kode_wilayah text,
  nama_kec text,
  nama_desa text,
  nama_sls text,
  status_text text,
  nama_petugas text,
  jml_tabung3kg integer,
  jml_tabung5kg integer,
  jml_kulkas integer,
  jml_ac integer,
  jml_emas integer,
  jml_laptop integer,
  jml_motor integer,
  jml_mobil integer,
  jml_lahan integer,
  jml_rumah integer,
  aset_lewat text[],
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
begin
    select p.role into v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        return;
    end if;

    v_q   := nullif(btrim(coalesce(p_query, '')), '');
    v_ptg := nullif(btrim(coalesce(p_petugas, '')), '');

    return query
    with base as (
        select
            kl.assignment_id,
            nullif(btrim(ku.data1), '') as nama_kk,
            left(ku.kode_wilayah, 16) as kode_wilayah,
            wt.nm_kec, wt.nm_desa, wt.nm_sls, al.status_text,
            ppl.nama as nama_petugas,
            coalesce(kl.jumlah_tabung3kg_new, 0) as v_tabung3kg,
            coalesce(kl.jumlah_tabung5kg_new, 0) as v_tabung5kg,
            coalesce(kl.jumlah_kulkas_new, 0)    as v_kulkas,
            coalesce(kl.jumlah_ac_new, 0)        as v_ac,
            coalesce(kl.jumlah_emas_new, 0)      as v_emas,
            coalesce(kl.jumlah_laptop_new, 0)    as v_laptop,
            coalesce(kl.jumlah_motor_new, 0)     as v_motor,
            coalesce(kl.jumlah_mobil_new, 0)     as v_mobil,
            coalesce(kl.jumlah_lahan_new, 0)     as v_lahan,
            coalesce(kl.jumlah_rumah_new, 0)     as v_rumah
        from public.se2026_keluarga kl
        join public.se2026_keterangan_umum ku on ku.assignment_id = kl.assignment_id
        left join public.se2026_assignment_list al on al.assignment_id = kl.assignment_id
        left join lateral (
            select w.nm_kec, w.nm_desa, w.nm_sls, w.ppl_id
            from public.se2026_wilayah_tugas w
            where w.id = left(ku.kode_wilayah, 16) limit 1
        ) wt on true
        left join public.se2026_petugas ppl on ppl.id = wt.ppl_id
    ),
    flagged as (
        select b.*,
            array_remove(array[
                case when v_tabung3kg >= 4  then 'tabung3kg' end,
                case when v_tabung5kg >= 3  then 'tabung5kg' end,
                case when v_kulkas    >= 3  then 'kulkas'    end,
                case when v_ac        >= 3  then 'ac'        end,
                case when v_emas      >= 100 then 'emas'     end,
                case when v_laptop    >= 4  then 'laptop'    end,
                case when v_motor     >= 5  then 'motor'     end,
                case when v_mobil     >= 3  then 'mobil'     end,
                case when v_lahan     >= 4  then 'lahan'     end,
                case when v_rumah     >= 3  then 'rumah'     end
            ], null) as aset_lewat
        from base b
    )
    select
        f.assignment_id, f.nama_kk, f.kode_wilayah,
        f.nama_kec, f.nama_desa, f.nama_sls, f.status_text, f.nama_petugas,
        f.v_tabung3kg, f.v_tabung5kg, f.v_kulkas, f.v_ac, f.v_emas,
        f.v_laptop, f.v_motor, f.v_mobil, f.v_lahan, f.v_rumah,
        f.aset_lewat,
        exists (
            select 1 from public.anomali_pusat_temuan t
            where t.scope = 'keluarga' and t.assignment_id = f.assignment_id
              and t.nama_subjek = coalesce(f.nama_kk, 'KK ' || f.assignment_id)
              and t.kategori_kode = 'UW5' and t.is_active = true
        ) as sudah_anomali,
        (select r.keterangan from public.anomali_pusat_respons r
         where r.sumber = 'pusat_baru' and r.scope = 'keluarga'
           and r.assignment_id = f.assignment_id
           and r.nama_subjek = coalesce(f.nama_kk, 'KK ' || f.assignment_id)
           and r.kategori_kode = 'UW5' and r.jenis_respons = 'konfirmasi'
         order by r.updated_at desc limit 1) as komentar_admin
    from flagged f
    where (v_ptg is null or f.nama_petugas = v_ptg)
      and (not p_hanya_anomali or cardinality(f.aset_lewat) > 0)
      and (v_q is null or f.nama_kk ilike '%' || v_q || '%')
    order by f.assignment_id
    offset greatest(p_offset, 0)
    limit greatest(p_limit, 1);
end;
$function$;

create or replace function public.get_keluarga_aset_filter_options()
returns table(tipe text, nilai text)
language plpgsql
security definer
set search_path = public
as $function$
declare v_role text;
begin
    select p.role into v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true limit 1;
    if v_role is distinct from 'admin' then
        return;
    end if;
    return query
    select 'petugas'::text, y.nama from (
        select distinct ppl.nama
        from public.se2026_keluarga kl
        join public.se2026_keterangan_umum ku on ku.assignment_id = kl.assignment_id
        left join lateral (
            select w.ppl_id from public.se2026_wilayah_tugas w
            where w.id = left(ku.kode_wilayah, 16) limit 1
        ) wt on true
        join public.se2026_petugas ppl on ppl.id = wt.ppl_id
    ) y
    where y.nama is not null
    order by 2;
end;
$function$;

create or replace function public.insert_anomali_aset(
  p_assignment_id text,
  p_komentar text
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_role     text;
    v_admin_id uuid;
    v_nama     text;
    v_desk     text;
begin
    select p.id, p.role into v_admin_id, v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true limit 1;
    if v_role is distinct from 'admin' then
        raise exception 'Hanya admin yang dapat menandai anomali aset';
    end if;
    if p_komentar is null or length(btrim(p_komentar)) = 0 then
        raise exception 'Catatan wajib diisi';
    end if;

    insert into public.anomali_pusat_kategori (anomali_id, scope, kategori, deskripsi_rule)
    values ('UW5', 'keluarga', 'Kepemilikan Aset Tidak Wajar',
            'Jumlah aset keluarga melewati batas wajar kepemilikan.')
    on conflict (anomali_id) do update set kategori = excluded.kategori;

    select coalesce(nullif(btrim(ku.data1), ''), 'KK ' || kl.assignment_id),
           'Aset melewati batas: ' || array_to_string(array_remove(array[
                case when coalesce(kl.jumlah_tabung3kg_new,0) >= 4  then coalesce(kl.jumlah_tabung3kg_new,0) || ' tabung 3kg' end,
                case when coalesce(kl.jumlah_tabung5kg_new,0) >= 3  then coalesce(kl.jumlah_tabung5kg_new,0) || ' tabung 5kg' end,
                case when coalesce(kl.jumlah_kulkas_new,0)    >= 3  then coalesce(kl.jumlah_kulkas_new,0)    || ' kulkas' end,
                case when coalesce(kl.jumlah_ac_new,0)        >= 3  then coalesce(kl.jumlah_ac_new,0)        || ' AC' end,
                case when coalesce(kl.jumlah_emas_new,0)      >= 100 then coalesce(kl.jumlah_emas_new,0)     || ' emas' end,
                case when coalesce(kl.jumlah_laptop_new,0)    >= 4  then coalesce(kl.jumlah_laptop_new,0)    || ' laptop' end,
                case when coalesce(kl.jumlah_motor_new,0)     >= 5  then coalesce(kl.jumlah_motor_new,0)     || ' motor' end,
                case when coalesce(kl.jumlah_mobil_new,0)     >= 3  then coalesce(kl.jumlah_mobil_new,0)     || ' mobil' end,
                case when coalesce(kl.jumlah_lahan_new,0)     >= 4  then coalesce(kl.jumlah_lahan_new,0)     || ' lahan' end,
                case when coalesce(kl.jumlah_rumah_new,0)     >= 3  then coalesce(kl.jumlah_rumah_new,0)     || ' rumah' end
           ], null), ', ')
    into v_nama, v_desk
    from public.se2026_keluarga kl
    join public.se2026_keterangan_umum ku on ku.assignment_id = kl.assignment_id
    where kl.assignment_id = p_assignment_id
    limit 1;

    if v_nama is null then
        raise exception 'Keluarga tidak ditemukan';
    end if;

    insert into public.anomali_pusat_temuan (
        scope, assignment_id, nama_subjek,
        kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
        kategori_kode, kategori_nama, deskripsi_detail, status_asal, link_fasih,
        is_active, imported_at, updated_at
    )
    select
        'keluarga', kl.assignment_id, v_nama,
        left(ku.kode_wilayah, 7), wt.nm_kec,
        left(ku.kode_wilayah, 10), wt.nm_desa,
        substring(ku.kode_wilayah from 11 for 4),
        substring(ku.kode_wilayah from 15 for 2),
        'UW5', 'Kepemilikan Aset Tidak Wajar',
        nullif(v_desk, 'Aset melewati batas: '),
        null,
        'https://fasih-sm.bps.go.id/app/assignment-detail/' || kl.assignment_id || '/edit',
        true, now(), now()
    from public.se2026_keluarga kl
    join public.se2026_keterangan_umum ku on ku.assignment_id = kl.assignment_id
    left join lateral (
        select w.nm_kec, w.nm_desa from public.se2026_wilayah_tugas w
        where w.id = left(ku.kode_wilayah, 16) limit 1
    ) wt on true
    where kl.assignment_id = p_assignment_id
    limit 1
    on conflict (scope, assignment_id, nama_subjek, kategori_kode)
    do update set deskripsi_detail = excluded.deskripsi_detail,
                  is_active = true, updated_at = now();

    insert into public.anomali_pusat_respons (
        sumber, scope, assignment_id, nama_subjek, kategori_kode,
        petugas_id, jenis_respons, keterangan, updated_at
    ) values (
        'pusat_baru', 'keluarga', p_assignment_id, v_nama, 'UW5',
        v_admin_id, 'konfirmasi', btrim(p_komentar), now()
    )
    on conflict on constraint anomali_pusat_respons_unique_key
    do update set jenis_respons = excluded.jenis_respons,
                  keterangan = excluded.keterangan, updated_at = now();
end;
$function$;

create or replace function public.insert_anomali_aset_batch(
  p_items jsonb,
  p_komentar text
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare v_item jsonb; v_count integer := 0;
begin
    for v_item in select * from jsonb_array_elements(p_items)
    loop
        perform public.insert_anomali_aset(v_item ->> 'assignment_id', p_komentar);
        v_count := v_count + 1;
    end loop;
    return v_count;
end;
$function$;

notify pgrst, 'reload schema';
