async function readResume(input) {
  const file = input.files[0];
  if (!file) return null;
  if (file.size > 2 * 1024 * 1024 || await file.slice(0, 5).text() !== '%PDF-') {
    throw new Error('Choose a PDF résumé of 2 MB or less.');
  }
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result.split(',')[1]);
    reader.onerror = () => reject(new Error('Could not read the selected PDF. Please select it again.'));
    reader.readAsDataURL(file);
  });
}

function enableResumeDownloads(container, client) {
  container.addEventListener('click', async event => {
    const button = event.target.closest('button[data-resume]');
    if (!button) return;
    button.disabled = true;
    try {
      const { data, error } = await client.from('application_resumes')
        .select('pdf').eq('id', button.dataset.resume).single();
      if (error) throw new Error('Unable to download this résumé. Please sign in and try again.');
      const bytes = Uint8Array.from(atob(data.pdf), char => char.charCodeAt(0));
      const url = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
      const link = document.createElement('a');
      link.href = url;
      link.download = 'resume.pdf';
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    } catch (error) {
      alert(error.message);
    } finally {
      button.disabled = false;
    }
  });
}
