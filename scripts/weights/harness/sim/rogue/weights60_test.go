package rogue

import (
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// The three trees as the UI's preset builds 'Asn Muti', 'Combat SS' and 'Subtlety Hemo' of
// ui/specs/rogue/dps/presets.ts. Each build's rotation is the UI's Simple rotation at its defaults, which is
// apls/default.apl.json as the file stands: Start In Stealth, Use Backstab and Use Expose Armor are false in both.
func TestWeights60(t *testing.T) {
	const specs = "../../ui/specs/rogue/dps"

	// DefaultConsumables of the UI presets: Elixir of the Mongoose, Elixir of Greater Fortitude, Elixir of Ferocity,
	// Juju Might, Swiftstrike Steak, Major Frenzy Potion, Thistle Tea, Dense Weightstone and Dense Sharpening Stone,
	// Instant Poison VI on the main hand and Deadly Poison IV on the off hand.
	consumables := &proto.ConsumesSpec{
		ElixirIds:       []int32{13452, 250335, 250350, 12460},
		FoodId:          250072,
		OffensivePotId:  250943,
		ConjuredId:      7676,
		MhImbueId:       12643,
		OhImbueId:       12404,
		MhWeaponImbueId: 8928,
		OhWeaponImbueId: 8985,
	}
	build := func(gear string, talents string) *core.CharacterSuiteConfig {
		return &core.CharacterSuiteConfig{
			Class:            proto.Class_ClassRogue,
			Race:             proto.Race_RaceHuman,
			GearSet:          weights60.Gear(specs+"/gear_sets", gear),
			Talents:          talents,
			Consumables:      consumables,
			SpecOptions:      core.SpecOptionsCombo{Label: "Rogue", SpecOptions: DefaultOptions},
			Rotation:         weights60.APL(specs+"/apls", "default"),
			StartingDistance: 5,
		}
	}
	const rotation = "ui/specs/rogue/dps/apls/default.apl.json (DEFAULT_APL 'Direct APL'), which is the UI's Simple rotation at its defaults"
	const consumablesName = "DefaultConsumables of ui/specs/rogue/dps/presets.ts"

	weights60.Run(t, "sim/rogue", []weights60.Tree{
		{
			Class: "Rogue", Tree: "Assassination", SimStatus: "Alpha", Reference: proto.Stat_StatAttackPower,
			Config: build("p1_muti", "00530311231251031-32030302020103-001"),
			Baseline: weights60.Baseline{
				Gear:        "ui/specs/rogue/dps/gear_sets/p1_muti.gear.json (P1_MUTI_GEAR 'Mutilate')",
				Talents:     "TALENTS_MUTILATE_ASN 'Asn Muti'",
				Rotation:    rotation,
				Consumables: consumablesName,
				Quality:     "preset",
				Note:        "UI preset build 'Asn Muti'. The gear preset is marked devOnly in the UI.",
			},
		},
		{
			Class: "Rogue", Tree: "Combat", SimStatus: "Alpha", Reference: proto.Stat_StatAttackPower,
			Config: build("p1_slowmh", "00530320201-3200132202012321551"),
			Baseline: weights60.Baseline{
				Gear:           "ui/specs/rogue/dps/gear_sets/p1_slowmh.gear.json (P1_SLOW_MH_GEAR 'Slow Main Hand')",
				Talents:        "TALENTS_COMBAT_SS 'Combat SS'",
				Rotation:       rotation,
				Consumables:    consumablesName,
				Quality:        "preset",
				Note:           "UI preset build 'Combat SS', the spec's default. The gear preset is marked devOnly in the UI. The UI also has the builds 'Combat BS' and 'Combat Venom'.",
				GearSharedWith: []string{"Subtlety"},
			},
		},
		{
			Class: "Rogue", Tree: "Subtlety", SimStatus: "Alpha", Reference: proto.Stat_StatAttackPower,
			Config: build("p1_slowmh", "00530301-320003-305230031321001151"),
			Baseline: weights60.Baseline{
				Gear:           "ui/specs/rogue/dps/gear_sets/p1_slowmh.gear.json (P1_SLOW_MH_GEAR 'Slow Main Hand')",
				Talents:        "TALENTS_SUB_HEMO 'Subtlety Hemo'",
				Rotation:       rotation,
				Consumables:    consumablesName,
				Quality:        "preset",
				Note:           "UI preset build 'Subtlety Hemo', which the UI itself pairs with the Combat SS build's gear set: the tree has no gear set of its own. The gear preset is marked devOnly in the UI.",
				GearSharedWith: []string{"Combat"},
			},
		},
	})
}
