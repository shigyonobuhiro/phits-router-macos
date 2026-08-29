use framework "AppKit"
use scripting additions

-- =========================
-- Debug mode
-- =========================
-- Set to true to show popups and extra diagnostics; false for normal use.
property debugMode : false

on run {input, parameters}
	-- Resolve PHITSPATH (fallback to ~/phits)
	set phitsBase to (do shell script "/bin/sh -lc 'if [ -n \"$PHITSPATH\" ]; then printf %s \"$PHITSPATH\"; else printf %s \"$HOME/phits\"; fi'")
	
	-- Program paths (as provided)
	set appPHITSPad to phitsBase & "/phitspad/macos/PhitsPad.app"
	set appEPSPDF to phitsBase & "/bin/EPSPDF.app"
	
	-- Preferred text editor (fallback to TextEdit)
	set preferredEditorName to "CotEditor"
	set fallbackEditorName to "TextEdit"
	
	-- PHITS input extensions
	set phitsInputExts to {"inp", "in", "i"}
	
	-- Modifiers via AppKit
	set mods to my currentModifierFlags()
	set isShift to mods's shift
	set isCmd to mods's command
	set isOpt to mods's option
	set isCtrl to mods's control
	set noMods to (not isShift) and (not isCmd) and (not isOpt) and (not isCtrl)
	
	repeat with f in input
		set p to POSIX path of f
		set ext to my lowerExt(p)
		
		-- EPS always -> EPSPDF (no chooser)
		if ext is "eps" then
			my dbg(p, ext, true, false, false, isCmd, isOpt, isCtrl, isShift, "EPS -> EPSPDF")
			my openWithAppPathOrName(p, appEPSPDF, "EPSPDF")
			
		else
			set textish to my isTextish(p, ext, phitsInputExts)
			
			-- Non-text-ish -> open normally with Finder default
			if textish is false then
				my dbg(p, ext, textish, false, false, isCmd, isOpt, isCtrl, isShift, "Non-text -> open default")
				do shell script "open " & quoted form of p
				
			else
				-- DCHAIN detection only makes sense for text
				set isDchain to my isDchainInput(p)
				
				-- No-modifiers: always chooser, with smart default pre-selected
				if noMods then
					set defaultChoice to my suggestedDefaultFor(p, ext, isDchain, phitsInputExts, preferredEditorName, fallbackEditorName)
					my dbg(p, ext, textish, isDchain, (ext is in phitsInputExts), isCmd, isOpt, isCtrl, isShift, "No mods -> chooser (default " & defaultChoice & ")")
					my chooserOpenWithDefault(p, defaultChoice, preferredEditorName, fallbackEditorName, appPHITSPad, appEPSPDF)
				else
					my dbg(p, ext, textish, isDchain, (ext is in phitsInputExts), isCmd, isOpt, isCtrl, isShift, "Routing (modifiers)")
					my routeOpen(p, ext, isDchain, isCmd, isOpt, isCtrl, isShift, phitsInputExts, preferredEditorName, fallbackEditorName, appPHITSPad)
				end if
			end if
		end if
	end repeat
	
	return input
end run


-- =========================================
-- Routing logic (modifiers-only path)
-- =========================================
-- Semantics:
-- - No modifiers: chooser (handled in run)
-- - Shift: PHITS-Pad (for ANY text-ish file category)
-- - Command: "primary action" (PHITS or DCHAIN; otherwise editor)
-- - Option: visualization (PHIG-3D for PHITS input; ANGEL for other text)
-- - Control: editor (for PHITS input, DCHAIN input, or any other text-ish file)
on routeOpen(p, ext, isDchain, isCmd, isOpt, isCtrl, isShift, phitsInputExts, preferredEditorName, fallbackEditorName, appPHITSPad)
	set isPhitsInput to (ext is in phitsInputExts) and (not isDchain)
	
	-- PHITS input
	if isPhitsInput then
		if isShift then
			my openWithAppPathOrName(p, appPHITSPad, "PhitsPad")
		else if isCmd then
			my runInTerminal(p, "phits.sh")
		else if isOpt then
			my runInTerminal(p, "phig3d.sh")
		else if isCtrl then
			my openWithEditor(p, preferredEditorName, fallbackEditorName)
		else
			-- Shouldn't happen (no-mods handled earlier), but keep safe default:
			my openWithAppPathOrName(p, appPHITSPad, "PhitsPad")
		end if
		return
	end if
	
	-- DCHAIN input
	if isDchain then
		if isShift then
			my openWithAppPathOrName(p, appPHITSPad, "PhitsPad")
		else if isCmd then
			my runInTerminal(p, "dchain.sh")
		else if isCtrl then
			my openWithEditor(p, preferredEditorName, fallbackEditorName)
		else
			-- Safe default:
			my openWithAppPathOrName(p, appPHITSPad, "PhitsPad")
		end if
		return
	end if
	
	-- Otherwise: any other text-ish file (including PHITS outputs)
	if isShift then
		my openWithAppPathOrName(p, appPHITSPad, "PhitsPad")
	else if isCmd then
		my openWithEditor(p, preferredEditorName, fallbackEditorName)
	else if isCtrl then
		my openWithEditor(p, preferredEditorName, fallbackEditorName)
	else if isOpt then
		my runInTerminal(p, "angel.sh")
	else
		-- Shouldn't happen (no-mods handled earlier), but choose editor:
		my openWithEditor(p, preferredEditorName, fallbackEditorName)
	end if
