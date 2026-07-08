-- Tambah nama_pml (untuk filter PML di sisi admin) dan link_fasih (untuk tombol
-- buka di Fasih) ke get_anomali_gabungan. Tetap versi pusat_baru-only.
-- Menggantikan definisi di 20260707140000.

drop function if exists public.get_anomali_gabungan(
  text, text, text, text, text, text, integer, integer
);

create function public.get_anomali_gabungan(
  p_sumber text default null,
  p_kategori_besar text default null,
  p_kategori_kode text default null,
  p_status text default null,
  p_pengawas_id text default null,
  p_petugas_id text default null,
  p_limit integer default 500,
  p_offset integer default 0
)
returns table(
  sumber text,
  assignment_id text,
  kode_wilayah text,
  nama_wilayah text,
  kategori_besar text,
  kategori_kode text,
  kategori_label text,
  subjek text,
  no_anomali integer,
  deskripsi text,
  status_tindak_lanjut text,
  jenis_respons text,
  keterangan text,
  diperiksa_oleh text,
  diperiksa_at timestamptz,
  status_assignment text,
  jumlah_respons integer,
  nm_sls text,
  sub_sls text,
  nama_petugas text,
  link_fasih text,
  nama_pml text
)
language plpgsql
security definer
as $function$
declare
    v_petugas_id       text;
    v_role             text;
    v_where_pusat_baru text;
    v_petugas_col      text;
    v_pml_col          text;
    v_sql              text := '';
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

    if v_role = 'pendata' then
        v_where_pusat_baru := format(
            ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
            v_petugas_id);

    elsif v_role = 'pengawas' then
        if p_petugas_id is not null then
            v_where_pusat_baru := format(
                ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
        else
            v_where_pusat_baru := format(
                ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                v_petugas_id);
        end if;

    elsif v_role = 'admin' then
        if p_petugas_id is not null then
            v_where_pusat_baru := format(
                ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
        elsif p_pengawas_id is not null then
            v_where_pusat_baru := format(
                ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                p_pengawas_id);
        else
            v_where_pusat_baru := ' where true';
        end if;

    else
        return;
    end if;

    v_petugas_col := case
        when v_role in ('pengawas', 'admin') then 'ppl.nama'
        else 'null::text'
    end;
    v_pml_col := case
        when v_role in ('pengawas', 'admin') then 'pml.nama'
        else 'null::text'
    end;

    v_sql := $q$
        select
            'pusat_baru'::text,
            t.assignment_id,
            t.kode_wilayah,
            concat_ws(' / ', t.nama_kec, t.nama_desa),
            t.scope::text,
            t.kategori_kode,
            t.kategori_nama,
            t.nama_subjek,
            null::integer,
            t.kategori_nama,
            coalesce(r_mine.jenis_respons, 'belum_diperiksa'),
            r_mine.jenis_respons,
            r_mine.keterangan,
            p_mine.nama,
            r_mine.updated_at,
            al.status_text,
            (select count(*)::integer from public.anomali_pusat_respons r2
             where r2.sumber = 'pusat_baru'
               and r2.scope = t.scope
               and r2.assignment_id = t.assignment_id
               and r2.nama_subjek = t.nama_subjek
               and r2.kategori_kode = t.kategori_kode),
            wt.nm_sls,
            t.sub_sls,
            $q$ || v_petugas_col || $q$,
            t.link_fasih,
            $q$ || v_pml_col || $q$
        from public.anomali_pusat_temuan t
        left join public.anomali_pusat_respons r_mine
          on r_mine.sumber = 'pusat_baru'
         and r_mine.scope = t.scope
         and r_mine.assignment_id = t.assignment_id
         and r_mine.nama_subjek = t.nama_subjek
         and r_mine.kategori_kode = t.kategori_kode
         and r_mine.petugas_id = (select p.id from se2026_petugas p
                                   join users u on u.id = p.user_id
                                   where u.auth_uid = auth.uid() limit 1)
        left join public.se2026_petugas p_mine on p_mine.id = r_mine.petugas_id
        left join public.se2026_assignment_list al on al.assignment_id = t.assignment_id
        left join lateral (
            select w.nm_sls, w.ppl_id, w.pml_id
            from public.se2026_wilayah_tugas w
            where w.id = left(t.kode_wilayah, 16)
            limit 1
        ) wt on true
        left join public.se2026_petugas ppl on ppl.id = wt.ppl_id
        left join public.se2026_petugas pml on pml.id = wt.pml_id
    $q$ || v_where_pusat_baru || ' and t.is_active = true';

    if p_kategori_besar is not null then
        v_sql := v_sql || format(' and t.scope::text = %L', p_kategori_besar);
    end if;
    if p_kategori_kode is not null then
        v_sql := v_sql || format(' and t.kategori_kode = %L', p_kategori_kode);
    end if;
    if p_status is not null then
        v_sql := v_sql || format(' and coalesce(r_mine.jenis_respons, ''belum_diperiksa'') = %L', p_status);
    end if;

    v_sql := v_sql || format(' order by 2, 3 limit %s offset %s', p_limit, p_offset);

    return query execute v_sql;
end;
$function$;

notify pgrst, 'reload schema';
