extends Control

# TODO Card vs Item, Hand vs Board, Bag vs ?, Skills?, etc.

var dir_dialog: FileDialog
var dir_location: String

func _ready() -> void:
    DisplayServer.window_set_min_size(Vector2i(620, 450))
    _select_directory("C:/Program Files/Tempo Launcher - Beta/The Bazaar game_64/bazaarwinprodlatest/TheBazaar_Data/StreamingAssets/StaticData/.derived")


func _on_pick_directory_pressed() -> void:
    dir_dialog = FileDialog.new()
    add_child(dir_dialog)
    dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
    dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
    dir_dialog.dir_selected.connect(_select_directory)
    dir_dialog.popup(Rect2i(Vector2i(0, 0), Vector2i(600, 400)))


func _select_directory(path: String) -> void:
    if !DirAccess.dir_exists_absolute(path):
        log_textbox("Selected directory does not exist - " + path)
        return

    var has_file: bool = false
    for filename: String in DirAccess.get_files_at(path):
        if filename == "v2_Cards.json":
            has_file = true
            break
    if !has_file:
        log_textbox("Selected directory does not contain v2_Cards.json - " + path)
        return

    if !path.ends_with("/"):
        path = path + "/"

    dir_location = path
    $VBoxContainer/HBoxContainer/SelectedDirectory.text = path
    if dir_dialog:
        dir_dialog.queue_free()


func log_textbox(text: String, new_line: bool = true) -> void:
    print(text)
    $VBoxContainer/LoggingPanel/LoggingLabel.text += text
    if new_line:
        $VBoxContainer/LoggingPanel/LoggingLabel.text += "\n"
    await get_tree().create_timer(0.1).timeout


func _on_process_pressed() -> void:
    var raw_card_data: Dictionary = _read_file("v2_Cards.json")

    var all_card_data: Dictionary[String, Dictionary] = {}
    var unhandled_types := []
    for key: String in raw_card_data.keys():
        var raw_card: Dictionary = raw_card_data[key]
        var type: String = raw_card["$type"]

        var card_data := {}
        card_data["type"] = type

        match type:
            "TCardEncounterStep":
                card_data["name"] = raw_card["Localization"]["Title"]["Text"]
                if raw_card["Localization"]["Description"]:
                    card_data["desc"] = raw_card["Localization"]["Description"]["Text"]

            "TCardItem":
                # Abilities (priority?)
                # Auras
                # Tiers
                # Enchantments
                # Heroes/Tags/HiddenTags
                # Localization.Title.Text
                card_data["name"] = raw_card["Localization"]["Title"]["Text"]

                var tooltips: Array[String] = []
                for tooltip: Dictionary in raw_card["Localization"]["Tooltips"]:
                    tooltips.push_back(tooltip["Content"]["Text"])
                card_data["tooltips"] = tooltips

                var abilities: Array[String] = []
                for ability: Dictionary in raw_card["Abilities"].values():
                    abilities.push_back(_parse_ability(ability))
                card_data["abilities"] = abilities


            _:
                if !unhandled_types.has(type):
                    unhandled_types.push_back(type)
                continue

        all_card_data[key] = card_data

    # Post-processing
    for card: Dictionary in all_card_data.values():
        if card["type"] == "TCardItem":
            for i: int in range(card["abilities"].size()):
                var ability: String = card["abilities"][i]
                while ability.contains("{"):
                    var start_idx := ability.find("{")
                    var end_idx := ability.find("}")
                    var id := ability.substr(start_idx + 1, end_idx - start_idx - 1)
                    var name: String
                    if all_card_data.has(id):
                        name = all_card_data[id]["name"]
                    else:
                        name = "Unknown"
                    ability = ability.substr(0, start_idx) + "[" + name + "]" + ability.substr(end_idx + 1)
                card["abilities"][i] = ability
            print(str(card))


    log_textbox("Unsupported card types - " + str(unhandled_types))

