-- One row per day a timed event happens on, between two days in Calendar's seconds.
SELECT event.ROWID eventRow, event.UUID uuid, event.summary title, event.has_recurrences repeats,
       event.start_date eventStart, event.end_date eventEnd, occurrence.day day,
       occurrence.occurrence_start_date occurrenceStart, occurrence.occurrence_end_date occurrenceEnd
FROM OccurrenceCache occurrence
JOIN CalendarItem event ON event.ROWID = occurrence.event_id
WHERE occurrence.day BETWEEN $fromDay AND $toDay AND event.all_day = 0 AND event.entity_type = 2;
