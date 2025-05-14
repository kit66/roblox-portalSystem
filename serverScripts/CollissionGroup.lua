-- manage collission Groups.
-- Limit coin spread and disable collision with the player  
local PhysicsService = game:GetService("PhysicsService")	
local RS = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local walls = "walls"
local coins = "coins"
local user = "player"


PhysicsService:CreateCollisionGroup(coins)
PhysicsService:CreateCollisionGroup(walls)
PhysicsService:CreateCollisionGroup(user)

-- Set collision group for player parts 
local function onDescendantAdded(descendant)
	if descendant:IsA("BasePart") then
		PhysicsService:SetPartCollisionGroup(descendant, user)
	end
end

-- Process all descendants parts setup
local function onCharacterAdded(character)
	for _, descendant in pairs(character:GetDescendants()) do
		onDescendantAdded(descendant)
	end
	character.DescendantAdded:Connect(onDescendantAdded)
end

-- Detect when player is added
players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacterAdded)
end)

-- add walls from plot to collision group
for _,plot in ipairs(workspace.plots:GetChildren()) do
	if plot:FindFirstChild("wal") then
		for _,wal in ipairs(plot:FindFirstChild("wal"):GetChildren()) do
			PhysicsService:SetPartCollisionGroup(wal,walls)
		end
	end
end

PhysicsService:CollisionGroupSetCollidable(walls, user, false)