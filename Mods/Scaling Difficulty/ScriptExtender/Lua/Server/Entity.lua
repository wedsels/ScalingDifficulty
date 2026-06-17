--- @param _V _V
--- @param _F _F
return function( _V, _F )
    ---@class Entity
    local _E = {}
    _E.__index = _E

    _E.AddNPC = function( ent )
        local uuid = _F.UUID( ent )
        if not uuid or _V.Entities[ uuid ] then return end

        local eoc = ent.EocLevel
        local data = ent.Data
        local stats = ent.Stats
        local health = ent.Health

        if not eoc or not data or not stats or not health then return end

        local xp = Ext.Stats.Get( data.StatsId )

        ent.Vars.SDCache = ent.Vars.SDCache or {}
        local cache = ent.Vars.SDCache
        cache.Name = cache.Name or ( ent.DisplayName and Ext.Loca.GetTranslatedString( ent.DisplayName.Name.Handle.Handle ) or ent.ServerCharacter and ent.ServerCharacter.Template.Name or data.StatsId or uuid ):gsub( "[%s%p]", "" ):lower()
        cache.Health = cache.Health or {
            Hp = health.Hp,
            MaxHp = math.max( 1, health.MaxHp ),
            Percent = health.Hp / math.max( 1, health.MaxHp ),
            Transformed = false,
            TransformedHp = 0,
            TransformedMaxHp = 0,
            TransformedPercent = 0
        }
        cache.Stats = cache.Stats or _F.Default( _V.Stats )
        cache.Resource = cache.Resource or _F.Default( _V.Resource )
        cache.Skills = cache.Skills or {}
        cache.Spells = cache.Spells or {}
        cache.Blacklist = cache.Blacklist or {}
        cache.Size = cache.Size or 0
        cache.SpellCount = cache.SpellCount or 0

        _V.Entities[ uuid ] = setmetatable( {
            UUID = uuid,
            Instance = ent,
            Disabled = false,
            Faction = "",
            Scaled = false,
            Type = nil,
            Hub = nil,
            LevelBase = eoc.Level,
            LevelChange = 0,
            Experience = xp and _V.Experience[ xp.XPReward ],
            Physical = stats.Abilities[ 2 ] <= stats.Abilities[ 3 ] and "Dexterity" or "Strength",
            Casting = tostring( stats.SpellCastingAbility ),
            Stats = _F.Default( _V.Stats ),
            Skills = {},
            Resource = _F.Default( _V.Resource, true ),
            AC = {
                Type = false,
                ACBonus = 0,
                ACModifier = 0
            },
            Modifiers = {
                Original = {},
                Current = _F.Default( _F.Keys( _V.Abilities ) )
            },
            Hooks = nil,
            Cache = cache,
            RNG = _F.RNG( _F.Hash( uuid ) )
        }, _E )

        local entity = _V.Entities[ uuid ]

        for k,v in pairs( _V.Abilities ) do
            entity.Modifiers.Original[ k ] = stats.AbilityModifiers[ v ]
        end

        entity.Hooks = {
            Ext.Entity.OnChange( "Stats", function( _,_,i ) entity:SetAbilities( i ) end, ent ),
            Ext.Entity.OnChange( "Health", function( _,_,i ) entity:SetHealth( i ) end, ent ),
            Ext.Entity.OnChange( "EocLevel", function( _,_,i ) entity:SetLevel( i ) end, ent ),
            Ext.Entity.OnChange( "Resistances", function( _,_,i ) entity:SetAC( i ) end, ent ),
            Ext.Entity.OnChange( "Faction", function( _,_,_ ) entity:SetFaction() end, ent ),
            Ext.Entity.OnChange(
                "TurnBased",
                function( _,_,i )
                    if i ~= 128 and ent.TurnBased.CanActInCombat then
                        entity:SetArchetype()
                    end
                end,
                ent
            ),
            Ext.Entity.OnCreateDeferred(
                "LevelChanged",
                function( _,_,i )
                    local l = ent.LevelChanged
                    if l.PreviousLevel == _V.PartyLevel and l.NewLevel > _V.PartyLevel and entity.Type == "Player" then
                        _V.PartyLevel = l.NewLevel
                        _E.Update()
                    end
                end,
                ent
            ),
            Ext.Entity.OnDestroyOnce( "Active", function( _,_,_ ) entity:Destroy() end, ent )
        }

        entity:SetFaction( true )
        entity:SetArchetype( true )
        entity:Recalculate()
    end

    _E.Update = function( disable )
        for _,i in pairs( _V.Entities ) do
            i:Recalculate( disable )
        end
    end

    function _E:Destroy( pass )
        for _,i in ipairs( self.Hooks ) do
            Ext.Entity.Unsubscribe( i )
        end

        if not pass then
            self:Recalculate( true )
        end
        _V.Entities[ self.UUID ] = nil
    end

    function _E:SetFaction( pass )
        local old = self.Faction

        self.Faction = self.Instance.Faction and self.Instance.Faction.field_8 or self.Instance.ServerCharacter and self.Instance.ServerCharacter.OriginalTemplate and self.Instance.ServerCharacter.OriginalTemplate.CombatComponent.Faction or ""

        if not pass and old ~= self.Faction then
            self:Recalculate()
        end
    end

    function _E:SetArchetype( pass )
        local old = self.Type

        if _F.IsPlayer( self.Instance, self.UUID ) then self.Type = "Player"
        elseif _F.IsSummon( self.Instance ) then self.Type = "Summon"
        elseif _F.IsElite( self.Instance ) then self.Type = "Elite"
        elseif Osi.GetRelation( self.Faction, "a1542c81-6895-929e-4522-10ce218bb360" ) == 0 then self.Type = "Hostile"
        else self.Type = "Ally" end

        self.Hub = _V.Hub[ self.Type ]

        if not pass and old ~= self.Type then
            self:Recalculate()
        end
    end

    function _E:Recalculate( disable )
        if not self.Instance then self:Destroy( true ) return end

        self.Disabled = disable or _V.Blacklist[ self.Cache.Name ]

        for _,resource in ipairs( _V.Resource ) do
            if resource ~= "Enabled" then
                self.Resource[ resource ] = ( self.Disabled or not self.Hub.Resource.Enabled ) and "" or self.Hub.Resource[ resource ]
            end
        end

        local level = math.max( 0, _V.PartyLevel + ( ( not self.Disabled and self.Hub.General.Enabled ) and self.Hub.General.LevelBonus or 0 ) )

        if self.Hub.General.MaxLevel > 0 then
            level = math.min( level, self.Hub.General.MaxLevel )
        end

        if level < self.LevelBase and ( ( self.Disabled or not self.Hub.General.Enabled ) or not self.Hub.General.Downscaling ) then
            level = self.LevelBase
        elseif self.Type == "Player" then
            self.LevelBase = 1
            level = self.Instance.EocLevel.Level
        end

        self.LevelChange = ( self.Disabled or not self.Hub.Leveling.Enabled ) and 0 or level - self.LevelBase

        local ran = self.RNG:New()

        for _,stat in ipairs( _V.Stats ) do
            if stat ~= "Enabled" then
                local vari = ran( self.Hub.Variation[ stat ] )
                if ran( 1.0 ) < 0.5 then
                    vari = vari * -1.0
                end

                self.Stats[ stat ]
                    = ( ( self.Disabled or not self.Hub.Bonus.Enabled ) and 0 or self.Hub.Bonus[ stat ] )
                    + self.Hub.Leveling[ stat ] * self.LevelChange
                    + ( ( self.Disabled or not self.Hub.Variation.Enabled ) and 0 or vari )
            end
        end

        self:SetAbilities()
        self:SetAC()
        self:SetHealth()
        if not disable then
            self:SetBoosts()
            self:SetSpells()
        end
        self:SetExperience()
        self:SetLevel()
    end

    function _E:SetSpells()
        if self.Type == "Player" then return end

        local book = self.Instance.SpellBook and self.Instance.SpellBook.Spells
        if not book then return end

        local num = self.Hub.General.Enabled and _F.Whole( self.Hub.General.Spells * ( self.LevelBase + self.LevelChange ) ) or 0
        num = math.min( num, 18 )
        if num == self.Cache.SpellCount and _V.SpellBlacklist == self.Cache.Blacklist then return end

        local selection = {}
        for i,_ in pairs( _V.Classes[ self.Casting ] or {} ) do
            if _F.HasResource( self.Instance, _V.SpellResources[ i ] ) then
                selection[ #selection + 1 ] = i
            end
        end

        local spells = {}
        local ran = self.RNG:New()

        local roll = ran( num, 2 )
        for _=1,roll do
            if #selection == 0 then break end

            local rng = 1 + math.floor( ran( #selection ) )
            if not _V.SpellBlacklist[ selection[ rng ] ] then
                spells[ selection[ rng ] ] = true
            end

            selection[ rng ] = selection[ #selection ]
            selection[ #selection ] = nil
        end

        for spell,_ in pairs( spells ) do
            if not self.Cache.Spells[ spell ] then
                Osi.AddSpell( self.UUID, spell )
            end
        end

        for spell,_ in pairs( self.Cache.Spells ) do
            if not spells[ spell ] then
                Osi.RemoveSpell( self.UUID, spell )
            end
        end

        self.Cache.SpellCount = num
        self.Cache.Blacklist = _V.SpellBlacklist
        self.Cache.Spells = spells
    end

    function _E:SetAC( index )
        if index == -1 then return end

        local res = self.Instance.Resistances
        if not res then return end

        local clean = index ~= 4
        local ac = _F.Whole( self.Stats.AC + ( clean and self.Modifiers.Current.Dexterity - self.Modifiers.Original.Dexterity or 0 ) )

        res.AC = res.AC + ac
        if clean then
            res.AC = res.AC - self.Cache.Stats.AC
        end

        self.Cache.Stats.AC = _F.Whole( self.Stats.AC + self.Modifiers.Current.Dexterity - self.Modifiers.Original.Dexterity )

        self.Instance:Replicate( "Resistances" )
    end

    function _E:SetAbilities( index )
        if index == -1 then return end

        local stats = self.Instance.Stats
        if not stats then return end

        local clean = index ~= 79

        for k,v in pairs( _V.Abilities ) do
            local stat = self.Stats[ k ]
            if k == self.Physical then stat = stat + self.Stats.Physical end
            if k == self.Casting then stat = stat + self.Stats.Casting end
            stat = _F.Whole( stat )

            stats.Abilities[ v ] = stats.Abilities[ v ] + stat
            if clean then
                stats.Abilities[ v ] = stats.Abilities[ v ] - self.Cache.Stats[ k ]
            else
                self.Modifiers.Original[ k ] = stats.AbilityModifiers[ v ]
            end

            stats.AbilityModifiers[ v ] = math.floor( ( stats.Abilities[ v ] - 10.0 ) / 2.0 )
            self.Modifiers.Current[ k ] = stats.AbilityModifiers[ v ]

            self.Cache.Stats[ k ] = stat
        end

        for i,k in ipairs( _V.AbilitiesMatch ) do
            if index ~= 8 and clean then
                self.Skills[ i ] = self.Skills[ i ] or stats.Skills[ i ]
            else
                self.Skills[ i ] = stats.Skills[ i ];
            end

            stats.Skills[ i ] = self.Skills[ i ] + ( stats.AbilityModifiers[ k ] - ( self.Modifiers.Original[ _V.AbilitiesReverse[ k ] ] or 0 ) )
            self.Cache.Skills[ i ] = stats.Skills[ i ]
        end

        stats.InitiativeBonus = _F.Whole( stats.InitiativeBonus + self.Stats.Initiative - ( clean and self.Cache.Stats.Initiative or 0 ) )
        self.Cache.Stats.Initiative = self.Stats.Initiative

        if self.Type ~= "Player" then
            stats.ProficiencyBonus = 2 + math.floor( ( self.LevelBase + self.LevelChange - 1 ) / 4.0 )
        end

        if not clean then
            self.Instance.Resistances.AC = self.Instance.Resistances.AC + self.Modifiers.Current.Dexterity - self.Modifiers.Original.Dexterity
        end

        self.Instance:Replicate( "Stats" )
    end

    function _E:SetHealth( index )
        if index == -1 then return end

        local health = self.Instance.Health
        if not health then return end

        if index == 59 then
            self:SetAbilities( 79 )
            self:SetAC( 4 )

            if self.Cache.Health.Transformed then
                self.Cache.Health.Hp = self.Cache.Health.TransformedHp
                self.Cache.Health.MaxHp = self.Cache.Health.TransformedMaxHp
                self.Cache.Health.Percent = self.Cache.Health.TransformedPercent
            else
                self.Cache.Health.TransformedHp = self.Cache.Health.Hp
                self.Cache.Health.TransformedMaxHp = self.Cache.Health.MaxHp
                self.Cache.Health.TransformedPercent = self.Cache.Health.Percent

                self.Cache.Health.Percent = 1
            end

            self.Cache.Health.Transformed = not self.Cache.Health.Transformed
        elseif index == 1 or index == 5 or health.Hp <= 0 or Osi.IsActive( self.UUID ) ~= 1 then
            if health.Hp ~= self.Cache.Health.Hp then
                self.Cache.Health.Percent = health.Hp / math.max( 1, health.MaxHp )
                self.Cache.Health.Hp = health.Hp
            end
        elseif index ~= 1 and health.MaxHp ~= self.Cache.Health.MaxHp then
            health.Hp = self.Cache.Health.Hp
        end

        if index == 59 or index == 3 or index == 2 or not index then
            if index then
                self.Cache.Health.MaxHp = health.MaxHp
            end

            local hp = self.Cache.Health.MaxHp + self.Stats.HP
            if self.Type ~= "Player" then
                hp = hp + self.Modifiers.Current.Constitution * self.LevelChange
                hp = hp + ( self.Modifiers.Current.Constitution - self.Modifiers.Original.Constitution ) * self.LevelBase
            end
            hp = hp * ( 1.0 + self.Stats.PercentHP + self.Stats.Size )

            health.MaxHp = math.max( 1, _F.Whole( hp ) )

            health.Hp = math.min( health.MaxHp, _F.Whole( health.MaxHp * self.Cache.Health.Percent ) )
            self.Cache.Health.Hp = health.Hp
        end

        self.Instance:Replicate( "Health" )
    end

    function _E:SetLevel( index )
        local eoc = self.Instance.EocLevel
        if not eoc or self.Type == "Player" then return end

        local level = self.LevelBase + self.LevelChange
        if eoc.Level == level then return end

        if index ~= -1 then
            self.Instance:Replicate( "EocLevel" )
            return
        end

        self.Instance:RemoveComponent( "EocLevel" )

        self.Instance:OnDestroyDeferredOnce(
            "EocLevel",
            function()
                self.Instance:CreateComponent( "EocLevel" )
            end
        )

        self.Instance:OnCreateDeferredOnce(
            "EocLevel",
            function()
                self.Instance.EocLevel.Level = level
                self.Instance:Replicate( "EocLevel" )
            end
        )
    end

    function _E:SetBoosts()
        local data = self.Instance.Data
        if not data then return end

        if self.Cache.Stats.DamageBonus ~= self.Stats.DamageBonus then
            local oldstat = _F.Whole( self.Cache.Stats.DamageBonus )
            if oldstat ~= 0 then
                Osi.RemoveBoosts( self.UUID, string.format( _V.Boosts.DamageBonus, oldstat ), 0, _V.Key, "" )
            end

            local stat = _F.Whole( self.Stats.DamageBonus )
            if stat ~= 0 then
                Osi.AddBoosts( self.UUID, string.format( _V.Boosts.DamageBonus, stat ), _V.Key, "" )
            end

            self.Cache.Stats.DamageBonus = self.Stats.DamageBonus
        end

        if self.Cache.Stats.Attack ~= self.Stats.Attack then
            local oldstat = _F.Whole( self.Cache.Stats.Attack )
            if oldstat ~= 0 then
                Osi.RemoveBoosts( self.UUID, string.format( _V.Boosts.RollBonus, "Attack", oldstat ), 0, _V.Key, "" )
            end

            local stat = _F.Whole( self.Stats.Attack )
            if stat ~= 0 then
                Osi.AddBoosts( self.UUID, string.format( _V.Boosts.RollBonus, "Attack", stat ), _V.Key, "" )
            end

            self.Cache.Stats.Attack = self.Stats.Attack
        end

        if self.Cache.Stats.Size ~= self.Stats.Size then
            if self.Cache.Stats.Size ~= 0.0 then
                Osi.RemoveBoosts( self.UUID, string.format( _V.Boosts.Size, 1.0 + self.Cache.Stats.Size, 1.0 + self.Cache.Stats.Size, self.Cache.Size ), 0, _V.Key, "" )
            end

            local weight = _F.Whole( ( data.Weight * ( 1.0 + self.Stats.Size ) - data.Weight ) / 1000.0 )
            if self.Stats.Size ~= 0 then
                Osi.AddBoosts( self.UUID, string.format( _V.Boosts.Size, 1.0 + self.Stats.Size, 1.0 + self.Stats.Size, weight ), _V.Key, "" )
            end

            self.Cache.Stats.Size = self.Stats.Size
            self.Cache.Size = weight
        end

        local elvl = self.LevelBase + self.LevelChange
        for _,resource in ipairs( _V.Resource ) do
            if resource ~= "Enabled" then
                local amount = 0
                for v in string.gmatch( self.Resource[ resource ], "%d+" ) do
                    if elvl >= tonumber( v ) then
                        amount = amount + 1
                    end
                end

                if self.Cache.Resource[ resource ] ~= amount then
                    local level = resource:match( "Level([%d])" ) or 0
                    local boost = resource:gsub( "Level[%d]", "" )

                    if self.Cache.Resource[ resource ] ~= 0 then
                        Osi.RemoveBoosts( self.UUID, string.format( _V.Boosts.Resource, boost, self.Cache.Resource[ resource ], level ), 0, _V.Key, "" )
                    end

                    if amount ~= 0 then
                        Osi.AddBoosts( self.UUID, string.format( _V.Boosts.Resource, boost, amount, level ), _V.Key, "" )
                    end

                    self.Cache.Resource[ resource ] = amount
                end
            end
        end
    end

    function _E:SetExperience()
        if not self.Experience then return end

        local xp = self.Instance.ServerExperienceGaveOut
        if not xp then return end

        local base = self.Experience and self.Experience[ math.min( #self.Experience, self.Hub.General.ExperienceLevel and self.LevelBase + self.LevelChange or self.LevelBase ) ] or 0
        if not base then return end

        xp.Experience = math.max( 0, _F.Whole( ( base + self.Stats.Experience ) * ( 1.0 + self.Stats.PercentExperience ) ) )
    end

    for name,i in pairs( _E ) do
        if type( i ) == "function" then
            --- @param self Entity
            _E[ name ] = function( self, ... )
                if getmetatable( self ) == _E then
                    local ret
                    if _V.Debug then
                        local time = Ext.Utils.MicrosecTime()
                        ret = i( self, ... )
                        time = Ext.Utils.MicrosecTime() - time

                        local extradata
                        if name == "SetArchetype" then
                            extradata = self.Type
                        elseif name == "SetSpells" then
                            for spell,_ in pairs( self.Cache.Spells ) do
                                extradata = ( extradata and ( extradata .. ", " ) or "" ) .. spell
                            end
                        end

                        print(
                            string.format(
                                "\27[33m%-20s\27[0m \27[32m%-15s\27[0m \27[31m%6.1f μs\27[0m \27[34m%s\27[0m",
                                self.Cache.Name,
                                name:gsub( "Set", "" ),
                                time,
                                extradata or ""
                            )
                        )
                    else
                        ret = i( self, ... )
                    end

                    self.Instance.Vars.SDCache = self.Instance.Vars.SDCache
                    return ret
                end

                return i( self, ... )
            end
        end
    end

    return _E
end