func _parse_ability(ability: Dictionary) -> String:
    var desc := str(ability["Id"]) + ": "
    match ability["ActiveIn"]:
        "HandOnly":
            pass

        "HandAndStash":
            desc += "[Anywhere] "

        _:
            log_textbox("Unhandled ability condition - " + ability["ActiveIn"])

    if ability["Prerequisites"]:
        for prereq: Dictionary in ability["Prerequisites"]:
            desc += _parse_prereq(prereq)

    desc += _parse_trigger(ability["Trigger"])

    # TODO Action
    desc += _parse_action(ability["Action"])

    # Cleanup
    if desc.contains("[Anywhere] On Use,"):
        # On use only triggers on the board, so the anywhere flag is irrelevant
        desc = desc.replace("[Anywhere] ", "")
    desc = desc.strip_edges()

    return desc


func _parse_subject(subject: Dictionary) -> String:
    if subject == null:
        return ""

    var str: String = ""
    match subject["$type"]:
        "TTargetCardSelf":
            # TODO sometimes this means the card that triggered the effect, e.g. another card
            str = "This Card "

        "TTargetCardSection":
            if subject["TargetSection"] == "SelfBoard":
                str = "Own Card "
            elif subject["TargetSection"] == "SelfHand":
                str = "Own Card "
            elif subject["TargetSection"] == "OpponentHand":
                str = "Enemy Card "
            elif subject["TargetSection"] == "SelfHandAndStash":
                str = "Hand Or Bag Card "
            elif subject["TargetSection"] == "AllHands":
                str = "Any Card "
            else:
                log_textbox("Unhandled subject section type - " + str(subject))
                return ""

        "TTargetCardPositional":
            if subject["IncludeOrigin"]:
                str += "This And "
            if subject["Origin"] == "Self":
                if subject["TargetMode"] == "Neighbor":
                    str = "Neighbors "
                elif subject["TargetMode"] == "AllLeftCards":
                    str = "All Cards To Left "
                elif subject["TargetMode"] == "AllRightCards":
                    str = "All Cards To Right "
                elif subject["TargetMode"] == "LeftCard":
                    str = "Card On Left "
                elif subject["TargetMode"] == "RightCard":
                    str = "Card On Right "
                else:
                    log_textbox("Unhandled subject position - " + str(subject))
                    return ""
            else:
                log_textbox("Unhandled subject origin - " + str(subject))
                return ""

        "TTargetCardTriggerSource":
            if subject["ExcludeSelf"]:
                str = "Other "
            else:
                pass

        "TTargetPlayerRelative":
            if subject["TargetMode"] == "Self":
                str = "Self "
            elif subject["TargetMode"] == "Opponent":
                str = "Enemy "
            else:
                log_textbox("Unhandled subject player - " + str(subject))

        "TTargetPlayerAbsolute":
            if subject["TargetMode"] == "Player":
                str = "You "
            else:
                log_textbox("Unhandled subject player - " + str(subject))

        "TTargetCardXMost":
            if subject["TargetSection"] == "SelfHand":
                if subject["TargetMode"] == "LeftMostCard":
                    str = "Left-Most "
                    if subject["ExcludeSelf"]:
                        str += "(ignore this card) "
                else:
                    log_textbox("Unhandled subject target card mode - " + str(subject))
            else:
                log_textbox("Unhandled subject target card - " + str(subject))

        _:
            log_textbox("Unhandled subject type - " + str(subject))
            return ""

    if subject["Conditions"]:
        str += _parse_condition(subject["Conditions"])

    return str


