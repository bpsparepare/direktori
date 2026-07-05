-- ============================================================
-- 3. RPC gabungan: upsert & baca thread respons (dipakai kedua sumber)
-- ============================================================
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
begin
    if p_sumber not in ('kualitas', 'pusat_baru') then
        raise exception 'sumber tidak valid: %', p_sumber;
    end if;
    if p_jenis_respons not in ('perbaikan', 'konfirmasi_valid') then
        raise exception 'jenis_respons tidak valid: %', p_jenis_respons;
    end if;
    if p_jenis_respons = 'konfirmasi_valid'
       and (p_keterangan is null or length(trim(p_keterangan)) = 0) then
        raise exception 'Keterangan wajib diisi untuk konfirmasi data benar';
    end if;

    select p.id into v_petugas_id
    from public.se2026_petugas p
    join public.users u on u.id = p.user_id
    where u.auth_uid = auth.uid() and p.is_active = true
    limit 1;

    if v_petugas_id is null then
        raise exception 'Petugas tidak ditemukan';
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

create or replace function public.get_anomali_respons(
  p_sumber text,
  p_scope text,
  p_assignment_id text,
  p_kategori_kode text,
  p_nama_subjek text default ''
)
returns table(
  petugas_id uuid,
  nama_petugas text,
  role text,
  jenis_respons text,
  keterangan text,
  updated_at timestamptz
)
language plpgsql
security definer
as $function$
begin
    return query
    select
        r.petugas_id,
        p.nama as nama_petugas,
        p.role,
        r.jenis_respons,
        r.keterangan,
        r.updated_at
    from public.anomali_pusat_respons r
    join public.se2026_petugas p on p.id = r.petugas_id
    where r.sumber = p_sumber
      and r.scope = p_scope
      and r.assignment_id = p_assignment_id
      and r.nama_subjek = p_nama_subjek
      and r.kategori_kode = p_kategori_kode
    order by r.updated_at desc;
end;
$function$;
