-- Player Trading Post / Market Service.
-- Manages item listings posted by players at a "puesto_mercado" furniture piece.
-- Handlers for listing items for Gold, browsing market listings, and buying items.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Items = require(Shared:WaitForChild("Items"))
local PlayerService = require(script.Parent.PlayerService)

local MarketService = {}

local listings = {} -- list of { id, sellerId, sellerName, itemId, quantity, pricePerUnit, createdAt }
local nextListingId = 0

local function notify(player, text)
	Remotes.get("Notify"):FireClient(player, text)
end

function MarketService.start()
	local openMarketRemote = Remotes.get("OpenMarket")
	local getListings = Remotes.getFunction("GetMarketListings")
	local createListing = Remotes.getFunction("CreateMarketListing")
	local buyItem = Remotes.getFunction("BuyMarketItem")

	getListings.OnServerInvoke = function(player)
		local valid = {}
		for _, item in ipairs(listings) do
			if item.quantity > 0 then
				table.insert(valid, item)
			end
		end
		return valid
	end

	createListing.OnServerInvoke = function(player, payload)
		if typeof(payload) ~= "table" then
			return { ok = false, error = "bad_request" }
		end
		local itemId = payload.itemId
		local quantity = tonumber(payload.quantity) or 1
		local pricePerUnit = tonumber(payload.pricePerUnit) or 1

		if not itemId or quantity <= 0 or pricePerUnit <= 0 then
			return { ok = false, error = "invalid_input" }
		end

		local itemDef = Items.get(itemId)
		if not itemDef then
			return { ok = false, error = "unknown_item" }
		end

		local count = PlayerService.getItemCount(player, itemId)
		if count < quantity then
			notify(player, "No tienes suficientes ítems en tu inventario.")
			return { ok = false, error = "insufficient" }
		end

		local removed = PlayerService.removeItem(player, itemId, quantity)
		if not removed then
			notify(player, "No se pudo retirar el ítem del inventario.")
			return { ok = false, error = "inventory_error" }
		end

		nextListingId += 1
		local listing = {
			id = nextListingId,
			sellerId = player.UserId,
			sellerName = player.Name,
			itemId = itemId,
			quantity = quantity,
			pricePerUnit = pricePerUnit,
			createdAt = os.time(),
		}
		table.insert(listings, listing)

		notify(player, string.format("Publicado %dx %s por %d de oro c/u.", quantity, itemDef.name, pricePerUnit))
		return { ok = true, listing = listing }
	end

	buyItem.OnServerInvoke = function(player, listingId)
		listingId = tonumber(listingId)
		if not listingId then
			return { ok = false, error = "bad_request" }
		end

		local targetIndex = nil
		local targetListing = nil
		for idx, item in ipairs(listings) do
			if item.id == listingId then
				targetIndex = idx
				targetListing = item
				break
			end
		end

		if not targetListing or targetListing.quantity <= 0 then
			notify(player, "Esta oferta ya no está disponible.")
			return { ok = false, error = "not_found" }
		end

		if targetListing.sellerId == player.UserId then
			notify(player, "No puedes comprar tu propia oferta.")
			return { ok = false, error = "own_item" }
		end

		local totalCost = targetListing.quantity * targetListing.pricePerUnit
		local currentGold = PlayerService.getGold(player)
		if currentGold < totalCost then
			notify(player, "No tienes suficiente oro.")
			return { ok = false, error = "no_gold" }
		end

		-- Deduct gold from buyer
		PlayerService.addGold(player, -totalCost)

		-- Give gold to seller if online
		local sellerPlayer = Players:GetPlayerByUserId(targetListing.sellerId)
		if sellerPlayer then
			PlayerService.addGold(sellerPlayer, totalCost)
			notify(sellerPlayer, string.format("¡Vendiste %dx %s por %d de oro!", targetListing.quantity, Items.get(targetListing.itemId).name, totalCost))
		end

		-- Add item to buyer
		PlayerService.addItem(player, targetListing.itemId, targetListing.quantity, true)

		-- Remove listing
		table.remove(listings, targetIndex)

		notify(player, string.format("Compraste %dx %s por %d de oro.", targetListing.quantity, Items.get(targetListing.itemId).name, totalCost))
		return { ok = true }
	end
end

return MarketService