func _parse_condition(condition: Dictionary) -> String:
    var str := ""
    match condition["$type"]:
        "TCardConditionalTag":
            if condition["Operator"] == "None":
                str += "Non-"
            elif condition["Operator"] == "Any":
                pass
            else:
                log_textbox("Unhandled subject conditional operator - " + str(condition))
            if condition["Tags"].size() > 1:
                log_textbox("Unhandled subject conditional size - " + str(condition))
            str += "[" + condition["Tags"][0] + "] "

        "TCardConditionalSize":
            if condition["IsNot"]:
                str += "Non-"
            if condition["Sizes"].size() > 1:
                log_textbox("Unhandled subject conditional size - " + str(condition))
            str += "[" + condition["Sizes"][0] + "] "

        "TCardConditionalAnd":
            str += "("
            for i: int in range(condition["Conditions"].size()):
                if i > 0:
                    str += "& "
                str += _parse_condition(condition["Conditions"][i])
            str = str.substr(0, str.length() - 1) + ") "

        "TCardConditionalOr":
            str += "("
            for i: int in range(condition["Conditions"].size()):
                if i > 0:
                    str += "| "
                str += _parse_condition(condition["Conditions"][i])
            str = str.substr(0, str.length() - 1) + ") "

        "TCardConditionalId":
            if condition["IsNot"]:
                str += "Not {" + condition["Id"] + "} "
            else:
                str += "{" + condition["Id"] + "} "

        "TCardConditionalType":
            if condition["IsNot"]:
                str += "Card Is Not " + condition["CardType"] + " "
            else:
                str += "Card Is " + condition["CardType"] + " "

        "TCardConditionalAttribute":
            if condition["Attribute"] == "AmmoMax":
                str += "Card Uses Ammo "
            elif condition["Attribute"] == "CooldownMax":
                str += "Card Uses Cooldown "
            else:
                log_textbox("Unhandled subject condition attribute - " + str(condition))

        _:
            log_textbox("Unhandled subject condition - " + str(condition))
            return ""

    return str


