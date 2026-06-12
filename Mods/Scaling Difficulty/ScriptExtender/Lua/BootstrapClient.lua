local _V = require( "Server/Variables" )
local _F = require( "Server/Functions" )( _V )

if MCM and MCM.EventButton then
    local function Button( name, func, blue )
        MCM.EventButton.RegisterCallback(
            name,
            function()
                if func then
                    func()
                end

                if blue then
                    for id,default in pairs( _F.DefaultBlueprint() ) do
                        blue( id, default )
                    end
                end

                MCM.Set( name, nil, ModuleUUID, true )
            end
        )
    end

    Button(
        "Default",
        nil,
        function( id, default )
            if MCM.Get( id ) ~= default then
                MCM.Set( id, default, ModuleUUID, true )
            end
        end
    )

    Button(
        "Disable",
        nil,
        function( id, default )
            if id:find( "Enabled" ) then
                MCM.Set( id, false, ModuleUUID, true )
            end
        end
    )

    Button(
        "Enable",
        nil,
        function( id, default )
            if id:find( "Enabled" ) then
                MCM.Set( id, true, ModuleUUID, true )
            end
        end
    )

    Button( "Seed" )

    Button( "RefreshHealth" )
end