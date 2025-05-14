-- add storage bar to GUI
wait(1)
local tween = game:GetService("TweenService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local getPlot = RS.request:WaitForChild("requestPlot")

local plot = getPlot:InvokeServer()
local gui = script.Parent
local max = plot.LevelData.Storage.Value*120

local count = 0

gui.TextLabel.Text = tostring(count).."/"..tostring(max)

local tweenInfo = TweenInfo.new(0.5)

-- +size bar
local function scaleAdd(countMoney)
	count +=countMoney

	gui.ImageLabel:TweenSize(UDim2.fromScale(count/max, gui.ImageLabel.Size["Y"]["Scale"]),_,_,0.5,true)
	gui.TextLabel.Text = tostring(count).."/"..tostring(max)
end

-- -size bar
local function scaleRemove(child)
	local price = 10^child.ID.Value/10
	count -=price

	gui.ImageLabel:TweenSize(UDim2.fromScale(count/max, gui.ImageLabel.Size["Y"]["Scale"]),_,_,0.5,true)
	gui.TextLabel.Text = tostring(count).."/"..tostring(max)
end


RS.events.GuiCapacity.Event:Connect(scaleAdd)
-- add event when any coin is removed from plot (picked up by player)
plot.coins.ChildRemoved:Connect(scaleRemove)

RS.events.MaxStorageAdded.OnClientEvent:Connect(function(value)
	max = value
	scaleAdd(0)
end)