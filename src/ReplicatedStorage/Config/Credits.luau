--!strict
-- Explorer: ReplicatedStorage/Config/Credits (ModuleScript)
-- Shown verbatim on the in-game Credits screen. Keep in sync with ASSETS.md.
-- game-icons.net (CC BY 3.0) requires visible attribution, which is why this
-- screen exists.

export type CreditEntry = {
	title: string,
	author: string,
	licence: string,
	url: string,
}

local Credits: { CreditEntry } = {
	{
		title = "UI icons",
		author = "Lorc, Delapouite and contributors at game-icons.net",
		licence = "CC BY 3.0",
		url = "https://game-icons.net",
	},
	{
		title = "UI panels and bars",
		author = "Kenney (kenney.nl)",
		licence = "CC0 1.0",
		url = "https://kenney.nl/assets/ui-pack",
	},
	{
		title = "Props and pets",
		author = "Quaternius / Kenney (see ASSETS.md)",
		licence = "CC0 1.0",
		url = "https://quaternius.com",
	},
	{
		title = "ProfileStore",
		author = "loleris (Mad Studio)",
		licence = "Apache 2.0",
		url = "https://github.com/MadStudioRoblox/ProfileStore",
	},
	{
		title = "Audio",
		author = "Roblox Creator Store (see ASSETS.md for each track)",
		licence = "Creator Store terms",
		url = "https://create.roblox.com/store",
	},
}

return Credits
