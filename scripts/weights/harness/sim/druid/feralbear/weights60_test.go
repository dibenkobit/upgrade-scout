package feralbear

import (
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Feral Bear as the UI's defaults of ui/specs/druid/feralbear: the Level 60 gear, the Bear talents, the Adaptive
// Bear APL, DefaultConsumables, DefaultOptions and the healing model of OtherDefaults.
//
// The reference stays Agility, which make-weights.py weighs the bear's threat against (see TANK there), though
// the UI's epReferenceStat of both feral specs is now Strength.
func TestWeights60(t *testing.T) {
	const specs = "../../../ui/specs/druid/feralbear"
	config := core.CharacterSuiteConfig{
		Class: proto.Class_ClassDruid,
		Race:  proto.Race_RaceTauren,
		SpecOptions: core.SpecOptionsCombo{Label: "Default", SpecOptions: &proto.Player_FeralBearDruid{
			FeralBearDruid: &proto.FeralBearDruid{Options: &proto.FeralBearDruid_Options{AssumeBleedActive: true}},
		}},
		GearSet:  weights60.Gear(specs+"/gear_sets", "default"),
		Talents:  DefaultTalents,
		Rotation: weights60.APL(specs+"/apls", "adaptive"),
		// Flask of Natural Precision, Dirge's Kickin' Chimaerok Chops, Major Healthstone, Elemental Sharpening Stone,
		// Goblin Sapper Charge, Juju Might, Lung Juice Cocktail, Gift of Arthas, the Grizzly, Cunning and Phalanx
		// elixirs, Greater Stoneshield Potion and Mighty Rage Potion.
		Consumables: &proto.ConsumesSpec{
			FlaskId:        274275,
			FoodId:         21023,
			ConjuredId:     9421,
			MhImbueId:      18262,
			SwapMhImbueId:  12643,
			ExtraIds:       []int32{10646, 12460, 8411},
			ElixirIds:      []int32{9088, 250351, 250328, 250329},
			DefensivePotId: 13455,
			OffensivePotId: 13442,
		},
		Profession1:      proto.Profession_Engineering,
		Profession2:      proto.Profession_Enchanting,
		IndividualBuffs:  core.FullTankIndividualBuffs,
		IsTank:           true,
		InFrontOfTarget:  true,
		StartingDistance: 25,
		ReactionTimeMs:   250,
		HealingModel: &proto.HealingModel{
			Hps:               2200,
			CadenceSeconds:    0.4,
			CadenceVariation:  1.2,
			AbsorbFrac:        0.02,
			BurstWindow:       6,
			InspirationUptime: 0.25,
		},
	}
	weights60.Run(t, "sim/druid/feralbear", []weights60.Tree{{
		Class: "Druid", Tree: "Feral Bear", SimStatus: "Alpha", Reference: proto.Stat_StatAgility, Tank: true, Config: &config,
		// The bear sims several times slower than any other tree, and its threat is noisy: uncapped, one stat asks
		// for some 400,000 iterations a side.
		IterationCap: 100000,
		Baseline: weights60.Baseline{
			Gear:        "ui/specs/druid/feralbear/gear_sets/default.gear.siml (Level60Gear 'Level 60')",
			Talents:     "BearTalents 'Bear'",
			Rotation:    "ui/specs/druid/feralbear/apls/adaptive.apl.siml (ROTATION_ADAPTIVE 'Adaptive Bear')",
			Consumables: "DefaultConsumables of ui/specs/druid/feralbear/presets.ts",
			Quality:     "preset",
			Note:        "The UI's default setup; it ships no named build. The gear preset is marked devOnly in the UI. The target hits the bear, healed by the healing model of the UI's OtherDefaults. The Manual Crowd Pummeler of the UI's default swap set is not worn.",
		},
	}})
}
