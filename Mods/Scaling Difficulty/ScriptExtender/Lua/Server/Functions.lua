--- @param _V _V
return function( _V )
    --- @class _F
    local _F = {}

    _F.Whole = function( n )
        if n < 0.0 then
            return math.ceil( n - 0.5 )
        end
        return math.floor( n + 0.5 )
    end

    _F.Split = function( str, splt )
        if type( str ) ~= "string" then return {} end

        local ret = {}
        if str == "" then
            return ret
        end
        for match in ( str .. splt ):gmatch( "(.-)" .. splt ) do
            table.insert( ret, match )
        end
        return ret
    end

    _F.UUID = function( target )
        if type( target ) == "userdata" and target.Uuid then
            return string.sub( target.Uuid.EntityUuid, -36 )
        elseif type( target ) == "string" then
            return string.sub( target, -36 )
        end
    end

    _F.RNG = function( seed )
        local self = { seed = seed + _V.Seed }

        setmetatable(
            self,
            {
                __call = function( _, range, reroll )
                    local roll = 0
                    range = range or 1
                    reroll = reroll or 1

                    for _ = 1, reroll do
                        self.seed = ( 1103515245 * self.seed + 12345 ) % 0x80000000
                        local r = self.seed / 0x80000000
                        if r > roll then
                            roll = r
                        end
                    end
                    local t = type( range )

                    if t == "number" then
                        return roll * range
                    elseif t == "table" then
                        return range[ math.floor( roll * #range + 1 ) ]
                    end
                end
            }
        )

        return self
    end

    _F.Hash = function( str )
        local h = 5381

        for i = 1, #str do
            h = h * 32 + h + str:byte( i )
        end

        return h
    end

    _F.Keys = function( tbl )
        local ret = {}
        for k,_ in pairs( tbl ) do
            table.insert( ret, k )
        end
        return ret
    end

    _F.DefaultBlueprint = function()
        local ret = {}

        for _,setting in pairs( _V.JsonBlueprint.Tabs[ 1 ].Settings ) do
            ret[ setting.Id ] = setting.Default
        end

        return ret
    end

    _F.Default = function( tbl, str )
        local stat = {}
        for _,v in ipairs( tbl ) do
            stat[ v ] = str and "" or 0
        end
        return stat
    end

    _F.GetClass = function( ent )
        local class = {}
        local uuid = _F.UUID( ent )
        local book = ent.SpellBook and ent.SpellBook.Spells

        if uuid and book then
            for _,data in ipairs( book ) do
                local spell = data.Id.Prototype
                if _V.SpellLists[ spell ] then
                    table.insert( class, _V.SpellLists[ spell ] )
                end
            end
        end

        return class
    end

    _F.IsElite = function( ent )
        local uuid = _F.UUID( ent )

        if not uuid then
            return false
        end

        if Osi.IsBoss( uuid ) == 1 then
            return true
        end

        if ent.ServerCharacter and ent.ServerCharacter.Template and ent.ServerCharacter.Template.CombatComponent and ent.ServerCharacter.Template.CombatComponent.IsBoss then
            return true
        end

        if ent.ServerPassiveBase then
            for _,t in ipairs( ent.ServerPassiveBase.Passives ) do
                if t:find( "Legendary" ) then
                    return true
                end
            end
        end

        if ent.DisplayName then
            local str = Osi.ResolveTranslatedString( ent.DisplayName.Title.Handle.Handle )
            if str and str ~= "" and str ~= "Novice of the Absolute" and str ~= "Matriphagous Child" then
                return true
            end
        end

        if ent.ActionResources and ent.ActionResources.Resources and
            (
                ent.ActionResources.Resources[ "732e23a8-bb1d-4bec-a4df-1dd0e03b56c4" ] or
                ent.ActionResources.Resources[ "4ebba3a3-f42e-42a6-87af-d36592ba8d49" ] or
                ent.ActionResources.Resources[ "67581067-020c-4e0d-814f-963714479f8a" ]
            )
        then return true end

        return false
    end

    _F.IsPlayer = function( ent )
        local uuid = _F.UUID( ent )
        return not ent.Bound and ent.Stats or Osi.DB_Players:Get( uuid )[ 1 ] or Osi.DB_Origins:Get( uuid )[ 1 ]
    end

    _F.Blacklist = function()
        if MCM then
            local b

            _V.Blacklist = {}
            b = _F.Split( MCM.Get( "Blacklist" ), "," )
            for _,i in ipairs( b ) do
                _V.Blacklist[ i:gsub( "[%s%p]", "" ):lower() ] = true
            end

            _V.SpellBlacklist = {}
            b = _F.Split( MCM.Get( "SpellBlacklist" ), "," )
            for _,i in ipairs( b ) do
                local tbl = _V.SpellNames[ i:gsub( "[%s%p]", "" ):lower() ]
                if tbl then
                    for _,name in ipairs( tbl ) do
                        _V.SpellBlacklist[ name ] = true
                    end
                end
            end
        end
    end

    return _F
end