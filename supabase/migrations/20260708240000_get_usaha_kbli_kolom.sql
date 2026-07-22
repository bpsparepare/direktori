-- get_usaha_kbli + kolom kategori (se2026_usaha.kategori), status_text
-- (se2026_assignment_list), dan nama_petugas (PPL) untuk filter & tabel.

drop function if exists public.get_usaha_kbli(text, integer);
drop function if exists public.get_usaha_kbli(text, integer, integer);

create function public.get_usaha_kbli(
  p_query text default null,
  p_limit integer default 200,
  p_offset integer default 0
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
  kategori text,
  status_text text,
  nama_petugas text,
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
        us.kategori,
        al.status_text,
        ppl.nama as nama_petugas,
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
    left join public.se2026_assignment_list al on al.assignment_id = us.assignment_id
    left join lateral (
        select w.nm_kec, w.nm_desa, w.nm_sls, w.ppl_id
        from public.se2026_wilayah_tugas w
        where w.id = left(ku.kode_wilayah, 16)
        limit 1
    ) wt on true
    left join public.se2026_petugas ppl on ppl.id = wt.ppl_id
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
    offset greatest(p_offset, 0)
    limit greatest(p_limit, 1);
end;
$function$;

notify pgrst, 'reload schema';
