// The UUID of the display to record, as OBS's screen capture wants it: the
// built-in one, or the main display when there is none (lid closed, a Mac mini).
// usage: osascript -l JavaScript display.js
ObjC.import("AppKit");
ObjC.import("CoreGraphics");
ObjC.import("ColorSync");

function run() {
	var screens = $.NSScreen.screens, id = $.CGMainDisplayID();
	for (var i = 0; i < screens.count; i++) {
		var n = ObjC.unwrap(screens.objectAtIndex(i).deviceDescription.objectForKey("NSScreenNumber"));
		if ($.CGDisplayIsBuiltin(n)) id = n;
	}
	return ObjC.castRefToObject($.CFUUIDCreateString(null, $.CGDisplayCreateUUIDFromDisplayID(id))).js;
}
