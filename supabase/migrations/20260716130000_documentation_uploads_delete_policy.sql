-- Izinkan pengguna menghapus baris dokumentasi miliknya sendiri.
drop policy if exists "documentation_uploads_delete_own" on public.documentation_uploads;
create policy "documentation_uploads_delete_own"
on public.documentation_uploads
for delete
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = documentation_uploads.user_id
      and u.auth_uid = auth.uid()
  )
);
