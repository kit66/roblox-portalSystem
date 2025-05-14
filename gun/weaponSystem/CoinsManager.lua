-- managing what type and how much coins will spawn 
local replicated = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")	

local eventfolder = replicated.events
local rand = Random.new()
local IDs = {}
-- init coins types
local coins = replicated.coins:GetChildren()
for _,coin in coins  do
	local key = coin.ID.Value
	IDs[key] = coin
end

local defaultSizeMultiplier = 120
local defaultDamageSplitter = 20
local defaultCoinSplitter = 10

local CoinsManager = {}

function CoinsManager.spawncoin(damage,object)
	local id = 1
	local max = object.Parent.LevelData.Storage.Value * defaultSizeMultiplier
	local current = object.Parent.coins.CurrentMoneyOnPlot
	local countMoney = damage / defaultDamageSplitter

	-- get values to check - do we have capasity on plot?
	if countMoney > max-current.Value then
		countMoney = max-current.Value
		if countMoney < 0 then
			countMoney =0
		end
	end

	if countMoney ~= 0
		current.Value +=countMoney
		replicated.events.GuiCapacity:Fire(countMoney)

		while countMoney > 0 do
			-- cycle will spawn coins in order from higher value to lower 
			local kolvoIDmoney = countMoney % defaultCoinSplitter
			for i=1,kolvoIDmoney  do
				-- set collision with invisible walls 
				local clone = IDs[id]:Clone()
				clone.Parent = object.Parent.coins
				PhysicsService:SetPartCollisionGroup(clone,"coins")
				clone.CFrame = object.CFrame * CFrame.new(0,10,0)
				
				-- create random impulse to make 'popped out' effect
				local direction = Vector3.new(rand:NextInteger(-5,5),rand:NextInteger(0,10),rand:NextInteger(-5,5))
				local forceMultipliter = 10 * clone:GetMass()
				clone:ApplyImpulse(direction * forceMultipliter)
				
				clone.Touched:Connect(function(part)
					local partofwho = part.Parent

					-- Make coins bounce off the block to prevent them from getting stuck on top
					if part.Name == "LuckyBlock" then	
						clone:ApplyImpulse((direction + Vector3.new(1,1,1)) * forceMultipliter)	
					end
					
					-- if player picked up the coin
					if partofwho == Players.LocalPlayer.Character then
						current.Value -= defaultCoinSplitter ^ clone.ID.Value / defaultCoinSplitter
						eventfolder.collected:FireServer(clone.ID.Value)
						clone:Destroy()
					end
				end)
			end
			-- next coin cycle
			countMoney = math.floor(countMoney/defaultCoinSplitter)
			id += 1
		end
	end

end

return CoinsManager