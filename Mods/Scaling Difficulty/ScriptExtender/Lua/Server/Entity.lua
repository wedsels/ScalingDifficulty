--- @param _V _V
--- @param _F _F
return function( _V, _F )
    ---@class Entity
    local _E = {}
    _E.__index = _E

    _E.RemoveNPC = function( ent )
        local uuid = _F.UUID( ent )
        if not uuid or not _V.Entities[ uuid ] then return end

        _V.Entities[ uuid ]:Recalculate( true )
        _V.Entities[ uuid ] = nil
    end

    _E.AddNPC = function( ent )
        local uuid = _F.UUID( ent )
        if not uuid or _V.Entities[ uuid ] then return end

        local eoc = ent.EocLevel
        local data = ent.Data
        local stats = ent.Stats
        local health = ent.Health

        if not eoc or not data or not stats or not health then return end

        local xp = Ext.Stats.Get( data.StatsId )

        ent.Vars.HealthCache = ent.Vars.HealthCache or {
            Hp = health.Hp,
            MaxHp = math.max( 1, health.MaxHp ),
            Percent = health.Hp / math.max( 1, health.MaxHp ),
            Transformed = false,
            TransformedHp = 0,
            TransformedMaxHp = 0,
            TransformedPercent = 0
        }
        ent.Vars.SpellCache = ent.Vars.SpellCache or {}
        ent.Vars.NameCache = ( ent.Vars.NameCache or ent.DisplayName and Ext.Loca.GetTranslatedString( ent.DisplayName.Name.Handle.Handle ) or ent.ServerCharacter and ent.ServerCharacter.Template.Name or data.StatsId or uuid ):gsub( "[%s%p]", "" ):lower()

        _V.Entities[ uuid ] = setmetatable( {
            Name = ent.Vars.NameCache,
            UUID = uuid,
            Instance = ent,
            Disabled = false,
            Faction = "",
            Scaled = false,
            Type = "",
            Hub = _V.Hub[ nil ],
            LevelBase = eoc.Level,
            LevelChange = 0,
            Experience = xp and _V.Experience[ xp.XPReward ],
            Physical = stats.Abilities[ 2 ] <= stats.Abilities[ 3 ] and "Dexterity" or "Strength",
            Casting = tostring( stats.SpellCastingAbility ),
            Stats = _F.Default( _V.Stats ),
            Skills = {},
            Resource = _F.Default( _V.Resource, true ),
            OldStats = _F.Default( _V.Stats ),
            OldResource = _F.Default( _V.Resource ),
            OldSpells = 0,
            OldBlacklist = {},
            OldSize = 0,
            OldSkills = {},
            OldWeight = data.Weight,
            AC = {
                Type = false,
                ACBonus = 0,
                ACModifier = 0
            },
            Health = ent.Vars.HealthCache,
            Modifiers = {
                Original = {},
                Current = _F.Default( _F.Keys( _V.Abilities ) )
            },
            SpellCache = ent.Vars.SpellCache
        }, _E )

        local entity = _V.Entities[ uuid ]

        for k,v in pairs( _V.Abilities ) do
            entity.Modifiers.Original[ k ] = stats.AbilityModifiers[ v ]
        end

        entity:SetFaction()
        entity:Archetype()
        entity:Recalculate()
    end

    _E.Update = function( disable )
        for _,i in pairs( _V.Entities ) do
            i:Recalculate( disable )
        end
    end

    function _E:SetFaction()
        self.Faction = self.Instance.Faction and self.Instance.Faction.field_8 or self.Instance.ServerCharacter and self.Instance.ServerCharacter.OriginalTemplate and self.Instance.ServerCharacter.OriginalTemplate.CombatComponent.Faction or ""
    end

    function _E:Archetype()
        if _F.IsPlayer( self.Instance ) then self.Type = "Player"
        elseif Osi.IsSummon( self.UUID ) == 1 then self.Type = "Summon"
        elseif _F.IsElite( self.Instance ) then self.Type = "Elite"
        elseif Osi.GetRelation( self.Faction, "a1542c81-6895-929e-4522-10ce218bb360" ) == 0 then self.Type = "Hostile"
        else self.Type = "Ally" end

        self.Hub = _V.Hub[ self.Type ]
    end

    function _E:Recalculate( disable )
        if not self.Instance then _V.Entities[ self.UUID ] = nil return end

        self.Disabled = disable or _V.Blacklist[ self.Name ]

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

        local ran = _F.RNG( _F.Hash( self.UUID ) )

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
        self:SetLevel()
        if not disable then
            self:SetBoosts()
            self:SetSpells()
        end
        self:SetExperience()
    end

    function _E:SetSpells()
        if self.Type == "Player" then return end

        local book = self.Instance.SpellBook and self.Instance.SpellBook.Spells
        if not book then return end

        local num = self.Hub.General.Enabled and _F.Whole( self.Hub.General.Spells * ( self.LevelBase + self.LevelChange ) ) or 0
        num = math.min( num, 18 )
        if num == self.OldSpells and _V.SpellBlacklist == self.OldBlacklist then return end

        local spells = {}

        local ran = _F.RNG( _F.Hash( self.UUID ) )

        local roll = ran( num, 2 )
        for _=1,roll do
            for _=0,10 do
                local spell = ran( _V.Classes[ self.Casting ] )
                if spell and not _V.SpellBlacklist[ spell ] and Osi.CanShowSpellForCharacter( self.UUID, spell ) == 1 then
                    spells[ #spells + 1 ] = spell
                    break
                end
            end
        end

        for _,spell in ipairs( spells ) do
            local match = false
            for _,old in ipairs( self.SpellCache ) do
                match = old == spell
                if match then break end
            end
            if not match then Osi.AddSpell( self.UUID, spell ) end
        end

        for _,old in ipairs( self.SpellCache ) do
            local match = false
            for _,spell in ipairs( spells ) do
                match = spell == old
                if match then break end
            end
            if not match then Osi.RemoveSpell( self.UUID, old ) end
        end

        self.OldSpells = num
        self.OldBlacklist = _V.SpellBlacklist
        self.SpellCache = spells
        self.Instance.Vars.SpellCache = self.Instance.Vars.SpellCache
    end

    function _E:SetAC( index )
        if index == -1 then return end

        local res = self.Instance.Resistances
        if not res then return end

        local clean = index ~= 4
        local ac = _F.Whole( self.Stats.AC + ( clean and self.Modifiers.Current.Dexterity - self.Modifiers.Original.Dexterity or 0 ) )

        res.AC = res.AC + ac
        if clean then
            res.AC = res.AC - self.OldStats.AC
        end

        self.OldStats.AC = _F.Whole( self.Stats.AC + self.Modifiers.Current.Dexterity - self.Modifiers.Original.Dexterity )

        self.Instance:Replicate( "Resistances" )
    end

    function _E:SetAbilities( index )
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
                stats.Abilities[ v ] = stats.Abilities[ v ] - self.OldStats[ k ]
            else
                self.Modifiers.Original[ k ] = stats.AbilityModifiers[ v ]
            end

            stats.AbilityModifiers[ v ] = math.floor( ( stats.Abilities[ v ] - 10.0 ) / 2.0 )
            self.Modifiers.Current[ k ] = stats.AbilityModifiers[ v ]

            self.OldStats[ k ] = stat
        end

        for i,k in ipairs( _V.AbilitiesMatch ) do
            if index ~= 8 and clean then
                self.Skills[ i ] = self.Skills[ i ] or stats.Skills[ i ]
            else
                self.Skills[ i ] = stats.Skills[ i ];
            end

            if index == -1 then
                self.Skills[ i ] = self.Skills[ i ] + ( stats.Skills[ i ] - self.OldSkills[ i ] )
            end

            stats.Skills[ i ] = self.Skills[ i ] + ( stats.AbilityModifiers[ k ] - ( self.Modifiers.Original[ _V.AbilitiesReverse[ k ] ] or 0 ) )
            self.OldSkills[ i ] = stats.Skills[ i ]
        end

        stats.InitiativeBonus = _F.Whole( stats.InitiativeBonus + self.Stats.Initiative - ( clean and self.OldStats.Initiative or 0 ) )
        self.OldStats.Initiative = self.Stats.Initiative

        if self.Type ~= "Player" then
            stats.ProficiencyBonus = 2 + math.floor( ( self.LevelBase + self.LevelChange - 1 ) / 4.0 )
        end

        if not clean then
            self.Instance.Resistances.AC = self.Instance.Resistances.AC + self.Modifiers.Current.Dexterity - self.Modifiers.Original.Dexterity
        end

        self.Instance:Replicate( "Stats" )
    end

    function _E:SetHealth( index )
        local health = self.Instance.Health
        if not health then return end

        if index == 59 then
            self:SetAbilities( 79 )
            self:SetAC( 4 )

            if self.Health.Transformed then
                self.Health.Hp = self.Health.TransformedHp
                self.Health.MaxHp = self.Health.TransformedMaxHp
                self.Health.Percent = self.Health.TransformedPercent
            else
                self.Health.TransformedHp = self.Health.Hp
                self.Health.TransformedMaxHp = self.Health.MaxHp
                self.Health.TransformedPercent = self.Health.Percent

                self.Health.Percent = 1
            end

            self.Health.Transformed = not self.Health.Transformed
        elseif index == -1 or index == 1 or index == 5 or health.Hp <= 0 or Osi.IsActive( self.UUID ) ~= 1 then
            if health.Hp ~= self.Health.Hp then
                self.Health.Percent = health.Hp / math.max( 1, health.MaxHp )
                self.Health.Hp = health.Hp
            end
        elseif index ~= 1 and health.MaxHp ~= self.Health.MaxHp then
            health.Hp = self.Health.Hp
        end

        if index == 59 or index == 3 or index == 2 or not index then
            if index then
                self.Health.MaxHp = health.MaxHp
            end

            local hp = self.Health.MaxHp + self.Stats.HP
            if self.Type ~= "Player" then
                hp = hp + self.Modifiers.Current.Constitution * self.LevelChange
                hp = hp + ( self.Modifiers.Current.Constitution - self.Modifiers.Original.Constitution ) * self.LevelBase
            end
            hp = hp * ( 1.0 + self.Stats.PercentHP + self.Stats.Size )

            health.MaxHp = math.max( 1, _F.Whole( hp ) )

            health.Hp = math.min( health.MaxHp, _F.Whole( health.MaxHp * self.Health.Percent ) )
            self.Health.Hp = health.Hp
        end

        self.Instance:Replicate( "Health" )
        self.Instance.Vars.HealthCache = self.Instance.Vars.HealthCache
    end

    function _E:SetLevel( index )
        local eoc = self.Instance.EocLevel
        if not eoc or self.Type == "Player" then return end

        local level = self.LevelBase + self.LevelChange
        if eoc.Level == level then return end

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

    function _E:SetBoosts( remove )
        local data = self.Instance.Data
        if not data then return end

        if remove or self.OldStats.DamageBonus ~= self.Stats.DamageBonus then
            if remove or self.OldStats.DamageBonus ~= 0 then
                Osi.RemoveBoosts( self.UUID, string.format( _V.Boosts.DamageBonus, self.OldStats.DamageBonus ), 0, _V.Key, "" )
            end

            local stat = _F.Whole( self.Stats.DamageBonus )

            if stat ~= 0 then
                Osi.AddBoosts( self.UUID, string.format( _V.Boosts.DamageBonus, stat ), _V.Key, "" )
            end

            self.OldStats.DamageBonus = stat
        end

        if remove or self.OldStats.Attack ~= self.Stats.Attack then
            if remove or self.OldStats.Attack ~= 0 then
                Osi.RemoveBoosts( self.UUID, string.format( _V.Boosts.RollBonus, "Attack", self.OldStats.Attack ), 0, _V.Key, "" )
            end

            local stat = _F.Whole( self.Stats.Attack )

            if stat ~= 0 then
                Osi.AddBoosts( self.UUID, string.format( _V.Boosts.RollBonus, "Attack", stat ), _V.Key, "" )
            end

            self.OldStats.Attack = stat
        end

        if remove or self.OldStats.Size ~= self.Stats.Size then
            if remove or self.OldStats.Size ~= 0.0 then
                Osi.RemoveBoosts( self.UUID, string.format( _V.Boosts.Size, 1.0 + self.OldStats.Size, 1.0 + self.OldStats.Size, self.OldSize ), 0, _V.Key, "" )
            end

            local stat = self.Stats.Size
            local weight = _F.Whole( ( data.Weight * ( 1.0 + stat ) - data.Weight ) / 1000.0 )

            if stat ~= 0 then
                Osi.AddBoosts( self.UUID, string.format( _V.Boosts.Size, 1.0 + stat, 1.0 + stat, weight ), _V.Key, "" )
            end

            self.OldStats.Size = stat
            self.OldSize = weight
        end

        for _,resource in ipairs( _V.Resource ) do
            if resource ~= "Enabled" then
                local amount = 0
                local elvl = self.LevelBase + self.LevelChange
                for v in string.gmatch( self.Resource[ resource ], "%d+" ) do
                    if elvl >= tonumber( v ) then
                        amount = amount + 1
                    end
                end

                if remove or self.OldResource[ resource ] ~= amount then
                    local level = resource:match( "Level([%d])" ) or 0
                    local boost = resource:gsub( "Level[%d]", "" )

                    if remove or self.OldResource[ resource ] ~= 0 then
                        Osi.RemoveBoosts( self.UUID, string.format( _V.Boosts.Resource, boost, self.OldResource[ resource ], level ), 0, _V.Key, "" )
                    end

                    if amount ~= 0 then
                        Osi.AddBoosts( self.UUID, string.format( _V.Boosts.Resource, boost, amount, level ), _V.Key, "" )
                    end

                    self.OldResource[ resource ] = amount
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

    return _E
end