end routeOpen


-- =========================================
-- Suggested default for chooser (no modifiers)
-- =========================================
-- Defaults:
-- - PHITS input: PHITS-Pad
-- - DCHAIN input: PHITS-Pad
-- - Other text: preferred editor if installed else fallback
on suggestedDefaultFor(p, ext, isDchain, phitsInputExts, preferredEditorName, fallbackEditorName)
	set isPhitsInput to (ext is in phitsInputExts) and (not isDchain)
	if isPhitsInput then return "PHITS-Pad"
	if isDchain then return "PHITS-Pad"
	if my appExistsByName(preferredEditorName) then
		return preferredEditorName
	else
		return fallbackEditorName
	end if
end suggestedDefaultFor


-- =========================================
-- Chooser with default selection (no modifiers)
-- =========================================
-- Order requested:
-- PHITS, DCHAIN, PHIG-3D, PHITS-Pad, CotEditor, TextEdit, ANGEL, EPSPDF
on chooserOpenWithDefault(p, defaultChoice, preferredEditorName, fallbackEditorName, appPHITSPad, appEPSPDF)
	set options to {"PHITS", "DCHAIN", "PHIG-3D", "PHITS-Pad", preferredEditorName, fallbackEditorName, "ANGEL", "EPSPDF"}
	
	-- Ensure defaultChoice appears in list; if not, fall back sensibly
	set defaultItem to defaultChoice
	if defaultItem is "" then set defaultItem to preferredEditorName
	
	set choice to choose from list options with title "Open withÉ" with prompt "Choose app for:
" & p default items {defaultItem}
	if choice is false then return
	
	set picked to item 1 of choice
	if picked is "PHITS" then
		my runInTerminal(p, "phits.sh")
	else if picked is "DCHAIN" then
		my runInTerminal(p, "dchain.sh")
	else if picked is "PHIG-3D" then
		my runInTerminal(p, "phig3d.sh")
	else if picked is "PHITS-Pad" then
		my openWithAppPathOrName(p, appPHITSPad, "PhitsPad")
	else if picked is "ANGEL" then
		my runInTerminal(p, "angel.sh")
	else if picked is "EPSPDF" then
		my openWithAppPathOrName(p, appEPSPDF, "EPSPDF")
	else if picked is preferredEditorName then
		my openWithEditor(p, preferredEditorName, fallbackEditorName)
	else
		my openWithAppName(p, fallbackEditorName)
	end if
end chooserOpenWithDefault


-- =========================================
-- DCHAIN detection:
-- first nonblank, noncomment line (not starting with * or !) contains "htitle"
-- =========================================
on isDchainInput(posixPath)
	try
		set f to POSIX file posixPath as alias
		set fh to open for access f
		set raw to read fh for 20000 -- first ~20 KB
		close access fh
	on error
		try
			close access (POSIX file posixPath as alias)
		end try
		return false
	end try
	
	set AppleScript's text item delimiters to {linefeed, return}
	set linesList to text items of raw
	set AppleScript's text item delimiters to {""}
	
	repeat with L in linesList
		set s to my trimText(L as text)
		if s is "" then
			-- skip
		else if s starts with "*" or s starts with "!" then
			-- skip comment
		else
			set sLower to my toLowerFast(s)
			return (sLower contains "htitle")
		end if
	end repeat
	
	return false
end isDchainInput


