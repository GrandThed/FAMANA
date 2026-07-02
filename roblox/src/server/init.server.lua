-- Server entry point. Rojo turns this folder into a Script named "Server";
-- the sibling modules are its children.

local PlayerService = require(script:WaitForChild("PlayerService"))
local HealthService = require(script:WaitForChild("HealthService"))
local ToolService = require(script:WaitForChild("ToolService"))

PlayerService.start()
HealthService.start()
ToolService.start()

print("[FAMANA] Server systems started (cell "
	.. require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")).cell
	.. ").")
