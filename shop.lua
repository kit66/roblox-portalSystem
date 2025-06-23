local marketPlaceS = game:GetService("MarketplaceService")

local products = {
	coins5000 = 3297475576,
	coins400 = 3297566965
}

-- TODO сделать функцию которая будет создавать продукт по ID и ProximityPrompt
-- map of handlers for each product
local makepurchase = {
	[products.coins5000] = function(player)
		dataManager:addMoney(player, 5000)
	end,
	[products.coins400] = function(player)
		dataManager:addMoney(player, 400)
	end,
}

-- tiggers for purchase
workspace.shop.ProximityPrompt.Triggered:Connect(function(player)
	marketPlaceS:PromptProductPurchase(player, products.coins5000) 
end)

workspace.smallShop.ProximityPrompt.Triggered:Connect(function(player)
	marketPlaceS:PromptProductPurchase(player, products.coins400) 
end)



-- handle purchases
local function process(info)
	-- theck that the player is still in game
	local player = playersS:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- look up the handler for this product
	local purchaseFunction = makepurchase[info.ProductId]
	if not purchaseFunction then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- run handler
	local succsess, result = pcall(purchaseFunction, player)
	if not succsess then
		warn("error while purchasing", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	giveBadge(player, purchaseBadgeId) -- checking if player already has badge - not necessary
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

marketPlaceS.ProcessReceipt = process