local weapon = script.Parent
local plotManager = require(game.ServerScriptService.ServerModules.PlotManager)
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local events = RS.events

-- clear params from upgrade stantion
local function clearParams(Stantion)
	Stantion.UpgradeButton.PriceGui.num.Text = ""
	Stantion.wallInfo.SurfaceGui.Frame.TextLabel.Text = "equip gun to upgrade"
end

-- set gun params to upgrade stantion
local function SetParams()
	local user = Players:GetPlayerFromCharacter(weapon.Parent)
	local plot = plotManager.returnPlot(workspace.plots,user)
	local Stantion = plot.upgradeStantion
	local WeaponData = plot.LevelData:FindFirstChild(weapon.Name)

	-- set price
	Stantion.UpgradeButton.PriceGui.num.Text =
		math.round(weapon.Configuration.BasePrice.Value * WeaponData.Value * weapon.Configuration.multiplier.Value)
	
	-- set weapon name to wall
	Stantion.wallInfo.SurfaceGui.Frame.TextLabel.Text = weapon.Name
	
	-- set damage to gun based on lvl from levelData
	weapon.Configuration.Damage.Value = 
		WeaponData.Value * weapon.Configuration.BaseDamage.Value
	
	weapon.Unequipped:Connect(function()
		clearParams(Stantion)
	end)
end




weapon.Equipped:Connect(SetParams)


