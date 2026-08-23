--!strict

-- Compatibility shim for Studio places that briefly run an older Main.server
-- while Argon applies a file-by-file sync. World creation and lighting changes
-- are intentionally forbidden here; the creator-owned place remains untouched.
local WorldService = {}

function WorldService.Build()
	-- Intentionally empty.
end

return table.freeze(WorldService)
