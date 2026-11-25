const applicationForm = document.getElementById('application-profile');
const profileStatus = document.getElementById('application-profile-status');
let applicationOwner;
let profileRevision = 0;

async function loadApplicationProfile(user) {
  const owner = user?.id || null;
  if (applicationOwner === owner) return;
  applicationOwner = owner;
  const revision = ++profileRevision;
  applicationForm.reset();
  applicationForm.hidden = !owner;
  profileStatus.textContent = '';
  if (!owner) return;
  const fields = applicationForm.querySelector('fieldset');
  fields.disabled = true;
  const {data, error} = await db.from('worker_application_profiles')
    .select('experience,has_resume').eq('worker_id', owner).maybeSingle();
  if (revision !== profileRevision) return;
  if (error) {
    profileStatus.textContent = 'Your application profile could not load. Refresh to try again.';
    return;
  }
  fields.disabled = false;
  applicationForm.elements.experience.value = data?.experience || '';
  applicationForm.elements.removeResume.parentElement.hidden = !data?.has_resume;
  profileStatus.textContent = data?.has_resume ? 'A résumé is saved.' : '';
}

applicationForm.addEventListener('submit', async event => {
  event.preventDefault();
  const owner = applicationOwner;
  if (!owner) return;
  const fields = applicationForm.querySelector('fieldset');
  const file = applicationForm.elements.resume.files[0];
  const remove = applicationForm.elements.removeResume.checked;
  const changes = {worker_id: owner, experience: applicationForm.elements.experience.value.trim()};
  fields.disabled = true;
  try {
    if (file && remove) throw Error('Choose either a replacement or removal.');
    if (file) {
      if (file.size > 1048576 || await file.slice(0,5).text() !== '%PDF-')
        throw Error('Choose a PDF of 1 MB or less.');
      changes.resume_pdf = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result.split(',')[1]);
        reader.onerror = () => reject(Error('Unable to read the file.'));
        reader.readAsDataURL(file);
      });
    } else if (remove) changes.resume_pdf = null;
    if (owner !== applicationOwner) return;
    const {data,error} = await db.from('worker_application_profiles')
      .upsert(changes).select('has_resume').single();
    if (error) throw error;
    if (owner !== applicationOwner) return;
    applicationForm.elements.resume.value = '';
    applicationForm.elements.removeResume.checked = false;
    applicationForm.elements.removeResume.parentElement.hidden = !data.has_resume;
    profileStatus.textContent = data.has_resume ? 'Profile saved with résumé.' : 'Profile saved without a résumé.';
  } catch (error) {
    if (owner === applicationOwner) profileStatus.textContent = error.message;
  } finally {
    if (owner === applicationOwner) fields.disabled = false;
  }
});
