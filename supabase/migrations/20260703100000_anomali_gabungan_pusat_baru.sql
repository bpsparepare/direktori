-- Tambah sumber 'pusat_baru' (anomali_pusat_temuan + anomali_pusat_respons,
-- excel Fasih usaha/keluarga) ke get_anomali_gabungan(). Sumber 'pusat' lama
-- (se2026_anomali_pusat, via v_anomali_pusat_petugas) dianggap duplikat/usang
-- untuk app ini -- masih bisa diakses eksplisit (p_sumber='pusat') karena
-- masih dipakai app lain, tapi TIDAK lagi ikut default (p_sumber=null).
--
-- Default (p_sumber=null) sekarang = 'kualitas' (wilayah) + 'pusat_baru'.

create or replace function public.get_anomali_gabungan(
  p_sumber text default null,      -- 'pusat_baru' | 'kualitas' | 'pusat' (legacy) | null (kualitas+pusat_baru)
  p_kategori text default null,
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
  kategori text,
  subjek text,
  no_anomali integer,
  deskripsi text,
  status_tindak_lanjut text,
  jenis_respons text,
  keterangan text,
  diperiksa_oleh text,
  diperiksa_at timestamptz
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

    -- scoping direplikasi dari get_anomali_wilayah (a.kode_wilayah),
    -- get_anomali_pusat (v.ppl_id/v.pml_id), dan get_anomali_pusat_v2
    -- (t.kode_wilayah, pola sama dgn wilayah).
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
                a.nama_subjek::text,
                a.no_anomali::integer,
                a.deskripsi::text,
                coalesce(t.status_tindak_lanjut, 'belum_diperiksa')::text,
                case
                  when t.status_tindak_lanjut = 'dikonfirmasi_valid' then 'konfirmasi_valid'
                  when t.status_tindak_lanjut in ('dikonfirmasi_salah_entri', 'sudah_diperbaiki') then 'perbaikan'
                  else null
                end::text,
                t.catatan_petugas::text,
                t.diperiksa_oleh::text,
                t.diperiksa_at
            from mv_anomali a
            left join se2026_anomali_temuan t
              on t.assignment_id = a.assignment_id
             and t.kategori = a.kategori::text
             and t.no_anomali = a.no_anomali::integer
        $q$ || v_where_wilayah;

        if p_kategori is not null then
            v_sql := v_sql || format(' and a.kategori::text = %L', p_kategori);
        end if;
        if p_status is not null then
            v_sql := v_sql || format(' and coalesce(t.status_tindak_lanjut, ''belum_diperiksa'') = %L', p_status);
        end if;
    end if;

    if p_sumber = 'pusat' then
        if v_sql <> '' then
            v_sql := v_sql || ' union all ';
        end if;
        -- keterangan pusat legacy sengaja null di sini (bisa multi-baris/
        -- multi-petugas); detail lengkap tetap diambil lewat
        -- get_anomali_pusat_keterangan di layar detail.
        v_sql := v_sql || $q$
            select
                'pusat'::text,
                v.assignment_id,
                v.kode_wilayah,
                concat_ws(' / ', v.nm_kec, v.nm_desa, v.nm_sls),
                v.kategori,
                v.nama,
                null::integer,
                v.nama_anomali,
                coalesce(v.tindak_lanjut, 'belum_diperiksa'),
                null::text,
                null::text,
                null::text,
                null::timestamptz
            from v_anomali_pusat_petugas v
        $q$ || v_where_pusat;

        if p_kategori is not null then
            v_sql := v_sql || format(' and v.kategori::text = %L', p_kategori);
        end if;
        if p_status is not null then
            v_sql := v_sql || format(' and v.status_text::text = %L', p_status);
        end if;
    end if;

    if p_sumber = 'pusat_baru' or p_sumber is null then
        if v_sql <> '' then
            v_sql := v_sql || ' union all ';
        end if;
        -- jenis_respons/keterangan di sini milik user yang login (r_mine),
        -- bukan gabungan semua petugas -- konsisten dengan get_anomali_pusat_v2.
        v_sql := v_sql || $q$
            select
                'pusat_baru'::text,
                t.assignment_id,
                t.kode_wilayah,
                concat_ws(' / ', t.nama_kec, t.nama_desa),
                t.kategori_kode,
                t.nama_subjek,
                null::integer,
                t.kategori_nama,
                coalesce(r_mine.jenis_respons, 'belum_diperiksa'),
                r_mine.jenis_respons,
                r_mine.keterangan,
                p_mine.nama,
                r_mine.updated_at
            from public.anomali_pusat_temuan t
            left join public.anomali_pusat_respons r_mine
              on r_mine.scope = t.scope
             and r_mine.assignment_id = t.assignment_id
             and r_mine.nama_subjek = t.nama_subjek
             and r_mine.kategori_kode = t.kategori_kode
             and r_mine.petugas_id = (select p.id from se2026_petugas p
                                       join users u on u.id = p.user_id
                                       where u.auth_uid = auth.uid() limit 1)
            left join public.se2026_petugas p_mine on p_mine.id = r_mine.petugas_id
        $q$ || v_where_pusat_baru || ' and t.is_active = true';

        if p_kategori is not null then
            v_sql := v_sql || format(' and t.kategori_kode = %L', p_kategori);
        end if;
        if p_status is not null then
            v_sql := v_sql || format(' and coalesce(r_mine.jenis_respons, ''belum_diperiksa'') = %L', p_status);
        end if;
    end if;

    v_sql := v_sql || format(' order by 2, 3 limit %s offset %s', p_limit, p_offset);

    return query execute v_sql;
end;
$function$;
