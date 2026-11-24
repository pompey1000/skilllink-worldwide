// Only the provider's explicit Start action creates a sharing session.
let activeTrip = null;
function tripControls(booking, customer) {
  if (booking.status !== 'accepted') return '';
  const id = safe(booking.id);
  if (customer) return '<div data-trip-view="'+id+'"><button type="button" class="btn alt" data-trip-show>View provider location</button><p role="status"></p></div>';
  const sharing = activeTrip?.booking === booking.id;
  return '<div><button type="button" class="btn alt" data-trip-toggle="'+id+'">'+
    (sharing ? 'Arrived / stop sharing' : 'On my way — share location')+'</button></div>';
}

function refreshTripButtons() {
  for (const button of document.querySelectorAll('[data-trip-toggle]')) {
    button.textContent = button.dataset.tripToggle === activeTrip?.booking ? 'Arrived / stop sharing' : 'On my way — share location';
  }
}

async function stopTrip(message) {
  const session = activeTrip;
  activeTrip = null;
  refreshTripButtons();
  if (!session) return;
  clearTimeout(session.timer);
  el('booking-status').textContent = message;
  if (session.token) {
    const {error} = await db.rpc('stop_booking_trip', {p_token: session.token});
    if (error && !activeTrip) el('booking-status').textContent = message+' The last shared point expires within a minute.';
  }
}

async function updateTrip(session) {
  if (session !== activeTrip) return;
  try {
    const position = await new Promise((resolve,reject) => navigator.geolocation.getCurrentPosition(resolve,reject,
      {maximumAge:0,timeout:15000,enableHighAccuracy:true}));
    if (session !== activeTrip) return;
    const {data,error} = await db.rpc('update_booking_trip',{p_token:session.token,
      p_lat:position.coords.latitude,p_lon:position.coords.longitude});
    if (session !== activeTrip) return;
    if (error || !data) throw new Error();
    el('booking-status').textContent = 'Sharing with this customer. Tap Arrived / stop sharing when you reach the job.';
    session.timer = setTimeout(() => updateTrip(session),15000);
  } catch {
    if (session === activeTrip) await stopTrip('Location sharing stopped. Check location permission and your connection before trying again.');
  }
}

async function showTrip(view) {
  const status = view.querySelector('p');
  const {data,error} = await db.rpc('read_booking_trip',{p_booking:view.dataset.tripView});
  if (!view.isConnected || !view.dataset.following) return;
  status.replaceChildren();
  const point = data?.[0];
  if (error || !point) {
    status.textContent = error ? 'Location unavailable.' : 'Your provider is not currently sharing a location.';
    return;
  }
  const link = document.createElement('a');
  link.href='https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(point.latitude+','+point.longitude);
  link.target='_blank'; link.rel='noopener noreferrer'; link.textContent='Open latest position in Maps';
  status.append('Updated '+new Date(point.updated_at).toLocaleTimeString()+' · ',link);
}

function initializeBookingTrips() {
  const list = el('booking-list');
  list.addEventListener('click', async event => {
    const viewButton = event.target.closest('[data-trip-show]');
    if (viewButton) {
      const view=viewButton.closest('[data-trip-view]');
      view.dataset.following='yes'; await showTrip(view); return;
    }
    const button = event.target.closest('[data-trip-toggle]');
    if (!button || !activeUser) return;
    const booking = button.dataset.tripToggle;
    if (booking === activeTrip?.booking) { await stopTrip('Location sharing stopped.'); return; }
    if (!navigator.geolocation) { el('booking-status').textContent='This device does not support GPS sharing.'; return; }
    if (!confirm('Share your current location with this booking’s customer during your trip? Keep this page open. Tap Arrived / stop sharing at any time.')) return;
    await stopTrip('Previous trip ended.');
    const session={booking,token:null,timer:null};
    activeTrip=session;refreshTripButtons();
    const {data,error}=await db.rpc('start_booking_trip',{p_booking:booking});
    if (activeTrip !== session) { if(data) await db.rpc('stop_booking_trip',{p_token:data}); return; }
    if (error) { await stopTrip('Could not start sharing for this booking.'); return; }
    session.token=data;
    await updateTrip(session);
  });
  setInterval(() => {
    for(const view of list.querySelectorAll('[data-trip-view][data-following]')) {
      if (!document.hidden && !view.closest('[hidden]')) showTrip(view);
    }
  },15000);
  window.addEventListener('pagehide',()=>stopTrip('Location sharing stopped.'));
  document.addEventListener('visibilitychange',()=>{if(document.hidden) stopTrip('Location sharing stopped when the page was hidden.');});
}
