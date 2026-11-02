-- Everyone on one event, by its row: a name, or the bare address when it has none,
-- and whether that one is me.
SELECT coalesce(identity.display_name, replace(identity.address, 'mailto:', '')) name,
       identity.address address, participant.ROWID = event.self_attendee_id isMe
FROM Participant participant
JOIN Identity identity ON identity.ROWID = participant.identity_id
JOIN CalendarItem event ON event.ROWID = participant.owner_id
WHERE participant.owner_id = :eventRow AND coalesce(identity.display_name, identity.address) IS NOT NULL
ORDER BY participant.ROWID;
