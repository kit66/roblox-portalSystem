local plotManager = {}

-- assign unowned plot to the player
function plotManager.assignPlot(plots,player)
	for i,plot in pairs(plots:GetChildren()) do
		if plot.owner.Value == "" then	
			plot.owner.Value = player.Name
			plot.LuckyBlock.Transparency = 0
			--plot.LuckyBlock.CanCollide = true
			break
		end
	end
end

-- get player plot
function plotManager.returnPlot(plots,player)
	for i,plot in pairs(plots:GetChildren()) do
		if plot.owner.Value == player.Name then
			return plot
		end
	end
end

return plotManager
