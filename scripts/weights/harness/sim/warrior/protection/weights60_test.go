package protection

import (
	"testing"

	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Protection as the UI's defaults of ui/specs/warrior/protection, which are its 'Pre-BiS' build of the Balanced
// group: the Balanced Pre-BiS gear and talents, the Generic APL, DefaultConsumables, DefaultOptions and the
// healing model of OtherDefaults. The Go suite's own config differs only in the tier 2 Battle Shout set option and
// in having no healing model.
func TestWeights60(t *testing.T) {
	config := protectionWarriorSuite()
	config.SpecOptions = core.SpecOptionsCombo{Label: "Protection", SpecOptions: &proto.Player_ProtectionWarrior{
		ProtectionWarrior: &proto.ProtectionWarrior{Options: &proto.ProtectionWarrior_Options{
			ClassOptions: &proto.WarriorOptions{
				QueueDelay:     250,
				UseBattleShout: true,
				DefaultStance:  proto.WarriorStance_WarriorStanceDefensive,
				StanceSnapshot: true,
			},
		}},
	}}
	config.HealingModel = &proto.HealingModel{
		Hps:               760,
		CadenceSeconds:    0.3,
		CadenceVariation:  0.64,
		AbsorbFrac:        0.015,
		BurstWindow:       6,
		InspirationUptime: 0.25,
	}

	weights60.Run(t, "sim/warrior/protection", []weights60.Tree{{
		Class: "Warrior", Tree: "Protection", SimStatus: "Alpha", Reference: proto.Stat_StatStrength, Tank: true, Config: &config,
		Baseline: weights60.Baseline{
			Gear:        "ui/specs/warrior/protection/gear_sets/prebis_balanced.gear.json (PreBiSBalancedGear 'Pre-BiS' of the Balanced group)",
			Talents:     "BalancedTalents 'Balanced'",
			Rotation:    "ui/specs/warrior/protection/apls/default.apl.json (ROTATION_DEFAULT 'Generic')",
			Consumables: "DefaultConsumables of ui/specs/warrior/protection/presets.ts, which the Go suite's are too",
			Quality:     "preset",
			Note:        "UI preset build 'Pre-BiS' of the Balanced group, the spec's default. The UI also has a 'Pre-BiS' build of the Offensive group. The target hits the warrior, healed by the healing model of the UI's OtherDefaults.",
		},
	}})
}
