-- Ambang aset dikirim dari klien (setting lokal) via p_thresholds jsonb,
-- fallback ke default bila tidak diisi. Mengganti signature get/insert.

drop function if exists public.get_keluarga_aset(
  text, text, boolean, integer, integer
);

create or replace function public.get_keluarga_aset(
  p_query text default null,
  p_petugas text default null,
  p_hanya_anomali boolean default false,
  p_thresholds jsonb default '{}'::jsonb,
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
    t_tabung3kg int := coalesce((p_thresholds->>'tabung3kg')::int, 4);
    t_tabung5kg int := coalesce((p_thresholds->>'tabung5kg')::int, 3);
    t_kulkas    int := coalesce((p_thresholds->>'kulkas')::int, 3);
    t_ac        int := coalesce((p_thresholds->>'ac')::int, 3);
    t_emas      int := coalesce((p_thresholds->>'emas')::int, 100);
    t_laptop    int := coalesce((p_thresholds->>'laptop')::int, 4);
    t_motor     int := coalesce((p_thresholds->>'motor')::int, 5);
    t_mobil     int := coalesce((p_thresholds->>'mobil')::int, 3);
    t_lahan     int := coalesce((p_thresholds->>'lahan')::int, 4);
    t_rumah     int := coalesce((p_thresholds->>'rumah')::int, 3);
begin
    select p.role into v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true limit 1;
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
            wt.nm_kec as nama_kec, wt.nm_desa as nama_desa,
            wt.nm_sls as nama_sls, al.status_text,
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
                case when v_tabung3kg >= t_tabung3kg then 'tabung3kg' end,
                case when v_tabung5kg >= t_tabung5kg then 'tabung5kg' end,
                case when v_kulkas    >= t_kulkas    then 'kulkas'    end,
                case when v_ac        >= t_ac        then 'ac'        end,
                case when v_emas      >= t_emas      then 'emas'      end,
                case when v_laptop    >= t_laptop    then 'laptop'    end,
                case when v_motor     >= t_motor     then 'motor'     end,
                case when v_mobil     >= t_mobil     then 'mobil'     end,
                case when v_lahan     >= t_lahan     then 'lahan'     end,
                case when v_rumah     >= t_rumah     then 'rumah'     end
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

-- insert dengan ambang dari klien.
drop function if exists public.insert_anomali_aset(text, text);

create or replace function public.insert_anomali_aset(
  p_assignment_id text,
  p_komentar text,
  p_thresholds jsonb default '{}'::jsonb
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
    t_tabung3kg int := coalesce((p_thresholds->>'tabung3kg')::int, 4);
    t_tabung5kg int := coalesce((p_thresholds->>'tabung5kg')::int, 3);
    t_kulkas    int := coalesce((p_thresholds->>'kulkas')::int, 3);
    t_ac        int := coalesce((p_thresholds->>'ac')::int, 3);
    t_emas      int := coalesce((p_thresholds->>'emas')::int, 100);
    t_laptop    int := coalesce((p_thresholds->>'laptop')::int, 4);
    t_motor     int := coalesce((p_thresholds->>'motor')::int, 5);
    t_mobil     int := coalesce((p_thresholds->>'mobil')::int, 3);
    t_lahan     int := coalesce((p_thresholds->>'lahan')::int, 4);
    t_rumah     int := coalesce((p_thresholds->>'rumah')::int, 3);
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
                case when coalesce(kl.jumlah_tabung3kg_new,0) >= t_tabung3kg then coalesce(kl.jumlah_tabung3kg_new,0) || ' tabung 3kg' end,
                case when coalesce(kl.jumlah_tabung5kg_new,0) >= t_tabung5kg then coalesce(kl.jumlah_tabung5kg_new,0) || ' tabung 5kg' end,
                case when coalesce(kl.jumlah_kulkas_new,0)    >= t_kulkas    then coalesce(kl.jumlah_kulkas_new,0)    || ' kulkas' end,
                case when coalesce(kl.jumlah_ac_new,0)        >= t_ac        then coalesce(kl.jumlah_ac_new,0)        || ' AC' end,
                case when coalesce(kl.jumlah_emas_new,0)      >= t_emas      then coalesce(kl.jumlah_emas_new,0)      || ' emas' end,
                case when coalesce(kl.jumlah_laptop_new,0)    >= t_laptop    then coalesce(kl.jumlah_laptop_new,0)    || ' laptop' end,
                case when coalesce(kl.jumlah_motor_new,0)     >= t_motor     then coalesce(kl.jumlah_motor_new,0)     || ' motor' end,
                case when coalesce(kl.jumlah_mobil_new,0)     >= t_mobil     then coalesce(kl.jumlah_mobil_new,0)     || ' mobil' end,
                case when coalesce(kl.jumlah_lahan_new,0)     >= t_lahan     then coalesce(kl.jumlah_lahan_new,0)     || ' lahan' end,
                case when coalesce(kl.jumlah_rumah_new,0)     >= t_rumah     then coalesce(kl.jumlah_rumah_new,0)     || ' rumah' end
           ], null), ', ')
    into v_nama, v_desk
    from public.se2026_keluarga kl
    join public.se2026_keterangan_umum ku on ku.assignment_id = kl.assignment_id
    where kl.assignment_id = p_assignment_id limit 1;

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

drop function if exists public.insert_anomali_aset_batch(jsonb, text);

create or replace function public.insert_anomali_aset_batch(
  p_items jsonb,
  p_komentar text,
  p_thresholds jsonb default '{}'::jsonb
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
        perform public.insert_anomali_aset(
            v_item ->> 'assignment_id', p_komentar, p_thresholds);
        v_count := v_count + 1;
    end loop;
    return v_count;
end;
$function$;

notify pgrst, 'reload schema';
