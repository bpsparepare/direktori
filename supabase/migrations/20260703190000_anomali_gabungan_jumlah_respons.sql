-- "Sudah diperiksa" harus berarti ADA respons dari petugas manapun (termasuk
-- hasil backfill dari petugas lain), bukan cuma respons milik petugas yang
-- sedang login. Tambah kolom jumlah_respons (hitungan agregat per kasus),
-- jenis_respons/keterangan/diperiksa_oleh/diperiksa_at tetap punya petugas
-- yang login sendiri (dipakai form edit di detail sheet).

drop function if exists public.get_anomali_gabungan(
  text, text, text, text, text, text, integer, integer
);

create or replace function public.get_anomali_gabungan(
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
  jumlah_respons integer
)
language plpgsql
security definer
as $function$
declare
    v_petugas_id       text;
    v_role             text;
    v_where_wilayah    text;
    v_where_pusat      text;
    v_where_pusat_baru text;
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
        v_where_wilayah := format(
            ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
            v_petugas_id);
        v_where_pusat := format(' where v.ppl_id::text = %L', v_petugas_id);
        v_where_pusat_baru := format(
            ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
            v_petugas_id);

    elsif v_role = 'pengawas' then
        if p_petugas_id is not null then
            v_where_wilayah := format(
                ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
            v_where_pusat := format(' where v.ppl_id::text = %L', p_petugas_id);
            v_where_pusat_baru := format(
                ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
        else
            v_where_wilayah := format(
                ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                v_petugas_id);
            v_where_pusat := format(' where v.pml_id::text = %L', v_petugas_id);
            v_where_pusat_baru := format(
                ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                v_petugas_id);
        end if;

    elsif v_role = 'admin' then
        if p_petugas_id is not null then
            v_where_wilayah := format(
                ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
            v_where_pusat := format(' where v.ppl_id::text = %L', p_petugas_id);
            v_where_pusat_baru := format(
                ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
        elsif p_pengawas_id is not null then
            v_where_wilayah := format(
                ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                p_pengawas_id);
            v_where_pusat := format(' where v.pml_id::text = %L', p_pengawas_id);
            v_where_pusat_baru := format(
                ' where left(t.kode_wilayah, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                p_pengawas_id);
        else
            v_where_wilayah := ' where true';
            v_where_pusat := ' where true';
            v_where_pusat_baru := ' where true';
        end if;

    else
        return;
    end if;

    if p_sumber = 'kualitas' or p_sumber is null then
        v_sql := v_sql || $q$
            select
                'kualitas'::text,
                a.assignment_id::text,
                a.kode_wilayah::text,
                a.nama_wilayah::text,
                a.kategori::text,
                'ANOM-' || lpad(a.no_anomali::text, 3, '0'),
                k.kategori::text,
                a.nama_subjek::text,
                a.no_anomali::integer,
                a.deskripsi::text,
                coalesce(r_mine.jenis_respons, 'belum_diperiksa')::text,
                r_mine.jenis_respons,
                r_mine.keterangan,
                p_mine.nama,
                r_mine.updated_at,
                al.status_text,
                (select count(*)::integer from public.anomali_pusat_respons r2
                 where r2.sumber = 'kualitas'
                   and r2.scope = a.kategori::text
                   and r2.assignment_id = a.assignment_id::text
                   and r2.nama_subjek = ''
                   and r2.kategori_kode = ('ANOM-' || lpad(a.no_anomali::text, 3, '0')))
            from mv_anomali a
            left join public.anomali_pusat_kategori k
              on k.anomali_id = 'ANOM-' || lpad(a.no_anomali::text, 3, '0')
             and k.scope = a.kategori::text
            left join public.anomali_pusat_respons r_mine
              on r_mine.sumber = 'kualitas'
             and r_mine.scope = a.kategori::text
             and r_mine.assignment_id = a.assignment_id::text
             and r_mine.nama_subjek = ''
             and r_mine.kategori_kode = ('ANOM-' || lpad(a.no_anomali::text, 3, '0'))
             and r_mine.petugas_id = (select p.id from se2026_petugas p
                                       join users u on u.id = p.user_id
                                       where u.auth_uid = auth.uid() limit 1)
            left join public.se2026_petugas p_mine on p_mine.id = r_mine.petugas_id
            left join public.se2026_assignment_list al on al.assignment_id = a.assignment_id::text
        $q$ || v_where_wilayah;

        if p_kategori_besar is not null then
            v_sql := v_sql || format(' and a.kategori::text = %L', p_kategori_besar);
        end if;
        if p_kategori_kode is not null then
            v_sql := v_sql || format(
                ' and (''ANOM-'' || lpad(a.no_anomali::text, 3, ''0'')) = %L', p_kategori_kode);
        end if;
        if p_status is not null then
            v_sql := v_sql || format(' and coalesce(r_mine.jenis_respons, ''belum_diperiksa'') = %L', p_status);
        end if;
    end if;

    if p_sumber = 'pusat' then
        if v_sql <> '' then
            v_sql := v_sql || ' union all ';
        end if;
        v_sql := v_sql || $q$
            select
                'pusat'::text,
                v.assignment_id,
                v.kode_wilayah,
                concat_ws(' / ', v.nm_kec, v.nm_desa, v.nm_sls),
                v.kategori,
                null::text,
                v.nama_anomali,
                v.nama,
                null::integer,
                v.nama_anomali,
                coalesce(v.tindak_lanjut, 'belum_diperiksa'),
                null::text,
                null::text,
                null::text,
                null::timestamptz,
                al.status_text,
                0
            from v_anomali_pusat_petugas v
            left join public.se2026_assignment_list al on al.assignment_id = v.assignment_id
        $q$ || v_where_pusat;

        if p_kategori_besar is not null then
            v_sql := v_sql || format(' and v.kategori::text = %L', p_kategori_besar);
        end if;
        if p_status is not null then
            v_sql := v_sql || format(' and v.status_text::text = %L', p_status);
        end if;
    end if;

    if p_sumber = 'pusat_baru' or p_sumber is null then
        if v_sql <> '' then
            v_sql := v_sql || ' union all ';
        end if;
        v_sql := v_sql || $q$
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
                   and r2.kategori_kode = t.kategori_kode)
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
    end if;

    v_sql := v_sql || format(' order by 2, 3 limit %s offset %s', p_limit, p_offset);

    return query execute v_sql;
end;
$function$;
