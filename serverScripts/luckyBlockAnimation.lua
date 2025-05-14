local RS = game:GetService("ReplicatedStorage")
local TweenS = game:GetService("TweenService")
local plotModule = require(script.Parent.ServerModules.PlotManager)



-- generate an animation in the direction of the fired vector
local function animate(player,object,direction)
	local plot = plotModule.returnPlot(workspace.plots,player)

		if object.Parent == plot then
			local module = require(plot.LuckyBlock.constant)
			local firstPosition = module.basepos()
			local goal = {}
			
			object.Position = (CFrame.new(object.Position, object.Position+direction.Unit)* CFrame.new(0,0,-5)).Position
			goal.Position = firstPosition
	
			local tweenInfo = TweenInfo.new(3, Enum.EasingStyle.Elastic)
			local tween = TweenS:Create(object,tweenInfo, goal)
	
			tween:Play()
		end
end





RS.events.anima.OnServerEvent:Connect(animate)
