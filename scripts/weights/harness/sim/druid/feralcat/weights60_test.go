package feralcat

import (
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Feral Cat as the UI's defaults of ui/specs/druid/feralcat: the Pre-raid gear, the Cat talents, the Adaptive Cat
// APL, DefaultConsumables, DefaultOptions and OtherDefaults. The Go suite sims the Level 60 gear with no
// consumables and no bleed assumed.
//
// The reference stays Agility, as for the bear (see its file), though the UI's epReferenceStat of both feral
// specs is now Strength: a cat's weights only change their scale with it.
func TestWeights60(t *testing.T) {
	const specs = "../../../ui/specs/druid/feralcat"
	config := core.CharacterSuiteConfig{
		Class: proto.Class_ClassDruid,
		Race:  proto.Race_RaceTauren,
		SpecOptions: core.SpecOptionsCombo{Label: "Default", SpecOptions: &proto.Player_FeralCatDruid{
			FeralCatDruid: &proto.FeralCatDruid{Options: &proto.FeralCatDruid_Options{AssumeBleedActive: true}},
		}},
		GearSet:  weights60.Gear(specs+"/gear_sets", "pre_raid"),
		Talents:  DefaultTalents,
		Rotation: weights60.APL(specs+"/apls", "adaptive"),
		// Flask of Natural Aggression, Swiftstrike Steak, Demonic Rune, EZ-Thro Dark Bomb, Dense Weightstone, Juju
		// Might, Ground Scorpok Assay, Goblin Sapper Charge, the Cunning, Phalanx, Greater Mageblood and Grizzly
		// elixirs, Major Mana Potion and Mighty Rage Potion.
		Consumables: &proto.ConsumesSpec{
			FlaskId:        274274,
			FoodId:         250072,
			ConjuredId:     12662,
			ExplosiveId:    260817,
			MhImbueId:      12643,
			SwapMhImbueId:  12643,
			ExtraIds:       []int32{12460, 8412, 10646},
			ElixirIds:      []int32{250328, 250329, 250341, 250351},
			ResourcePotId:  13444,
			OffensivePotId: 13442,
		},
		Profession1:      proto.Profession_Engineering,
		Profession2:      proto.Profession_Enchanting,
		StartingDistance: 25,
		ReactionTimeMs:   250,
	}
	weights60.Run(t, "sim/druid/feralcat", []weights60.Tree{{
		Class: "Druid", Tree: "Feral Cat", SimStatus: "Alpha", Reference: proto.Stat_StatAgility, Config: &config,
		Baseline: weights60.Baseline{
			Gear:        "ui/specs/druid/feralcat/gear_sets/pre_raid.gear.siml (PreRaidGear 'Pre-raid')",
			Talents:     "CatTalents 'Cat'",
			Rotation:    "ui/specs/druid/feralcat/apls/adaptive.apl.siml ('Adaptive Cat')",
			Consumables: "DefaultConsumables of ui/specs/druid/feralcat/presets.ts",
			Quality:     "preset",
			Note:        "The UI's default setup; it ships no named build. The gear preset is marked devOnly in the UI. The repo also holds a 'Level 60' gear set and 'Hybrid' talents. The Manual Crowd Pummeler of the UI's default swap set is not worn.",
		},
	}})
}
