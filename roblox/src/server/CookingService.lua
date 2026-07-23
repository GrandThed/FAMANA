-- Cooking & Alchemy Service.
-- Handlers for cooking recipes and brewing potions at cauldrons ("olla_campamento").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local CookingRecipes = require(Shared:WaitForChild("CookingRecipes"))
local Items = require(Shared:WaitForChild("Items"))
local PlayerService = require(script.Parent.PlayerService)

local CookingService = {}

local function notify(player, text)
	Remotes.get("Notify"):FireClient(player, text)
end

function CookingService.start()
	local openCookingRemote = Remotes.get("OpenCooking")
	local cookRemote = Remotes.getFunction("CookRecipe")

	cookRemote.OnServerInvoke = function(player, recipeId)
		if typeof(recipeId) ~= "string" then
			return { ok = false, error = "bad_request" }
		end

		local recipe = CookingRecipes.get(recipeId)
		if not recipe then
			return { ok = false, error = "unknown_recipe" }
		end

		-- Verify player has all ingredients
		for _, ing in ipairs(recipe.ingredients) do
			local count = PlayerService.getItemCount(player, ing.itemId)
			if count < ing.quantity then
				notify(player, "No tienes suficientes ingredientes.")
				return { ok = false, error = "missing_ingredients" }
			end
		end

		-- Consume ingredients
		for _, ing in ipairs(recipe.ingredients) do
			PlayerService.removeItem(player, ing.itemId, ing.quantity)
		end

		-- Add result
		PlayerService.addItem(player, recipe.result.itemId, recipe.result.quantity, true)

		local itemDef = Items.get(recipe.result.itemId)
		notify(player, string.format("¡Preparado: %dx %s!", recipe.result.quantity, itemDef and itemDef.name or recipe.result.itemId))

		return { ok = true }
	end
end

return CookingService
