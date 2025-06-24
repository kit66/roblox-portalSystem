local marketPlaceS = game:GetService("MarketplaceService")
local badgeS = game:GetService("BadgeService")
local playersS = game:GetService("Players")


local Shop = {}
Shop.productsList = {}
Shop.BadgeId = 3225353430882368

local ProductsList = {}


function Shop:createProduct(productId, ProximityPrompt:ProximityPrompt, handler)
	self.productsList[productId] = handler
	
	ProximityPrompt.Triggered:Connect(function(playerWhoTriggered)
		marketPlaceS:PromptProductPurchase(playerWhoTriggered, productId)
	end)
end

-- handle purchases
function Shop:process(info)
	-- theck that the player is still in game
	local player = playersS:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- look up the handler for this product
	local purchaseFunction = self.ProductsList[info.ProductId]
	if not purchaseFunction then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- run handler
	local succsess, result = pcall(purchaseFunction, player)
	if not succsess then
		warn("error while purchasing", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	badgeS:AwardBadge(info.PlayerId, self.BadgeId)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

marketPlaceS.ProcessReceipt = Shop.process

-- TODO перекинуть в мейн всё что ниже
local products = {
	coins5000 = 3297475576,
	coins400 = 3297566965
}

Shop.createDonate(products.coins5000, workspace.shop.ProximityPrompt, function()
	dataManager:addMoney(player, 5000)
end)
Shop.createDonate(products.coins5000, workspace.smallShop.ProximityPrompt, function()
	dataManager:addMoney(player, 5000)
end)