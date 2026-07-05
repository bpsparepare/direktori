-- "File gabungan": satu RPC yang menyatukan anomali wilayah (kualitas) dan
-- anomali pusat jadi satu daftar, ditandai kolom `sumber`, plus fungsi
-- verifikasi ulang untuk cabang "perbaiki" (baru dianggap selesai kalau
-- rule tidak lagi mendeteksi kasusnya).
--
-- PERHATIAN: berbeda dari migration sebelumnya, file ini menduplikasi logika
-- scoping akses per role (pendata/pengawas/admin) dari get_anomali_wilayah
-- dan get_anomali_pusat. Review dulu sebelum apply -- salah scoping berarti
-- petugas bisa melihat data di luar wilayah/binaannya.

-- ============================================================
-- 1. VERIFIKASI ULANG (cabang "perbaiki")
-- ============================================================
-- Panggil fungsi ini SETELAH mv_anomali di-refresh (di job/cron yang sama).
-- Kasus yang sebelumnya ditandai "dikonfirmasi_salah_entri" tapi sudah tidak
-- lagi muncul di mv_anomali otomatis naik status jadi "sudah_diperbaiki".
create or replace function public.verifikasi_ulang_anomali_wilayah()
returns integer
language plpgsql
security definer
as $function$
declare
    v_count integer;
begin
    update public.se2026_anomali_temuan t
    set status_tindak_lanjut = 'sudah_diperbaiki',
        updated_at = now()
    where t.status_tindak_lanjut = 'dikonfirmasi_salah_entri'
      and not exists (
        select 1 from mv_anomali a
        where a.assignment_id = t.assignment_id
          and a.kategori::text = t.kategori
          and a.no_anomali::integer = t.no_anomali
      );
    get diagnostics v_count = row_count;
    return v_count;
end;
$function$;

-- ============================================================
-- 2. RPC GABUNGAN
-- ============================================================
create or replace function public.get_anomali_gabungan(
  p_sumber text default null,      -- 'pusat' | 'kualitas' | null (semua)
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
    v_petugas_id    text;
    v_role          text;
    v_where_wilayah text;
    v_where_pusat   text;
    v_sql           text := '';
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

    -- scoping direplikasi persis dari get_anomali_wilayah (kolom a.kode_wilayah)
    -- dan get_anomali_pusat (kolom v.ppl_id/v.pml_id).
    if v_role = 'pendata' then
        v_where_wilayah := format(
            ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
            v_petugas_id);
        v_where_pusat := format(' where v.ppl_id::text = %L', v_petugas_id);

    elsif v_role = 'pengawas' then
        if p_petugas_id is not null then
            v_where_wilayah := format(
                ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
            v_where_pusat := format(' where v.ppl_id::text = %L', p_petugas_id);
        else
            v_where_wilayah := format(
                ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                v_petugas_id);
            v_where_pusat := format(' where v.pml_id::text = %L', v_petugas_id);
        end if;

    elsif v_role = 'admin' then
        if p_petugas_id is not null then
            v_where_wilayah := format(
                ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.ppl_id::text = %L)',
                p_petugas_id);
            v_where_pusat := format(' where v.ppl_id::text = %L', p_petugas_id);
        elsif p_pengawas_id is not null then
            v_where_wilayah := format(
                ' where left(a.kode_wilayah::text, 16) in (select wt.id from se2026_wilayah_tugas wt where wt.pml_id::text = %L)',
                p_pengawas_id);
            v_where_pusat := format(' where v.pml_id::text = %L', p_pengawas_id);
        else
            v_where_wilayah := ' where true';
            v_where_pusat := ' where true';
        end if;

    else
        return;
    end if;

    if p_sumber is null or p_sumber = 'kualitas' then
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

    if p_sumber is null or p_sumber = 'pusat' then
        if v_sql <> '' then
            v_sql := v_sql || ' union all ';
        end if;
        -- keterangan pusat sengaja null di sini (bisa multi-baris/multi-petugas);
        -- detail lengkap tetap diambil lewat get_anomali_pusat_keterangan di layar detail.
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

    v_sql := v_sql || format(' order by 2, 3 limit %s offset %s', p_limit, p_offset);

    return query execute v_sql;
end;
$function$;
