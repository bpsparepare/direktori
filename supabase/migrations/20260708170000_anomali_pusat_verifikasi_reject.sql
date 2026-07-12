-- Tambah status verifikasi admin: selain 'verified' (disetujui), kini bisa
-- 'rejected' (ditolak admin). Sebelumnya keberadaan baris di
-- anomali_pusat_verifikasi = terverifikasi; sekarang baris selalu ada saat
-- admin bertindak, dengan kolom `status` yang membedakan setuju vs tolak.
-- Tidak ada baris = admin belum bertindak.

alter table public.anomali_pusat_verifikasi
  add column if not exists status text not null default 'verified'
    check (status in ('verified', 'rejected'));

-- set_anomali_pusat_verifikasi: ganti p_verified boolean -> p_status text.
--   p_status null           -> hapus (batalkan tindakan admin)
--   p_status 'verified'     -> tandai disetujui
--   p_status 'rejected'     -> tandai ditolak
drop function if exists public.set_anomali_pusat_verifikasi(
  text, text, text, text, boolean, text
);

create or replace function public.set_anomali_pusat_verifikasi(
  p_scope text,
  p_assignment_id text,
  p_nama_subjek text,
  p_kategori_kode text,
  p_status text default null,
  p_catatan text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_petugas_id uuid;
    v_role       text;
begin
    select p.id, p.role
    into   v_petugas_id, v_role
    from   public.se2026_petugas p
    join   public.users u on u.id = p.user_id
    where  u.auth_uid = auth.uid() and p.is_active = true
    limit  1;

    if v_petugas_id is null then
        raise exception 'Petugas tidak ditemukan';
    end if;
    if v_role not in ('pengawas', 'admin') then
        raise exception 'Hanya PML/admin yang dapat memverifikasi';
    end if;

    if p_status is null then
        delete from public.anomali_pusat_verifikasi
        where scope = p_scope
          and assignment_id = p_assignment_id
          and nama_subjek = p_nama_subjek
          and kategori_kode = p_kategori_kode;
        return;
    end if;

    if p_status not in ('verified', 'rejected') then
        raise exception 'status verifikasi tidak valid: %', p_status;
    end if;

    insert into public.anomali_pusat_verifikasi (
        scope, assignment_id, nama_subjek, kategori_kode,
        petugas_id, status, catatan, updated_at
    ) values (
        p_scope, p_assignment_id, p_nama_subjek, p_kategori_kode,
        v_petugas_id, p_status, p_catatan, now()
    )
    on conflict (scope, assignment_id, nama_subjek, kategori_kode)
    do update set
        petugas_id = excluded.petugas_id,
        status     = excluded.status,
        catatan    = excluded.catatan,
        updated_at = now();
end;
$function$;

-- get_anomali_gabungan + kolom verifikasi_status (vf.status). Sisanya identik
-- dengan 20260708160000_anomali_gabungan_deskripsi_rule.sql (deskripsi_rule
-- + agregat respons).
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
  nama_pml text,
  verified_at timestamptz,
  verified_oleh text,
  boleh_verifikasi boolean,
  ada_konfirmasi boolean,
  jenis_semua text,
  keterangan_semua text,
  verifikasi_status text
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
    v_verif_at         text;
    v_verif_by         text;
    v_can_verify       text;
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

    v_petugas_col := case when v_role in ('pengawas', 'admin') then 'ppl.nama' else 'null::text' end;
    v_pml_col     := case when v_role in ('pengawas', 'admin') then 'pml.nama' else 'null::text' end;
    v_verif_at    := case when v_role = 'admin' then 'vf.updated_at' else 'null::timestamptz' end;
    v_verif_by    := case when v_role = 'admin' then 'vp.nama' else 'null::text' end;
    v_can_verify  := case when v_role = 'admin' then 'true' else 'false' end;

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
            coalesce(nullif(trim(k.deskripsi_rule), ''), t.kategori_nama),
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
            $q$ || v_pml_col || $q$,
            $q$ || v_verif_at || $q$,
            $q$ || v_verif_by || $q$,
            $q$ || v_can_verify || $q$,
            (exists (select 1 from public.anomali_pusat_respons rk
                     where rk.sumber = 'pusat_baru' and rk.scope = t.scope
                       and rk.assignment_id = t.assignment_id
                       and rk.nama_subjek = t.nama_subjek
                       and rk.kategori_kode = t.kategori_kode
                       and rk.jenis_respons = 'konfirmasi')),
            (select string_agg(distinct
                      case rr.jenis_respons
                        when 'perbaikan' then 'Salah Input'
                        when 'konfirmasi_valid' then 'Data Benar'
                        when 'konfirmasi' then 'Konfirmasi'
                        else rr.jenis_respons end, ', ')
             from public.anomali_pusat_respons rr
             where rr.sumber = 'pusat_baru' and rr.scope = t.scope
               and rr.assignment_id = t.assignment_id
               and rr.nama_subjek = t.nama_subjek
               and rr.kategori_kode = t.kategori_kode),
            (select string_agg(
                      pp.nama || ' (' ||
                      (case rr.jenis_respons
                         when 'perbaikan' then 'Salah Input'
                         when 'konfirmasi_valid' then 'Data Benar'
                         when 'konfirmasi' then 'Konfirmasi'
                         else rr.jenis_respons end) || '): ' ||
                      coalesce(nullif(trim(rr.keterangan), ''), '-'),
                      ' | ' order by rr.updated_at)
             from public.anomali_pusat_respons rr
             join public.se2026_petugas pp on pp.id = rr.petugas_id
             where rr.sumber = 'pusat_baru' and rr.scope = t.scope
               and rr.assignment_id = t.assignment_id
               and rr.nama_subjek = t.nama_subjek
               and rr.kategori_kode = t.kategori_kode),
            vf.status
        from public.anomali_pusat_temuan t
        left join public.anomali_pusat_kategori k on k.anomali_id = t.kategori_kode
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
        left join public.anomali_pusat_verifikasi vf
          on vf.scope = t.scope
         and vf.assignment_id = t.assignment_id
         and vf.nama_subjek = t.nama_subjek
         and vf.kategori_kode = t.kategori_kode
        left join public.se2026_petugas vp on vp.id = vf.petugas_id
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
