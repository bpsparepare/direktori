-- import_anomali_pusat_batch: JANGAN menimpa deskripsi_rule pada
-- anomali_pusat_kategori saat re-import. deskripsi_rule diisi/di-edit manual
-- (dipakai sebagai deskripsi anomali di get_anomali_gabungan), jadi hanya
-- di-seed saat kategori pertama kali muncul (INSERT), tidak diubah lagi
-- (ON CONFLICT). Sisa fungsi identik dengan 20260706120000.

create or replace function public.import_anomali_pusat_batch(
  p_scope text,
  p_rows jsonb,
  p_mode text default 'refresh'
)
returns table(diperbarui integer, dinonaktifkan integer, dihapus integer)
language plpgsql
security definer
as $function$
declare
    v_row           jsonb;
    v_nama_anomali  text;
    v_kategori_kode text;
    v_kategori_nama text;
    v_prefix        text;
    v_match         text[];
    v_count         integer := 0;
    v_deactivated   integer := 0;
    v_deleted       integer := 0;
    v_keys          text[] := '{}';
begin
    if p_scope not in ('usaha', 'keluarga') then
        raise exception 'scope tidak valid: %', p_scope;
    end if;
    if p_mode not in ('refresh', 'replace', 'tambahkan') then
        raise exception 'mode tidak valid: %', p_mode;
    end if;

    v_prefix := case when p_scope = 'usaha' then 'UP' else 'KP' end;

    if p_mode = 'refresh' then
        update public.anomali_pusat_temuan
        set is_active = false, updated_at = now()
        where scope = p_scope;
        get diagnostics v_deactivated = row_count;
    end if;

    for v_row in select * from jsonb_array_elements(p_rows)
    loop
        v_nama_anomali := v_row ->> 'nama_anomali';

        v_match := regexp_match(
            coalesce(v_nama_anomali, ''),
            'Anomali\s+(?:Data\s+)?(\d+)\s*\(([^)]*)\)'
        );

        if v_match is null then
            v_kategori_kode := v_prefix || 'LAINNYA';
            v_kategori_nama := coalesce(nullif(v_nama_anomali, ''), '-');
        else
            v_kategori_kode := v_prefix || v_match[1];
            v_kategori_nama := trim(v_match[2]);
        end if;

        -- deskripsi_rule hanya diseed saat INSERT (kategori baru); saat konflik
        -- TIDAK diubah supaya penjelasan manual tidak tertimpa.
        insert into public.anomali_pusat_kategori (
            anomali_id, scope, kategori, deskripsi_rule
        ) values (
            v_kategori_kode, p_scope, v_kategori_nama, v_nama_anomali
        )
        on conflict (anomali_id) do update set
            scope    = excluded.scope,
            kategori = excluded.kategori;

        insert into public.anomali_pusat_temuan (
            scope, assignment_id, nama_subjek,
            kode_prov, nama_provinsi, kode_kab, nama_kab,
            kode_kec, nama_kec, kode_desa, nama_desa, kode_sls, sub_sls,
            kategori_kode, kategori_nama, status_asal,
            id_petugas_asal, email_petugas_asal, link_fasih,
            is_active, imported_at, updated_at
        ) values (
            p_scope,
            v_row ->> 'assignment_id',
            v_row ->> 'nama_subjek',
            v_row ->> 'kode_prov', v_row ->> 'nama_provinsi',
            v_row ->> 'kode_kab', v_row ->> 'nama_kab',
            v_row ->> 'kode_kec', v_row ->> 'nama_kec',
            v_row ->> 'kode_desa', v_row ->> 'nama_desa',
            v_row ->> 'kode_sls', v_row ->> 'sub_sls',
            v_kategori_kode, v_kategori_nama,
            v_row ->> 'tindak_lanjut',
            nullif(v_row ->> 'id_petugas', '-'),
            nullif(v_row ->> 'email_petugas', '-'),
            v_row ->> 'link_fasih',
            true, now(), now()
        )
        on conflict (scope, assignment_id, nama_subjek, kategori_kode)
        do update set
            nama_provinsi       = excluded.nama_provinsi,
            nama_kab            = excluded.nama_kab,
            nama_kec            = excluded.nama_kec,
            nama_desa           = excluded.nama_desa,
            kode_kec            = excluded.kode_kec,
            kode_desa           = excluded.kode_desa,
            kode_sls            = excluded.kode_sls,
            sub_sls             = excluded.sub_sls,
            kategori_nama       = excluded.kategori_nama,
            status_asal         = excluded.status_asal,
            id_petugas_asal     = excluded.id_petugas_asal,
            email_petugas_asal  = excluded.email_petugas_asal,
            link_fasih          = excluded.link_fasih,
            is_active           = true,
            updated_at          = now();

        v_count := v_count + 1;
        v_keys := v_keys || (
            (v_row ->> 'assignment_id') || '||' ||
            (v_row ->> 'nama_subjek') || '||' ||
            v_kategori_kode
        );
    end loop;

    if p_mode = 'replace' then
        delete from public.anomali_pusat_temuan t
        where t.scope = p_scope
          and (t.assignment_id || '||' || t.nama_subjek || '||' || t.kategori_kode)
              <> all (v_keys);
        get diagnostics v_deleted = row_count;
    end if;

    return query select v_count, v_deactivated, v_deleted;
end;
$function$;
