-- Hitung jumlah anomali pusat yang "perlu saya tanggapi", untuk badge di tab
-- Anomali. Ringan (satu count), scoping & makna menyesuaikan role pemanggil:
--
--   pendata / pengawas -> kasus aktif di wilayah tugasnya yang BELUM ia
--                         beri respons (belum ada baris anomali_pusat_respons
--                         atas namanya). Termasuk kasus ber-'konfirmasi' dari
--                         admin yang belum ia jawab.
--   admin              -> kasus yang SUDAH dijawab petugas (respons
--                         'perbaikan'/'konfirmasi_valid') tapi BELUM admin
--                         verifikasi atau tolak -- backlog keputusan admin.
--                         (Respons 'konfirmasi' dibuat oleh admin sendiri dan
--                         menunggu jawaban petugas, jadi tidak dihitung.)
--
-- Scoping wilayah memakai pola yang sama dengan get_anomali_gabungan.

create or replace function public.get_anomali_pusat_notif_count()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_petugas_id text;
    v_role       text;
    v_count      integer := 0;
begin
    select p.id::text, p.role
    into   v_petugas_id, v_role
    from   users u
    join   se2026_petugas p on p.user_id = u.id
    where  u.auth_uid = auth.uid()
      and  p.is_active = true
    limit  1;

    if v_petugas_id is null then
        return 0;
    end if;

    if v_role = 'admin' then
        select count(*)
        into   v_count
        from   public.anomali_pusat_temuan t
        where  t.is_active
          and  exists (
                   select 1 from public.anomali_pusat_respons r
                   where r.sumber = 'pusat_baru' and r.scope = t.scope
                     and r.assignment_id = t.assignment_id
                     and r.nama_subjek = t.nama_subjek
                     and r.kategori_kode = t.kategori_kode
                     and r.jenis_respons in ('perbaikan', 'konfirmasi_valid'))
          and  not exists (
                   select 1 from public.anomali_pusat_verifikasi vf
                   where vf.scope = t.scope and vf.assignment_id = t.assignment_id
                     and vf.nama_subjek = t.nama_subjek
                     and vf.kategori_kode = t.kategori_kode);
        return v_count;
    end if;

    if v_role not in ('pendata', 'pengawas') then
        return 0;
    end if;

    select count(*)
    into   v_count
    from   public.anomali_pusat_temuan t
    where  t.is_active
      and  left(t.kode_wilayah, 16) in (
               select wt.id from public.se2026_wilayah_tugas wt
               where (v_role = 'pendata'  and wt.ppl_id::text = v_petugas_id)
                  or (v_role = 'pengawas' and wt.pml_id::text = v_petugas_id))
      and  not exists (
               select 1 from public.anomali_pusat_respons r
               where r.sumber = 'pusat_baru' and r.scope = t.scope
                 and r.assignment_id = t.assignment_id
                 and r.nama_subjek = t.nama_subjek
                 and r.kategori_kode = t.kategori_kode
                 and r.petugas_id = v_petugas_id::uuid);
    return v_count;
end;
$function$;

notify pgrst, 'reload schema';