func _parse_prereq(prereq: Dictionary) -> String:
    match prereq["$type"]:
        "TPrerequisiteCardCount":
            if prereq["Subject"]["$type"] == "TTargetCardSelf" \
                and prereq["Subject"]["Conditions"]["$type"] == "TCardConditionalAttribute" \
                and prereq["Subject"]["Conditions"]["Attribute"].begins_with("Custom_") \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["$type"] == "TFixedValue" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["Value"] == 0:
                # Life preserver, first time below 50% health, etc.
                return "Only Once, "
            elif prereq["Subject"]["$type"] == "TTargetCardSelf" \
                and prereq["Subject"]["Conditions"]["$type"] == "TCardConditionalAttribute" \
                and prereq["Subject"]["Conditions"]["Attribute"] == "AmmoMax" \
                and prereq["Subject"]["Conditions"]["ComparisonOperator"] == "GreaterThan" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["$type"] == "TFixedValue" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["Value"] == 0:
                # Sweet ammo-based buffs
                return "If This Has Max Ammo Left, "
            elif prereq["Comparison"] == "GreaterThanOrEqual" \
                and prereq["Subject"]["$type"] == "TTargetCardSection" \
                and prereq["Subject"]["TargetSection"] == "OpponentHand" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TCardConditionalSize":
                # Hacksaw + Bugged Diana Saur
                return "If Opponent Has " + str(prereq["Amount"]) + "+ " + str(prereq["Subject"]["Conditions"]["Sizes"]) + " Items, "
            elif prereq["Comparison"] == "GreaterThanOrEqual" \
                and prereq["Subject"]["$type"] == "TTargetCardSection" \
                and prereq["Subject"]["TargetSection"] == "OpponentHand":
                # Diana Saur + Dinonysus
                return "If Opponent Has " + str(prereq["Amount"]) + "+ Items, "
            elif prereq["Comparison"] == "GreaterThanOrEqual" \
                and prereq["Subject"]["$type"] == "TTargetCardSection" \
                and prereq["Subject"]["TargetSection"] == "SelfHandAndStash" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TCardConditionalTag":
                # Hammer
                return "If You Have " + str(prereq["Amount"]) + "+ " + str(prereq["Subject"]["Conditions"]["Tags"]) + " Items Anywhere, "
            elif prereq["Comparison"] == "Equal" \
                and prereq["Subject"]["$type"] == "TTargetCardSection" \
                and prereq["Subject"]["TargetSection"] == "SelfHand" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TCardConditionalTag":
                # Rifle
                return "If You Have Exactly " + str(prereq["Amount"]) + " " + str(prereq["Subject"]["Conditions"]["Tags"]) + " Items, "
            elif prereq["Subject"]["$type"] == "TTargetCardSelf" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TCardConditionalHasEnchantment":
                # Dragon Tooth
                var str := "If This Is "
                if prereq["Subject"]["Conditions"]["IsNot"]:
                    str += "Not "
                str += "[" + prereq["Subject"]["Conditions"]["Enchantment"] + "], "
                return str
            elif prereq["Subject"]["$type"] == "TTargetCardSelf" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TCardConditionalAttribute" \
                and prereq["Subject"]["Conditions"]["Attribute"].begins_with("Custom_") \
                and prereq["Subject"]["Conditions"]["ComparisonOperator"] == "Equal":
                # Business Card
                return "If This Happens " + str(prereq["Subject"]["Conditions"]["ComparisonValue"]["Value"]) + " Times, "
            elif prereq["Subject"]["$type"] == "TTargetCardSelf" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TCardConditionalAttribute" \
                and prereq["Subject"]["Conditions"]["Attribute"].begins_with("Custom_") \
                and prereq["Subject"]["Conditions"]["ComparisonOperator"] == "GreaterThanOrEqual":
                # Bootstraps
                return "If This Happens " + str(prereq["Subject"]["Conditions"]["ComparisonValue"]["Value"]) + "+ Times, "
            elif prereq["Subject"]["$type"] == "TTargetCardSelf" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TCardConditionalTier":
                # Bootstraps
                return "If This Is " + str(prereq["Subject"]["Conditions"]["Tiers"]) + " Tier, "
            else:
                log_textbox("Unhandled ability prerequisite count - " + str(prereq))

        "TPrerequisitePlayer":
            if prereq["Subject"]["$type"] == "TTargetPlayerRelative" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TPlayerConditionalAttribute" \
                and prereq["Subject"]["Conditions"]["Attribute"] == "Health" \
                and prereq["Subject"]["Conditions"]["ComparisonOperator"] == "LessThan" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["$type"] == "TReferenceValuePlayerAttribute" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["AttributeType"] == "HealthMax":
                # Losing health text is generated elsewhere
                pass
            elif prereq["Subject"]["$type"] == "TTargetPlayerRelative" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TPlayerConditionalAttribute" \
                and prereq["Subject"]["Conditions"]["Attribute"] == "Gold" \
                and prereq["Subject"]["Conditions"]["ComparisonOperator"] == "GreaterThanOrEqual":
                # Piggy Bank
                return "If You Have " + str(prereq["Subject"]["Conditions"]["ComparisonValue"]["Value"]) + "+ Gold, "
            elif prereq["Subject"]["$type"] == "TTargetPlayerRelative" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TPlayerConditionalAttribute" \
                and prereq["Subject"]["Conditions"]["Attribute"] == "Health" \
                and prereq["Subject"]["Conditions"]["ComparisonOperator"] == "GreaterThanOrEqual" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["$type"] == "TReferenceValuePlayerAttribute" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["AttributeType"] == "Health":
                # Gavel
                return "If You Have More Health Than Enemy, "
            elif prereq["Subject"]["$type"] == "TTargetPlayerRelative" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TPlayerConditionalAttribute" \
                and prereq["Subject"]["Conditions"]["Attribute"] == "Health" \
                and prereq["Subject"]["Conditions"]["ComparisonOperator"] == "LessThan" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["$type"] == "TReferenceValuePlayerAttribute" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["AttributeType"] == "Health":
                # Gavel
                return "If You Have Less Health Than Enemy, "
            elif prereq["Subject"]["$type"] == "TTargetPlayerRelative" \
                and prereq["Subject"]["TargetMode"] == "Opponent" \
                and prereq["Subject"]["Conditions"] == null:
                # Langxian and Darts
                return "If Human Opponent, "
            elif prereq["Subject"]["$type"] == "TTargetPlayerRelative" \
                and prereq["Subject"]["Conditions"] != null \
                and prereq["Subject"]["Conditions"]["$type"] == "TPlayerConditionalAttribute" \
                and prereq["Subject"]["Conditions"]["Attribute"] == "Health" \
                and prereq["Subject"]["Conditions"]["ComparisonOperator"] == "GreaterThanOrEqual" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["$type"] == "TReferenceValuePlayerAttribute" \
                and prereq["Subject"]["Conditions"]["ComparisonValue"]["AttributeType"] == "HealthMax":
                # Weights
                return "If You Overheal, "
            else:
                log_textbox("Unhandled ability prerequisite player - " + str(prereq))


        _:
            log_textbox("Unhandled ability prerequisite - " + str(prereq))

    return ""


