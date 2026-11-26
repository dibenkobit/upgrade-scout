package dps

import (
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Arms and Fury as the UI's preset builds PreBiSArmsBuild and PreBiSFuryBuild of ui/specs/warrior/dps/presets.ts.
func TestWeights60(t *testing.T) {
	const specs = "../../../ui/specs/warrior/dps"

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
	// DefaultConsumables of the UI presets: Smoked Desert Dumplings, SAF-T Clever Dynamite, Elixir of the Mongoose,
	// Goblin Sapper Charge, Juju Power, Juju Might, Bogling Root, R.O.I.D.S., Mighty Rage Potion, Dense Weightstone
	// on the main hand and Dense Sharpening Stone on the off hand.
	furyConsumables := &proto.ConsumesSpec{
		FoodId:        20452,
		ExplosiveId:   260814,
		ElixirIds:     []int32{13452},
		ExtraIds:      []int32{10646, 12451, 12460, 5206, 8410},
		ResourcePotId: 13442,
		MhImbueId:     12643,
		OhImbueId:     12404,
	}
	// ArmsConsumables: the same with Dense Sharpening Stone on the two-hander and no off hand.
	armsConsumables := &proto.ConsumesSpec{
		FoodId:        20452,
		ExplosiveId:   260814,
		ElixirIds:     []int32{13452},
		ExtraIds:      []int32{10646, 12451, 12460, 5206, 8410},
		ResourcePotId: 13442,
		MhImbueId:     12404,
	}

	// The UI's Simple rotation with its default options is the tree's APL file as it stands: the trainer's ranks of
	// Heroic Strike and Battle Shout, and every group toggle as the file has it.
	fury := dpsWarriorSuite()
	fury.GearSet = weights60.Gear(specs+"/gear_sets", "prebis_fury")
	fury.Talents = DefaultFuryTalents
	fury.Rotation = weights60.APL(specs+"/apls", "fury")
	fury.Consumables = furyConsumables
	fury.SpecOptions = core.SpecOptionsCombo{Label: "Fury", SpecOptions: options}
	fury.StartingDistance = 25

	arms := dpsWarriorSuite()
	arms.GearSet = weights60.Gear(specs+"/gear_sets", "prebis_arms")
	arms.Talents = DefaultArmsTalents
	arms.Rotation = weights60.APL(specs+"/apls", "arms")
	arms.Consumables = armsConsumables
	arms.SpecOptions = core.SpecOptionsCombo{Label: "Arms", SpecOptions: options}
	arms.StartingDistance = 25

	weights60.Run(t, "sim/warrior/dps", []weights60.Tree{
		{
			Class: "Warrior", Tree: "Arms", SimStatus: "Alpha", Reference: proto.Stat_StatStrength, Config: &arms,
			Baseline: weights60.Baseline{
				Gear:        "ui/specs/warrior/dps/gear_sets/prebis_arms.gear.json (PreBiSArmsGear 'Pre-BiS' of the Arms group)",
				Talents:     "ArmsTalents 'Arms'",
				Rotation:    "ui/specs/warrior/dps/apls/arms.apl.json, which is the UI's Simple rotation at its defaults",
				Consumables: "ArmsConsumables of ui/specs/warrior/dps/presets.ts",
				Quality:     "preset",
				Note:        "UI preset build 'Pre-BiS' of the Arms group. The repo also holds a p1 gear set for the tree, which only the Go suite uses.",
			},
		},
		{
			Class: "Warrior", Tree: "Fury", SimStatus: "Alpha", Reference: proto.Stat_StatStrength, Config: &fury,
			Baseline: weights60.Baseline{
				Gear:        "ui/specs/warrior/dps/gear_sets/prebis_fury.gear.json (PreBiSFuryGear 'Pre-BiS' of the Fury group)",
				Talents:     "FuryTalents 'Fury'",
				Rotation:    "ui/specs/warrior/dps/apls/fury.apl.json, which is the UI's Simple rotation at its defaults",
				Consumables: "DefaultConsumables of ui/specs/warrior/dps/presets.ts",
				Quality:     "preset",
				Note:        "UI preset build 'Pre-BiS' of the Fury group, the spec's default: two one-handers. The UI also has a 'Pre-BiS' build of the Fury 2H group. The repo also holds a p1 gear set for the tree, which only the Go suite uses.",
			},
		},
	})
}
