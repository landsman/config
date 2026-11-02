-- The names on one event, by its UUID, in the order Calendar lists them.
SELECT identity.display_name AS name
FROM CalendarItem event
JOIN Participant participant ON participant.owner_id = event.ROWID
JOIN Identity identity ON identity.ROWID = participant.identity_id
WHERE event.UUID = :eventId AND identity.display_name IS NOT NULL
ORDER BY participant.ROWID;