func _parse_trigger(trigger: Dictionary) -> String:
    var subject: String = ""
    if trigger.has("Subject"):
        subject = _parse_subject(trigger["Subject"])
    match trigger["$type"]:
        "TTriggerOnCardFired":
            if subject:
                log_textbox("Unhandled trigger subject - " + str(trigger))
            return "On Use, "

        "TTriggerOnCardSold":
            return "On " + subject + "Sell, "

        "TTriggerOnFightStarted":
            if subject:
                log_textbox("Unhandled trigger subject - " + str(trigger))
            return "On Combat Start, "

        "TTriggerOnDayStarted":
            if subject:
                log_textbox("Unhandled trigger subject - " + str(trigger))
            return "On Day Start, "

        "TTriggerOnCardPerformedFreeze":
            return "On " + subject + "Performed Freeze, "

        "TTriggerOnCardSelected":
            if subject:
                log_textbox("Unhandled trigger subject - " + str(trigger))
            return "When Selected, "

        "TTriggerOnItemUsed":
            if subject.begins_with("This Card "):
                subject = subject.replace("This", "Any")
            return "On " + subject + "Use, "

        "TTriggerOnCardPerformedBurn":
            return "On " + subject + "Burn, "

        "TTriggerOnCardCritted":
            return "On " + subject + "Crit, "

        "TTriggerOnCardAttributeChanged":
            return "On " + subject + "Hasted, "

        "TTriggerOnCardPerformedShield":
            return "On " + subject + "Shield, "

        "TTriggerOnPlayerAttributeChanged":
            var str := "On " + subject
            if trigger["AttributeType"] == "HealthRegen":
                if trigger["ChangeType"] == "Gain":
                    str += "Health Regen Changed"
                else:
                    log_textbox("Unhandled ability trigger attribute - " + trigger["AttributeType"])
            elif trigger["AttributeType"] == "Health":
                if trigger["ChangeType"] == "Loss":
                    str += "50% Health"
                else:
                    log_textbox("Unhandled ability trigger attribute - " + trigger["AttributeType"])
            elif trigger["AttributeType"] == "Level":
                if trigger["ChangeType"] == "Gain":
                    str += "Level-Up"
                else:
                    log_textbox("Unhandled ability trigger attribute - " + trigger["AttributeType"])
            elif trigger["AttributeType"] == "Shield":
                if trigger["ChangeType"] == "Loss":
                    str += "Shield Broken"
                else:
                    log_textbox("Unhandled ability trigger attribute - " + trigger["AttributeType"])
            elif trigger["AttributeType"] == "Burn":
                if trigger["ChangeType"] == "Gain":
                    str += "Burned"
                else:
                    log_textbox("Unhandled ability trigger attribute - " + trigger["AttributeType"])
            elif trigger["AttributeType"] == "Gold":
                if trigger["ChangeType"] == "Gain":
                    str += "Gold Gained"
                else:
                    str += "Gold Spent"
            else:
                log_textbox("Unhandled ability trigger attribute - " + trigger["AttributeType"])
            str += ", "
            return str

        "TTriggerOnFightEnded":
            if trigger["CombatOutcome"] == "Lose":
                return "On Combat Loss, "
            else:
                return "On Combat Win, "

        "TTriggerOnPlayerDied":
            return "On " + subject + "Death, "

        "TTriggerOnCardUpgraded":
            return "On " + subject + "Upgrade, "

        "TTriggerOnCardPerformedHaste":
            return "On " + subject + "Performed Haste, "

        "TTriggerOnCardPerformedSlow":
            return "On " + subject + "Performed Slow, "

        "TTriggerOnHourStarted":
            return "On Hour Start, "

        "TTriggerOnCardPurchased":
            return "On " + subject + "Purchase, "

        "TTriggerOnCardPerformedHeal":
            return "On " + subject + "Performed Heal, "

        "TTriggerOnCardPerformedDestruction":
            return "On " + subject + "Performed Card Destruction, "

        "TTriggerOnCardPerformedPoison":
            return "On " + subject + "Performed Poison, "

        "TTriggerOnPlayerAttributePercentChange":
            return "On " + subject + trigger["AttributeType"] + " Changed, "

        "TTriggerOnEncounterSelected":
            return "On " + _parse_condition(trigger["Conditions"]) + "Encountered, "

        _:
            log_textbox("Unhandled ability trigger - " + str(trigger))

    return ""


