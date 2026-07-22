-- get_anggota_profesi + kolom nama_kk (se2026_keterangan_umum.data1).
-- Hasil tetap terurut per assignment_id (anggota satu KK berkelompok).

drop function if exists public.get_anggota_profesi(
  text, text, text, boolean, integer, integer
);

create function public.get_anggota_profesi(
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
  nama_kk text,
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
        nullif(btrim(ku.data1), '') as nama_kk,
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
        or ku.data1 ilike '%' || v_q || '%'
        or btrim(ak.profesi) = v_q
      )
    order by ak.assignment_id, ak.no_urut::integer
    offset greatest(p_offset, 0)
    limit greatest(p_limit, 1);
end;
$function$;

notify pgrst, 'reload schema';
