-- Progres pemeriksaan anomali pusat (untuk grafik donut di tab Anomali).
--
-- Mengembalikan agregat total & "sudah diperiksa" (ada respons di
-- anomali_pusat_respons) dengan breakdown per grup sesuai role:
--   - admin (tanpa filter)      -> per PML  (dimensi = 'pml')
--   - admin + p_pengawas_id     -> per PPL di bawah PML itu (dimensi = 'ppl')
--   - admin/pengawas + p_petugas_id -> PPL tsb saja (dimensi = 'ppl')
--   - pengawas (tanpa filter)   -> per PPL wilayahnya (dimensi = 'ppl')
--   - pendata                   -> dirinya sendiri (dimensi = 'self')
--
-- Overall = jumlahkan semua baris di sisi klien.

create or replace function public.get_anomali_pusat_progress(
  p_pengawas_id text default null,
  p_petugas_id text default null
)
returns table(
  dimensi text,
  grup_id text,
  grup_nama text,
  total integer,
  sudah integer
)
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_petugas_id text;
    v_role       text;
    v_dim        text;
    v_filter_ppl text := null;
    v_filter_pml text := null;
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
        v_dim := 'self';
        v_filter_ppl := v_petugas_id;
    elsif v_role = 'pengawas' then
        v_dim := 'ppl';
        if p_petugas_id is not null then
            v_filter_ppl := p_petugas_id;
        else
            v_filter_pml := v_petugas_id;
        end if;
    elsif v_role = 'admin' then
        if p_petugas_id is not null then
            v_dim := 'ppl';
            v_filter_ppl := p_petugas_id;
        elsif p_pengawas_id is not null then
            v_dim := 'ppl';
            v_filter_pml := p_pengawas_id;
        else
            v_dim := 'pml';
        end if;
    else
        return;
    end if;

    return query
    with base as (
        select
            t.scope, t.assignment_id, t.nama_subjek, t.kategori_kode,
            wt.ppl_id, wt.pml_id
        from public.anomali_pusat_temuan t
        left join lateral (
            select w.ppl_id, w.pml_id
            from public.se2026_wilayah_tugas w
            where w.id = left(t.kode_wilayah, 16)
            limit 1
        ) wt on true
        where t.is_active = true
          and t.scope in ('usaha', 'keluarga')
          and (v_filter_ppl is null or wt.ppl_id::text = v_filter_ppl)
          and (v_filter_pml is null or wt.pml_id::text = v_filter_pml)
    ),
    flagged as (
        select
            b.*,
            case when v_dim = 'pml' then b.pml_id else b.ppl_id end as grup_uuid,
            exists (
                select 1 from public.anomali_pusat_respons r
                where r.sumber = 'pusat_baru'
                  and r.scope = b.scope
                  and r.assignment_id = b.assignment_id
                  and r.nama_subjek = b.nama_subjek
                  and r.kategori_kode = b.kategori_kode
            ) as sudah_flag
        from base b
    )
    select
        v_dim,
        f.grup_uuid::text,
        coalesce(gp.nama, '(Tanpa wilayah tugas)'),
        count(*)::integer,
        count(*) filter (where f.sudah_flag)::integer
    from flagged f
    left join public.se2026_petugas gp on gp.id = f.grup_uuid
    group by f.grup_uuid, gp.nama
    order by 3;
end;
$function$;

notify pgrst, 'reload schema';