func _parse_action(action: Dictionary) -> String:
    # TODO conditions, e.g. freeze small
    match action["$type"]:
        "TActionPlayerDamage":
            return "Damage #DamageAmount#"

        "TActionPlayerHeal":
            return "Heal #HealAmount#"

        "TActionPlayerShieldApply":
            return "Shield #ShieldApplyAmount#"

        "TActionPlayerBurnApply":
            return "Burn #BurnApplyAmount#"

        "TActionPlayerPoisonApply":
            return "Poison #PoisonApplyAmount#"

        "TActionPlayerBurnRemove":
            return "Remove Burn #BurnRemoveAmount#"

        "TActionPlayerPoisonRemove":
            return "Remove Poison #PoisonRemoveAmount#"

        "TActionCardHaste":
            return "Haste #HasteTargets# Items #HasteAmount#"

        "TActionCardCharge":
            return "Charge #ChargeTargets# Items #ChargeAmount#"

        "TActionCardSlow":
            return "Slow #SlowTargets# Items #SlowAmount#"

        "TActionCardFreeze":
            return "Freeze #FreezeTargets# Items #FreezeAmount#"

        "TActionPlayerJoyApply":
            return "Apply #JoyApplyAmount# Joy"

        "TActionCardReload":
            if action["Target"]["Conditions"] == null:
                # Bugged card?
                pass
            else:
                return "Reload " + _parse_condition(action["Target"]["Conditions"])

        "TActionCardDisable":
            if action["Target"]["Conditions"] == null:
                return "Destroy An Item"
            else:
                return "Destroy " + _parse_condition(action["Target"]["Conditions"])

        "TActionCardUpgrade":
            if action["Target"]["$type"] == "TTargetCardXMost":
                if action["Target"]["TargetMode"] == "LeftMostCard":
                    return "Upgrade Left-Most Card"
                else:
                    log_textbox("Unhandled action upgrade - " + str(action))
            elif action["Target"]["$type"] == "TTargetCardSection":
                return "Upgrade " + _parse_condition(action["Target"]["Conditions"])
            elif action["Target"]["$type"] == "TTargetCardSelf":
                return "Upgrade This"
            elif action["Target"]["$type"] == "TTargetCardRandom":
                return "Upgrade Random"
            else:
                log_textbox("Unhandled action upgrade - " + str(action))

        "TActionCardForceUse":
            var str := "Use "
            if action["Target"]["$type"] == "TTargetCardSection":
                "All Other Items "
            elif action["Target"]["$type"] == "TTargetCardSelf":
                "This "
            elif action["Target"]["$type"] != "TTargetCardRandom" or action["Target"]["TargetSection"] != "SelfHand":
                # 3D printer can self use
                log_textbox("Unhandled action force state - " + str(action))
            else:
                str += "Item "
                if action["Target"]["Conditions"] != null:
                    str += _parse_condition(action["Target"]["Conditions"])
            return str

        "TActionCardModifyAttribute", "TActionPlayerModifyAttribute":
            var amount: String
            if action["Value"]["$type"] == "TReferenceValueCardAttribute":
                amount = "#" + action["Value"]["AttributeType"] + "#"
            elif action["Value"]["$type"] == "TFixedValue":
                amount = str(action["Value"]["Value"])
            elif action["Value"]["$type"] == "TRangeValue":
                amount = str(action["Value"]["MinValue"]) + "-" + str(action["Value"]["MaxValue"])
            elif action["Value"]["$type"] == "TReferenceValuePlayerAttribute":
                amount = "#Player" + action["Value"]["AttributeType"] + "#"
            elif action["Value"]["$type"] == "TReferenceValuePlayerAttributeChange":
                # No idea, balloon bot
                pass
            else:
                log_textbox("Unhandled action attribute value - " + str(action))

            if action["Operation"] == "Add":
                return "+" + amount + " $" + action["AttributeType"] + "Name$"
            elif action["Operation"] == "Subtract":
                return "-" + amount + " $" + action["AttributeType"] + "Name$"
            elif action["Operation"] == "Multiply":
                return "x" + amount + " $" + action["AttributeType"] + "Name$"
            else:
                log_textbox("Unhandled action attribute modification - " + str(action))

        "TActionGameSpawnCards", "TActionGameDealCards":
            var amount: String
            if action["SpawnContext"]["Limit"]["$type"] == "TFixedValue":
                amount = str(action["SpawnContext"]["Limit"]["Value"])
            elif action["SpawnContext"]["Limit"]["$type"] == "TReferenceValueCardAttribute":
                amount = "#" + action["SpawnContext"]["Limit"]["AttributeType"] + "#"
            else:
                log_textbox("Unhandled action spawn limit - " + str(action))

            var str := "Spawn " + amount + " "
            for j: int in range(action["SpawnContext"]["Groups"].size()):
                if j > 0:
                    str += "+ "
                var group: Dictionary = action["SpawnContext"]["Groups"][j]
                if group["Prerequisites"] != null:
                     log_textbox("Unhandled action spawn setting - " + str(action))
                for filter: Dictionary in group["Filters"]:
                    if filter["$type"] == "TSpawnFilterIdList":
                        str += "("
                        for i: int in range(filter["Ids"].size()):
                            if i > 0:
                                str += "| "
                            str += "{" + filter["Ids"][i] + "} "
                        str = str.substr(0, str.length() - 1) + ") "
                    elif filter["$type"] == "TSpawnFilterQuery":
                        # TODO
                        pass
                    else:
                        log_textbox("Unhandled action spawn filter - " + str(action))

            if action["SpawnContext"]["Behaviors"] != null:
                str += "("
                for i: int in range(action["SpawnContext"]["Behaviors"].size()):
                    if i > 0:
                        str += "| "
                    var behavior: Dictionary = action["SpawnContext"]["Behaviors"][i]
                    if behavior["$type"] == "TSpawnBehaviorAllowDuplicates":
                        if behavior["AllowDuplicates"]:
                            str += "dupes ok "
                        else:
                            str += "no dupes "
                    elif behavior["$type"] == "TSpawnBehaviorIgnoreHero":
                        if behavior["IgnoreHero"]:
                            str += "any hero "
                        else:
                            str += "this hero "
                    else:
                        log_textbox("Unhandled action spawn behavior - " + str(action))
                str = str.substr(0, str.length() - 1) + ") "

            return str

        _:
            log_textbox("Unhandled action type - " + str(action))

    return ""


func _read_file(filename: String) -> Variant:
    return JSON.parse_string(FileAccess.get_file_as_string(dir_location + filename))
