// Content-state dates use Swift's reference epoch; plan dates are normalized at upload.
export function contentDate(value) {
  return new Date(typeof value === 'number' ? (value + 978307200) * 1000 : value);
}

export function reminderEvents(state = {}, events) {
  if (!state.isReminderActive) return [];
  if (Array.isArray(events) && events.length) return events;
  return (state.reminderPerformanceIDs ?? [state.reminderArtistName]).filter(Boolean).map(performanceID => ({
    performanceID, startsAt: state.reminderStartsAt,
    artistName: state.reminderArtistName, stageName: state.reminderStageName
  }));
}

export function reminderKey(event) {
  return `${event.performanceID}:${contentDate(event.startsAt).getTime()}`;
}

export function deliveredReminderKeys(plan) {
  return [...new Set([...(plan?.deliveredReminderKeys ?? []),
    ...(plan?.steps ?? []).filter(s => s.isConsumed && !s.skipped && s.pushStatus === 200 && s.isReminder)
      .flatMap(s => s.deliveredReminderKeys ?? reminderEvents(s.state, s.reminderEvents).map(reminderKey))])];
}

export function reminderAlert(state, events, language) {
  const first = events[0] ?? {};
  const name = first.artistName ?? state.reminderArtistName ?? state.showName;
  const stage = first.stageName ?? state.reminderStageName;
  const lang = language?.startsWith('en') ? 'en'
    : /Hant|TW|HK/.test(language ?? '') ? 'zh-Hant' : 'zh-Hans';
  const startsAt = contentDate(first.startsAt ?? state.reminderStartsAt);
  const clockOptions = { hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    timeZone: state.timeZoneIdentifier || 'UTC' };
  let clock = '';
  if (!Number.isNaN(startsAt.getTime())) {
    // Older clients may provide only the fixed event offset.
    if (!state.timeZoneIdentifier && state.timeZoneSecondsFromGMT != null) {
      startsAt.setTime(startsAt.getTime() + state.timeZoneSecondsFromGMT * 1000);
    }
    clock = new Intl.DateTimeFormat('en-GB', clockOptions).format(startsAt);
  }
  const count = (state.reminderCount ?? state.reminderPerformanceIDs?.length ?? events.length) - 1;
  const copies = {
    en: { title: `${name} is starting soon`, time: clock && `Starts at ${clock}`,
      more: `${count} more saved ${count === 1 ? 'set starts' : 'sets start'} soon` },
    'zh-Hans': { title: `${name}快开始了`, time: clock && `${clock} 开演`, more: `另有 ${count} 场想看即将开演` },
    'zh-Hant': { title: `${name}快開始了`, time: clock && `${clock} 開演`, more: `另有 ${count} 場想看即將開演` }
  };
  const copy = copies[lang];
  return { title: copy.title, body: [copy.time, stage, count > 0 ? copy.more : null].filter(Boolean).join(' · '), sound: 'default' };
}
