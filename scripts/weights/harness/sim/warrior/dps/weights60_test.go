package dps

import (
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Arms and Fury as the UI's two preset builds, PreBiSArmsBuild and PreBiSFuryBuild of ui/specs/warrior/dps/presets.ts.
func TestWeights60(t *testing.T) {
	const specs = "../../../ui/specs/warrior/dps"

	// The UI's Simple rotation with its default options is the tree's APL file with the trainer's Heroic Strike
	// and Battle Shout in place of the class book ranks; every group toggle already stands as the file has it.
	trainerRanks := map[int32]int32{25286: 11567, 25289: 11551}

	// DefaultOptions and OtherDefaults of the UI presets.
	options := &proto.Player_DpsWarrior{DpsWarrior: &proto.DpsWarrior{Options: &proto.DpsWarrior_Options{
		ClassOptions: &proto.WarriorOptions{
			QueueDelay:     250,
			StartingRage:   50,
			UseBattleShout: true,
			DefaultStance:  proto.WarriorStance_WarriorStanceBerserker,
			StanceSnapshot: true,
		},
	}}}
	// DefaultConsumables of the UI presets: Smoked Desert Dumplings, EZ-Thro Dark Bomb, Elixir of Ferocity, Elixir
	// of the Mongoose, Winterfall Firewater, Goblin Sapper Charge, Mighty Rage Potion, Dense Weightstone on the main
	// hand and Dense Sharpening Stone on the off hand.
	furyConsumables := &proto.ConsumesSpec{
		FoodId:        20452,
		ExplosiveId:   260817,
		ElixirIds:     []int32{250350, 13452, 12820},
		ExtraIds:      []int32{10646},
		ResourcePotId: 13442,
		MhImbueId:     12643,
		OhImbueId:     12404,
	}
	// ArmsConsumables: the same with Dense Sharpening Stone on the two-hander and no off hand.
	armsConsumables := &proto.ConsumesSpec{
		FoodId:        20452,
		ExplosiveId:   260817,
		ElixirIds:     []int32{250350, 13452, 12820},
		ExtraIds:      []int32{10646},
		ResourcePotId: 13442,
		MhImbueId:     12404,
	}

	fury := dpsWarriorSuite()
	fury.GearSet = weights60.Gear(specs+"/gear_sets", "prebis_fury")
	fury.Talents = DefaultFuryTalents
	fury.Rotation = core.RotationWithSpellIds("fury", weights60.APL(specs+"/apls", "fury"), trainerRanks)
	fury.Consumables = furyConsumables
	fury.SpecOptions = core.SpecOptionsCombo{Label: "Fury", SpecOptions: options}
	fury.StartingDistance = 25

	arms := dpsWarriorSuite()
	arms.GearSet = weights60.Gear(specs+"/gear_sets", "prebis_arms")
	arms.Talents = DefaultArmsTalents
	arms.Rotation = core.RotationWithSpellIds("arms", weights60.APL(specs+"/apls", "arms"), trainerRanks)
	arms.Consumables = armsConsumables
	arms.SpecOptions = core.SpecOptionsCombo{Label: "Arms", SpecOptions: options}
	arms.StartingDistance = 25

	const note = "UI preset build 'Pre-BiS' of this tree. Its gear preset is marked devOnly in the UI. The repo also holds a p1 gear set for the tree, which only the Go suite uses."
	weights60.Run(t, "sim/warrior/dps", []weights60.Tree{
		{
			Class: "Warrior", Tree: "Arms", SimStatus: "Alpha", Reference: proto.Stat_StatStrength, Config: &arms,
			Baseline: weights60.Baseline{
				Gear:        "ui/specs/warrior/dps/gear_sets/prebis_arms.gear.json (PreBiSArmsGear 'Pre-BiS')",
				Talents:     "ArmsTalents 'Arms'",
				Rotation:    "ui/specs/warrior/dps/apls/arms.apl.json with the trainer ranks of Heroic Strike and Battle Shout, which is the UI's Simple rotation at its defaults",
				Consumables: "ArmsConsumables of ui/specs/warrior/dps/presets.ts",
				Quality:     "preset",
				Note:        note,
			},
		},
		{
			Class: "Warrior", Tree: "Fury", SimStatus: "Alpha", Reference: proto.Stat_StatStrength, Config: &fury,
			Baseline: weights60.Baseline{
				Gear:        "ui/specs/warrior/dps/gear_sets/prebis_fury.gear.json (PreBiSFuryGear 'Pre-BiS')",
				Talents:     "FuryTalents 'Fury'",
				Rotation:    "ui/specs/warrior/dps/apls/fury.apl.json with the trainer ranks of Heroic Strike and Battle Shout, which is the UI's Simple rotation at its defaults",
				Consumables: "DefaultConsumables of ui/specs/warrior/dps/presets.ts",
				Quality:     "preset",
				Note:        note,
			},
		},
	})
}
