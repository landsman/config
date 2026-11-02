on run argv
	tell application "Contacts"
		set newPerson to make new person with properties {first name:item 1 of argv, last name:item 2 of argv}
		make new email at end of emails of newPerson with properties {label:"work", value:item 3 of argv}
		save
	end tell
end run
