--!strict
-- Assign uploaded, authorized audio from assets/audio. Roblox requires uploaded asset IDs;
-- local WAVs cannot be referenced by an experience. An empty ID intentionally stays silent.
-- AMBIENCE: one quiet local loop chosen from the room at the camera (BuildingEffectsController).
-- INTERACTIONS: short positional one-shots played through CampusSoundService.play(part, key).
return {
	AMBIENCE = { office = "", compute = "", kitchen = "", garage = "" },
	INTERACTIONS = {
		coffee = "",
		door = "",
		flush = "",
		liftChime = "",
		liftDoor = "",
		server = "",
		lobby = "",
	},
}
