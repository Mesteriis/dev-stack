on open inputItems
	repeat with itemAlias in inputItems
		set composePath to POSIX path of itemAlias
		set devStackApp to POSIX path of ((path to applications folder from user domain as text) & "DevStackMenu.app")
		do shell script "open -a " & quoted form of devStackApp & " " & quoted form of composePath
	end repeat
end open

on run
	set devStackApp to POSIX path of ((path to applications folder from user domain as text) & "DevStackMenu.app")
	do shell script "open -a " & quoted form of devStackApp
end run
