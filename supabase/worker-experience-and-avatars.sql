-- Optional worker experience and profile photo.
alter table public.provider_profiles
  add column if not exists years_experience integer,
  add column if not exists profile_photo_path text;
alter table public.provider_profiles
  drop constraint if exists provider_profiles_years_experience_check;
alter table public.provider_profiles
  add constraint provider_profiles_years_experience_check
  check (years_experience is null or (years_experience >= 0 and years_experience <= 80));
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('worker-avatars','worker-avatars',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "worker avatar public read" on storage.objects;
create policy "worker avatar public read" on storage.objects for select to public using (bucket_id='worker-avatars');
drop policy if exists "worker avatar own upload" on storage.objects;
create policy "worker avatar own upload" on storage.objects for insert to authenticated with check (bucket_id='worker-avatars' and (storage.foldername(name))[1] = auth.uid()::text and exists (select 1 from public.provider_profiles where user_id=auth.uid()));
drop policy if exists "worker avatar own delete" on storage.objects;
create policy "worker avatar own delete" on storage.objects for delete to authenticated using (bucket_id='worker-avatars' and (storage.foldername(name))[1] = auth.uid()::text);
