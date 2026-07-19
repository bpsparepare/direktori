-- Kolom per-baris deskripsi_detail: penjelasan spesifik tiap temuan (mis. nilai
-- pendapatan + nama usaha untuk UW1/UW2). deskripsi_rule tetap per-kategori.
-- get_anomali_gabungan.deskripsi memakai prioritas:
--   deskripsi_detail (per baris) -> deskripsi_rule (per kategori) -> kategori_nama.

alter table public.anomali_pusat_temuan
  add column if not exists deskripsi_detail text;

-- Backfill baris UW1/UW2 yang sudah ada dengan nilai + nama usaha.
update public.anomali_pusat_temuan t
set deskripsi_detail =
      'Total pendapatan usaha "' || t.nama_subjek || '" ' ||
      (case when t.kategori_kode = 'UW1' then 'sangat tinggi' else 'sangat rendah' end) ||
      ': Rp ' ||
      replace(to_char(round(us.total_pendapatan)::bigint, 'FM999,999,999,999'), ',', '.') ||
      ' (perlu dicek).'
from public.se2026_usaha us
where t.scope = 'usaha'
  and t.kategori_kode in ('UW1', 'UW2')
  and us.assignment_id = t.assignment_id
  and coalesce(nullif(btrim(us.nama_usaha), ''),
               nullif(btrim(us.nama_komersial), ''),
               'Usaha ' || us.no_usaha) = t.nama_subjek;

-- insert_anomali_usaha_pendapatan: isi deskripsi_detail per baris.
create or replace function public.insert_anomali_usaha_pendapatan(
  p_jenis text,
  p_items jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_role     text;
    v_kode     text;
    v_nama_kat text;
    v_desk     text;
    v_item     jsonb;
    v_aid      text;
    v_no       integer;
    v_count    integer := 0;
begin
    select p.role into v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        raise exception 'Hanya admin yang dapat memasukkan anomali';
    end if;
    if p_jenis not in ('tinggi', 'rendah') then
        raise exception 'jenis tidak valid: %', p_jenis;
    end if;

    if p_jenis = 'tinggi' then
        v_kode := 'UW1';
        v_nama_kat := 'Pendapatan Anomali Tinggi';
        v_desk := 'Total pendapatan usaha tergolong sangat tinggi (perlu dicek).';
    else
        v_kode := 'UW2';
        v_nama_kat := 'Pendapatan Anomali Rendah';
        v_desk := 'Total pendapatan usaha tergolong sangat rendah (perlu dicek).';
    end if;

    insert into public.anomali_pusat_kategori (anomali_id, scope, kategori, deskripsi_rule)
    values (v_kode, 'usaha', v_nama_kat, v_desk)
    on conflict (anomali_id) do update set kategori = excluded.kategori;

    for v_item in select * from jsonb_array_elements(p_items)
    loop
        v_aid := v_item ->> 'assignment_id';
        v_no  := (v_item ->> 'no_usaha')::integer;

        insert into public.anomali_pusat_temuan (
            scope, assignment_id, nama_subjek,
            kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
            kategori_kode, kategori_nama, deskripsi_detail, status_asal, link_fasih,
            is_active, imported_at, updated_at
        )
        select
            'usaha',
            us.assignment_id,
            coalesce(nullif(btrim(us.nama_usaha), ''),
                     nullif(btrim(us.nama_komersial), ''),
                     'Usaha ' || us.no_usaha),
            left(ku.kode_wilayah, 7),
            wt.nm_kec,
            left(ku.kode_wilayah, 10),
            wt.nm_desa,
            substring(ku.kode_wilayah from 11 for 4),
            substring(ku.kode_wilayah from 15 for 2),
            v_kode, v_nama_kat,
            'Total pendapatan usaha "' ||
              coalesce(nullif(btrim(us.nama_usaha), ''),
                       nullif(btrim(us.nama_komersial), ''),
                       'Usaha ' || us.no_usaha) || '" ' ||
              (case when p_jenis = 'tinggi' then 'sangat tinggi' else 'sangat rendah' end) ||
              ': Rp ' ||
              replace(to_char(round(us.total_pendapatan)::bigint, 'FM999,999,999,999'), ',', '.') ||
              ' (perlu dicek).',
            null,
            'https://fasih-sm.bps.go.id/app/assignment-detail/'
              || us.assignment_id || '/edit',
            true, now(), now()
        from public.se2026_usaha us
        join public.se2026_keterangan_umum ku on ku.assignment_id = us.assignment_id
        left join lateral (
            select w.nm_kec, w.nm_desa
            from public.se2026_wilayah_tugas w
            where w.id = left(ku.kode_wilayah, 16)
            limit 1
        ) wt on true
        where us.assignment_id = v_aid and us.no_usaha = v_no
        on conflict (scope, assignment_id, nama_subjek, kategori_kode)
        do update set
            deskripsi_detail = excluded.deskripsi_detail,
            is_active = true,
            updated_at = now();

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$function$;

-- get_anomali_gabungan: deskripsi memakai deskripsi_detail per baris dulu.
-- Identik dengan 20260708190000 kecuali baris "deskripsi".
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
  verifikasi_status text,
  perlu_tindak_lanjut boolean
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
    v_perlu            text;
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
    v_perlu := case
        when v_role = 'admin' then
            '(vf.status is null and exists (select 1 from public.anomali_pusat_respons rtl'
            || ' where rtl.sumber = ''pusat_baru'' and rtl.scope = t.scope'
            || ' and rtl.assignment_id = t.assignment_id and rtl.nama_subjek = t.nama_subjek'
            || ' and rtl.kategori_kode = t.kategori_kode'
            || ' and rtl.jenis_respons in (''perbaikan'', ''konfirmasi_valid'')))'
        when v_role in ('pendata', 'pengawas') then
            '(r_mine.jenis_respons is null)'
        else 'false'
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
            coalesce(nullif(trim(t.deskripsi_detail), ''), nullif(trim(k.deskripsi_rule), ''), t.kategori_nama),
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
            vf.status,
            $q$ || v_perlu || $q$
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
