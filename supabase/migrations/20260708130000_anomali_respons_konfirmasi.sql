-- Jenis respons baru 'konfirmasi' (khusus admin), + flag ada_konfirmasi di
-- get_anomali_gabungan, + RPC hitung notifikasi konfirmasi untuk petugas/PML.

-- 1) Izinkan jenis_respons 'konfirmasi'.
alter table public.anomali_pusat_respons
  drop constraint if exists anomali_pusat_respons_jenis_respons_check;
alter table public.anomali_pusat_respons
  add constraint anomali_pusat_respons_jenis_respons_check
  check (jenis_respons = any (array['perbaikan', 'konfirmasi_valid', 'konfirmasi']));

-- 2) upsert respons menerima 'konfirmasi'.
create or replace function public.upsert_anomali_respons(
  p_sumber text,
  p_scope text,
  p_assignment_id text,
  p_kategori_kode text,
  p_jenis_respons text,
  p_nama_subjek text default '',
  p_keterangan text default null
)
returns void
language plpgsql
security definer
as $function$
declare
    v_petugas_id uuid;
    v_role       text;
begin
    if p_sumber not in ('kualitas', 'pusat_baru') then
        raise exception 'sumber tidak valid: %', p_sumber;
    end if;
    if p_jenis_respons not in ('perbaikan', 'konfirmasi_valid', 'konfirmasi') then
        raise exception 'jenis_respons tidak valid: %', p_jenis_respons;
    end if;
    if p_jenis_respons = 'konfirmasi_valid'
       and (p_keterangan is null or length(trim(p_keterangan)) = 0) then
        raise exception 'Keterangan wajib diisi untuk konfirmasi data benar';
    end if;

    select p.id, p.role into v_petugas_id, v_role
    from public.se2026_petugas p
    join public.users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;

    if v_petugas_id is null then
        raise exception 'Petugas tidak ditemukan';
    end if;
    if p_jenis_respons = 'konfirmasi' and v_role <> 'admin' then
        raise exception 'Hanya admin yang dapat memberi respons Konfirmasi';
    end if;

    insert into public.anomali_pusat_respons (
        sumber, scope, assignment_id, nama_subjek, kategori_kode,
        petugas_id, jenis_respons, keterangan, updated_at
    ) values (
        p_sumber, p_scope, p_assignment_id, p_nama_subjek, p_kategori_kode,
        v_petugas_id, p_jenis_respons, p_keterangan, now()
    )
    on conflict on constraint anomali_pusat_respons_unique_key
    do update set
        jenis_respons = excluded.jenis_respons,
        keterangan    = excluded.keterangan,
        updated_at    = now();
end;
$function$;

-- 3) Hitung notifikasi konfirmasi: kasus di wilayah petugas/PML yang punya
-- respons 'konfirmasi' (dari admin) DAN belum ditanggapi petugas ybs.
create or replace function public.get_anomali_konfirmasi_count()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_petugas_id text;
    v_role       text;
    v_scope_col  text;
    v_count      integer := 0;
begin
    select p.id::text, p.role
    into   v_petugas_id, v_role
    from   users u
    join   se2026_petugas p on p.user_id = u.id
    where  u.auth_uid = auth.uid() and p.is_active = true
    limit  1;

    if v_petugas_id is null then
        return 0;
    end if;

    if v_role = 'pendata' then
        v_scope_col := 'ppl_id';
    elsif v_role = 'pengawas' then
        v_scope_col := 'pml_id';
    else
        -- admin adalah pembuat konfirmasi, bukan penerima notifikasi.
        return 0;
    end if;

    execute format($q$
        select count(*)::integer
        from public.anomali_pusat_temuan t
        where t.is_active = true
          and left(t.kode_wilayah, 16) in (
              select wt.id from public.se2026_wilayah_tugas wt
              where wt.%I::text = %L)
          and exists (
              select 1 from public.anomali_pusat_respons rk
              where rk.sumber = 'pusat_baru' and rk.scope = t.scope
                and rk.assignment_id = t.assignment_id
                and rk.nama_subjek = t.nama_subjek
                and rk.kategori_kode = t.kategori_kode
                and rk.jenis_respons = 'konfirmasi')
          and not exists (
              select 1 from public.anomali_pusat_respons rm
              join public.se2026_petugas p2 on p2.id = rm.petugas_id
              join public.users u2 on u2.id = p2.user_id
              where rm.sumber = 'pusat_baru' and rm.scope = t.scope
                and rm.assignment_id = t.assignment_id
                and rm.nama_subjek = t.nama_subjek
                and rm.kategori_kode = t.kategori_kode
                and u2.auth_uid = auth.uid())
    $q$, v_scope_col, v_petugas_id)
    into v_count;

    return v_count;
end;
$function$;

-- 4) get_anomali_gabungan + kolom ada_konfirmasi.
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
  ada_konfirmasi boolean
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
            $q$ || v_pml_col || $q$,
            $q$ || v_verif_at || $q$,
            $q$ || v_verif_by || $q$,
            $q$ || v_can_verify || $q$,
            (exists (select 1 from public.anomali_pusat_respons rk
                     where rk.sumber = 'pusat_baru' and rk.scope = t.scope
                       and rk.assignment_id = t.assignment_id
                       and rk.nama_subjek = t.nama_subjek
                       and rk.kategori_kode = t.kategori_kode
                       and rk.jenis_respons = 'konfirmasi'))
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