on trimText(t)
	set ws to {" ", tab}
	repeat while (t is not "") and ((character 1 of t) is in ws)
		set t to text 2 thru -1 of t
	end repeat
	repeat while (t is not "") and ((character -1 of t) is in ws)
		set t to text 1 thru -2 of t
	end repeat
	return t
end trimText


-- Fast lowercasing for whole strings (shell tr; lightweight and reliable)
on toLowerFast(t)
	try
		return do shell script "printf %s " & quoted form of t & " | tr '[:upper:]' '[:lower:]'"
	on error
		return t
	end try
end toLowerFast


-- Extension helper (pure AppleScript; no python dependency)
on lowerExt(p)
	try
		set f to POSIX file p as alias
		set e to name extension of (info for f)
		if e is missing value then return ""
		return my toLowerFast(e as text)
	on error
		return ""
	end try
end lowerExt


-- Text-ish detection (file(1))
on isTextish(p, ext, phitsInputExts)
	if ext is in phitsInputExts then return true
	try
		set mt to do shell script "/usr/bin/file -b --mime-type " & quoted form of p
		return (mt starts with "text/") or (mt is "application/json") or (mt is "application/xml")
	on error
		return false
	end try
end isTextish


-- =========================================
-- Open helpers
-- =========================================
on openWithEditor(p, preferredName, fallbackName)
	if my appExistsByName(preferredName) then
		my openWithAppName(p, preferredName)
	else
		my openWithAppName(p, fallbackName)
	end if
end openWithEditor

on openWithAppName(p, appName)
	do shell script "open -a " & quoted form of appName & " " & quoted form of p
end openWithAppName

on openWithAppPathOrName(p, appPath, friendlyName)
	if my pathExists(appPath) then
		do shell script "open -a " & quoted form of appPath & " " & quoted form of p
	else
		display alert (friendlyName & " not found") message ("Expected at:
" & appPath & "

Check PHITSPATH or edit paths.") as warning
	end if
end openWithAppPathOrName

on pathExists(posixPath)
	try
		do shell script "test -e " & quoted form of posixPath
		return true
	on error
		return false
	end try
end pathExists

on appExistsByName(appName)
	try
		do shell script "osascript -e " & quoted form of ("id of application \"" & appName & "\"")
		return true
	on error
		return false
	end try
end appExistsByName


-- =========================================
-- Modifier flags (AppKit)
-- =========================================
on currentModifierFlags()
	set f to (current application's NSEvent's modifierFlags()) as integer
	set shiftDown to ((f div 131072) mod 2) = 1
	set ctrlDown to ((f div 262144) mod 2) = 1
	set optDown to ((f div 524288) mod 2) = 1
	set cmdDown to ((f div 1048576) mod 2) = 1
	return {command:cmdDown, option:optDown, control:ctrlDown, shift:shiftDown}
end currentModifierFlags

-- =========================================
-- A common handler that runs shell scripts in the terminal
-- =========================================
on runInTerminal(posixPath, shellScriptName)
	-- Separating the path into folders and filenames
	set AppleScript's text item delimiters to "/"
	set FolderPath to (text 1 thru text item -2 of posixPath)
	set FileName to (text item -1 of posixPath)
	set AppleScript's text item delimiters to ""
	
	-- Terminal operations
	if application "Terminal" is not running then
		tell application "Terminal"
			activate
			delay 0.5
		end tell
	end if
	
	tell application "Terminal"
		activate
		-- Check the window status and execute
		if not (exists front window) or busy of front window then
			set targetTab to do script "clear; echo -e \"\\nNew terminal opened.\\n\""
		else
			set targetTab to selected tab of front window
		end if
		
		do script "cd" & space & quoted form of FolderPath in targetTab
		delay 0.3
		do script shellScriptName & space & quoted form of FileName in targetTab
	end tell
end runInTerminal

-- =========================================
-- Debug helper (gated)
-- =========================================
on dbg(p, ext, textish, isDchain, isPhitsInputGuess, isCmd, isOpt, isCtrl, isShift, stage)
	if debugMode is false then return
	display dialog stage & "

File: " & p & "
Ext: " & ext & "
Textish: " & textish & "
DCHAIN: " & isDchain & "

Mods: " & Â
		"Cmd=" & isCmd & " Opt=" & isOpt & " Ctrl=" & isCtrl & " Shift=" & isShift buttons {"OK"} default button "OK"
end dbg
