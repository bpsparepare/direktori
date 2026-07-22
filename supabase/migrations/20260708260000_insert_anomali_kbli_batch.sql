-- Tandai banyak usaha sebagai anomali UW3 sekaligus dengan catatan yang sama.

create or replace function public.insert_anomali_kbli_batch(
  p_items jsonb,       -- [{assignment_id, no_usaha}, ...]
  p_komentar text
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_role      text;
    v_admin_id  uuid;
    v_item      jsonb;
    v_aid       text;
    v_no        integer;
    v_nama_subj text;
    v_count     integer := 0;
begin
    select p.id, p.role into v_admin_id, v_role
    from se2026_petugas p join users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;
    if v_role is distinct from 'admin' then
        raise exception 'Hanya admin yang dapat menandai anomali KBLI';
    end if;
    if p_komentar is null or length(btrim(p_komentar)) = 0 then
        raise exception 'Catatan koreksi KBLI wajib diisi';
    end if;

    insert into public.anomali_pusat_kategori (anomali_id, scope, kategori, deskripsi_rule)
    values ('UW3', 'usaha', 'Salah Penentuan KBLI',
            'KBLI kemungkinan tidak sesuai kegiatan utama/produk usaha.')
    on conflict (anomali_id) do update set kategori = excluded.kategori;

    for v_item in select * from jsonb_array_elements(p_items)
    loop
        v_aid := v_item ->> 'assignment_id';
        v_no  := (v_item ->> 'no_usaha')::integer;

        select coalesce(nullif(btrim(us.nama_usaha), ''),
                        nullif(btrim(us.nama_komersial), ''),
                        'Usaha ' || us.no_usaha)
        into v_nama_subj
        from public.se2026_usaha us
        where us.assignment_id = v_aid and us.no_usaha = v_no;

        if v_nama_subj is null then
            continue;
        end if;

        insert into public.anomali_pusat_temuan (
            scope, assignment_id, nama_subjek,
            kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
            kategori_kode, kategori_nama, deskripsi_detail, status_asal, link_fasih,
            is_active, imported_at, updated_at
        )
        select
            'usaha', us.assignment_id, v_nama_subj,
            left(ku.kode_wilayah, 7), wt.nm_kec,
            left(ku.kode_wilayah, 10), wt.nm_desa,
            substring(ku.kode_wilayah from 11 for 4),
            substring(ku.kode_wilayah from 15 for 2),
            'UW3', 'Salah Penentuan KBLI',
            'KBLI: ' || coalesce(nullif(btrim(us.kbli_akhir), ''), '-')
              || ' · Keg utama: ' || coalesce(nullif(btrim(us.keg_utama), ''), '-')
              || ' · Produk: ' || coalesce(nullif(btrim(us.produk), ''), '-'),
            null,
            'https://fasih-sm.bps.go.id/app/assignment-detail/'
              || us.assignment_id || '/edit',
            true, now(), now()
        from public.se2026_usaha us
        join public.se2026_keterangan_umum ku on ku.assignment_id = us.assignment_id
        left join lateral (
            select w.nm_kec, w.nm_desa from public.se2026_wilayah_tugas w
            where w.id = left(ku.kode_wilayah, 16) limit 1
        ) wt on true
        where us.assignment_id = v_aid and us.no_usaha = v_no
        on conflict (scope, assignment_id, nama_subjek, kategori_kode)
        do update set
            deskripsi_detail = excluded.deskripsi_detail,
            is_active = true,
            updated_at = now();

        insert into public.anomali_pusat_respons (
            sumber, scope, assignment_id, nama_subjek, kategori_kode,
            petugas_id, jenis_respons, keterangan, updated_at
        ) values (
            'pusat_baru', 'usaha', v_aid, v_nama_subj, 'UW3',
            v_admin_id, 'konfirmasi', btrim(p_komentar), now()
        )
        on conflict on constraint anomali_pusat_respons_unique_key
        do update set
            jenis_respons = excluded.jenis_respons,
            keterangan    = excluded.keterangan,
            updated_at    = now();

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$function$;

notify pgrst, 'reload schema';
