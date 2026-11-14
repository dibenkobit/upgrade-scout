package balance

import (
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Balance as the UI's defaults of ui/specs/druid/balance: the Pre-BiS gear, the Moonkin talents, the Default APL
// and DefaultConsumables, which are the Go suite's too. The suite's own default gear is the P1 set.
func TestWeights60(t *testing.T) {
	const specs = "../../../ui/specs/druid/balance"
	config := core.CharacterSuiteConfig{
		Class: proto.Class_ClassDruid,
		Race:  proto.Race_RaceNightElf,
		SpecOptions: core.SpecOptionsCombo{Label: "Standard", SpecOptions: &proto.Player_BalanceDruid{
			BalanceDruid: &proto.BalanceDruid{Options: &proto.BalanceDruid_Options{ClassOptions: &proto.DruidOptions{}}},
		}},
		GearSet:            weights60.Gear(specs+"/gear_sets", "prebis"),
		Talents:            DefaultTalents,
		Rotation:           weights60.APL(specs+"/apls", "default"),
		Consumables:        DefaultConsumables,
		Profession1:        proto.Profession_Enchanting,
		Profession2:        proto.Profession_Tailoring,
		StartingDistance:   20,
		ChannelClipDelayMs: 100,
	}
	weights60.Run(t, "sim/druid/balance", []weights60.Tree{{
		Class: "Druid", Tree: "Balance", SimStatus: "Alpha", Reference: proto.Stat_StatSpellDamage, Config: &config,
		Baseline: weights60.Baseline{
			Gear:        "ui/specs/druid/balance/gear_sets/prebis.gear.json (PreBiSGear 'Pre-BiS')",
			Talents:     "StandardTalents 'Moonkin'",
			Rotation:    "ui/specs/druid/balance/apls/default.apl.json (StandardRotation 'Default')",
			Consumables: "DefaultConsumables of ui/specs/druid/balance/presets.ts, which the Go suite's are too",
			Quality:     "preset",
			Note:        "The UI's default setup; it ships no named build. The gear preset is marked devOnly in the UI. The repo also holds a P1 gear set.",
		},
	}})
}
