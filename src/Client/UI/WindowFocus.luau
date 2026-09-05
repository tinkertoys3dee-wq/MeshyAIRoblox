--!strict

local WindowFocus = {}

-- Automatic celebrations must not cover a tutorial, checkout, active game,
-- or another celebration. Toasts are intentionally not blocking windows.
function WindowFocus.HasOverlay(gui: ScreenGui): boolean
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and child.Name ~= "Toasts" and child.ZIndex >= 200 then
			return true
		end
	end
	return false
end

function WindowFocus.CanCelebrate(app: any): boolean
	return app.shell.Visible
		and app.studioOpen ~= false
		and (app.activePage == "Create" or app.activePage == "Avatar Graphics")
		and not WindowFocus.HasOverlay(app.gui)
end

return WindowFocus
