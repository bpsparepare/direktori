-- get_keluarga_aset + filter p_aset: hanya keluarga yang aset TERTENTU melewati
-- ambang (memakai aset_lewat). Signature berubah -> drop lama, create baru.

drop function if exists public.get_keluarga_aset(
  text, text, boolean, jsonb, integer, integer
);

create or replace function public.get_keluarga_aset(
  p_query text default null,
  p_petugas text default null,
  p_hanya_anomali boolean default false,
  p_aset text default null,
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
    v_aset text;
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

    v_q    := nullif(btrim(coalesce(p_query, '')), '');
    v_ptg  := nullif(btrim(coalesce(p_petugas, '')), '');
    v_aset := nullif(btrim(coalesce(p_aset, '')), '');

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
      and (v_aset is null or v_aset = any(f.aset_lewat))
      and (not p_hanya_anomali or cardinality(f.aset_lewat) > 0)
      and (v_q is null or f.nama_kk ilike '%' || v_q || '%')
    order by f.assignment_id
    offset greatest(p_offset, 0)
    limit greatest(p_limit, 1);
end;
$function$;

notify pgrst, 'reload schema';
