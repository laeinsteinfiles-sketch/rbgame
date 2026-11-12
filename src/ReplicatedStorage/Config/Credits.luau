--!strict
-- Explorer: ReplicatedStorage/Config/Credits (ModuleScript)
-- Shown verbatim on the in-game Credits screen. Keep in sync with ASSETS.md.

export type CreditEntry = {
	title: string,
	author: string,
	licence: string,
	url: string,
}

local Credits: { CreditEntry } = {
	{
		title = "Sound effects",
		author = "Roblox Audio Library and Pro Sound Effects (see ASSETS.md)",
		licence = "Licensed for Roblox experiences",
		url = "https://create.roblox.com/store/audio",
	},
	{
		title = "Music",
		author = "APM Music and Roblox (see ASSETS.md)",
		licence = "Licensed for Roblox experiences",
		url = "https://create.roblox.com/store/audio",
	},
	{
		title = "Fonts",
		author = "Fredoka One, Luckiest Guy (bundled with Roblox)",
		licence = "Open font licences",
		url = "https://fonts.google.com",
	},
	{
		title = "ProfileStore",
		author = "loleris (Mad Studio)",
		licence = "Apache 2.0",
		url = "https://github.com/MadStudioRoblox/ProfileStore",
	},
}

return Credits
