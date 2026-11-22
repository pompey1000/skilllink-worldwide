-- Private resume storage. The owner can upload/read their own files.
-- Employer downloads must use a separately authenticated server function.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('job-resumes','job-resumes',false,5242880,array['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;
create policy "Applicants upload own resume" on storage.objects for insert to authenticated
with check(bucket_id='job-resumes' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Applicants read own resume" on storage.objects for select to authenticated
using(bucket_id='job-resumes' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Applicants delete own resume" on storage.objects for delete to authenticated
using(bucket_id='job-resumes' and (storage.foldername(name))[1]=(select auth.uid())::text);
