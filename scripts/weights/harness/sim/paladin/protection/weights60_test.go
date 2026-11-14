package protection

import (
	"testing"

	"github.com/wowsims/forever/sim/core/proto"
	"github.com/wowsims/forever/sim/weights60"
)

// Protection as the UI's defaults, ui/specs/paladin/protection/defaults.siml: the Default gear, talents and APL,
// the spec's consumables and options and its healing model. The Go suite sims the same gear, talents and APL
// with one consumable.
func TestWeights60(t *testing.T) {
	const specs = "../../../ui/specs/paladin/protection"
	weights60.Run(t, "sim/paladin/protection", []weights60.Tree{{
		Class: "Paladin", Tree: "Protection", SimStatus: "Alpha", Reference: proto.Stat_StatStrength, Tank: true,
		Player: weights60.SimlPlayer(specs+"/defaults.siml", ""),
		Baseline: weights60.Baseline{
			Gear:        "ui/specs/paladin/protection/gear_sets/default.gear.siml (GEAR_DEFAULT 'Default')",
			Talents:     "ui/specs/paladin/protection/defaults.siml (DefaultTalents 'Default')",
			Rotation:    "ui/specs/paladin/protection/apls/default.apl.siml (APL_PRESET 'Default')",
			Consumables: "ui/specs/paladin/protection/defaults.siml",
			Quality:     "preset",
			Note:        "The UI's default setup; it ships no named build. The gear preset is marked devOnly in the UI. The target hits the paladin, healed by the healing model of defaults.siml.",
		},
	}})
}
