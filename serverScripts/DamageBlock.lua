local RS = game:GetService("ReplicatedStorage")
local TweenS = game:GetService("TweenService")

-- update health of hitted object (for future mechanics, like killing 'luckyBlock' to get extra reward)
local function AddDamage(player,damage,object,direction)
	if object.Parent.owner.Value == player.Name then
		
		object.Health.Value -= damage
	end
end

RS.events.blockDamaged.OnServerEvent:Connect(AddDamage)